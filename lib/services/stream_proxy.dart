import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A loopback reverse-proxy with its own DNS resolution.
///
/// Purpose: the device's system DNS can fail (intermittently or permanently)
/// for self-hosted/DDNS names, while public DoH resolvers resolve them fine —
/// that is exactly why the same URL worked in the owner's browser but died in
/// the app ("Failed host lookup, errno 7"). ExoPlayer resolves independently
/// and cannot be taught DoH, so instead of fighting it, every stream URL is
/// rewritten to **this** proxy: `http://127.0.0.1:<port>/stream?u=<encoded>`.
/// The proxy forwards to the real server, resolving the hostname itself:
/// system DNS first, then DNS-over-HTTPS via 1.1.1.1 / 8.8.8.8 (IP-literal
/// endpoints — they need no DNS to reach).
///
/// Range requests are forwarded verbatim, so seeking works; 206/Content-Range
/// and all other response headers are passed straight back.
class StreamProxy {
  StreamProxy._();

  static HttpServer? _server;
  static bool get isRunning => _server != null;

  /// Whether outbound clients should use the DoH-resolving connector.
  /// Engaged ONLY when the device resolver fails a startup health check: the
  /// manual connector, while DNS-robust, has been observed breaking TLS
  /// handshakes on some emulators ("Connection closed before full header was
  /// received" — TCP connects, then the handshake dies), so it must stay off
  /// unless the system resolver is genuinely broken.
  static bool _dohEnabled = false;

  static bool get dohEnabled => _dohEnabled;

  /// One-shot startup check: if the device cannot resolve a well-known name,
  /// route all outbound clients through DoH for this session. Call once from
  /// main() before the first request. Healthy resolvers answer in tens of
  /// milliseconds; broken ones fail immediately (no health-check delay).
  static Future<void> checkDeviceDns() async {
    try {
      final result =
          await InternetAddress.lookup('one.one.one.one').timeout(const Duration(seconds: 4));
      _dohEnabled = result.isEmpty;
    } catch (_) {
      _dohEnabled = true;
    }
  }

  /// Starts the loopback server. Idempotent.
  static Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handle, onError: (Object _) {});
    } catch (_) {
      _server = null;
    }
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
  }

  /// Rewrites an absolute http(s) URL to a loopback proxy URL. Non-http URLs
  /// (local file paths) are returned unchanged.
  static String wrap(String url) {
    final server = _server;
    if (server == null) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
    return 'http://127.0.0.1:${server.port}/stream?u=${Uri.encodeComponent(url)}';
  }

  static Future<void> _handle(HttpRequest request) async {
    try {
      final targetParam = request.uri.queryParameters['u'];
      if (request.method != 'GET' || targetParam == null) {
        await request.response.close();
        return;
      }
      final target = Uri.parse(targetParam);

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      // DoH-resolving connector only when the device resolver is broken
      // (see checkDeviceDns). On a healthy resolver the default connect path
      // must stay untouched — it owns socket lifecycle through the TLS
      // handshake, and replacing it broke HTTPS on emulators.
      if (_dohEnabled) {
        client.connectionFactory = (uri, proxyHost, proxyPort) => connectResolvingDoh(uri);
      }
      try {
        final upstreamRequest = await client.openUrl('GET', target);
        final upstream = await upstreamRequest.close();
        final proxied = request.response;
        proxied.statusCode = upstream.statusCode;
        for (final name in const ['content-type', 'content-length', 'content-range', 'accept-ranges', 'icy-metaint', 'content-disposition']) {
          final value = upstream.headers.value(name);
          if (value != null) proxied.headers.set(name, value);
        }
        await proxied.addStream(upstream);
        await proxied.close();
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }
}

/// Shared connector: resolves [uri.host] via system DNS first and falls back
/// to DNS-over-HTTPS, then returns the connected socket. Used by the image
/// cache layer (its HTTP client) and the stream proxy, so every request in the
/// app survives a broken device resolver. TLS is unaffected: dart:io performs
/// the handshake on the returned socket using the original hostname, so
/// certificate validation and SNI stay correct.
Future<ConnectionTask<Socket>> connectResolvingDoh(Uri uri) async {
  final port = uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port;

  List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(uri.host);
  } catch (_) {
    addresses = const [];
  }
  if (addresses.isEmpty) {
    addresses = await _dohLookup(uri.host);
  }
  if (addresses.isEmpty) {
    throw SocketException('Failed host lookup: ${uri.host}');
  }

  // IPv4 first: virtualised networks (emulators, VPNs) frequently advertise
  // AAAA records with no working IPv6 route — connecting there stalls. Only
  // when there is no A record at all do we fall back to the full list.
  final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4).toList();
  final ordered = ipv4.isNotEmpty ? ipv4 : addresses;

  // Try each address in order — startConnect returns a proper
  // ConnectionTask that dart:io manages for the TLS handshake (wrapping an
  // already-connected socket manually broke HTTPS with "Connection closed
  // before full header was received").
  Object? lastError;
  for (final address in ordered) {
    try {
      return await Socket.startConnect(address, port);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? SocketException('Failed host lookup: ${uri.host}');
}

final Map<String, List<InternetAddress>> _dohCache = {};

/// DNS-over-HTTPS lookups against 1.1.1.1 then 8.8.8.8 — both are
/// IP-literal endpoints, reachable even when name resolution is what's broken.
Future<List<InternetAddress>> _dohLookup(String host) async {
  final cached = _dohCache[host];
  if (cached != null) return cached;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    for (final endpoint in [
      'https://1.1.1.1/dns-query?name=$host&type=A',
      'https://8.8.8.8/resolve?name=$host&type=A',
    ]) {
      try {
        final request = await client.openUrl('GET', Uri.parse(endpoint));
        request.headers.set('accept', 'application/dns-json');
        final response = await request.close().timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) continue;
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final answers = json['Answer'] as List<dynamic>?;
        if (answers == null) continue;
        final addresses = <InternetAddress>[];
        for (final answer in answers) {
          if (answer is! Map<String, dynamic>) continue;
          if (answer['type'] != 1) continue; // A records only
          final data = answer['data'] as String?;
          if (data != null && InternetAddress.tryParse(data) != null) {
            addresses.add(InternetAddress(data));
          }
        }
        if (addresses.isNotEmpty) {
          _dohCache[host] = addresses;
          return addresses;
        }
      } catch (_) {
        // Try the next resolver.
      }
    }
    return const [];
  } finally {
    client.close(force: true);
  }
}

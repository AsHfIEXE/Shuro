import 'dart:async';
import 'dart:io';

import '../playback/event_log.dart';

/// One-shot network self-test for the lyrics hosts. Every stage is timed
/// separately and written to the diagnostics ring as `net.probe`, so a
/// "lyrics never load" report says WHERE it stalls (DNS, TCP over IPv4 or
/// IPv6, TLS, or the HTTP reply) instead of just "network". Sequential on
/// purpose (this machine's resolver stalls under bursts), nothing sensitive
/// is recorded - only host names, address families and milliseconds.
class NetProbe {
  NetProbe._();

  static bool _ran = false;

  static Future<void> run({
    List<String> hosts = const ['lrclib.net', 'lrc.red', 'musicbrainz.org'],
  }) async {
    if (_ran) return;
    _ran = true;
    for (final host in hosts) {
      await _probeHost(host);
    }
  }

  static void _log(String host, String stage, Map<String, Object?> d) {
    try {
      PlaybackEventLog.instance.add('net.probe', {'host': host, 'stage': stage, ...d});
    } catch (_) {}
  }

  static Future<void> _probeHost(String host) async {
    final sw = Stopwatch()..start();
    List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 25));
      _log(host, 'dns', {
        'ms': sw.elapsedMilliseconds,
        'v4': addrs.where((a) => a.type == InternetAddressType.IPv4).length,
        'v6': addrs.where((a) => a.type == InternetAddressType.IPv6).length,
      });
    } catch (e) {
      _log(host, 'dns', {'ms': sw.elapsedMilliseconds, 'err': e.runtimeType.toString()});
      return;
    }

    // TCP 443 to the first address of each family, timed on its own.
    for (final type in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
      final a = addrs.where((x) => x.type == type).firstOrNull;
      if (a == null) continue;
      final t = Stopwatch()..start();
      try {
        final s = await Socket.connect(a, 443, timeout: const Duration(seconds: 6));
        s.destroy();
        _log(host, 'tcp', {'fam': type.name, 'ms': t.elapsedMilliseconds});
      } catch (e) {
        _log(host, 'tcp', {
          'fam': type.name,
          'ms': t.elapsedMilliseconds,
          'err': e.runtimeType.toString(),
        });
      }
    }

    // Full HTTPS round trip through a plain dart:io client (what the lyrics
    // services use): TLS + first byte.
    final t = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.headUrl(Uri.https(host, '/')).timeout(const Duration(seconds: 9));
      final res = await req.close().timeout(const Duration(seconds: 9));
      _log(host, 'https', {'ms': t.elapsedMilliseconds, 'status': res.statusCode});
      await res.drain<void>();
    } catch (e) {
      _log(host, 'https', {'ms': t.elapsedMilliseconds, 'err': e.runtimeType.toString()});
    } finally {
      client.close(force: true);
    }
  }
}

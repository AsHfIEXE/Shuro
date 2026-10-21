import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'stream_proxy.dart';

/// A disk cache for everything the app fetches over HTTP that is an *image* —
/// cover art, artist pictures — layered transparently under all
/// `NetworkImage`s via [HttpOverrides].
///
/// Why this exists: Flutter's `NetworkImage` has NO disk cache. Every app
/// start re-downloaded the whole library's cover art before the grid looked
/// right — the single biggest reason the library felt slow after the first
/// install. With this layer the first launch fills a local cache and every
/// launch after that renders covers straight from disk instantly, while only
/// the small JSON catalog requests touch the network.
///
/// Safety rails:
///  * only GET responses with status 200 and an `image/*` content type are
///    written — API/JSON/stream traffic is never cached (the audio stream
///    must stay live);
///  * the cache key strips the per-launch auth query params, so a new
///    session's signed URLs still hit the same cache entry;
///  * every cache touch is guarded — any failure falls through to the plain
///    network path, so this can never break loading;
///  * pruned to a size cap at startup.
class ImageDiskCache {
  ImageDiskCache._();

  static const int _maxCacheBytes = 300 * 1024 * 1024;
  static const int _pruneToBytes = 200 * 1024 * 1024;
  static Directory? _directory;
  static bool _pruned = false;

  static Future<Directory> directory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}image_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _directory = dir;
    if (!_pruned) {
      _pruned = true;
      unawaited(_prune(dir));
    }
    return dir;
  }

  /// Cache key: the URL with per-session auth params removed. Two sessions
  /// build different signed URLs for the same cover — they must share one
  /// cache file.
  @visibleForTesting
  static String keyFor(Uri uri) {
    final normalised = uri.replace(queryParameters: {
      for (final entry in uri.queryParameters.entries)
        if (entry.key != 'u' && entry.key != 't' && entry.key != 's') entry.key: entry.value,
    });
    return base64Url.encode(utf8.encode(normalised.toString())).replaceAll('=', '');
  }

  static File _fileFor(Directory dir, String key) => File('${dir.path}${Platform.pathSeparator}$key.img');

  static Future<void> _prune(Directory dir) async {
    try {
      final files = dir.listSync().whereType<File>().toList();
      var total = 0;
      final sized = <(File, DateTime, int)>[];
      for (final file in files) {
        final length = file.lengthSync();
        total += length;
        sized.add((file, file.lastModifiedSync(), length));
      }
      if (total <= _maxCacheBytes) return;
      sized.sort((a, b) => a.$2.compareTo(b.$2)); // oldest first
      for (final (file, _, length) in sized) {
        if (total <= _pruneToBytes) break;
        try {
          file.deleteSync();
          total -= length;
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// Installs the caching client for every `NetworkImage`/HTTP image fetch.
/// Call once from main() before runApp: `HttpOverrides.global = CachingHttpOverrides();`
class CachingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = CachingHttpClient(inner: super.createHttpClient(context));
    // Self-signed certificates on the user's OWN LAN (192.168.x, 10.x,
    // 172.16-31.x, localhost) are accepted — the classic homelab setup.
    // Public hosts keep full validation.
    client.badCertificateCallback = (cert, host, port) => _isPrivateHost(host);
    return client;
  }

  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan')) return true;
    if (h.startsWith('192.168.') || h.startsWith('10.')) return true;
    if (h.startsWith('172.')) {
      final second = int.tryParse(h.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    return false;
  }
}

/// An [HttpClient] whose GETs are served from, and written to, the image disk
/// cache. Everything else passes straight through to the platform client, so
/// nothing about networking changes except images getting faster on repeat
/// runs.
class CachingHttpClient implements HttpClient {
  final HttpClient inner;

  CachingHttpClient({required HttpClient inner}) : inner = inner {
    // DoH-resolving connector only when the device resolver is broken (the
    // StreamProxy startup health check decides). On a healthy resolver the
    // default connect path must stay untouched — it owns socket lifecycle
    // through the TLS handshake, and replacing it broke HTTPS on emulators.
    if (StreamProxy.dohEnabled) {
      inner.connectionFactory = (uri, proxyHost, proxyPort) => connectResolvingDoh(uri);
    }
  }

  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String Function(Uri url)? findProxy;

  @override
  String? userAgent;

  @override
  void addCredentials(Uri uri, String realm, HttpClientCredentials credentials) =>
      inner.addCredentials(uri, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) => inner.authenticate = f;

  @override
  set authenticateProxy(
      Future<bool> Function(String host, int port, String scheme, String? realm)? f) => inner.authenticateProxy = f;

  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      inner.badCertificateCallback = callback;

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri uri, String? proxyHost, int? proxyPort)? f) =>
      inner.connectionFactory = f;

  @override
  set keyLog(void Function(String line)? callback) => inner.keyLog = callback;

  @override
  void close({bool force = false}) => inner.close(force: force);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) => _route(method, uri);

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _route(method, Uri.parse('${port == 443 ? 'https' : 'http'}://$host:$port$path'));

  @override
  Future<HttpClientRequest> getUrl(Uri uri) => openUrl('get', uri);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => open('get', host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri uri) => openUrl('post', uri);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => open('post', host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri uri) => openUrl('put', uri);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => open('put', host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri uri) => openUrl('delete', uri);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => open('delete', host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri uri) => openUrl('patch', uri);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => open('patch', host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri uri) => openUrl('head', uri);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => open('head', host, port, path);

  Future<HttpClientRequest> _route(String method, Uri uri) async {
    // Only complete GETs are served from disk; anything else — streams,
    // posts, auth exchanges — passes straight through.
    if (method.toLowerCase() == 'get') {
      try {
        final dir = await ImageDiskCache.directory();
        final file = ImageDiskCache._fileFor(dir, ImageDiskCache.keyFor(uri));
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          return _CacheHitRequest(targetUri: uri, payload: bytes);
        }
        final real = await inner.openUrl(method, uri);
        return _TeeingRequest(real, uri, dir, () => inner.openUrl(method, uri));
      } catch (_) {
        // Any cache-layer problem: straight network, as if this class
        // didn't exist.
      }
    }
    return inner.openUrl(method, uri);
  }
}

/// GET whose bytes live on disk.
class _CacheHitRequest implements HttpClientRequest {
  final Uri targetUri;
  final Uint8List payload;
  bool _finished = false;

  _CacheHitRequest({required this.targetUri, required this.payload});

  @override
  bool bufferOutput = true;

  @override
  int contentLength = 0;

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  final HttpHeaders headers = _CachedHeaders();

  @override
  List<Cookie> get cookies => const [];

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  String get method => 'GET';

  @override
  Uri get uri => targetUri;

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<HttpClientResponse> close() {
    if (_finished) return done;
    _finished = true;
    return Future.value(_CacheHitResponse(payload));
  }

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}

/// The cached bytes, as a response.
class _CacheHitResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List bytes;

  _CacheHitResponse(this.bytes);

  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK (cached)';

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _CachedHeaders();

  @override
  List<Cookie> get cookies => const [];

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  Future<Socket> detachSocket() => throw UnsupportedError('cached response');

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) =>
      throw UnsupportedError('No redirects on cached response');

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> data)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone ?? () {},
      cancelOnError: cancelOnError ?? false,
    );
  }
}

/// Real network GET whose bytes are teed into the cache on the way through.
class _TeeingRequest implements HttpClientRequest {
  final HttpClientRequest delegate;
  final Uri targetUri;
  final Directory cacheDir;

  /// Re-creates the underlying request — used to retry transient
  /// connection/DNS failures exactly once.
  final Future<HttpClientRequest> Function() reopen;

  _TeeingRequest(this.delegate, this.targetUri, this.cacheDir, this.reopen);

  @override
  bool get bufferOutput => delegate.bufferOutput;

  @override
  set bufferOutput(bool value) => delegate.bufferOutput = value;

  @override
  int get contentLength => delegate.contentLength;

  @override
  set contentLength(int value) => delegate.contentLength = value;

  @override
  Encoding get encoding => delegate.encoding;

  @override
  set encoding(Encoding value) => delegate.encoding = value;

  @override
  bool get followRedirects => delegate.followRedirects;

  @override
  set followRedirects(bool value) => delegate.followRedirects = value;

  @override
  int get maxRedirects => delegate.maxRedirects;

  @override
  set maxRedirects(int value) => delegate.maxRedirects = value;

  @override
  bool get persistentConnection => delegate.persistentConnection;

  @override
  set persistentConnection(bool value) => delegate.persistentConnection = value;

  @override
  HttpHeaders get headers => delegate.headers;

  @override
  List<Cookie> get cookies => delegate.cookies;

  @override
  HttpConnectionInfo? get connectionInfo => delegate.connectionInfo;

  @override
  String get method => delegate.method;

  @override
  Uri get uri => targetUri;

  @override
  Future<HttpClientResponse> get done => delegate.done;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => delegate.abort(exception, stackTrace);

  @override
  void add(List<int> data) => delegate.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => delegate.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => delegate.addStream(stream);

  @override
  Future<void> flush() => delegate.flush();

  @override
  void write(Object? object) => delegate.write(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) => delegate.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => delegate.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => delegate.writeln(object);

  @override
  Future<HttpClientResponse> close() async {
    HttpClientResponse response;
    try {
      response = await delegate.close();
    } on SocketException {
      // Transient resolution/connect failure (flaky resolvers drop DDNS
      // lookups intermittently — measured on the owner's network). One
      // retry, then let the error surface.
      final retry = await reopen();
      response = await retry.close();
    }
    try {
      final contentType = response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (response.statusCode == 200 && contentType.startsWith('image/')) {
        final file = File(
          '${cacheDir.path}${Platform.pathSeparator}${ImageDiskCache.keyFor(targetUri)}.img',
        );
        final sink = file.openWrite();
        return _TeeingResponse(response, sink, file);
      }
    } catch (_) {
      // Telemetry-only failure: serve the network response untouched.
    }
    return response;
  }
}

/// Streams the network bytes through to the caller AND into the cache file.
class _TeeingResponse extends Stream<List<int>> implements HttpClientResponse {
  final HttpClientResponse delegate;
  final IOSink sink;
  final File file;

  _TeeingResponse(this.delegate, this.sink, this.file);

  @override
  int get statusCode => delegate.statusCode;

  @override
  String get reasonPhrase => delegate.reasonPhrase;

  @override
  int get contentLength => delegate.contentLength;

  @override
  HttpClientResponseCompressionState get compressionState => delegate.compressionState;

  @override
  HttpHeaders get headers => delegate.headers;

  @override
  List<Cookie> get cookies => delegate.cookies;

  @override
  bool get isRedirect => delegate.isRedirect;

  @override
  bool get persistentConnection => delegate.persistentConnection;

  @override
  X509Certificate? get certificate => delegate.certificate;

  @override
  HttpConnectionInfo? get connectionInfo => delegate.connectionInfo;

  @override
  List<RedirectInfo> get redirects => delegate.redirects;

  @override
  Future<Socket> detachSocket() => delegate.detachSocket();

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) =>
      delegate.redirect(method, url, followLoops);

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> data)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return delegate.listen(
      (chunk) {
        try {
          sink.add(chunk);
        } catch (_) {}
        onData?.call(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(sink.close().catchError((_) {}));
        onError?.call(error, stackTrace);
      },
      onDone: () {
        unawaited(sink.close().catchError((_) {}));
        onDone?.call();
      },
      cancelOnError: cancelOnError ?? false,
    );
  }
}

/// Minimal HttpHeaders for cache-hit responses (nothing mutates them; the
/// content type is what image decoding checks).
class _CachedHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void clear() {}

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) {}

  @override
  List<String> operator [](String name) => const [];

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  String? value(String name) {
    if (name.toLowerCase() == HttpHeaders.contentTypeHeader) return 'image/jpeg';
    return null;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  int contentLength = 0;

  @override
  bool persistentConnection = true;

  @override
  bool chunkedTransferEncoding = false;

  @override
  // (HttpHeaders.noFolding is a method on this SDK; nothing needs it.)

  @override
  void noFolding(String name) {}

  @override
  String? host;

  @override
  int? port;

  @override
  DateTime? ifModifiedSince;

  @override
  DateTime? date;

  @override
  DateTime? expires;

  @override
  ContentType? get contentType => ContentType.parse('image/jpeg');

  @override
  set contentType(ContentType? value) {}
}

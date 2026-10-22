import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/download_state.dart';
import 'music_repository.dart';

/// Low-level Subsonic/OpenSubsonic REST client — Navidrome implements this
/// API, so this is what actually talks to the server. Nothing here knows
/// about Shuro's app models; [NavidromeMusicRepository] maps the raw JSON
/// this returns onto [Song]/[Album]/[Artist].
///
/// Auth is token-based per the Subsonic spec: a random salt is generated
/// once per client instance, and every request's token is
/// md5(password + salt) — the plaintext password is never sent on the
/// wire. Every request also carries the standard `u`/`t`/`s`/`v`/`c`/`f`
/// query params.
class NavidromeApiClient {
  factory NavidromeApiClient({
    required String baseUrl,
    required String username,
    required String password,
    http.Client? httpClient,
  }) {
    final salt = _generateSalt();
    final token = _computeToken(password, salt);
    return NavidromeApiClient._(
      baseUrl: _normalizeBaseUrl(baseUrl),
      username: username,
      salt: salt,
      token: token,
      httpClient: httpClient ?? http.Client(),
    );
  }

  NavidromeApiClient._({
    required this.baseUrl,
    required this.username,
    required String salt,
    required String token,
    required http.Client httpClient,
  })  : _salt = salt,
        _token = token,
        _httpClient = httpClient;

  /// Subsonic API version this client speaks. Navidrome accepts older
  /// clients too, but this is a recent, well-supported version.
  static const String _apiVersion = '1.16.1';
  static const String _clientId = 'shuro';

  final String baseUrl;
  final String username;
  final http.Client _httpClient;
  final String _salt;
  final String _token;

  static String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _computeToken(String password, String salt) {
    return md5.convert(utf8.encode('$password$salt')).toString();
  }

  static String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    // Strip every trailing slash, but never eat the `://` of the scheme
    // itself. A leftover slash would build `//rest/...`, which Navidrome
    // answers with a redirect to its web UI instead of the API.
    while (trimmed.endsWith('/') && !trimmed.endsWith('://')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _buildUri(String method, Map<String, String> params) {
    final query = {
      'u': username,
      't': _token,
      's': _salt,
      'v': _apiVersion,
      'c': _clientId,
      'f': 'json',
      ...params,
    };
    return Uri.parse('$baseUrl/rest/$method.view').replace(queryParameters: query);
  }

  /// A plain URL (with auth params baked in) for streaming [songId]'s
  /// audio. Subsonic doesn't require a separate round-trip for this — the
  /// URL itself, once built, is directly playable by an HTTP-capable
  /// audio player.
  ///
  /// [quality] controls transcoding, not just a label in Settings:
  /// [StreamingQuality.original] sends `format=raw`, the Subsonic/
  /// OpenSubsonic signal to skip transcoding entirely and serve the
  /// source file's own bytes — genuinely "pure" audio, not a bitrate-capped
  /// re-encode (Navidrome, like most Subsonic servers, otherwise applies
  /// its own server-side default transcode to every stream regardless of
  /// what the client wants, which is what made every quality setting here
  /// decorative before this). Anything else sends `maxBitRate` and lets
  /// the server pick its own transcode format, same as the Subsonic
  /// reference clients do for a capped-quality stream.
  String streamUrl(String songId, {StreamingQuality quality = StreamingQuality.original}) {
    final params = <String, String>{'id': songId};
    switch (quality) {
      case StreamingQuality.original:
        params['format'] = 'raw';
      case StreamingQuality.high:
        params['maxBitRate'] = '320';
      case StreamingQuality.medium:
        params['maxBitRate'] = '160';
      case StreamingQuality.low:
        params['maxBitRate'] = '96';
    }
    return _buildUri('stream', params).toString();
  }

  /// A plain URL for fetching cover art, suitable for `NetworkImage`.
  String coverArtUrl(String coverArtId, {int size = 500}) =>
      _buildUri('getCoverArt', {'id': coverArtId, 'size': '$size'}).toString();

  /// Verifies the server is reachable and the credentials are valid.
  Future<void> ping() async {
    final response = await _get('ping', {});
    _checkOk(response);
  }

  Future<List<Map<String, dynamic>>> getArtists() async {
    final response = await _get('getArtists', {});
    final body = _checkOk(response);
    final artists = <Map<String, dynamic>>[];
    final index = body['artists']?['index'] as List<dynamic>? ?? const [];
    for (final group in index) {
      final items = group['artist'] as List<dynamic>? ?? const [];
      for (final a in items) {
        artists.add(a as Map<String, dynamic>);
      }
    }
    return artists;
  }

  /// Fetches the album list in pages of [pageSize], newest-added first
  /// (so `AppState.recentlyAddedSongs/Albums` is accurate for free,
  /// without a separate request), stopping once a page comes back short
  /// (or after [maxPages], as a hard safety cap so a misbehaving server
  /// can't cause an unbounded loop).
  Future<List<Map<String, dynamic>>> getAllAlbums({int pageSize = 500, int maxPages = 20}) async {
    final albums = <Map<String, dynamic>>[];
    for (var page = 0; page < maxPages; page++) {
      final response = await _get('getAlbumList2', {
        'type': 'newest',
        'size': '$pageSize',
        'offset': '${page * pageSize}',
      });
      final body = _checkOk(response);
      final batch = body['albumList2']?['album'] as List<dynamic>? ?? const [];
      if (batch.isEmpty) break;
      albums.addAll(batch.cast<Map<String, dynamic>>());
      if (batch.length < pageSize) break;
    }
    return albums;
  }

  /// Fetches one album's detail, including its song list (`song[]`).
  Future<Map<String, dynamic>> getAlbum(String albumId) async {
    final response = await _get('getAlbum', {'id': albumId});
    final body = _checkOk(response);
    return body['album'] as Map<String, dynamic>? ?? const {};
  }

  /// OpenSubsonic's `getLyricsBySongId` extension — returns whatever
  /// lyrics the server already extracted from [songId]'s own file tags
  /// (ID3 `USLT`/`SYLT`, Vorbis comments, etc.), synced when the file
  /// embeds synced lyrics. Navidrome supports this; plenty of other
  /// Subsonic-ish servers don't, so this treats "unsupported extension,"
  /// "HTTP error," and "nothing embedded for this track" all the same
  /// way — null — rather than surfacing any of them as a hard failure
  /// that would stop the LRCLIB fallback from running.
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async {
    try {
      final response = await _get('getLyricsBySongId', {'id': songId});
      final body = _checkOk(response);
      return body['lyricsList'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// A self-hosted server on a home LAN (the common case for Shuro) drops
  /// a request far more often than a hosted one would — a phone roaming
  /// between Wi-Fi and mobile data, a router hiccup, the server machine
  /// briefly asleep. One silent retry after a short delay absorbs that
  /// class of transient failure instead of surfacing it as a hard error
  /// on the first blip; a genuinely-down server or a real HTTP/auth
  /// error still fails normally; and retrying is skipped entirely once a
  /// deadline has already been missed (see [_get]'s timeout), since
  /// trying again straight after a 15s timeout would just double the wait
  /// for no benefit.
  Future<http.Response> _getOnce(String method, Map<String, String> params) {
    return _httpClient.get(_buildUri(method, params)).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _get(String method, Map<String, String> params) async {
    try {
      return await _getOnce(method, params);
    } on TimeoutException catch (e) {
      throw MusicRepositoryException('The server took too long to respond: $e', MusicRepositoryFailure.unreachable);
    } on SocketException catch (_) {
      // Likely transient (network handoff, router blip) — worth one retry
      // before giving up.
      try {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return await _getOnce(method, params);
      } catch (e) {
        throw MusicRepositoryException('Could not reach the server: $e', MusicRepositoryFailure.unreachable);
      }
    } catch (e) {
      throw MusicRepositoryException('Could not reach the server: $e', MusicRepositoryFailure.unreachable);
    }
  }

  /// Parses a `subsonic-response` envelope, returning its body on
  /// `status: "ok"` and throwing a classified [MusicRepositoryException]
  /// otherwise.
  Map<String, dynamic> _checkOk(http.Response response) {
    if (response.statusCode != 200) {
      throw MusicRepositoryException(
        'Server returned HTTP ${response.statusCode}.',
        MusicRepositoryFailure.unreachable,
      );
    }
    Map<String, dynamic> decoded;
    try {
      decoded = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      final looksLikeWebPage = response.body.trimLeft().startsWith('<');
      throw MusicRepositoryException(
        looksLikeWebPage
            ? 'The server answered with a web page instead of the Subsonic '
                'API. Check the server address — it should be the Navidrome '
                'root (for example http://192.168.1.10:4533) with no extra '
                'path after it.'
            : 'Unexpected response from server.',
        MusicRepositoryFailure.unknown,
      );
    }
    final envelope = decoded['subsonic-response'] as Map<String, dynamic>?;
    if (envelope == null) {
      throw MusicRepositoryException('Unexpected response shape from server.', MusicRepositoryFailure.unknown);
    }
    if (envelope['status'] == 'ok') return envelope;

    final error = envelope['error'] as Map<String, dynamic>?;
    final code = error?['code'];
    final message = (error?['message'] as String?) ?? 'The server rejected the request.';
    // Subsonic error codes 40/41 are auth failures (wrong credentials /
    // token); everything else that still reached us with a parseable
    // envelope is treated as unknown rather than unreachable.
    if (code == 40 || code == 41) {
      throw MusicRepositoryException(message, MusicRepositoryFailure.invalidCredentials);
    }
    throw MusicRepositoryException(message, MusicRepositoryFailure.unknown);
  }

  void dispose() {
    _httpClient.close();
  }
}

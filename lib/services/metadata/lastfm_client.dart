import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../app_info.dart';

/// Last.fm credentials and the request-signing rules.
///
/// **How this app is meant to be configured.** Last.fm requires an *application*
/// key and shared secret, which belong to one API account the operator creates
/// once (https://www.last.fm/api/account/create, behind a Last.fm login). Every
/// end user then authorizes *the app* through their own Last.fm account — they
/// never see or paste a key. That is the model the user asked for: no per-user
/// API key, just an authorization step.
///
/// Supply the two values at build time, so no secret is committed to source:
///
/// ```
/// flutter build apk --dart-define=LASTFM_API_KEY=... --dart-define=LASTFM_API_SECRET=...
/// ```
///
/// With neither set, everything Last.fm-related reports "not configured" and
/// the app behaves exactly as before — scrobbling is an enhancement, never a
/// prerequisite ([isConfigured] is what the UI checks).
class LastFmConfig {
  LastFmConfig._();

  static const String apiKey = String.fromEnvironment('LASTFM_API_KEY');
  static const String sharedSecret = String.fromEnvironment('LASTFM_API_SECRET');

  static bool get isConfigured => apiKey.isNotEmpty && sharedSecret.isNotEmpty;

  /// Last.fm's own docs show only `http://` for the API root; the HTTPS endpoint
  /// answers identically (verified live during research) and signing happens over
  /// TLS here regardless. Noted because the contract flags it as undocumented.
  static const String apiRoot = 'https://ws.audioscrobbler.com/2.0/';

  /// The user-facing authorization page. The contract records one unresolved
  /// detail — the desktop docs print `;` between `api_key` and `token`, while the
  /// web-callback docs use `&` (and community clients use `&`). `&` is used here;
  /// if Last.fm ever rejects it, this single line changes to `;`.
  static String authorizationUrl(String token) =>
      'https://www.last.fm/api/auth/?api_key=${Uri.encodeQueryComponent(apiKey)}&token=${Uri.encodeQueryComponent(token)}';

  /// Last.fm asks for an identifiable User-Agent the same way MusicBrainz does.
  static const Map<String, String> headers = {
    'User-Agent': 'Shuro/$kAppVersion ( self-hosted Navidrome client )',
  };
}

/// Why a Last.fm call didn't succeed, in the categories the docs say to act on:
/// retry later, re-authenticate, or the request was malformed.
enum LastFmFailure {
  /// Not configured (no API key), or the user hasn't authorized yet.
  notConfigured,

  /// Error 9 — the session key is no longer valid; the user must re-authorize.
  needsReauthorization,

  /// Errors 11/16 (and a transport failure): worth retrying later, and the
  /// scrobble should be kept in the local cache rather than dropped.
  retryable,

  /// Error 29, or a 5xx: back off rather than hammering.
  rateLimited,

  /// Anything else — the request itself was wrong, so retrying won't help.
  rejected,
}

class LastFmResult {
  final bool ok;
  final LastFmFailure? failure;
  final String? detail;

  /// The parsed body, when the call succeeded — e.g. the token or session key.
  final Map<String, dynamic>? body;

  const LastFmResult.ok(this.body, {this.detail}) : ok = true, failure = null;
  const LastFmResult.failed(this.failure, {this.detail}) : ok = false, body = null;

  String? get sessionKey => body?['session'] is Map<String, dynamic> ? (body!['session'] as Map<String, dynamic>)['key'] as String? : null;
}

/// A read/write client for the handful of Last.fm methods this app needs.
///
/// Signing follows the documented algorithm exactly (contract §3): every
/// parameter *sent*, ordered alphabetically by name, concatenated as
/// `name`+`value` with no separators, `format` and `callback` excluded, the
/// shared secret appended, and the whole string MD5-hashed to 32 hex characters
/// ([signingString] is exposed so this is testable without a network).
class LastFmClient {
  LastFmClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// The exact pre-hash string, per the documented rule. Kept public because it
  /// is the part worth unit-testing (parameter selection and ordering) rather
  /// than the hash itself.
  static String signingString(Map<String, String> params, String secret) {
    // `format` and `callback` are the two the docs name as excluded; `api_sig`
    // is necessarily absent because it is the output. Array-notation keys must
    // sort by ASCII, which a plain string sort of the keys does.
    final keys = params.keys.where((k) => k != 'format' && k != 'callback' && k != 'api_sig').toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);
    return buffer.toString();
  }

  /// 32-character lowercase hex MD5, which is what Last.fm expects.
  static String sign(Map<String, String> params, String secret) =>
      crypto.md5.convert(utf8.encode(signingString(params, secret))).toString();

  // --- the desktop/browser authorization flow -------------------------------

  /// Step 1: an unauthorized token.
  Future<LastFmResult> requestToken() {
    if (!LastFmConfig.isConfigured) return Future.value(const LastFmResult.failed(LastFmFailure.notConfigured, detail: 'No Last.fm application key is configured.'));
    return _get({'method': 'auth.getToken'});
  }

  /// Step 3: exchange the user-authorized token for a session key, which the
  /// docs describe as having an infinite lifetime. Store it; the user can revoke
  /// it from their Last.fm settings at any time (which surfaces as error 9).
  Future<LastFmResult> createSession(String token) {
    if (!LastFmConfig.isConfigured) return Future.value(const LastFmResult.failed(LastFmFailure.notConfigured, detail: 'No Last.fm application key is configured.'));
    return _get({'method': 'auth.getSession', 'token': token});
  }

  // --- playback reporting ---------------------------------------------------

  Future<LastFmResult> updateNowPlaying({
    required String artist,
    required String track,
    String? album,
    String? albumArtist,
    Duration? duration,
    int? trackNumber,
    String? musicBrainzId,
    required String sessionKey,
  }) {
    if (!LastFmConfig.isConfigured) return Future.value(const LastFmResult.failed(LastFmFailure.notConfigured, detail: 'No Last.fm application key is configured.'));
    return _post({
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      if (album != null && album.isNotEmpty) 'album': album,
      if (albumArtist != null && albumArtist.isNotEmpty) 'albumArtist': albumArtist,
      if (duration != null) 'duration': '${duration.inSeconds}',
      if (trackNumber != null) 'trackNumber': '$trackNumber',
      if (musicBrainzId != null && musicBrainzId.isNotEmpty) 'mbid': musicBrainzId,
      'sk': sessionKey,
    });
  }

  /// `track.scrobble`, one call per batch of at most 50 — the documented limit.
  Future<LastFmResult> scrobble(List<ScrobbleEntry> entries, {required String sessionKey}) {
    if (!LastFmConfig.isConfigured) return Future.value(const LastFmResult.failed(LastFmFailure.notConfigured, detail: 'No Last.fm application key is configured.'));
    if (entries.isEmpty) return Future.value(const LastFmResult.ok(const {}));
    final batch = entries.take(LastFmClient.maxBatchSize).toList();

    final params = <String, String>{'method': 'track.scrobble', 'sk': sessionKey};
    // Array notation: artist[i], track[i], timestamp[i] … and the keys must sort
    // ASCII-wise, which signingString already does.
    for (var i = 0; i < batch.length; i++) {
      final entry = batch[i];
      params['artist[$i]'] = entry.artist;
      params['track[$i]'] = entry.track;
      // "The time the track started playing" — this is the documented meaning,
      // and it is why the entry carries startedAt rather than a completion time.
      params['timestamp[$i]'] = '${entry.startedAt.millisecondsSinceEpoch ~/ 1000}';
      if (entry.album != null && entry.album!.isNotEmpty) params['album[$i]'] = entry.album!;
      if (entry.albumArtist != null && entry.albumArtist!.isNotEmpty) params['albumArtist[$i]'] = entry.albumArtist!;
      if (entry.duration != null) params['duration[$i]'] = '${entry.duration!.inSeconds}';
      if (entry.trackNumber != null) params['trackNumber[$i]'] = '${entry.trackNumber}';
      if (entry.musicBrainzId != null && entry.musicBrainzId!.isNotEmpty) params['mbid[$i]'] = entry.musicBrainzId!;
    }
    return _post(params);
  }

  /// Documented maximum per request.
  static const int maxBatchSize = 50;

  /// Splits [entries] into scrobble-legal batches, in order.
  static List<List<ScrobbleEntry>> chunk(List<ScrobbleEntry> entries) {
    final chunks = <List<ScrobbleEntry>>[];
    for (var i = 0; i < entries.length; i += maxBatchSize) {
      chunks.add(entries.sublist(i, i + maxBatchSize > entries.length ? entries.length : i + maxBatchSize));
    }
    return chunks;
  }

  // --- transport ------------------------------------------------------------

  Future<LastFmResult> _get(Map<String, String> params) => _send(params, post: false);

  Future<LastFmResult> _post(Map<String, String> params) => _send(params, post: true);

  Future<LastFmResult> _send(Map<String, String> params, {required bool post}) async {
    final signed = <String, String>{
      ...params,
      'api_key': LastFmConfig.apiKey,
      'format': 'json',
    };
    signed['api_sig'] = sign(signed, LastFmConfig.sharedSecret);

    try {
      final uri = Uri.parse(LastFmConfig.apiRoot);
      final response = post
          ? await _client.post(uri, headers: LastFmConfig.headers, body: signed).timeout(const Duration(seconds: 12))
          : await _client.get(uri.replace(queryParameters: signed), headers: LastFmConfig.headers).timeout(const Duration(seconds: 12));

      // The docs are explicit that the status code alone decides nothing:
      // "No matter what the HTTP status code is, you must inspect the content of
      // the response." So the body is parsed first and the code is a hint.
      Map<String, dynamic>? body;
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = null;
      }

      if (body != null && body['error'] != null) {
        return LastFmResult.failed(_classify((body['error'] as num).toInt()), detail: body['message'] as String?);
      }
      if (body == null) {
        return LastFmResult.failed(
          response.statusCode == 429 || response.statusCode >= 500 ? LastFmFailure.rateLimited : LastFmFailure.rejected,
          detail: 'Last.fm returned an unreadable response (HTTP ${response.statusCode}).',
        );
      }
      return LastFmResult.ok(body);
    } catch (error) {
      // Transport-level failure: keep the scrobble and try again later.
      return LastFmResult.failed(LastFmFailure.retryable, detail: 'Could not reach Last.fm ($error).');
    }
  }

  /// Error-code categories the docs call out: 9 needs re-authorization, 11/16
  /// are retryable, 29 is the rate limit, everything else means the request was
  /// malformed and must not be retried.
  static LastFmFailure _classify(int code) {
    switch (code) {
      case 9:
        return LastFmFailure.needsReauthorization;
      case 11:
      case 16:
        return LastFmFailure.retryable;
      case 29:
        return LastFmFailure.rateLimited;
      default:
        return LastFmFailure.rejected;
    }
  }
}

/// One play, in the shape Last.fm wants.
class ScrobbleEntry {
  final String artist;
  final String track;
  final DateTime startedAt;
  final String? album;
  final String? albumArtist;
  final Duration? duration;
  final int? trackNumber;
  final String? musicBrainzId;

  const ScrobbleEntry({
    required this.artist,
    required this.track,
    required this.startedAt,
    this.album,
    this.albumArtist,
    this.duration,
    this.trackNumber,
    this.musicBrainzId,
  });

  Map<String, dynamic> toJson() => {
        'artist': artist,
        'track': track,
        'startedAt': startedAt.millisecondsSinceEpoch,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (musicBrainzId != null) 'mbid': musicBrainzId,
      };

  static ScrobbleEntry? fromJson(Map<String, dynamic> json) {
    final artist = json['artist'] as String?;
    final track = json['track'] as String?;
    final startedAt = json['startedAt'] as int?;
    if (artist == null || track == null || startedAt == null) return null;
    return ScrobbleEntry(
      artist: artist,
      track: track,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
      duration: json['durationMs'] == null ? null : Duration(milliseconds: json['durationMs'] as int),
      trackNumber: json['trackNumber'] as int?,
      musicBrainzId: json['mbid'] as String?,
    );
  }
}

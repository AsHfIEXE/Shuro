import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../models/lyrics.dart';
import 'lyrics_parser.dart';

/// Why a lyrics lookup produced nothing. Kept distinct — instead of one
/// anonymous "couldn't load lyrics" — so the screen can tell the user
/// something true and actionable: a rate-limited lookup clears up in a
/// minute, a missing match never will, and a rejected request means the
/// request itself was wrong.
enum LyricsFailureKind {
  /// LRCLIB answered, with no record for this track (HTTP 404 / empty search).
  notFound,

  /// The record exists but is explicitly instrumental — there is nothing to
  /// display, and that's a final answer, not a failure.
  instrumental,

  /// HTTP 429 (or 503): the app must wait. [LyricsLookupResult.retryAfter]
  /// carries the server's own `Retry-After` value.
  rateLimited,

  /// The request was refused or the response wasn't usable JSON (HTTP 4xx/5xx,
  /// or a non-JSON body — LRCLIB returns plain text for malformed parameters).
  rejected,

  /// Couldn't reach the server at all (offline, DNS, timeout).
  network,
}

class LyricsLookupResult {
  final LyricsTrack? track;
  final LyricsFailureKind? failure;

  /// How long the server asked this client to wait, when it said so.
  final Duration? retryAfter;

  /// Short, user-facing explanation — including which record was matched and
  /// how close its duration was, so a near-miss is visible rather than silent.
  final String? detail;

  const LyricsLookupResult.found(this.track, {this.detail}) : failure = null, retryAfter = null;
  const LyricsLookupResult.miss(this.failure, {this.retryAfter, this.detail}) : track = null;

  bool get isFound => track != null;
}

/// A classified failure thrown internally and converted to a
/// [LyricsLookupResult] at the boundary — so no exception escapes this class.
class _LyricsException implements Exception {
  final LyricsFailureKind kind;
  final String message;
  final Duration? retryAfter;
  const _LyricsException(this.kind, this.message, {this.retryAfter});
}

/// Real lyrics, fetched from LRCLIB (lrclib.net) — the one free, keyless,
/// public lyrics API that can actually answer for a self-hosted library.
///
/// What this class is careful about, and why:
///  - **Identifying the client is required.** LRCLIB's docs state that
///    clients must identify themselves via `User-Agent` (or `Lrclib-Client` /
///    `X-User-Agent`) — see lrclib.net/docs. A request with none of those is
///    exactly the kind of traffic their edge is entitled to refuse, which is
///    one of the ways this feature "stopped working" before.
///  - **429 and 503 are directives, not errors.** The docs require honoring
///    `Retry-After`; ignoring it risks a temporary ban. Request spacing is
///    kept at [_minSpacing] between calls, as their guidance asks.
///  - **Not every response is JSON.** Malformed parameters return plain text
///    before the API layer is even reached, so the content type is checked
///    before decoding; `json.decode` on an error page is a crash, not a
///    "no lyrics" result.
///  - **The best match wins, not the first.** The search fallback used to take
///    `results.first`, which is how a completely different recording's lyrics
///    (and its timings) end up attached to the song you're playing. See
///    [pickBestCandidate]/[trackFromRecord] in lyrics_parser.dart.
///
/// Provider note, verified against their published docs: Spicy Lyrics' own
/// API (`GET https://api.spicylyrics.org/v1/lyrics/{trackId}`, `Authorization:
/// Bearer <key>`) is key-protected *and* addressed by **Spotify** track IDs — a
/// self-hosted Navidrome library doesn't carry those, so there is no honest way
/// to call it from here. The "Spicy-style" setting is therefore a rendering
/// choice (word-level karaoke) over data that does exist: LRCLIB's word-synced
/// Lyricsfile and enhanced `.lrc`, plus embedded synced tags.
class LyricsService {
  LyricsService._();

  static const String _baseUrl = 'https://lrclib.net/api';
  static const Duration _timeout = Duration(seconds: 10);

  /// Minimum spacing between outbound requests. LRCLIB asks clients to leave
  /// 200–500 ms between calls.
  static const Duration _minSpacing = Duration(milliseconds: 300);

  /// A client identifier. LRCLIB's docs ask for the application name plus a
  /// version **and** a homepage/project link or an email address; Shuro ships
  /// without a public project URL, so this identifies the app and its version
  /// and is the single place to add a link or contact once one exists.
  static final String clientIdentifier = 'Shuro/$kAppVersion (self-hosted Navidrome client)';

  static final Map<String, String> _headers = {
    'User-Agent': clientIdentifier,
    // LRCLIB's documented alternatives to User-Agent, sent as well so the
    // client is identifiable even behind a proxy that rewrites User-Agent.
    'Lrclib-Client': clientIdentifier,
    'X-User-Agent': clientIdentifier,
    'Accept': 'application/json',
  };

  static final http.Client _client = http.Client();
  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime? _blockedUntil;

  /// Lookups are cached per track+metadata: the lyrics screen used to re-issue
  /// up to three HTTP requests every single time it was opened, for the same
  /// track, which is both slow and exactly the behaviour a rate limiter is for.
  static final Map<String, LyricsLookupResult> _cache = {};
  static const int _cacheLimit = 80;

  /// Identical lookups fired at the same moment (double-tapping, two screens)
  /// share one request instead of racing each other.
  static final Map<String, Future<LyricsLookupResult>> _inFlight = {};

  /// Fetches lyrics for one track, with the whole lookup policy in one place:
  /// exact match first, then a ranked search fallback.
  ///
  /// Local imports should not be passed here — their "artist" is a placeholder
  /// ("Local file"), not real metadata, so there's nothing honest to search by.
  static Future<LyricsLookupResult> lookup({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) {
    final key = _cacheKey(title: title, artist: artist, album: album, duration: duration);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _lookupUncached(title: title, artist: artist, album: album, duration: duration).then((result) {
      _remember(key, result);
      return result;
    }).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  static Future<LyricsLookupResult> _lookupUncached({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) async {
    final blockedUntil = _blockedUntil;
    if (blockedUntil != null) {
      final remaining = blockedUntil.difference(DateTime.now());
      if (remaining > Duration.zero) {
        return LyricsLookupResult.miss(
          LyricsFailureKind.rateLimited,
          retryAfter: remaining,
          detail: 'LRCLIB asked this app to wait ${remaining.inSeconds}s before trying again.',
        );
      }
      _blockedUntil = null;
    }

    try {
      final exact = await _requestGet(title: title, artist: artist, album: album, duration: duration);
      if (exact != null) {
        final delta = _durationOf(exact) != null ? (_durationOf(exact)! - duration).abs() : null;
        return _fromRecord(exact, duration: duration, matchDelta: delta);
      }

      final candidates = await _requestSearch(title: title, artist: artist);
      if (candidates.isEmpty) return const LyricsLookupResult.miss(LyricsFailureKind.notFound);

      final best = pickBestCandidate(candidates, title: title, artist: artist, album: album, duration: duration);
      if (best == null) return const LyricsLookupResult.miss(LyricsFailureKind.notFound);

      final result = _fromRecord(best.record, duration: duration, matchDelta: best.delta);
      if (!result.isFound) return result;
      if (!best.timingsTrustworthy && result.track!.type != LyricsSyncType.static_) {
        // Defensive: timings from a recording of a different length must never
        // drive the highlight. trackFromRecord already downgrades these, so
        // reaching here means something unexpected — fall back to plain text.
        final plain = (best.record['plainLyrics'] as String?)?.trim() ?? '';
        if (plain.isEmpty) return const LyricsLookupResult.miss(LyricsFailureKind.notFound);
        return LyricsLookupResult.found(
          LyricsTrack(
            type: LyricsSyncType.static_,
            source: LyricsSource.lrclib,
            lines: staticLines(plain),
            matchedTitle: best.record['trackName'] as String?,
            matchedArtist: best.record['artistName'] as String?,
            matchedDuration: _durationOf(best.record),
          ),
          detail: 'Matched ${best.label}, but its length differs by ${best.delta.inSeconds}s — shown unsynced.',
        );
      }
      return result;
    } on _LyricsException catch (e) {
      if (e.kind == LyricsFailureKind.rateLimited && e.retryAfter != null) {
        _blockedUntil = DateTime.now().add(e.retryAfter!);
      }
      return LyricsLookupResult.miss(e.kind, retryAfter: e.retryAfter, detail: e.message);
    } catch (e) {
      return LyricsLookupResult.miss(LyricsFailureKind.network, detail: "Couldn't load lyrics ($e).");
    }
  }

  static LyricsLookupResult _fromRecord(
    Map<String, dynamic> record, {
    required Duration duration,
    Duration? matchDelta,
  }) {
    if (record['instrumental'] == true) {
      return const LyricsLookupResult.miss(
        LyricsFailureKind.instrumental,
        detail: 'LRCLIB marks this track as instrumental.',
      );
    }
    final track = trackFromRecord(record, duration: duration, source: LyricsSource.lrclib, matchDelta: matchDelta);
    if (track == null) return const LyricsLookupResult.miss(LyricsFailureKind.notFound);

    final label = '${track.matchedTitle ?? '?'} — ${track.matchedArtist ?? '?'}';
    final delta = matchDelta ?? (track.matchedDuration != null ? (track.matchedDuration! - duration).abs() : null);
    final precision = switch (track.type) {
      LyricsSyncType.syllable => 'word-synced',
      LyricsSyncType.line => 'line-synced',
      LyricsSyncType.static_ => 'unsynced text',
    };
    final detail = delta == null
        ? 'Matched $label ($precision).'
        : 'Matched $label ($precision, ${delta.inSeconds}s length difference).';
    return LyricsLookupResult.found(track, detail: detail);
  }

  /// LRCLIB's exact lookup: it matches on title, artist, album and duration,
  /// and its own rule is that the duration must be within a couple of seconds.
  /// A 404 here is a normal miss (`null`), not an error.
  static Future<Map<String, dynamic>?> _requestGet({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) async {
    final params = <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (album != null && album.trim().isNotEmpty) 'album_name': album.trim(),
      'duration': '${duration.inSeconds}',
    };
    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: params);
    final decoded = await _getJson(uri);
    if (decoded == null) return null;
    if (decoded is! Map<String, dynamic>) {
      throw const _LyricsException(LyricsFailureKind.rejected, 'LRCLIB returned an unexpected record shape.');
    }
    return decoded;
  }

  static Future<List<Map<String, dynamic>>> _requestSearch({required String title, required String artist}) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {'track_name': title, 'artist_name': artist});
    final decoded = await _getJson(uri);
    if (decoded == null) return const [];
    if (decoded is! List) {
      throw const _LyricsException(LyricsFailureKind.rejected, 'LRCLIB returned an unexpected search shape.');
    }
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  /// One GET with the whole transport policy applied: spacing, timeouts,
  /// classification of status codes, and a content-type check before decoding.
  /// Returns null only for "matched nothing" (HTTP 404).
  static Future<dynamic> _getJson(Uri uri) async {
    await _throttle();

    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw const _LyricsException(LyricsFailureKind.network, 'LRCLIB took too long to answer.');
    } catch (_) {
      throw const _LyricsException(LyricsFailureKind.network, "Couldn't reach LRCLIB — check your connection.");
    }

    final status = response.statusCode;
    if (status == 404) return null;
    if (status == 429 || status == 503) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? (status == 503 ? 1 : 60);
      throw _LyricsException(
        LyricsFailureKind.rateLimited,
        status == 429
            ? 'LRCLIB rate-limited this app — waiting ${seconds}s before retrying.'
            : 'LRCLIB is busy right now — trying again in ${seconds}s.',
        retryAfter: Duration(seconds: seconds),
      );
    }
    if (status != 200) {
      throw _LyricsException(
        LyricsFailureKind.rejected,
        'LRCLIB refused the request (HTTP $status).',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('json')) {
      // Documented behavior: malformed/missing parameters are rejected by the
      // framework *before* the API, returning plain text.
      throw const _LyricsException(
        LyricsFailureKind.rejected,
        'LRCLIB returned a non-JSON response — the request parameters were rejected.',
      );
    }

    try {
      return json.decode(response.body);
    } catch (_) {
      throw const _LyricsException(LyricsFailureKind.rejected, 'LRCLIB returned an unreadable response.');
    }
  }

  /// Keeps outbound requests sequential with a small gap between them, as
  /// LRCLIB's docs ask clients to do.
  static Future<void> _throttle() async {
    final wait = _lastRequestAt.add(_minSpacing).difference(DateTime.now());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastRequestAt = DateTime.now();
  }

  static Duration? _durationOf(Map<String, dynamic> record) {
    final seconds = (record['duration'] as num?)?.toDouble();
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static String _cacheKey({required String title, required String artist, String? album, required Duration duration}) =>
      '${title.toLowerCase()}|${artist.toLowerCase()}|${(album ?? '').toLowerCase()}|${duration.inSeconds}';

  static void _remember(String key, LyricsLookupResult result) {
    // Only settle outcomes that won't change on their own. A network blip or a
    // rate limit must stay retryable.
    final cacheable = result.isFound ||
        result.failure == LyricsFailureKind.notFound ||
        result.failure == LyricsFailureKind.instrumental;
    if (!cacheable) return;
    _cache[key] = result;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Parses an OpenSubsonic `getLyricsBySongId` response (the `lyricsList`
  /// object, already unwrapped from the envelope) into a [LyricsTrack] — the
  /// embedded-lyrics counterpart to [lookup]. A server can offer several
  /// `structuredLyrics` entries (different languages); a synced one is
  /// preferred. Embedded text with no `start` values (which the spec says must
  /// be omitted when an entry isn't synced) becomes [LyricsSyncType.static_]
  /// rather than being given invented timings.
  static LyricsTrack? parseEmbedded(Map<String, dynamic> lyricsList, {required Duration songDuration}) =>
      parseEmbeddedStructured(lyricsList, songDuration: songDuration);
}

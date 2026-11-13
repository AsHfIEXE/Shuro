import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../models/lyrics.dart';
import 'image_disk_cache.dart' show rawHttpClient;
import 'lyrics_service.dart';
import 'ttml_parser.dart';

/// lrc.red lyrics provider: search -> ISRC -> metadata -> TTML -> validation.
///
/// Careful about:
///  - **Identity.** Every request carries Shuro's name, version, project link
///    and contact (lrc.red's terms ask for it).
///  - **Matching, not first-hit.** A candidate must agree on title, artist and
///    duration ([LrcRedMatcher]); a "Starboy" by another artist is rejected.
///  - **Real timing only.** The caller decides what to do with a line-only
///    result; this class never relabels it as word timing.
///  - **429 is a directive.** `Retry-After` blocks further calls until it
///    passes. Requests are spaced and de-duplicated, results cached.
class LrcRedService {
  LrcRedService._();

  static const String _base = 'https://lrc.red';
  // Short budgets: lrc.red must never hold up lyrics that LRCLIB already has
  // (the resolver also runs both at once), so a slow answer is a miss.
  static const Duration _searchTimeout = Duration(seconds: 4);
  static const Duration _fileTimeout = Duration(seconds: 5);
  static const Duration _minSpacing = Duration(milliseconds: 200);

  static String get userAgent =>
      'Shuro/$kAppVersion (https://github.com/ashfiexe/Shuro; contact: salahin0ashfi@gmail.com)';

  // X-Client-ID carries the same identity for clients that can't set a
  // User-Agent (lrc.red accepts either).
  static Map<String, String> get _headers =>
      {'User-Agent': userAgent, 'X-Client-ID': userAgent, 'Accept': 'application/json'};

  @visibleForTesting
  static http.Client client = IOClient(rawHttpClient());
  // (Still injectable for tests; the default bypasses the image-cache
  // HTTP wrapper - see rawHttpClient.)

  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime? _blockedUntil;

  // Parsed tracks by ISRC (bounded), negative results (short-lived), and
  // in-flight lookups so two screens share one request chain.
  static final Map<String, LyricsTrack> _byIsrc = {};
  static final Map<String, DateTime> _negative = {};
  static final Map<String, Future<LyricsLookupResult>> _inFlight = {};
  static const int _cacheLimit = 60;
  static const Duration _negativeTtl = Duration(minutes: 10);

  static String trackPageUrl(String isrc) => '$_base/s/$isrc';

  @visibleForTesting
  static void resetForTest() {
    _byIsrc.clear();
    _negative.clear();
    _inFlight.clear();
    _blockedUntil = null;
    _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Future<LyricsLookupResult> lookup({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) {
    final key = '${LrcRedMatcher.normalize(title)}|${LrcRedMatcher.normalize(artist)}|${duration.inSeconds ~/ 3}';
    final neg = _negative[key];
    if (neg != null) {
      if (DateTime.now().isBefore(neg)) return Future.value(const LyricsLookupResult.miss(LyricsFailureKind.notFound));
      _negative.remove(key);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _lookupUncached(title: title, artist: artist, album: album, duration: duration)
        .timeout(const Duration(seconds: 6), onTimeout: () {
      return const LyricsLookupResult.miss(LyricsFailureKind.network,
          detail: 'The lrc.red lookup stalled before finishing.');
    }).then((r) {
      if (!r.isFound && r.failure == LyricsFailureKind.notFound) {
        _negative[key] = DateTime.now().add(_negativeTtl);
      }
      return r;
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
    final blocked = _blockedUntil;
    if (blocked != null) {
      final remaining = blocked.difference(DateTime.now());
      if (remaining > Duration.zero) {
        return LyricsLookupResult.miss(LyricsFailureKind.rateLimited,
            retryAfter: remaining, detail: 'lrc.red asked this app to wait ${remaining.inSeconds}s.');
      }
      _blockedUntil = null;
    }

    try {
      var found = await _search('$title $artist');
      // Nothing at all for the combined query: one retry on the title alone
      // (the matcher still insists on the right artist and length).
      if (found.isEmpty) found = await _search(title);
      final ranked = <LrcRedCandidate>[
        for (final c in found)
          if (LrcRedMatcher.accept(c, title: title, artist: artist, album: album, duration: duration)) c,
      ]..sort((a, b) => LrcRedMatcher.score(b, title: title, artist: artist, album: album, duration: duration)
          .compareTo(LrcRedMatcher.score(a, title: title, artist: artist, album: album, duration: duration)));
      if (ranked.isEmpty) return const LyricsLookupResult.miss(LyricsFailureKind.notFound);

      LyricsTrack? fallbackLine;
      // Only the few best candidates are fetched; each is a real request.
      for (final c in ranked.take(2)) {
        final cached = _byIsrc[c.isrc];
        LyricsTrack? track = cached;
        if (track == null) {
          try {
            track = await _fetchTrack(c, duration);
          } on _RateLimited {
            rethrow;
          } on TimeoutException {
            continue;
          } catch (_) {
            continue; // one candidate's file missing must not end the lookup
          }
        }
        if (track == null) continue;
        if (cached == null) _remember(c.isrc, track);
        if (track.hasRealWordSync) {

        }
        fallbackLine ??= track;
      }
      if (fallbackLine != null) {
        return LyricsLookupResult.found(fallbackLine, detail: 'lrc.red has line timing only.');
      }
      return const LyricsLookupResult.miss(LyricsFailureKind.notFound);
    } on _RateLimited catch (e) {
      _blockedUntil = DateTime.now().add(e.retryAfter);
      return LyricsLookupResult.miss(LyricsFailureKind.rateLimited,
          retryAfter: e.retryAfter, detail: 'lrc.red asked this app to wait ${e.retryAfter.inSeconds}s.');
    } on TimeoutException {
      return const LyricsLookupResult.miss(LyricsFailureKind.network);
    } catch (e) {
      // Network errors are retryable and never cached.
      return LyricsLookupResult.miss(LyricsFailureKind.network, detail: "Couldn't reach lrc.red ($e).");
    }
  }

  static void _remember(String isrc, LyricsTrack track) {
    _byIsrc[isrc] = track;
    if (_byIsrc.length > _cacheLimit) _byIsrc.remove(_byIsrc.keys.first);
  }

  static Future<List<LrcRedCandidate>> _search(String q) async {
    final uri = Uri.parse('$_base/search.json').replace(queryParameters: {'q': q});
    final decoded = await _getJson(uri, _searchTimeout);
    return parseSearch(decoded);
  }

  /// Tolerant of the response shape: a bare list, or an object holding the
  /// list under a common key.
  @visibleForTesting
  static List<LrcRedCandidate> parseSearch(dynamic decoded) {
    Iterable<dynamic> items = const [];
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      // Documented shape: {"hits": [...], "next": "p24"}. The others are
      // tolerated in case it ever changes.
      for (final key in const ['hits', 'results', 'tracks', 'items', 'data']) {
        final v = decoded[key];
        if (v is List) {
          items = v;
          break;
        }
      }
    }
    final out = <LrcRedCandidate>[];
    for (final item in items) {
      if (item is! Map) continue;
      final c = LrcRedCandidate.fromJson(item.cast<String, dynamic>());
      if (c != null) out.add(c);
    }
    return out;
  }

  static Future<LyricsTrack?> _fetchTrack(LrcRedCandidate c, Duration duration) async {
    // The TTML URL is derivable from the ISRC, so the separate metadata call
    // (one more round trip) is skipped: the search hit already carries the
    // identity fields and the TTML itself is validated by the parser.
    final body = await _getText(Uri.parse('$_base/s/${c.isrc}.ttml'), _fileTimeout);
    return parseTtml(body, duration: duration, sourceUrl: trackPageUrl(c.isrc))?.withMatch(
      title: c.title,
      artist: c.artist,
      duration: c.duration,
    );
  }

  static Future<void> _space() async {
    final wait = _minSpacing - DateTime.now().difference(_lastRequestAt);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastRequestAt = DateTime.now();
  }

  static Future<http.Response> _get(Uri uri, Duration timeout) async {
    await _space();
    final response = await client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode == 429 || response.statusCode == 503) {
      final secs = int.tryParse(response.headers['retry-after'] ?? '');
      throw _RateLimited(Duration(seconds: (secs ?? 60).clamp(1, 3600)));
    }
    return response;
  }

  static Future<dynamic> _getJson(Uri uri, Duration timeout) async {
    final r = await _get(uri, timeout);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
    return json.decode(utf8.decode(r.bodyBytes));
  }

  static Future<String> _getText(Uri uri, Duration timeout) async {
    final r = await _get(uri, timeout);
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes);
  }
}

class _RateLimited implements Exception {
  final Duration retryAfter;
  const _RateLimited(this.retryAfter);
}

extension on LyricsTrack {
  LyricsTrack withMatch({String? title, String? artist, Duration? duration}) => LyricsTrack(
        type: type,
        source: source,
        lines: lines,
        uploader: uploader,
        maker: maker,
        matchedTitle: title,
        matchedArtist: artist,
        matchedDuration: duration,
        providerOffset: providerOffset,
        wordTimingIsEstimated: wordTimingIsEstimated,
        sourceUrl: sourceUrl,
      );
}

/// One search hit.
class LrcRedCandidate {
  final String isrc;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  const LrcRedCandidate({required this.isrc, required this.title, required this.artist, this.album, this.duration});

  static LrcRedCandidate? fromJson(Map<String, dynamic> j) {
    final isrc = (j['isrc'] ?? j['ISRC'] ?? j['id'])?.toString().trim() ?? '';
    final title = (j['title'] ?? j['trackName'] ?? j['track_name'] ?? j['name'] ?? j['track'])?.toString() ?? '';
    final artistRaw = j['artist'] ?? j['artistName'] ?? j['artist_name'] ?? j['artists'];
    final artist = artistRaw is List ? artistRaw.join(', ') : artistRaw?.toString() ?? '';
    if (isrc.isEmpty || title.isEmpty) return null;
    final d = j['duration'];
    Duration? duration;
    if (d is num) {
      // Seconds in the documented metadata; tolerate milliseconds.
      duration = Duration(milliseconds: (d > 10000 ? d : d * 1000).round());
    }
    return LrcRedCandidate(
      isrc: isrc,
      title: title,
      artist: artist,
      album: j['album']?.toString(),
      duration: duration,
    );
  }
}

/// Recording-identity matching. Weights per the engine plan: title 35 %,
/// artist 35 %, duration 25 %, album 5 %. A candidate must also clear hard
/// floors, so a perfect duration can't rescue the wrong song.
class LrcRedMatcher {
  LrcRedMatcher._();

  static const Duration maxDurationDelta = Duration(seconds: 5);

  static String normalize(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'\((feat|ft|with)\.?[^)]*\)|\[(feat|ft|with)\.?[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'\s*[-–]\s*(\d{4}\s*)?(remaster(ed)?|mono|stereo|single version|radio edit).*$'), ' ');
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 0..1 token similarity: equal strings 1, otherwise a mix of overlap and
  /// containment so "the weeknd" matches "the weeknd, daft punk".
  static double similarity(String a, String b) {
    final x = normalize(a), y = normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    final tx = x.split(' ').toSet(), ty = y.split(' ').toSet();
    final inter = tx.intersection(ty).length;
    if (inter == 0) return 0;
    final jaccard = inter / tx.union(ty).length;
    final containment = inter / (tx.length < ty.length ? tx.length : ty.length);
    return (jaccard * 0.5 + containment * 0.5).clamp(0.0, 1.0);
  }

  static double _durationScore(Duration? candidate, Duration wanted) {
    if (candidate == null) return 0.5; // unknown: neutral, validated later by the TTML
    final delta = (candidate - wanted).abs();
    if (delta <= const Duration(seconds: 1)) return 1;
    if (delta > maxDurationDelta) return 0;
    return 1 - (delta.inMilliseconds - 1000) / 8000;
  }

  static double score(LrcRedCandidate c,
      {required String title, required String artist, String? album, required Duration duration}) {
    final albumScore = (album == null || album.isEmpty || c.album == null) ? 0.5 : similarity(album, c.album!);
    return 0.35 * similarity(title, c.title) +
        0.35 * similarity(artist, c.artist) +
        0.25 * _durationScore(c.duration, duration) +
        0.05 * albumScore;
  }

  static bool accept(LrcRedCandidate c,
      {required String title, required String artist, String? album, required Duration duration}) {
    if (similarity(title, c.title) < 0.6) return false;
    if (similarity(artist, c.artist) < 0.5) return false;
    if (c.duration != null && (c.duration! - duration).abs() > maxDurationDelta) return false;
    return score(c, title: title, artist: artist, album: album, duration: duration) >= 0.72;
  }
}

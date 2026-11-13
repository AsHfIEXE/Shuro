import 'dart:async';

import '../models/lyrics.dart';
import 'lrc_red_service.dart';
import 'lyrics_service.dart';

/// The one place that decides which lyrics source wins. The lyrics screen and
/// the prefetcher both call this, so they can never disagree.
///
/// Order (a saved user edit is checked by the caller before this runs):
///   1. lrc.red   — real syllable / word timing
///   2. LRCLIB    — word-synced Lyricsfile / enhanced LRC
///   3. embedded  — the server's tags, keeping whatever timing they carry
/// The search continues past a line-only answer to look for genuine word
/// timing; if nothing better turns up, the best line-level result is used and
/// is labelled as line timing.
class LyricsResolver {
  LyricsResolver._();

  static final Map<String, LyricsLookupResult> _cache = {};
  static final Map<String, Future<LyricsLookupResult>> _inFlight = {};
  static const int _cacheLimit = 80;

  static String _key(String title, String artist, String? album, Duration d) =>
      '${title.toLowerCase()}|${artist.toLowerCase()}|${(album ?? '').toLowerCase()}|${d.inSeconds}';

  /// What a previous resolve already found, for an instant first frame.
  static LyricsLookupResult? peek({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
  }) =>
      _cache[_key(title, artist, album, duration)];

  static Future<LyricsLookupResult> resolve({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
    Future<LyricsTrack?> Function()? embedded,
  }) {
    final key = _key(title, artist, album, duration);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _resolve(title: title, artist: artist, album: album, duration: duration, embedded: embedded).then((r) {
      // Only settled answers are remembered; rate limits and network errors
      // must stay retryable.
      if (r.isFound || r.failure == LyricsFailureKind.notFound || r.failure == LyricsFailureKind.instrumental) {
        _cache[key] = r;
        if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
      }
      return r;
    }).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  static int _rank(LyricsTrack t) => switch (t.type) {
        LyricsSyncType.syllable || LyricsSyncType.word => 3,
        LyricsSyncType.line => 2,
        LyricsSyncType.static_ => 1,
      };

  static Future<LyricsLookupResult> _resolve({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
    Future<LyricsTrack?> Function()? embedded,
  }) async {
    LyricsLookupResult? best;
    LyricsLookupResult? lastMiss;

    void consider(LyricsLookupResult r) {
      if (r.isFound) {
        if (best == null || _rank(r.track!) > _rank(best!.track!)) best = r;
      } else {
        lastMiss = r;
      }
    }

    // 1. lrc.red
    final red = await LrcRedService.lookup(title: title, artist: artist, album: album, duration: duration);
    consider(red);
    if (best != null && best!.track!.hasRealWordSync) return best!;

    // 2. LRCLIB
    final lrclib = await LyricsService.lookup(title: title, artist: artist, album: album, duration: duration);
    consider(lrclib);
    if (best != null && best!.track!.hasRealWordSync) return best!;

    // 3. Embedded tags.
    if (embedded != null) {
      try {
        final track = await embedded();
        if (track != null && track.lines.isNotEmpty) {
          consider(LyricsLookupResult.found(track));
        }
      } catch (_) {
        // A server without the extension must not break the lookup.
      }
    }

    if (best != null) return best!;
    // Prefer the most informative failure: an instrumental / rate-limit answer
    // over a plain "not found".
    for (final r in [lrclib, red]) {
      if (r.failure == LyricsFailureKind.instrumental) return r;
    }
    for (final r in [lrclib, red]) {
      if (r.failure == LyricsFailureKind.rateLimited || r.failure == LyricsFailureKind.network) return r;
    }
    return lastMiss ?? const LyricsLookupResult.miss(LyricsFailureKind.notFound);
  }
}

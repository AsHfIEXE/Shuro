import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyrics.dart';
import '../playback/event_log.dart';
import '../screens/settings/settings_prefs.dart';
import 'lrc_red_service.dart';
import 'lyrics_service.dart';

/// The one place that decides which lyrics source wins. The lyrics screen and
/// the prefetcher both call this, so they can never disagree.
///
/// Sources (a saved user edit / imported .lrc is checked by the caller first):
///   lrc.red  > LRCLIB  > embedded tags      (on equal timing quality)
///
/// **Speed.** The sources run *at the same time* (they are different hosts, so
/// nothing is rate-limited by doing so), not one after another:
///  - lrc.red real word/syllable timing -> returned the moment it arrives;
///  - LRCLIB / embedded word timing -> returned right away unless lrc.red is
///    still pending, which gets a short grace (it is the better source);
///  - a line-synced or plain result is emitted immediately through
///    [onUpdate] so the screen shows lyrics at once, then upgrades in place if
///    better timing arrives.
/// Settled answers are cached in memory (and LRCLIB ones on disk), concurrent
/// callers share one lookup, and 429 / Retry-After are honoured inside each
/// provider - so replays and the prefetcher cost no requests at all.
class LyricsResolver {
  LyricsResolver._();

  static final Map<String, LyricsLookupResult> _cache = {};
  // When each negative (notFound) answer was cached: a "no lyrics
  // for this song" from a flaky moment deserves a second chance a
  // minute later instead of sticking for the whole session.
  static final Map<String, DateTime> _negAt = {};
  static const Duration _negTtl = Duration(seconds: 90);
  static final Map<String, Future<LyricsLookupResult>> _inFlight = {};
  static final Map<String, List<void Function(LyricsLookupResult)>> _listeners = {};
  static const int _cacheLimit = 80;

  /// How long a better (lrc.red) source may still delay an already-good
  /// word-timed answer from another source.
  static const Duration _grace = Duration(milliseconds: 1500);

  /// Which sources are on, folded into the cache key so changing a setting
  /// takes effect on the next open instead of serving the old answer.
  static String get _prefsSig {
    final x = SettingsExtras.instance;
    return '${x.lyricsUseLrcRed ? 1 : 0}${x.lyricsUseLrclib ? 1 : 0}'
        '${x.lyricsUseEmbedded ? 1 : 0}${x.lyricsPreferEmbedded ? 1 : 0}';
  }

  static String _key(String title, String artist, String? album, Duration d) =>
      '$_prefsSig|${title.toLowerCase()}|${artist.toLowerCase()}|${(album ?? '').toLowerCase()}|${d.inSeconds}';

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
    void Function(LyricsLookupResult)? onUpdate,
  }) {
    final key = _key(title, artist, album, duration);
    final cached = _cache[key];
    if (cached != null) {
      final negAt = _negAt[key];
      final stale = !cached.isFound &&
          cached.failure == LyricsFailureKind.notFound &&
          negAt != null &&
          DateTime.now().difference(negAt) > _negTtl;
      if (stale) {
        _cache.remove(key);
        _negAt.remove(key);
      } else {
        return Future.value(cached);
      }
    }
    final pending = _inFlight[key];
    if (pending != null) {
      if (onUpdate != null) _listeners[key]?.add(onUpdate);
      return pending;
    }

    _listeners[key] = [if (onUpdate != null) onUpdate];
    void emit(LyricsLookupResult r) {
      for (final l in List.of(_listeners[key] ?? const [])) {
        l(r);
      }
    }

    final future = _resolve(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      embedded: embedded,
      emit: emit,
    ).then((r) {
      // Only settled answers are remembered; rate limits and network errors
      // must stay retryable.
      if (r.isFound || r.failure == LyricsFailureKind.notFound || r.failure == LyricsFailureKind.instrumental) {
        _cache[key] = r;
        if (!r.isFound && r.failure == LyricsFailureKind.notFound) {
          _negAt[key] = DateTime.now();
        } else {
          _negAt.remove(key);
        }
        if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
      }
      return r;
    }).whenComplete(() {
      _inFlight.remove(key);
      _listeners.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  static int _rank(LyricsTrack t) => switch (t.type) {
        LyricsSyncType.syllable || LyricsSyncType.word => 3,
        LyricsSyncType.line => 2,
        LyricsSyncType.static_ => 1,
      };

  // Equal timing quality: lrc.red, then LRCLIB, then the file's own tags.
  static int _priority(LyricsTrack t) => switch (t.source) {
        LyricsSource.lrcRed => 3,
        LyricsSource.lrclib => 2,
        _ => 1,
      };

  static bool _better(LyricsLookupResult a, LyricsLookupResult? b) {
    if (b == null) return true;
    final ra = _rank(a.track!), rb = _rank(b.track!);
    if (ra != rb) return ra > rb;
    return _priority(a.track!) > _priority(b.track!);
  }

  static const LyricsLookupResult _timedOut = LyricsLookupResult.miss(LyricsFailureKind.network,
      detail: 'The source did not answer before its time budget.');

  static Future<LyricsLookupResult> _resolve({
    required String title,
    required String artist,
    String? album,
    required Duration duration,
    Future<LyricsTrack?> Function()? embedded,
    required void Function(LyricsLookupResult) emit,
  }) async {
    final prefs = SettingsExtras.instance;
    final done = Completer<LyricsLookupResult>();
    LyricsLookupResult? redR, lrclibR, embR;
    var outstanding = 0;
    var redPending = false;
    Timer? grace;
    LyricsLookupResult? emitted;

    LyricsLookupResult? best() {
      LyricsLookupResult? b;
      for (final r in [redR, lrclibR, embR]) {
        if (r != null && r.isFound && _better(r, b)) b = r;
      }
      return b;
    }

    /// Short per-source outcome line, e.g. "lrc.red: no match · LRCLIB: no
    /// record · embedded: none" — nothing sensitive, purely explanatory.
    String _summary() {
      final prefsNow = prefs;
      String part(String name, bool on, LyricsLookupResult? r) {
        if (!on) return '$name: off';
        if (r == null) return '$name: no answer';
        if (r.isFound) return '$name: found';
        return switch (r.failure) {
          LyricsFailureKind.notFound => '$name: no match',
          LyricsFailureKind.instrumental => '$name: instrumental',
          LyricsFailureKind.rateLimited => '$name: rate-limited',
          LyricsFailureKind.rejected => '$name: rejected',
          LyricsFailureKind.network => '$name: unreachable',
          null => '$name: no answer',
        };
      }
      return [
        part('lrc.red', prefsNow.lyricsUseLrcRed, redR),
        part('LRCLIB', prefsNow.lyricsUseLrclib, lrclibR),
        part('embedded', prefsNow.lyricsUseEmbedded && embedded != null, embR),
      ].join(' · ');
    }

    LyricsLookupResult bestMiss() {
      final misses = [lrclibR, redR].whereType<LyricsLookupResult>().where((r) => !r.isFound).toList();
      for (final r in misses) {
        if (r.failure == LyricsFailureKind.instrumental) return r;
      }
      // Show WHY every source missed — this string is what the lyrics screen
      // prints under "No lyrics for this song".
      final summary = _summary();
      for (final r in misses) {
        if (r.failure == LyricsFailureKind.rateLimited || r.failure == LyricsFailureKind.network) {
          return LyricsLookupResult.miss(r.failure!, retryAfter: r.retryAfter, detail: summary);
        }
      }
      return LyricsLookupResult.miss(LyricsFailureKind.notFound, detail: summary);
    }

    void settle(LyricsLookupResult r) {
      if (done.isCompleted) return;
      grace?.cancel();
      done.complete(r);
    }

    void evaluate() {
      if (done.isCompleted) return;
      final b = best();
      if (b != null) {
        final t = b.track!;
        if (t.source == LyricsSource.lrcRed && t.hasRealWordSync) return settle(b);
        if (t.hasRealWordSync) {
          if (!redPending) return settle(b);
          grace ??= Timer(_grace, () => settle(best() ?? b));
        }
      }
      if (outstanding == 0) return settle(b ?? bestMiss());
      // Show the best thing so far immediately; it upgrades in place later.
      if (b != null && _better(b, emitted)) {
        emitted = b;
        emit(b);
      }
    }

    void run(Future<LyricsLookupResult> f, Duration budget, void Function(LyricsLookupResult) set,
        {bool isRed = false, String name = 'embedded'}) {
      outstanding++;
      if (isRed) redPending = true;
      final sw = Stopwatch()..start();
      f.timeout(budget, onTimeout: () => _timedOut).catchError((_) => _timedOut).then((r) {
        set(r);
        debugPrint('[lyrics] ${isRed ? 'lrc.red' : 'source'} -> '
            '${r.isFound ? 'found ${r.track!.type.name}' : 'miss ${r.failure?.name} ${r.detail ?? ''}'}');
        outstanding--;
        if (isRed) redPending = false;
        // Every source outcome lands in the diagnostics ring (Settings →
        // About → Report a problem), so "no lyrics" is explainable after
        // the fact instead of a mystery.
        try {
          PlaybackEventLog.instance.add('lyrics.src', {
            'src': name,
            'ok': r.isFound,
            if (r.isFound) 'type': r.track!.type.name,
            if (r.isFound) 'lines': r.track!.lines.length,
            if (!r.isFound) 'why': r.failure!.name,
            if (!r.isFound && r.retryAfter != null) 'retryS': r.retryAfter!.inSeconds,
            if (sw.elapsedMilliseconds >= 0) 'ms': sw.elapsedMilliseconds,
          });
        } catch (_) {}
        evaluate();
      });
    }

    Future<LyricsLookupResult> embeddedResult() async {
      try {
        final track = await embedded!();
        if (track != null && track.lines.isNotEmpty) return LyricsLookupResult.found(track);
      } catch (_) {
        // A server without the extension must not break the lookup.
      }
      return const LyricsLookupResult.miss(LyricsFailureKind.notFound);
    }

    final useEmbedded = prefs.lyricsUseEmbedded && embedded != null;

    // "Prefer embedded": the file's own synced lyrics end the search at once,
    // without any network traffic.
    if (prefs.lyricsPreferEmbedded && useEmbedded) {
      final first = await embeddedResult();
      embR = first;
      if (first.isFound && first.track!.type != LyricsSyncType.static_) return first;
    }

    if (prefs.lyricsUseLrcRed) {
      run(LrcRedService.lookup(title: title, artist: artist, album: album, duration: duration),
          const Duration(seconds: 7), (r) => redR = r,
          isRed: true, name: 'lrc.red');
    }
    if (prefs.lyricsUseLrclib) {
      Timer(const Duration(milliseconds: 600), () {
        run(LyricsService.lookup(title: title, artist: artist, album: album, duration: duration),
            const Duration(seconds: 14), (r) => lrclibR = r, name: 'lrclib');
      });
    }
    if (useEmbedded && embR == null) {
      // Staggered starts: this machine's resolver stalls under concurrent
      // lookups, so the sources resolve DNS one at a time (lrc.red now,
      // embedded +250 ms, LRCLIB +600 ms). Budgets absorb the delay.
      Timer(const Duration(milliseconds: 250),
          () => run(embeddedResult(), const Duration(seconds: 8), (r) => embR = r, name: 'embedded'));
    }

    if (outstanding == 0) return best() ?? bestMiss();
    return done.future;
  }
}

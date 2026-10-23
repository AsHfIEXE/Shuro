import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyrics.dart';
import '../models/song.dart';

/// Keeps lyrics warm so opening the lyrics screen is a cache hit, not a
/// network wait (reported: visible stall on low-end devices while the song
/// was already playing).
///
/// Two layers:
///  - [EmbeddedLyricsCache] remembers the server's own lyrics per song, which
///    [fetch] populates from anywhere (the prefetcher or the screen itself).
///  - [LyricsPrefetcher] listens to playback: when the current song changes it
///    warms the current track and the next one in the queue — by the time the
///    user opens the screen, the data is local.
///
/// Nothing here blocks playback: every fetch is fire-and-forget and errors
/// resolve to null, exactly like the screen's own fallbacks.
class EmbeddedLyricsCache {
  EmbeddedLyricsCache._();

  static final Map<String, LyricsTrack?> _cache = {};
  static final Map<String, Future<LyricsTrack?>> _inFlight = {};
  static const int _limit = 40;

  /// Cached lyrics for [song], or null when nothing is cached YET — distinct
  /// from a cached null, which means "the server has none for this song".
  static bool isKnown(String songId) => _cache.containsKey(songId);

  static void _remember(String songId, LyricsTrack? track) {
    _cache[songId] = track;
    if (_cache.length > _limit) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Returns the song's embedded lyrics, fetching through [fetcher] at most
  /// once per song per process.
  static Future<LyricsTrack?> fetch(
      String songId, Future<LyricsTrack?> Function() fetcher) async {
    if (_cache.containsKey(songId)) return _cache[songId];
    final pending = _inFlight[songId];
    if (pending != null) return pending;
    final future = fetcher().then((track) {
      _remember(songId, track);
      return track;
    }).whenComplete(() => _inFlight.remove(songId));
    _inFlight[songId] = future;
    return future;
  }

  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _inFlight.clear();
  }
}

/// Watches playback and keeps lyrics warm for what is playing and what is
/// next. One instance per app; [start] returns a disposer.
class LyricsPrefetcher {
  LyricsPrefetcher._();

  static String? _lastSongId;

  /// [nextSongOf] maps the current playback to the track that follows it, so
  /// the prefetch also covers the moment a song ends and the next begins.
  ///
  /// No debounce timer: repeated notifications for the same song are stopped
  /// by [_lastSongId], and a genuine burst (shuffle, reorder) is absorbed by
  /// the cache's in-flight dedup — the worst case is one deduped request per
  /// song id, never a storm.
  static VoidCallback start({
    required Listenable player,
    required Song? Function() currentSong,
    required Song? Function() nextSong,
    required Future<LyricsTrack?> Function(Song) embeddedFetch,
    required Future<void> Function(Song) onlineLookup,
  }) {
    void onChange() {
      final song = currentSong();
      if (song == null || song.id == _lastSongId) return;
      _lastSongId = song.id;
      _warm(song, embeddedFetch, onlineLookup);
      final next = nextSong();
      if (next != null && next.id != song.id) {
        _warm(next, embeddedFetch, onlineLookup);
      }
    }

    player.addListener(onChange);
    return () {
      player.removeListener(onChange);
      _lastSongId = null;
    };
  }

  static void _warm(
    Song song,
    Future<LyricsTrack?> Function(Song) embeddedFetch,
    Future<void> Function(Song) onlineLookup,
  ) {
    unawaited(EmbeddedLyricsCache.fetch(song.id, () => embeddedFetch(song))
        .then((track) async {
      // Only look online when the server had nothing embedded — same rule
      // the screen applies, so the two paths can never disagree.
      if (track != null && track.lines.isNotEmpty) return;
      await onlineLookup(song);
    }).catchError((_) {}));
  }
}

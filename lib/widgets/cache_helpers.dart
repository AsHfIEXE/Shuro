import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_cache.dart';
import '../services/stream_proxy.dart';
import '../state/app_state.dart';

/// Songs (by id) that are available offline: a complete audio-cache file at
/// any quality, or an explicit download.
Set<String> offlineSongIds(AppState appState, Iterable<Song> songs) {
  final keys = {for (final e in AudioCache.instance.entries()) e.songKey};
  return {
    for (final s in songs)
      if (appState.downloadedSongIds.contains(s.id) ||
          keys.contains(AudioCache.sanitizeId(s.id)))
        s.id,
  };
}

/// Fills the song cache with [songs] (stream URLs resolved the same way
/// app.dart does). Fills run one at a time in the background; returns how many
/// were queued, or -1 when the cache is switched off.
Future<int> cacheSongs(BuildContext context, AppState appState, List<Song> songs) async {
  final cache = AudioCache.instance;
  if (!cache.enabled) return -1;
  final quality = appState.effectiveStreamingQuality.name;
  final todo = <Song>[];
  final have = offlineSongIds(appState, songs);
  for (final s in songs) {
    if (s.isLocal || have.contains(s.id)) continue;
    todo.add(s);
  }
  unawaited(() async {
    await cache.init();
    for (final s in todo) {
      final remote = appState.audioSourceFor(s);
      if (remote == null || !remote.startsWith('http')) continue;
      // prefetch() declines when two fills are already running, so wait
      // for the previous one to land before starting the next.
      await cache.prefetch(
        songId: s.id,
        qualityTag: quality,
        url: StreamProxy.wrap(remote),
        onWifi: appState.isOnWifi,
      );
    }
  }());
  return todo.length;
}

/// "Cache all" feedback shared by the favorites / artist / album screens.
Future<void> cacheSongsWithFeedback(
    BuildContext context, AppState appState, List<Song> songs, String what) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final n = await cacheSongs(context, appState, songs);
  final text = n < 0
      ? 'Song cache is turned off in Settings'
      : n == 0
          ? '$what already available offline'
          : 'Caching $n ${n == 1 ? 'song' : 'songs'} from $what';
  messenger?.showSnackBar(SnackBar(content: Text(text)));
}

/// "Today", "Yesterday", "2 days ago", "Last week", "2 weeks ago",
/// "Last month", then the date.
String relativeDay(DateTime? at) {
  if (at == null) return '—';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'Last week';
  if (days < 30) return '${days ~/ 7} weeks ago';
  if (days < 60) return 'Last month';
  if (days < 365) return '${days ~/ 30} months ago';
  return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}

String hoursMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '$h h $m m' : '$m min';
}

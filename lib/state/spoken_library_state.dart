import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImage;

import '../backend/audiobookshelf_api.dart';
import '../models/song.dart';
import '../models/spoken_media.dart';
import '../playback/event_log.dart';
import '../services/app_persistence.dart';
import '../services/server_secret_store.dart';
import '../services/stream_proxy.dart';
import '../models/abs_stats.dart';

@immutable
class AudiobookshelfConnection {
  const AudiobookshelfConnection({required this.url, required this.name});
  final String url;
  final String name;
}

/// Holds Audiobookshelf separately from Navidrome. No connection is assumed
/// to contain music; book and podcast libraries are discovered by mediaType.
class SpokenLibraryState extends ChangeNotifier {
  static const _configKey = 'audiobookshelf_connection_v1';
  static const _secretKey = 'audiobookshelf';
  AudiobookshelfConnection? connection;
  List<SpokenLibrary> libraries = const [];
  final Map<String, List<SpokenItem>> itemsByLibrary = {};
  bool loading = false;
  String? error;
  AudiobookshelfApi? _api;


  // --- Active play session ---------------------------------------------------
  // One ABS play session is live at a time. The sync timer lives HERE, not
  // in the Books screen, so progress keeps reporting while the user is on
  // any other screen (Now Playing, Lyrics, ...) - the readers below are
  // handed in by whoever opened the session.
  Timer? _syncTimer;
  String? _activeSessionId;
  String? _activeProgressId;
  double _activeDuration = 0;
  Map<String, double> _activeStartOffsetById = const {};
  List<String> _activeSongIds = const [];
  Duration Function()? _positionReader;
  String? Function()? _songIdReader;

  /// Freshest known positions (progressId -> seconds), updated by the sync
  /// timer while a session plays. The library listing is a snapshot from
  /// the last refresh; this is what happened since.
  final Map<String, double> _liveProgress = {};

  /// Sessions opened for songs that were QUEUED, not played. The sync tick
  /// promotes one to the active session the moment the player reaches it,
  /// so queued books sync progress too.
  final Map<String, _QueuedAbsSession> _queuedSessions = {};

  /// Items the minified listing disguised as audiobooks (episodes hidden,
  /// so the trait rule shelved them as books) but the full item fetch
  /// revealed as podcast shows. The expanded item - WITH episodes -
  /// replaces the listing one in podcastShows, and bookItems drops it.
  final Map<String, SpokenItem> _expandedShows = {};
  final Map<String, SpokenItem> _expandedBooks = {};
  List<SpokenLibrary> get bookLibraries =>
      libraries.where((l) => l.type == SpokenMediaType.book).toList();
  List<SpokenLibrary> get podcastLibraries =>
      libraries.where((l) => l.type == SpokenMediaType.podcast).toList();

  /// Forgets the Audiobookshelf connection and its token. The server itself
  /// is untouched; Books and podcasts simply disappear from the sidebar.
  Future<void> disconnect() async {
    await closeActiveSession();
    connection = null;
    _api = null;
    libraries = const [];
    itemsByLibrary.clear();
    error = null;
    progress = null;
    notifyListeners();
    await ServerSecretStore.removeEntry(_secretKey);
    final store = await AppPersistence.load();
    await store.remove(_configKey);
  }

  Future<void> restore() async {
    final store = await AppPersistence.load();
    final raw = store.getString(_configKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final token = await ServerSecretStore.readEntry(_secretKey);
      if (token == null || token.isEmpty) {
        // The connection config exists but its token is gone from secure
        // storage. This happened whenever a Navidrome re-save rewrote the
        // whole secret map without the ABS entry — it must never be silent
        // again, or the setup "gets deleted" with nothing to see.
        error = 'Saved Audiobookshelf token is missing — please reconnect.';
        notifyListeners();
        return;
      }
      connection = AudiobookshelfConnection(
          url: json['url'] as String, name: json['name'] as String);
      _api = AudiobookshelfApi(baseUrl: connection!.url, token: token);
      await refresh();
    } catch (_) {
      error = 'Saved Audiobookshelf connection could not be restored.';
      notifyListeners();
    }
  }

  Future<void> connect(
      {required String url, required String token, String? name}) async {
    final trimmed = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!Uri.tryParse(trimmed)!.hasScheme || token.trim().isEmpty) {
      error = 'Enter an http(s) server URL and an API token.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final api = AudiobookshelfApi(baseUrl: trimmed, token: token.trim());
    try {
      await api.validate();
      await closeActiveSession();
      connection = AudiobookshelfConnection(
          name: (name?.trim().isNotEmpty ?? false)
              ? name!.trim()
              : 'Audiobookshelf',
          url: trimmed);
      _api = api;
      // writeEntry preserves every other secret (Navidrome passwords)
      // instead of rewriting the whole map from this feature's view.
      await ServerSecretStore.writeEntry(_secretKey, token.trim());
      final store = await AppPersistence.load();
      await store.setString(_configKey,
          jsonEncode({'name': connection!.name, 'url': connection!.url}));
      await refresh();
    } on AudiobookshelfApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not reach Audiobookshelf. Check the server URL.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Human-readable progress, e.g. "Fetching Podcasts (2 of 3)…" — a big
  /// library on a NAS takes real seconds, and a silent wait read as "the
  /// whole implementation is broken".
  String? progress;

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    loading = true;
    error = null;
    progress = null;
    notifyListeners();
    try {
      final next = await api.libraries();
      libraries = next;
      // Sequential with per-library isolation: one slow or failing library
      // must neither time out the burst nor erase the libraries that did
      // fetch. Failures surface per library instead of as one dead screen.
      final entries = <MapEntry<String, List<SpokenItem>>>[];
      for (var i = 0; i < next.length; i++) {
        final library = next[i];
        progress = 'Fetching ${library.name} (${i + 1} of ${next.length})…';
        notifyListeners();
        try {
          entries.add(MapEntry(library.id, await api.items(library)));
        } on AudiobookshelfApiException catch (e) {
          entries.add(MapEntry(library.id, const <SpokenItem>[]));
          error = '${library.name}: ${e.message}';
        } catch (_) {
          entries.add(MapEntry(library.id, const <SpokenItem>[]));
          error = '${library.name}: could not reach the server.';
        }
      }
      itemsByLibrary
        ..clear()
        ..addEntries(entries);
    } on AudiobookshelfApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Audiobookshelf could not refresh right now.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // --- Classification & playback -------------------------------------------

  /// Listening stats from the server (null when not connected). The UI
  /// asks on open and on pull-to-refresh; nothing is cached here so the
  /// numbers are always the server's.
  Future<AbsListeningStats?> loadStats() async => _api?.listeningStats();

  /// Maps a player song id (`abs_<item>`, `abs_<item>_t<n>`,
  /// `abs_<item>_<episode>`) back to the book / show + episode it belongs
  /// to, or null when it is not an ABS song (music). Item ids contain
  /// underscores (`li_...`), so this matches known ids instead of splitting.
  /// Expanded copies are checked first: the listing hides a show's episodes
  /// and a book's chapters, and only the expanded copy knows both.
  ({SpokenItem item, SpokenEpisode? episode})? resolveSong(String? songId) {
    if (songId == null || !songId.startsWith('abs_')) return null;
    for (final item in [..._expandedShows.values, ..._expandedBooks.values, ...allItems]) {
      final base = 'abs_${item.id}';
      if (!songId.startsWith(base)) continue;
      for (final e in item.episodes) {
        final eb = '${base}_${e.id}';
        if (songId == eb || songId.startsWith('${eb}_t')) {
          return (item: item, episode: e);
        }
      }
      if (songId == base || songId.startsWith('${base}_t')) {
        return (item: item, episode: null);
      }
    }
    return null;
  }

  /// Seconds into the item at which the active ABS track [songId] starts
  /// (multi-file books play one track per file); 0 when unknown.
  double trackOffsetFor(String songId) => _activeStartOffsetById[songId] ?? 0;

  /// Test hook: seed the expanded-show cache directly.
  @visibleForTesting
  void debugCacheExpandedShow(SpokenItem item) {
    _expandedShows[item.id] = item;
  }

  /// Every fetched item, across libraries.
  Iterable<SpokenItem> get allItems sync* {
    for (final items in itemsByLibrary.values) {
      yield* items;
    }
  }

  /// An item is a BOOK when it has no episodes to play independently -
  /// regardless of how the ABS library is typed. Audiobooks filed inside a
  /// podcast-type library (common single-library setup) classify correctly
  /// here; shows with real episodes stay podcasts.
  /// Items that behave as audiobooks: book-type items, or episode-less
  /// items from podcast libraries.
  List<SpokenItem> get bookItems => [
        for (final item in allItems)
          if (!_expandedShows.containsKey(item.id) &&
              (item.type == SpokenMediaType.book || item.episodes.isEmpty))
            item,
      ];

  /// Items that behave as podcast shows (they have episodes).
  List<SpokenItem> get podcastShows => [
        for (final item in allItems)
          if (_expandedShows.containsKey(item.id) || item.episodes.isNotEmpty)
            _expandedShows[item.id] ?? item,
      ];

  // --- Playback sessions -----------------------------------------------------

  /// Cover URL for an item, carrying the token as a query param so plain
  /// Image.network can fetch it.
  String? coverUrlFor(SpokenItem item) => _api?.coverUrl(item.id).toString();

  /// The freshest known position for an item/episode (seconds), or null
  /// when nothing has played it this session. UI falls back: live value ->
  /// library listing -> untouched.
  double? liveProgressSecondsFor(SpokenItem item, {SpokenEpisode? episode}) =>
      _liveProgress[episode == null ? item.id : '${item.id}/${episode.id}'];

  /// The full item behind a listing row. ABS's library listing hides a
  /// podcast's episodes — and the item GET often does too (the dedicated
  /// podcast endpoint is the source of truth) — and hides book chapters, so
  /// detail screens ask for the whole thing here instead of rendering
  /// "0 episodes" forever. Podcasts found to carry episodes are cached in
  /// the same map playback uses, so the shelves reclassify and the rail
  /// picks up episodes. Books are returned but never cached: bookItems
  /// excludes expanded shows, and a book must stay on the book rail.
  Future<SpokenItem?> expandShow(SpokenItem listed) async {
    final api = _api;
    if (api == null) return null;
    var full = listed;
    var via = 'listing';
    try {
      final expanded = await api.itemExpanded(listed);
      full = expanded.item;
      via = 'item';
    } catch (_) {
      // A failed item GET is not fatal — the podcast endpoint may still
      // answer below.
    }
    // Zero-length rows count as missing too: some servers serialize the
    // length somewhere the parser has to dig for, and the podcast endpoint
    // is the source of truth for the real numbers.
    final episodesLookEmpty = full.episodes.isEmpty ||
        full.episodes.every((e) => e.duration <= Duration.zero);
    if (episodesLookEmpty && full.type == SpokenMediaType.podcast) {
      try {
        final eps = await api.podcastEpisodes(listed.id);
        if (eps.isNotEmpty) {
          full = _withEpisodes(full, _mergeEpisodeTruth(full.episodes, eps));
          via = via == 'listing' ? 'podcast' : 'item+podcast';
        }
      } catch (_) {}
    }
    PlaybackEventLog.instance.add('abs.expand', {
      'id': listed.id,
      'via': via,
      'episodes': full.episodes.length,
      'chapters': full.chapters.length,
    });
    // Both fetches failed and we are still holding the listing row: report
    // failure so the screen can offer a retry.
    if (identical(full, listed)) return null;
    if (full.episodes.isNotEmpty) {
      _expandedShows[full.id] = full;
      notifyListeners();
    } else if (full.chapters.isNotEmpty) {
      // Books are cached separately: bookItems excludes expanded shows, and
      // a book must stay on the book rail. resolveSong checks both caches.
      _expandedBooks[full.id] = full;
      notifyListeners();
    }
    return full;
  }

  /// [item] with [eps] swapped in — the item GET and the podcast endpoint
  /// each carry half the truth, and the shelves must carry both.
  SpokenItem _withEpisodes(SpokenItem item, List<SpokenEpisode> eps) => SpokenItem(        id: item.id,
        libraryId: item.libraryId,
        type: item.type,
        title: item.title,
        creator: item.creator,
        duration: item.duration,
        description: item.description,
        coverUrl: item.coverUrl,
        progressSeconds: item.progressSeconds,
        episodes: eps,
        chapters: item.chapters,
        seriesNames: item.seriesNames,
        isFinished: item.isFinished,
        tracks: item.tracks,
      );

  /// The podcast endpoint carries the truth about lengths; the item GET and
  /// the listing carry the truth about this user's progress. Keep the best
  /// of both per episode id — neither source alone is complete.
  List<SpokenEpisode> _mergeEpisodeTruth(
      List<SpokenEpisode> have, List<SpokenEpisode> truth) {
    if (have.isEmpty) return truth;
    final byId = {for (final h in have) h.id: h};
    return [
      for (final t in truth)
        SpokenEpisode(
          id: t.id,
          title: t.title,
          fileIndex: t.fileIndex,
          duration: t.duration > Duration.zero
              ? t.duration
              : byId[t.id]?.duration ?? Duration.zero,
          description: t.description.isNotEmpty
              ? t.description
              : byId[t.id]?.description ?? '',
          progressSeconds: (byId[t.id]?.progressSeconds ?? 0) > t.progressSeconds
              ? byId[t.id]!.progressSeconds
              : t.progressSeconds,
          publishedAt: t.publishedAt ?? byId[t.id]?.publishedAt,
        ),
    ];
  }

  /// Series name -> books carrying that series (from item metadata; ABS
  /// maintains series on scan). Sorted by name, books in library order.
  Map<String, List<SpokenItem>> get seriesGroups {
    final groups = <String, List<SpokenItem>>{};
    for (final item in bookItems) {
      for (final name in item.seriesNames) {
        groups.putIfAbsent(name, () => []).add(item);
      }
    }
    final names = groups.keys.toList()..sort();
    return {for (final name in names) name: groups[name]!};
  }

  /// "Mark as played" - reports the full duration as finished, and updates
  /// the live position so rails and the NEW badge react immediately.
  Future<void> markPlayed(SpokenItem item, {SpokenEpisode? episode}) async {
    final api = _api;
    if (api == null) return;
    final progressId = episode == null ? item.id : '${item.id}/${episode.id}';
    final total =
        (episode?.duration ?? item.duration).inMilliseconds / 1000.0;
    await api.saveProgress(progressId,
        currentTime: total > 0 ? total : 1,
        duration: total,
        forceFinished: true);
    _liveProgress[progressId] = total;
    notifyListeners();
    PlaybackEventLog.instance.add('abs.mark', {'id': progressId});
  }

  // --- Per-book playback speed memory ----------------------------------------
  static const _speedKey = 'abs_speed_v1';

  Future<double> savedSpeedFor(String progressId) async {
    try {
      final store = await AppPersistence.load();
      final raw = store.getString(_speedKey);
      if (raw == null) return 1.0;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (map[progressId] as num?)?.toDouble() ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> saveSpeedFor(String progressId, double speed) async {
    try {
      final store = await AppPersistence.load();
      final map = <String, dynamic>{};
      final raw = store.getString(_speedKey);
      if (raw != null) map.addAll(jsonDecode(raw) as Map<String, dynamic>);
      map[progressId] = speed;
      await store.setString(_speedKey, jsonEncode(map));
    } catch (_) {}
  }

  // --- Bookmarks (passthrough to the API, filtered per item) -----------------

  Future<List<Map<String, dynamic>>> bookmarksFor(String itemId) async {
    final rows = await _api?.bookmarks() ?? const <Map<String, dynamic>>[];
    return [
      for (final row in rows)
        if (row['libraryItemId'] == itemId) row
    ];
  }

  Future<void> addBookmark(String itemId,
      {required double time, required String title}) async {
    await _api?.addBookmark(itemId, time: time, title: title);
  }

  Future<void> removeBookmark(String itemId, double time) async {
    await _api?.removeBookmark(itemId, time);
  }

  /// Opens a real ABS play session for a book or episode and returns the
  /// playable queue: one [Song] per server-issued audio track, resuming at
  /// the server-known position. This replaced the guessed
  /// `/api/items/:id/file/:index` URL, which some servers never answer -
  /// the session's own `contentUrl` is what ABS clients actually stream.
  Future<SpokenPlaybackSession?> openSession(SpokenItem item,
      {SpokenEpisode? episode,
      Duration Function()? positionReader,
      String? Function()? songIdReader,
      bool forQueue = false}) async {
    final api = _api;
    if (api == null || connection == null) return null;
    if (!forQueue) {
      // One ACTIVE session at a time: flush the old one's final position
      // before the server opens the next. A queued session must NOT close
      // whatever is playing right now.
      await closeActiveSession();
    }
    final session = await api.startPlayback(item.id, episodeId: episode?.id);
    // A play session may hand back an HLS transcode playlist (.m3u8),
    // which the Windows engine cannot open - it stalls to the 20 s
    // watchdog. When it does, the item's own media tracks are the
    // direct-play URLs ABS clients stream; the session stays open for
    // progress either way.
    final isHls = session.tracks.any((track) =>
        track.contentUrl.contains('/hls/') ||
        track.contentUrl.endsWith('.m3u8'));
    var trackSource = 'session';
    var playTracks = session.tracks;
    if (isHls) {
      // The engine cannot open the server's HLS playlist. Direct tracks,
      // in order of cheapness: the listing's media.tracks (some servers
      // include them), then the FULL item fetch - GET /api/items/:id is
      // the response that actually carries each file's /s/ contentUrl.
      var direct = <AbsTrack>[
        for (final track in item.tracks)
          AbsTrack(
            contentUrl: track.contentUrl,
            mimeType: track.mimeType,
            startOffset: track.startOffset,
            duration: track.duration,
          ),
      ];
      var src = item.tracks.isNotEmpty ? 'itemTracks' : '';
      var episodeNotDownloaded = false;
      if (direct.isEmpty && episode != null) {
        // Episodes keep their file in the episode object - the audioFile
        // index parsed from the listing is exactly what /file/:index wants.
        // PROBE it first: RSS-feed podcasts carry the episode metadata but
        // no local audio until someone downloads it server-side, and their
        // own HLS sessions die on the missing file - playing blind would
        // stall 20 s on a URL the server can never serve.
        final candidate = AbsTrack(
          contentUrl: '/api/items/${item.id}/file/${episode.fileIndex}',
          mimeType: 'audio/mpeg',
          startOffset: 0,
          duration: episode.duration.inMilliseconds / 1000.0,
        );
        final status =
            await api.probeRange(api.streamUrlOf(candidate));
        if (status == 200 || status == 206) {
          direct = [candidate];
          src = 'episodeFile';
        } else {
          episodeNotDownloaded = true;
          PlaybackEventLog.instance.add('abs.probe', {
            'item': item.id,
            'episode': episode.id,
            'file': episode.fileIndex,
            'status': status,
          });
        }
      } else if (direct.isEmpty) {
        try {
          final expanded = await api.itemExpanded(item);
          var episodes = expanded.item.episodes;
          var via = 'item';
          if (episodes.isEmpty && item.type == SpokenMediaType.podcast) {
            // The item GET can say episodes: [] while episodes exist -
            // the dedicated podcast endpoint is the source of truth.
            try {
              episodes = await api.podcastEpisodes(item.id);
              via = 'podcast';
            } catch (_) {}
          }
          if (episodes.isNotEmpty) {
            // A PODCAST SHOW the minified listing disguised as an
            // audiobook (episodes hidden, so the trait rule shelved it as
            // a book). Playing a show is what made the server answer with
            // an HLS transcode and zero tracks - the server logs show
            // ffmpeg dying on an empty files.txt. Play an episode
            // instead, and remember the truth so the shelves reclassify
            // immediately.
            // Cache the MERGED item: the item GET often says episodes: []
            // while the episodes came from the podcast endpoint — caching
            // the bare item kept every shelf copy of this show at "0
            // episodes" even after a successful play.
            _expandedShows[item.id] =
                episodes.isEmpty ? expanded.item : _withEpisodes(expanded.item, episodes);
            notifyListeners();
            final pick = _pickEpisode(episodes);
            PlaybackEventLog.instance.add('abs.redirect', {
              'item': item.id,
              'episode': pick.id,
              'episodes': episodes.length,
              'via': via,
            });
            return await openSession(item,
                episode: pick,
                positionReader: positionReader,
                songIdReader: songIdReader,
                forQueue: forQueue);
          }
          // media.tracks first; on servers without them this falls to
          // audioFiles -> numAudioFiles -> /api/items/:id/file/:n streams.
          direct = expanded.tracks;
          src = 'itemFetch';
        } catch (_) {}
      }
      if (direct.isEmpty) {
        // The server transcoded SOMETHING for this item, so audio exists
        // even though no API surface lists it (podcast-typed items hide
        // their files everywhere - and their HLS sessions can be empty
        // 404s). Probe the raw file indexes with 1-byte range requests:
        // whatever answers 206 becomes the playlist.
        var index = item.type == SpokenMediaType.podcast ? 1 : 0;
        while (index < 8) {
          final candidate = AbsTrack(
            contentUrl: '/api/items/${item.id}/file/$index',
            mimeType: 'audio/mpeg',
            startOffset: 0,
            duration: index == 0 && item.duration > Duration.zero
                ? item.duration.inMilliseconds / 1000.0
                : 0,
          );
          final status =
              await api.probeRange(api.streamUrlOf(candidate));
          if (status != 200 && status != 206) break;
          direct.add(candidate);
          index++;
        }
        if (direct.isNotEmpty) src = 'fileProbe';
        PlaybackEventLog.instance
            .add('abs.probe', {'item': item.id, 'files': direct.length});
      }
      if (direct.isEmpty) {
        // Nothing anywhere: no session tracks the engine can open, no
        // listing tracks, no item/audioFiles/count, no probeable raw
        // files. Fail fast and honestly instead of stalling 20 s on an
        // HLS URL that cannot play on this build. (The server's own log
        // for such sessions: "episode not found null", zero segments,
        // ffmpeg exits 183, stream deleted.)
        throw AudiobookshelfApiException(
            episode != null && episodeNotDownloaded
                ? 'This episode is not downloaded on the server yet. '
                    'Download it in Audiobookshelf (episode menu -> '
                    'Download), then play it here.'
                : episode == null && item.type == SpokenMediaType.podcast
                    ? 'This podcast has no playable episodes yet - open it '
                        'in Audiobookshelf and check its episodes.'
                    : 'No directly playable audio found, and this Windows '
                        'build cannot open the server\'s HLS stream.');
      }
      if (direct.isNotEmpty && src.isNotEmpty) {
        playTracks = direct;
        trackSource = src;
      }
      // Diagnostics: what does the HLS URL itself answer? (Non-blocking.)
      unawaited(api
          .probeUrl(api.streamUrlOf(session.tracks.first))
          .then((status) {
        PlaybackEventLog.instance
            .add('abs.hls', {'status': status, 'fellBack': trackSource != 'session'});
      }));
    }
    final session2 = AbsSession(
      id: session.id,
      currentTime: session.currentTime,
      tracks: playTracks,
    );
    final songs = await _sessionSongs(api, session2, item, episode);
    // Which track holds the resume point, and how far into it. The session
    // currentTime is item/episode-relative; each track has its offset.
    var trackIndex = session2.tracks.length - 1;
    for (var i = 0; i < session2.tracks.length; i++) {
      final candidate = session2.tracks[i];
      if (session2.currentTime <
              candidate.startOffset + candidate.duration ||
          i == session2.tracks.length - 1) {
        trackIndex = i;
        break;
      }
    }
    final track = session2.tracks[trackIndex];
    var within = session2.currentTime - track.startOffset;
    if (within < 0) within = 0;
    if (track.duration > 1 && within > track.duration - 1) {
      within = track.duration - 1;
    }
    var totalSeconds =
        (episode?.duration ?? item.duration).inMilliseconds / 1000.0;
    if (totalSeconds <= 0) {
      totalSeconds = session2.tracks.isEmpty
          ? 0
          : session2.tracks.last.startOffset + session2.tracks.last.duration;
    }

    final progressId = episode == null ? item.id : '${item.id}/${episode.id}';
    final songIds = [for (final song in songs) song.id];
    final startOffsetById = {
      for (var i = 0; i < songs.length; i++)
        songs[i].id: session2.tracks[i].startOffset,
    };
    if (forQueue) {
      _queuedSessions[songs.first.id] = _QueuedAbsSession(
        sessionId: session.id,
        progressId: progressId,
        durationSeconds: totalSeconds,
        songIds: songIds,
        startOffsetById: startOffsetById,
      );
      _positionReader = positionReader ?? _positionReader;
      _songIdReader = songIdReader ?? _songIdReader;
      _startSyncTimer();
      PlaybackEventLog.instance.add('abs.session.queue', {
        'item': item.id,
        'episode': episode?.id,
        'tracks': session2.tracks.length,
        'src': trackSource,
      });
      return SpokenPlaybackSession(
        song: songs.first,
        queue: songs,
        resumeAt: Duration(milliseconds: (within * 1000).round()),
        sessionId: session.id,
        progressId: progressId,
      );
    }
    _activeSessionId = session.id;
    if (trackSource == 'itemTracks') {
      // The server opened an ffmpeg transcode for the HLS session; the
      // direct tracks make it pointless. Stop it now (flushing the session
      // position) and keep syncing progress via PATCH only - syncSession
      // no-ops on an empty session id.
      _activeSessionId = null;
      unawaited(api.closeSession(session.id,
          currentTime: session.currentTime, duration: totalSeconds));
      PlaybackEventLog.instance.add('abs.session.close',
          {'session': session.id, 'src': 'hls-stopped'});
    }
    _activeProgressId = progressId;
    _activeDuration = totalSeconds;
    _activeSongIds = songIds;
    _activeStartOffsetById = startOffsetById;
    _positionReader = positionReader;
    _songIdReader = songIdReader;
    _liveProgress[progressId] = session.currentTime;
    _startSyncTimer();
    PlaybackEventLog.instance.add('abs.session', {
      'item': item.id,
      'episode': episode?.id,
      'session': session.id,
      'tracks': session2.tracks.length,
      'resumeS': session2.currentTime.round(),
      'src': trackSource,
      // Path only (never the query) so diagnostics show what was opened.
      'url': Uri.parse(api.streamUrlOf(session2.tracks.first)).path,
    });
    return SpokenPlaybackSession(
      song: songs[trackIndex],
      queue: songs,
      resumeAt: Duration(milliseconds: (within * 1000).round()),
      sessionId: session.id,
      progressId: progressId,
    );
  }

  Future<List<Song>> _sessionSongs(AudiobookshelfApi api, AbsSession session,
      SpokenItem item, SpokenEpisode? episode) async {
    final baseId =
        episode == null ? 'abs_${item.id}' : 'abs_${item.id}_${episode.id}';
    final cover = NetworkImage(api.coverUrl(item.id).toString());
    final songs = <Song>[];
    for (var i = 0; i < session.tracks.length; i++) {
      // Every ABS stream goes through the loopback proxy: the engine's
      // audio-only desktop libs cannot parse HLS, and its direct fetches
      // from this class of server have stalled where the app's own HTTP
      // stack succeeds. The proxy forwards Range, so seeking survives.
      final url =
          await StreamProxy.proxyUrl(api.streamUrlOf(session.tracks[i]));
      songs.add(Song(
        // Track 0 keeps the plain id the playing-highlight keys expect;
        // later tracks suffix _t<i> so queue ids stay unique.
        id: i == 0 ? baseId : '${baseId}_t$i',
        title: session.tracks.length > 1
            ? '${episode?.title ?? item.title} (${i + 1}/${session.tracks.length})'
            : (episode?.title ?? item.title),
        artist: episode == null ? item.creator : item.title,
        artistId: '',
        albumId: '',
        duration: Duration(
            milliseconds: (session.tracks[i].duration * 1000).round()),
        gradientColors: const [Color(0xFF7C3AED), Color(0xFFFF6B9D)],
        artwork: cover,
        localFilePath: url,
      ));
    }
    return songs;
  }

  /// The episode a disguised-show tap should play: the one in progress,
  /// else the newest unplayed, else the newest.
  SpokenEpisode _pickEpisode(List<SpokenEpisode> episodes) {
    for (final episode in episodes) {
      final unfinished = episode.duration <= Duration.zero ||
          episode.progressSeconds < episode.duration.inSeconds;
      if (episode.progressSeconds > 0 && unfinished) return episode;
    }
    for (var i = episodes.length - 1; i >= 0; i--) {
      if (episodes[i].progressSeconds <= 0) return episodes[i];
    }
    return episodes.last;
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _syncActiveProgress());
  }

  /// Reports the live position to the server every 15 s while the session's
  /// songs are what the player is actually playing. When the player moves
  /// on to other music, the session closes itself.
  Future<void> _syncActiveProgress() async {
    final api = _api;
    if (api == null) {
      _syncTimer?.cancel();
      _syncTimer = null;
      return;
    }
    // A queued session whose song just became the current one is promoted
    // to THE active session - queued books sync progress like any other.
    if (_activeProgressId == null && _queuedSessions.isNotEmpty) {
      final songId = _songIdReader?.call();
      if (songId != null) {
        for (final entry in _queuedSessions.values.toList()) {
          if (entry.songIds.contains(songId)) {
            _queuedSessions.remove(entry.firstSongId);
            _activeSessionId = entry.sessionId;
            _activeProgressId = entry.progressId;
            _activeDuration = entry.durationSeconds;
            _activeSongIds = entry.songIds;
            _activeStartOffsetById = entry.startOffsetById;
            _liveProgress.putIfAbsent(entry.progressId, () => 0);
            PlaybackEventLog.instance.add('abs.session.adopt', {
              'session': entry.sessionId,
              'id': entry.progressId,
            });
            break;
          }
        }
      }
    }
    final progressId = _activeProgressId;
    if (progressId == null) {
      // Nothing active; the timer stays alive only for queued sessions.
      if (_queuedSessions.isEmpty) {
        _syncTimer?.cancel();
        _syncTimer = null;
      }
      return;
    }
    final sessionId = _activeSessionId ?? '';
    final seconds = _currentActiveSeconds();
    if (seconds == null) {
      await closeActiveSession();
      return;
    }
    if (seconds <= 0) {
      // Nothing audible has happened yet (playback may have failed to
      // load): several ABS versions reject currentTime 0 as an invalid
      // payload, and there is nothing meaningful to report anyway.
      return;
    }
    _liveProgress[progressId] = seconds;
    notifyListeners();
    try {
      await api.syncSession(sessionId,
          currentTime: seconds, duration: _activeDuration);
      await api.saveProgress(progressId,
          currentTime: seconds, duration: _activeDuration);
      PlaybackEventLog.instance.add('abs.sync', {
        'id': progressId,
        's': seconds.round(),
        'progress': _activeDuration <= 0
            ? '0'
            : (seconds / _activeDuration).toStringAsFixed(2),
      });
    } catch (e) {
      PlaybackEventLog.instance.add('abs.sync.fail', {
        'id': progressId,
        'err': e.toString().split('\n').first,
      });
    }
  }

  /// Current item/episode-relative seconds, or null when the player is no
  /// longer on this session's songs.
  double? _currentActiveSeconds() {
    final songId = _songIdReader?.call();
    if (songId == null || !_activeSongIds.contains(songId)) return null;
    final startOffset = _activeStartOffsetById[songId] ?? 0;
    final position = _positionReader?.call() ?? Duration.zero;
    return startOffset + position.inMilliseconds / 1000.0;
  }

  /// Flushes the final position and closes the session. Safe to call with
  /// nothing open. The position saved is the freshest one available: live
  /// reader if the session's song is still current, else the last synced
  /// value.
  Future<void> closeActiveSession() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    final api = _api;
    final sessionId = _activeSessionId;
    final progressId = _activeProgressId;
    final duration = _activeDuration;
    final seconds = _currentActiveSeconds() ??
        (progressId != null ? _liveProgress[progressId] : null);
    _activeSessionId = null;
    _activeProgressId = null;
    _activeDuration = 0;
    _activeSongIds = const [];
    _activeStartOffsetById = const {};
    _queuedSessions.clear();
    _positionReader = null;
    _songIdReader = null;
    if (api == null) return;
    if (progressId != null && seconds != null && seconds > 0) {
      _liveProgress[progressId] = seconds;
      try {
        await api.saveProgress(progressId,
            currentTime: seconds, duration: duration);
      } catch (_) {}
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      await api.closeSession(sessionId,
          currentTime: seconds, duration: duration);
    }
    if (sessionId != null || progressId != null) {
      PlaybackEventLog.instance.add('abs.session.close',
          {'session': sessionId ?? '', 's': seconds?.round() ?? -1});
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    unawaited(closeActiveSession());
    super.dispose();
  }
}

/// A play session opened for a queued song, parked until the player
/// reaches it. The sync tick promotes it to the active session then.
class _QueuedAbsSession {
  const _QueuedAbsSession({
    required this.sessionId,
    required this.progressId,
    required this.durationSeconds,
    required this.songIds,
    required this.startOffsetById,
  });
  final String sessionId;
  final String progressId;
  final double durationSeconds;
  final List<String> songIds;
  final Map<String, double> startOffsetById;
  String get firstSongId => songIds.first;
}

/// Everything the Books screen needs to hand one ABS item to the shared
/// player: the per-track queue, where to resume, and the id progress syncs
/// back under.
class SpokenPlaybackSession {
  const SpokenPlaybackSession({
    required this.song,
    required this.queue,
    required this.resumeAt,
    required this.sessionId,
    required this.progressId,
  });
  final Song song;
  final List<Song> queue;
  final Duration resumeAt;
  final String sessionId;
  final String progressId;
}

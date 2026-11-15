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
          if (item.type == SpokenMediaType.book || item.episodes.isEmpty)
            item,
      ];

  /// Items that behave as podcast shows (they have episodes).
  List<SpokenItem> get podcastShows => [
        for (final item in allItems)
          if (item.episodes.isNotEmpty) item,
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

  /// Opens a real ABS play session for a book or episode and returns the
  /// playable queue: one [Song] per server-issued audio track, resuming at
  /// the server-known position. This replaced the guessed
  /// `/api/items/:id/file/:index` URL, which some servers never answer -
  /// the session's own `contentUrl` is what ABS clients actually stream.
  Future<SpokenPlaybackSession?> openSession(SpokenItem item,
      {SpokenEpisode? episode,
      Duration Function()? positionReader,
      String? Function()? songIdReader}) async {
    final api = _api;
    if (api == null || connection == null) return null;
    // One session at a time: flush the old one's final position before the
    // server opens the next.
    await closeActiveSession();
    final session = await api.startPlayback(item.id, episodeId: episode?.id);
    final baseId =
        episode == null ? 'abs_${item.id}' : 'abs_${item.id}_${episode.id}';
    final cover = NetworkImage(api.coverUrl(item.id).toString());
    final songs = <Song>[
      for (var i = 0; i < session.tracks.length; i++)
        Song(
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
          localFilePath: api.streamUrlOf(session.tracks[i]),
        ),
    ];
    // Which track holds the resume point, and how far into it. The session
    // currentTime is item/episode-relative; each track has its offset.
    var trackIndex = session.tracks.length - 1;
    for (var i = 0; i < session.tracks.length; i++) {
      final candidate = session.tracks[i];
      if (session.currentTime <
              candidate.startOffset + candidate.duration ||
          i == session.tracks.length - 1) {
        trackIndex = i;
        break;
      }
    }
    final track = session.tracks[trackIndex];
    var within = session.currentTime - track.startOffset;
    if (within < 0) within = 0;
    if (track.duration > 1 && within > track.duration - 1) {
      within = track.duration - 1;
    }
    var totalSeconds =
        (episode?.duration ?? item.duration).inMilliseconds / 1000.0;
    if (totalSeconds <= 0) {
      totalSeconds = session.tracks.isEmpty
          ? 0
          : session.tracks.last.startOffset + session.tracks.last.duration;
    }

    _activeSessionId = session.id;
    _activeProgressId = episode == null ? item.id : '${item.id}/${episode.id}';
    _activeDuration = totalSeconds;
    _activeSongIds = [for (final song in songs) song.id];
    _activeStartOffsetById = {
      for (var i = 0; i < songs.length; i++)
        songs[i].id: session.tracks[i].startOffset,
    };
    _positionReader = positionReader;
    _songIdReader = songIdReader;
    _liveProgress[_activeProgressId!] = session.currentTime;
    _startSyncTimer();
    PlaybackEventLog.instance.add('abs.session', {
      'item': item.id,
      'episode': episode?.id,
      'session': session.id,
      'tracks': session.tracks.length,
      'resumeS': session.currentTime.round(),
    });
    return SpokenPlaybackSession(
      song: songs[trackIndex],
      queue: songs,
      resumeAt: Duration(milliseconds: (within * 1000).round()),
      sessionId: session.id,
      progressId: _activeProgressId!,
    );
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
    final progressId = _activeProgressId;
    if (api == null || progressId == null) return;
    final sessionId = _activeSessionId ?? '';
    final seconds = _currentActiveSeconds();
    if (seconds == null) {
      await closeActiveSession();
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
    _positionReader = null;
    _songIdReader = null;
    if (api == null) return;
    if (progressId != null && seconds != null) {
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
    PlaybackEventLog.instance.add('abs.session.close',
        {'session': sessionId ?? '', 's': seconds?.round() ?? -1});
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    unawaited(closeActiveSession());
    super.dispose();
  }
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

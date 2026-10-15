import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/music_repository.dart';
import '../backend/navidrome_music_repository.dart';
import '../services/library_cache.dart';
import '../services/server_secret_store.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/artwork_style.dart';
import '../models/download_state.dart';
import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/server_config.dart';
import '../models/smart_playlist_preset.dart';
import '../services/app_persistence.dart';
import '../services/shuro_pulse.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../widgets/page_transitions.dart';

/// Thrown by [AppState.importLocalFiles]/[AppState.importLocalFolder] when
/// local file import genuinely can't work on the current platform (web —
/// see those methods' doc comments for why). [message] is already
/// user-facing; show it directly rather than wrapping or reformatting it.
class LocalImportUnsupportedException implements Exception {
  final String message;
  const LocalImportUnsupportedException(this.message);

  @override
  String toString() => message;
}

/// Everything outside of "what's currently playing": auth/connection,
/// favorites, downloads, playlists, recent searches, and settings.
/// `connectToServer` talks to a real Navidrome/Subsonic server through a
/// [MusicRepository] (see lib/backend/); downloads and the rest are still
/// in-memory only. This is the one place in the app that knows a
/// repository exists at all — every screen reads through the catalog
/// getters/helpers below instead.
class AppState extends ChangeNotifier {
  AppState() {
    _initConnectivity();
    _restoreState();
  }

  // --- Persistence --------------------------------------------------------
  // Everything below used to be in-memory only: closing the app lost every
  // favorite, playlist, saved server, and setting. This is the one place
  // that loads/saves any of it — see lib/services/app_persistence.dart for
  // the storage wrapper itself. Loading is fire-and-forget from the
  // constructor (same pattern as [_initConnectivity]) rather than gating
  // app startup on it; the splash screen's fixed ~1.8s animation gives it
  // room to finish before anything reads this state in practice, and a
  // slower load just means that one launch starts fresh instead of
  // crashing or hanging.
  AppPersistence? _persistence;
  static const _kSettingsKey = 'settings_v1';
  static const _kFavSongsKey = 'fav_songs_v1';
  static const _kFavAlbumsKey = 'fav_albums_v1';
  static const _kFavArtistsKey = 'fav_artists_v1';
  static const _kHistoryKey = 'listening_history_v1';
  static const _kAffinityKey = 'artist_affinity_v1';
  static const _kPlaylistsKey = 'playlists_v1';
  static const _kLocalFoldersKey = 'local_folders_v1';
  static const _kServersKey = 'servers_v1';
  static const _kActiveServerKey = 'active_server_v1';
  static const _kLocalOnlyKey = 'local_only_v1';
  static const _kSavedQueueKey = 'saved_queue_v1';
  static const _kSavedQueueIndexKey = 'saved_queue_index_v1';
  static const _kSavedPositionKey = 'saved_position_ms_v1';

  List<String>? _savedQueueSongIds;
  int? _savedQueueIndex;
  int? _savedPositionMs;

  Future<void> _restoreState() async {
    try {
      final persistence = await AppPersistence.load();
      _persistence = persistence;

      final settingsJson = persistence.getString(_kSettingsKey);
      if (settingsJson != null) {
        try {
          final map = jsonDecode(settingsJson) as Map<String, dynamic>;
          wifiQuality = _qualityFromName(map['wifiQuality']) ?? wifiQuality;
          mobileQuality = _qualityFromName(map['mobileQuality']) ?? mobileQuality;
          downloadQuality = _qualityFromName(map['downloadQuality']) ?? downloadQuality;
          downloadWifiOnly = map['downloadWifiOnly'] as bool? ?? downloadWifiOnly;
          gaplessPlayback = map['gaplessPlayback'] as bool? ?? gaplessPlayback;
          crossfade = map['crossfade'] as bool? ?? crossfade;
          volumeNormalization = map['volumeNormalization'] as bool? ?? volumeNormalization;
          replayGain = map['replayGain'] as bool? ?? replayGain;
          autoplay = map['autoplay'] as bool? ?? autoplay;
          rememberQueue = map['rememberQueue'] as bool? ?? rememberQueue;
          resumePlayback = map['resumePlayback'] as bool? ?? resumePlayback;
          dynamicColors = map['dynamicColors'] as bool? ?? dynamicColors;
          reduceAnimations = map['reduceAnimations'] as bool? ?? reduceAnimations;
          reduceMotionEnabled = reduceAnimations;
          fontFamily = map['fontFamily'] as String? ?? fontFamily;
          currentFontFamily = fontFamily;
          lyricsProvider = LyricsProviderType.values.firstWhere((e) => e.name == map['lyricsProvider'], orElse: () => lyricsProvider);
          artworkStyle = ArtworkStyle.values.firstWhere((e) => e.name == map['artworkStyle'], orElse: () => artworkStyle);
          lyricsOffsetMs = map['lyricsOffsetMs'] as int? ?? lyricsOffsetMs;
          lyricsAutoScroll = map['lyricsAutoScroll'] as bool? ?? lyricsAutoScroll;
        } catch (_) {
          // Malformed/old-shape JSON (a future version changed a field
          // type) — keep the in-code defaults rather than crashing startup.
        }
      }

      favoriteSongIds.addAll(persistence.getStringList(_kFavSongsKey));
      favoriteAlbumIds.addAll(persistence.getStringList(_kFavAlbumsKey));
      favoriteArtistIds.addAll(persistence.getStringList(_kFavArtistsKey));

      listeningHistory.addAll(persistence.getStringList(_kHistoryKey));
      final affinityJson = persistence.getString(_kAffinityKey);
      if (affinityJson != null) {
        try {
          final map = jsonDecode(affinityJson) as Map<String, dynamic>;
          artistAffinity.addAll(map.map((k, v) => MapEntry(k, (v as num).toDouble())));
        } catch (_) {}
      }

      final playlistsJson = persistence.getString(_kPlaylistsKey);
      if (playlistsJson != null) {
        try {
          final list = jsonDecode(playlistsJson) as List<dynamic>;
          // Artwork is an ImageProvider and was never persisted — a
          // restored playlist falls back to its auto-collage/icon until
          // the user picks a cover again, same as a brand-new playlist.
          playlists = list.map((e) {
            final m = e as Map<String, dynamic>;
            return Playlist(
              id: m['id'] as String,
              name: m['name'] as String,
              songIds: (m['songIds'] as List<dynamic>).cast<String>(),
              smartPreset: m['smartPreset'] != null
                  ? SmartPlaylistPreset.values.firstWhere((p) => p.name == m['smartPreset'], orElse: () => SmartPlaylistPreset.rediscover)
                  : null,
            );
          }).toList();
        } catch (_) {}
      }

      // Re-walk every remembered local folder so imported local songs
      // survive a restart too — file_picker never remembers a past pick,
      // so the only way "local library" means anything across launches is
      // to persist the folder paths and re-scan them, not the songs
      // themselves.
      final folders = persistence.getStringList(_kLocalFoldersKey);
      // Off the critical path: folder rescans are disk I/O over possibly
      // large trees — they no longer delay the server reconnect. The local
      // library list fills in as each scan finishes (notifyListeners per
      // folder keeps the UI live).
      for (final folder in folders) {
        unawaited(() async {
          try {
            await _rescanFolder(folder);
            if (!localFolderPaths.contains(folder)) localFolderPaths.add(folder);
          } catch (_) {
            // Folder moved/unmounted/permission revoked since last launch —
            // drop it silently rather than block the rest of startup.
          }
        }());
      }

      // Passwords live in OS-backed secure storage (plan §7), never in plain
      // prefs. Legacy installs migrate on first load: any password found in
      // the old prefs JSON moves to the secure store and is scrubbed from
      // prefs immediately.
      final serverSecrets = await ServerSecretStore.readAll();
      final serversJson = persistence.getString(_kServersKey);
      if (serversJson != null) {
        var migratedLegacyPassword = false;
        try {
          final list = jsonDecode(serversJson) as List<dynamic>;
          final sanitized = <Map<String, dynamic>>[];
          for (final entry in list) {
            final m = entry as Map<String, dynamic>;
            final id = m['id'] as String;
            var password = serverSecrets[id] ?? '';
            final legacy = m['password'] as String?;
            if (legacy != null && legacy.isNotEmpty) {
              password = legacy;
              migratedLegacyPassword = true;
            }
            servers.add(ServerConfig(id: id, name: m['name'] as String, url: m['url'] as String, username: m['username'] as String, password: password));
            sanitized.add({'id': m['id'], 'name': m['name'], 'url': m['url'], 'username': m['username']});
          }
          if (migratedLegacyPassword) {
            for (final s in servers) {
              if (s.password.isNotEmpty) serverSecrets[s.id] = s.password;
            }
            await ServerSecretStore.writeAll(serverSecrets);
            // Scrub passwords out of prefs right away.
            await persistence.setString(_kServersKey, jsonEncode(sanitized));
          }
        } catch (_) {}
      }

      _savedQueueSongIds = persistence.getStringList(_kSavedQueueKey);
      if (_savedQueueSongIds!.isEmpty) _savedQueueSongIds = null;
      _savedQueueIndex = persistence.getInt(_kSavedQueueIndexKey);
      _savedPositionMs = persistence.getInt(_kSavedPositionKey);

      notifyListeners();

      // Reconnect automatically to whichever server (or local-only mode)
      // was active when the app last closed, so relaunching doesn't dump
      // an already-set-up user back onto Welcome every time. This is the
      // one place a restore triggers a real network call.
      final wasLocalOnly = persistence.getBool(_kLocalOnlyKey) ?? false;
      final lastActiveId = persistence.getString(_kActiveServerKey);
      if (lastActiveId != null && servers.any((s) => s.id == lastActiveId)) {
        await switchServer(lastActiveId);
      } else if (wasLocalOnly) {
        continueWithoutServer();
      }
    } catch (_) {
      // Persistence genuinely unavailable on this platform/sandbox — the
      // app still works, it just starts fresh every time, same as before
      // this existed.
    }
  }

  StreamingQuality? _qualityFromName(dynamic name) {
    if (name is! String) return null;
    for (final q in StreamingQuality.values) {
      if (q.name == name) return q;
    }
    return null;
  }

  Future<void> _persistSettings() async {
    final p = _persistence;
    if (p == null) return;
    final map = {
      'wifiQuality': wifiQuality.name,
      'mobileQuality': mobileQuality.name,
      'downloadQuality': downloadQuality.name,
      'downloadWifiOnly': downloadWifiOnly,
      'gaplessPlayback': gaplessPlayback,
      'crossfade': crossfade,
      'volumeNormalization': volumeNormalization,
      'replayGain': replayGain,
      'autoplay': autoplay,
      'rememberQueue': rememberQueue,
      'resumePlayback': resumePlayback,
      'dynamicColors': dynamicColors,
      'reduceAnimations': reduceAnimations,
      'fontFamily': fontFamily,
      'lyricsProvider': lyricsProvider.name,
      'artworkStyle': artworkStyle.name,
      'lyricsOffsetMs': lyricsOffsetMs,
      'lyricsAutoScroll': lyricsAutoScroll,
    };
    await p.setString(_kSettingsKey, jsonEncode(map));
  }

  Future<void> _persistFavorites() async {
    final p = _persistence;
    if (p == null) return;
    await Future.wait([
      p.setStringList(_kFavSongsKey, favoriteSongIds.toList()),
      p.setStringList(_kFavAlbumsKey, favoriteAlbumIds.toList()),
      p.setStringList(_kFavArtistsKey, favoriteArtistIds.toList()),
    ]);
  }

  Future<void> _persistHistory() async {
    final p = _persistence;
    if (p == null) return;
    await Future.wait([
      p.setStringList(_kHistoryKey, listeningHistory),
      p.setString(_kAffinityKey, jsonEncode(artistAffinity)),
    ]);
  }

  Future<void> _persistPlaylists() async {
    final p = _persistence;
    if (p == null) return;
    final list = playlists
        .map((pl) => {
              'id': pl.id,
              'name': pl.name,
              'songIds': pl.songIds,
              'smartPreset': pl.smartPreset?.name,
            })
        .toList();
    await p.setString(_kPlaylistsKey, jsonEncode(list));
  }

  Future<void> _persistLocalFolders() async {
    final p = _persistence;
    if (p == null) return;
    await p.setStringList(_kLocalFoldersKey, localFolderPaths);
  }

  Future<void> _persistServers() async {
    final p = _persistence;
    if (p == null) return;
    // The secret never touches prefs: it goes to OS-backed secure storage
    // (plan §7). Writing the current map also prunes entries for removed
    // servers.
    await ServerSecretStore.writeAll({for (final s in servers) s.id: s.password});
    final list = servers
        .map((s) => {'id': s.id, 'name': s.name, 'url': s.url, 'username': s.username}) // the secret itself goes to secure storage, below
        .toList();
    await Future.wait([
      p.setString(_kServersKey, jsonEncode(list)),
      activeServerId != null ? p.setString(_kActiveServerKey, activeServerId!) : p.remove(_kActiveServerKey),
      p.setBool(_kLocalOnlyKey, isLocalOnly),
    ]);
  }

  /// One-shot: hands back the queue/position saved from a previous session
  /// (if "Remember queue" was on then, persistence has finished loading,
  /// and the saved song IDs still resolve to real songs) and clears it so
  /// it's never replayed again this run. Wired from app.dart's startup
  /// into `PlayerController.restoreQueue`.
  ({List<Song> queue, int index, Duration position})? takeSavedQueue() {
    final ids = _savedQueueSongIds;
    if (ids == null || ids.isEmpty) return null;
    _savedQueueSongIds = null;
    final songs = songsByIds(ids);
    if (songs.isEmpty) return null;
    final index = (_savedQueueIndex ?? 0).clamp(0, songs.length - 1);
    return (queue: songs, index: index, position: Duration(milliseconds: _savedPositionMs ?? 0));
  }

  /// Saves the current queue/position so [takeSavedQueue] can restore it
  /// next launch — called from app.dart when the app is backgrounded.
  /// Gated on [rememberQueue]/[resumePlayback] here (not at the call
  /// site) so both toggles keep meaning exactly what their Settings rows
  /// say: queue remembered at all, and whether position within it is too.
  Future<void> persistQueueState(List<Song> queue, int index, Duration position) async {
    final p = _persistence;
    if (p == null) return;
    if (!rememberQueue || queue.isEmpty) {
      await p.setStringList(_kSavedQueueKey, const []);
      return;
    }
    await Future.wait([
      p.setStringList(_kSavedQueueKey, queue.map((s) => s.id).toList()),
      p.setInt(_kSavedQueueIndexKey, index),
      p.setInt(_kSavedPositionKey, resumePlayback ? position.inMilliseconds : 0),
    ]);
  }

  // --- Connection / servers --------------------------------------------
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  String? connectionErrorMessage;
  final List<ServerConfig> servers = [];
  String? activeServerId;

  // --- Network type (Wi-Fi vs. mobile data) --------------------------------
  // Drives which of wifiQuality/mobileQuality actually applies to a stream
  // (see [effectiveStreamingQuality]) — without this, those two Settings
  // rows picked a label but never changed what played. Optimistic default
  // (true) until the first real read comes back, matching the pre-existing
  // default behavior (wifiQuality, the higher-quality setting) rather than
  // guessing the slower/capped one while connectivity_plus is still
  // starting up.
  bool _isOnWifi = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Future<void> _initConnectivity() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _isOnWifi = _resolveIsWifi(initial);
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final onWifi = _resolveIsWifi(results);
        if (onWifi != _isOnWifi) {
          _isOnWifi = onWifi;
          notifyListeners();
        }
      });
    } catch (_) {
      // No connectivity plugin support on this platform/device — keep the
      // optimistic default rather than letting this block app startup.
    }
  }

  /// Wi-Fi wins if it's present at all (e.g. "Wi-Fi + mobile" dual
  /// connectivity still means a Wi-Fi quality cap, not a mobile one); an
  /// empty/none result means no connection, which isn't a quality
  /// decision this makes — streaming will simply fail downstream and
  /// surface through [PlayerController.lastPlaybackError] instead.
  bool _resolveIsWifi(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet)) return true;
    if (results.contains(ConnectivityResult.mobile)) return false;
    return _isOnWifi;
  }

  /// Which of [wifiQuality]/[mobileQuality] actually governs the next
  /// stream, resolved against the device's current connection type —
  /// see [audioSourceFor].
  StreamingQuality get effectiveStreamingQuality => _isOnWifi ? wifiQuality : mobileQuality;

  /// The live backend for whichever server is connected, and the one
  /// library fetch taken from it on connect (see [MusicRepository] for
  /// why this is fetched once and cached rather than queried per screen).
  /// Both are null/empty whenever [hasServer] is false.
  MusicRepository? _repository;
  MusicLibrarySnapshot _librarySnapshot = MusicLibrarySnapshot.empty;

  /// True while a fresh library fetch is running (either first connect or
  /// background revalidate). Skeletons key off this instead of fake timers.
  bool isSyncingLibrary = false;

  /// True while the visible library came from the disk cache and the fresh
  /// fetch is still in flight (or has failed) — cached data stays browsable.
  bool libraryFromCache = false;

  /// True when the last connect failed AND the cached library is what's on
  /// screen — offline browsing. Server streaming comes back with the server.
  bool libraryOffline = false;

  /// Server-side lastScan timestamp recorded with the cached snapshot.
  /// Compared against getScanStatus before a full re-fetch: unchanged scan
  /// means unchanged library, so the fetch is skipped entirely.
  int? _cachedLastScan;

  ServerConfig? get activeServer {
    if (activeServerId == null) return null;
    for (final s in servers) {
      if (s.id == activeServerId) return s;
    }
    return null;
  }

  /// True once a server is actually connected — gates every screen's
  /// access to the fetched server catalog (see [_librarySnapshot]). False
  /// while disconnected *and* while in [ConnectionStatus.localOnly], so a
  /// user who skips server setup sees only their own local files, never
  /// server data.
  bool get hasServer => connectionStatus == ConnectionStatus.connected && activeServer != null;

  bool get isLocalOnly => connectionStatus == ConnectionStatus.localOnly;

  /// Validates [draft], connects to it over the real Navidrome/Subsonic
  /// API (ping + a one-time full library fetch — see [MusicRepository]),
  /// and on success saves it and makes it the active server. A blank name
  /// defaults to "Server N" by connection order, so switching servers
  /// never just shows a bare URL.
  Future<void> connectToServer(ServerConfig draft) async {
    connectionStatus = ConnectionStatus.connecting;
    connectionErrorMessage = null;
    notifyListeners();

    // Cache-first: for an already-saved server, paint its cached library
    // IMMEDIATELY — launch stops waiting on the network for the first screen.
    // The validation + connect + full fetch below then swaps in fresh data
    // (and rewrites the cache). A first-time connect has no cache by
    // definition (the server isn't in [servers] yet).
    if (draft.id.isNotEmpty && servers.any((s) => s.id == draft.id)) {
      final cached = await LibraryCache.load(draft.id);
      if (cached != null) {
        _librarySnapshot = cached.snapshot;
        _cachedLastScan = cached.lastScan;
        activeServerId = draft.id;
        libraryFromCache = true;
        libraryOffline = false;
        connectionStatus = ConnectionStatus.connected;
        connectionErrorMessage = null;
        notifyListeners();
      }
    }

    final url = draft.url.trim();
    if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      connectionStatus = ConnectionStatus.unreachable;
      connectionErrorMessage = "Couldn't reach that server. Check the URL and try again.";
      notifyListeners();
      return;
    }
    if (draft.username.trim().isEmpty || draft.password.isEmpty) {
      connectionStatus = ConnectionStatus.invalidCredentials;
      connectionErrorMessage = 'Incorrect username or password.';
      notifyListeners();
      return;
    }

    final repository = NavidromeMusicRepository(baseUrl: url, username: draft.username, password: draft.password);
    try {
      await repository.connect();
      isSyncingLibrary = true;
      notifyListeners();
      final snapshot = await repository.fetchLibrary();

      // Only swap in the new repository/snapshot once both steps above
      // succeeded — a failed reconnect attempt must never wipe out an
      // already-working connection.
      _repository?.dispose();
      _repository = repository;
      _librarySnapshot = snapshot;

      final id = draft.id.isNotEmpty ? draft.id : 'server_${DateTime.now().microsecondsSinceEpoch}';
      final name = draft.name.trim().isNotEmpty ? draft.name.trim() : 'Server ${servers.length + 1}';
      final saved = ServerConfig(id: id, name: name, url: url, username: draft.username, password: draft.password);
      final existingIndex = servers.indexWhere((s) => s.id == id);
      if (existingIndex >= 0) {
        servers[existingIndex] = saved;
      } else {
        servers.add(saved);
      }
      activeServerId = id;
      connectionStatus = ConnectionStatus.connected;
      connectionErrorMessage = null;
      libraryFromCache = false;
      libraryOffline = false;
      isSyncingLibrary = false;
      if (id.isNotEmpty) unawaited(LibraryCache.save(id, snapshot, lastScan: _cachedLastScan));
      unawaited(_persistServers());
    } on MusicRepositoryException catch (e) {
      repository.dispose();
      isSyncingLibrary = false;
      if (libraryFromCache) {
        // Cached library stays up: offline browsing, downloads and local
        // files all work; server streaming returns with the server.
        libraryOffline = true;
        connectionStatus = ConnectionStatus.connected;
        connectionErrorMessage = null;
      } else {
        connectionStatus = switch (e.kind) {
          MusicRepositoryFailure.invalidCredentials => ConnectionStatus.invalidCredentials,
          MusicRepositoryFailure.unreachable => ConnectionStatus.unreachable,
          MusicRepositoryFailure.unknown => ConnectionStatus.unreachable,
        };
        connectionErrorMessage = e.message;
      }
    } catch (e) {
      repository.dispose();
      isSyncingLibrary = false;
      if (libraryFromCache) {
        libraryOffline = true;
        connectionStatus = ConnectionStatus.connected;
        connectionErrorMessage = null;
      } else {
        connectionStatus = ConnectionStatus.unreachable;
        connectionErrorMessage = "Couldn't reach that server. Check the URL and try again.";
      }
    }
    notifyListeners();
  }

  /// Lets a user with no Navidrome server at all skip straight into the
  /// app — Home/Library/Search/Discover then show local files only
  /// (see [hasServer]), and Settings offers "Connect a server" to upgrade
  /// into the full catalog later without losing anything local.
  void continueWithoutServer() {
    connectionStatus = ConnectionStatus.localOnly;
    connectionErrorMessage = null;
    notifyListeners();
    unawaited(_persistServers());
  }

  /// Re-fetches the active server's library from scratch and swaps it in —
  /// what pull-to-refresh on Home/Library actually calls now, instead of
  /// the fixed delay that used to stand in for it. A failure here is
  /// swallowed (the existing, already-working snapshot is kept) rather
  /// than surfaced as a hard error — a refresh that can't reach the server
  /// right now shouldn't nuke what's already loaded and playable.
  Future<void> refreshLibrary() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      // Change detection: when the server reports its last scan unchanged
      // since the cached snapshot, the library is unchanged — skip the full
      // fetch (one getAlbum per album) entirely.
      try {
        final scanInfo = await repository.getScanStatus();
        final remote = scanInfo.lastScan?.millisecondsSinceEpoch;
        if (remote != null && _cachedLastScan != null && remote == _cachedLastScan) {
          libraryOffline = false;
          return;
        }
        if (remote != null) _cachedLastScan = remote;
      } catch (_) {
        // Server without getScanStatus (older Navidrome): fall through to the
        // full fetch — change detection is an optimisation, not a gate.
      }
      isSyncingLibrary = true;
      notifyListeners();
      final snapshot = await repository.fetchLibrary();
      _librarySnapshot = snapshot;
      libraryFromCache = false;
      libraryOffline = false;
      final serverId = activeServerId;
      if (serverId != null && serverId.isNotEmpty) {
        unawaited(LibraryCache.save(serverId, snapshot, lastScan: _cachedLastScan));
      }
      isSyncingLibrary = false;
      notifyListeners();
    } catch (_) {
      isSyncingLibrary = false;
      // Transient network hiccup — keep showing the last good snapshot.
      notifyListeners();
    }
  }

  /// Switches to an already-saved server, re-connecting (and re-fetching
  /// its library) over the network with its saved credentials — reusing
  /// [connectToServer] so there's exactly one real-connection code path.
  Future<void> switchServer(String id) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    await connectToServer(servers[index]);
  }

  void removeServer(String id) {
    HapticFeedback.mediumImpact();
    servers.removeWhere((s) => s.id == id);
    if (activeServerId == id) {
      if (servers.isNotEmpty) {
        // Reconnecting is async; notify now so the removal itself shows
        // up immediately, then let switchServer's own notifyListeners
        // calls carry the connecting/connected-or-failed transition.
        activeServerId = servers.first.id;
        notifyListeners();
        switchServer(activeServerId!);
        return;
      }
      activeServerId = null;
      _repository?.dispose();
      _repository = null;
      _librarySnapshot = MusicLibrarySnapshot.empty;
      // Fall back to local-only rather than disconnected if there's
      // nothing left to reconnect to — removing a server shouldn't by
      // itself kick the user back out to onboarding when they still
      // have local music to listen to.
      connectionStatus = ConnectionStatus.localOnly;
    }
    notifyListeners();
    unawaited(_persistServers());
  }

  void renameServer(String id, String newName) {
    final index = servers.indexWhere((s) => s.id == id);
    if (index < 0 || newName.trim().isEmpty) return;
    servers[index] = servers[index].copyWith(name: newName.trim());
    notifyListeners();
    unawaited(_persistServers());
  }

  /// Signs out of the current session. Saved servers are kept so the
  /// Welcome screen can offer a one-tap reconnect instead of re-entering
  /// credentials.
  void disconnect() {
    connectionStatus = ConnectionStatus.disconnected;
    activeServerId = null;
    _repository?.dispose();
    _repository = null;
    _librarySnapshot = MusicLibrarySnapshot.empty;
    notifyListeners();
    // Clears the *active* server/local-only flag so the next launch lands
    // on Welcome rather than silently auto-reconnecting after a deliberate
    // sign-out — the saved server list itself is left alone, which is what
    // lets Welcome still offer a one-tap reconnect.
    unawaited(_persistServers());
  }

  // --- Catalog access (server-gated) --------------------------------------
  // Every screen reads the library through these instead of touching a
  // repository (or MockLibrary) directly, so "skip server, use local
  // files" actually means that — nothing from a connected server leaks
  // through when there's no server connected — and so the backend can be
  // swapped without any screen changing.
  List<Song> get catalogSongs => hasServer ? _librarySnapshot.songs : const [];
  List<Album> get catalogAlbums => hasServer ? _librarySnapshot.albums : const [];
  List<Artist> get catalogArtists => hasServer ? _librarySnapshot.artists : const [];
  Map<String, List<String>> get catalogGenres => hasServer ? _librarySnapshot.genreSongIds : const {};

  /// Everything actually playable right now: the server catalog (if
  /// connected) plus whatever's been imported from the device.
  List<Song> get allSongs => [...catalogSongs, ...localSongs];

  /// True once there's anything at all to listen to — used to decide
  /// between showing real content and a "get started" empty state.
  bool get hasAnyMusic => hasServer || localSongs.isNotEmpty;

  /// Resolves a song ID against local files first, then the connected
  /// server's catalog — the one place every screen should look up a song
  /// by ID, so favorites/playlists/queues built from local files resolve
  /// correctly instead of only ever finding server tracks.
  Song? songById(String id) {
    for (final s in localSongs) {
      if (s.id == id) return s;
    }
    if (!hasServer) return null;
    for (final s in _librarySnapshot.songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Song> songsByIds(List<String> ids) => ids.map(songById).whereType<Song>().toList();

  Album? albumById(String id) {
    if (!hasServer) return null;
    for (final a in _librarySnapshot.albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  Artist? artistById(String id) {
    if (!hasServer) return null;
    for (final a in _librarySnapshot.artists) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Song> songsForAlbum(String albumId) {
    final album = albumById(albumId);
    if (album == null) return const [];
    return songsByIds(album.songIds);
  }

  List<Album> albumsForArtist(String artistId) => catalogAlbums.where((a) => a.artistId == artistId).toList();

  /// Songs actually tagged with [genre] — keyed by song ID (see
  /// [MusicLibrarySnapshot.genreSongIds]), not by "any song this artist
  /// has ever released," so an artist who spans several genres doesn't
  /// have their whole catalog show up under each one.
  List<Song> songsForGenre(String genre) => songsByIds(catalogGenres[genre] ?? const []);

  List<Song> searchCatalogSongs(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return catalogSongs.where((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q)).toList();
  }

  List<Album> searchCatalogAlbums(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return catalogAlbums.where((a) => a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q)).toList();
  }

  List<Artist> searchCatalogArtists(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return catalogArtists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  /// A directly-playable source for [song] — its own file path if it was
  /// imported from the device, otherwise a stream URL from whichever
  /// backend is connected right now, built for [effectiveStreamingQuality]
  /// (Settings -> Wi-Fi/Mobile data quality, picked by the device's actual
  /// current connection). Null means there's genuinely nothing to play (no
  /// server connected, or the connected backend has no audio behind this
  /// particular song) — [PlayerController] is expected to fail that
  /// gracefully rather than crash.
  String? audioSourceFor(Song song) {
    if (song.localFilePath != null) return song.localFilePath;
    return _repository?.streamUrlFor(song, quality: effectiveStreamingQuality);
  }

  /// Lyrics the connected backend already extracted from [song]'s own
  /// file tags — null for a local import (there's no backend to ask) or
  /// when nothing's connected or embedded. Wired into `LyricsScreen` so
  /// embedded lyrics are tried before falling back to an LRCLIB lookup.
  /// Swallows any throw from the repository the same way "nothing
  /// embedded" is handled — a hiccup here should never block the LRCLIB
  /// fallback from running.
  Future<LyricsTrack?> fetchEmbeddedLyrics(Song song) async {
    if (!hasServer || song.isLocal) return null;
    try {
      return await _repository?.fetchEmbeddedLyrics(song);
    } catch (_) {
      return null;
    }
  }

  /// Lock-screen/notification metadata for [song] that [PlayerController]
  /// can't derive from the song alone — the real album title (songs only
  /// carry an albumId) and a URL the system notification can load artwork
  /// from. Wired to `PlayerController.metadataResolver` in app.dart.
  NowPlayingMetadata nowPlayingMetadataFor(Song song) {
    final artwork = song.artwork;
    return NowPlayingMetadata(
      albumTitle: albumById(song.albumId)?.title,
      artUri: artwork is NetworkImage ? Uri.tryParse(artwork.url) : null,
    );
  }

  /// Newest songs first. Accurate without any extra request: the
  /// Navidrome client already fetches albums newest-first (see
  /// NavidromeApiClient.getAllAlbums), so this just reads off that order.
  List<Song> recentlyAddedSongs({int limit = 10}) {
    if (!hasServer) return const [];
    final result = <Song>[];
    for (final album in catalogAlbums) {
      for (final id in album.songIds) {
        final song = songById(id);
        if (song == null) continue;
        result.add(song);
        if (result.length >= limit) return result;
      }
    }
    return result;
  }

  List<Album> recentlyAddedAlbums({int limit = 10}) => hasServer ? catalogAlbums.take(limit).toList() : const [];

  /// What's actually been played in this app, most-recent first — real
  /// signal from [listeningHistory], not anything the backend provides
  /// (Subsonic has no durable per-user play-history endpoint this client
  /// relies on).
  List<Song> recentlyPlayedSongs({int limit = 10}) => songsByIds(listeningHistory).take(limit).toList();

  // --- Favorites --------------------------------------------------------
  final Set<String> favoriteSongIds = {};
  final Set<String> favoriteAlbumIds = {};
  final Set<String> favoriteArtistIds = {};

  bool isFavoriteSong(String id) => favoriteSongIds.contains(id);
  bool isFavoriteAlbum(String id) => favoriteAlbumIds.contains(id);
  bool isFavoriteArtist(String id) => favoriteArtistIds.contains(id);

  void toggleFavoriteSong(String id) => _toggle(favoriteSongIds, id);
  void toggleFavoriteAlbum(String id) => _toggle(favoriteAlbumIds, id);
  void toggleFavoriteArtist(String id) => _toggle(favoriteArtistIds, id);

  void _toggle(Set<String> set, String id) {
    HapticFeedback.lightImpact();
    set.contains(id) ? set.remove(id) : set.add(id);
    notifyListeners();
    unawaited(_persistFavorites());
  }

  // --- Shuro Pulse signals ------------------------------------------------
  // Everything Discover/Smart Playlists/Build-with-Shuro read from — most
  // recently played first, and a lightweight per-artist like/dislike score
  // from the "More/Less like this" feedback. Both are in-memory only, same
  // as the rest of this mock layer; see ShuroPulse for how they're used.
  final List<String> listeningHistory = [];
  static const int _listeningHistoryCap = 40;

  final Map<String, double> artistAffinity = {};
  static const double _feedbackStep = 1.5;

  void recordPlay(String songId) {
    listeningHistory.remove(songId);
    listeningHistory.insert(0, songId);
    if (listeningHistory.length > _listeningHistoryCap) {
      listeningHistory.removeRange(_listeningHistoryCap, listeningHistory.length);
    }
    notifyListeners();
    unawaited(_persistHistory());
  }

  /// "More like this" / "Less like this" feedback from a recommendation
  /// surface — nudges that artist's songs up or down in future Discover
  /// rankings without an explicit unfavorite/block action.
  void recordArtistFeedback(String artistId, bool positive) {
    if (artistId.isEmpty) return;
    HapticFeedback.selectionClick();
    final current = artistAffinity[artistId] ?? 0;
    artistAffinity[artistId] = current + (positive ? _feedbackStep : -_feedbackStep);
    notifyListeners();
    unawaited(_persistHistory());
  }

  // --- Downloads ----------------------------------------------------------
  final Map<String, DownloadStatus> _downloads = {};

  DownloadStatus downloadStatusFor(String songId) => _downloads[songId] ?? const DownloadStatus();

  Set<String> get downloadedSongIds => _downloads.entries
      .where((e) => e.value.stage == DownloadStage.downloaded)
      .map((e) => e.key)
      .toSet();

  /// True when a download is actually allowed to proceed right now —
  /// Settings → Downloads → "Wi-Fi only" gates [startDownload] against the
  /// same real connectivity read [effectiveStreamingQuality] uses, so
  /// turning that toggle on genuinely blocks a mobile-data download
  /// instead of just displaying a preference that nothing reads.
  bool get canDownloadNow => _isOnWifi || !downloadWifiOnly;

  /// Returns false (without starting anything) when "Wi-Fi only" is on and
  /// the device isn't on Wi-Fi right now — callers check this first so
  /// they can show their own "connect to Wi-Fi to download this" message
  /// (see song_actions_sheet.dart/album_actions_sheet.dart), the same
  /// "check [canDownloadNow]/[importingLocalFiles] before calling"
  /// pattern already used for local import.
  Future<bool> startDownload(String songId) async {
    if (!canDownloadNow) return false;
    HapticFeedback.lightImpact();
    _downloads[songId] = const DownloadStatus(stage: DownloadStage.downloading, progress: 0);
    notifyListeners();
    for (var i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (_downloads[songId]?.stage != DownloadStage.downloading) return true; // cancelled/removed
      _downloads[songId] = DownloadStatus(stage: DownloadStage.downloading, progress: i / 10);
      notifyListeners();
    }
    _downloads[songId] = const DownloadStatus(stage: DownloadStage.downloaded, progress: 1);
    HapticFeedback.lightImpact();
    notifyListeners();
    return true;
  }

  void removeDownload(String songId) {
    _downloads.remove(songId);
    notifyListeners();
  }

  void clearAllDownloads() {
    HapticFeedback.mediumImpact();
    _downloads.clear();
    notifyListeners();
  }

  double get storageUsedGb => downloadedSongIds.length * 0.045; // rough mock estimate
  static const double storageLimitGb = 64;

  // --- Local files --------------------------------------------------------
  // See LocalImportUnsupportedException above for why this is a mobile/
  // desktop-only feature (Shuro is Android-first, iOS later — web was
  // never a target platform, and file_picker doesn't support real file
  // paths or folder picking in a browser anyway).
  final List<Song> localSongs = [];
  bool importingLocalFiles = false;

  /// Folders the user has pointed Shuro at via [importLocalFolder] — a
  /// folder is a standing "source" rather than a one-off action: it's
  /// remembered here (for display, and so [removeLocalFolder] can drop
  /// everything that came from it) even though re-scanning it is still a
  /// manual, explicit action rather than an automatic watch/sync.
  final List<String> localFolderPaths = [];

  static const List<List<Color>> _localGradients = [
    [Color(0xFF7C4DFF), Color(0xFF00C9A7)],
    [Color(0xFFFF7A00), Color(0xFFFEB722)],
    [Color(0xFF5642DD), Color(0xFFFF32C7)],
    [Color(0xFF0575E6), Color(0xFF00C9A7)],
  ];

  static const Set<String> _audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'aiff', 'alac',
  };

  bool _isAudioFile(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _audioExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Builds a [Song] for [path], or null if that exact file is already in
  /// [localSongs] — the one place both import flows below de-dupe, so
  /// picking the same file twice (once by hand, once inside a folder scan)
  /// never adds it twice.
  Song? _buildLocalSong(String path) {
    if (localSongs.any((s) => s.localFilePath == path)) return null;
    final name = path.split(Platform.pathSeparator).last;
    final title = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    return Song(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}_${localSongs.length}',
      title: title,
      artist: 'Local file',
      artistId: '',
      albumId: '',
      duration: const Duration(minutes: 3, seconds: 30),
      gradientColors: _localGradients[localSongs.length % _localGradients.length],
      localFilePath: path,
    );
  }

  /// Opens the device file picker for audio files and adds whatever the
  /// user selects to the local library. Real duration/metadata reading
  /// (ID3 tags, actual length) is a natural next step — titles are taken
  /// from the file name for now.
  ///
  /// Throws [LocalImportUnsupportedException] on web: Shuro is an Android
  /// (then iOS) app, and `file_picker`'s web backend exposes picked files
  /// as in-memory bytes with no real file path at all — accessing
  /// `PlatformFile.path` there throws rather than returning null, and
  /// there's nothing a path-based [Song.localFilePath]/`just_audio`
  /// could play even if it didn't. Failing fast with a clear message here
  /// beats letting that throw straight through to an unhandled crash.
  Future<int> importLocalFiles() async {
    if (kIsWeb) {
      throw const LocalImportUnsupportedException(
        "Importing local files isn't supported when running Shuro in a browser — try this on Android, iOS, or desktop instead.",
      );
    }
    importingLocalFiles = true;
    notifyListeners();
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
      if (result == null) return 0;
      var added = 0;
      for (final file in result.files) {
        final song = _buildLocalSong(file.path ?? file.name);
        if (song == null) continue;
        localSongs.add(song);
        added++;
      }
      if (added > 0) HapticFeedback.lightImpact();
      return added;
    } finally {
      importingLocalFiles = false;
      notifyListeners();
    }
  }

  /// Opens the device's folder picker and imports every audio file found
  /// inside it (recursively) — the "point me at a whole music folder"
  /// alternative to picking files one at a time. Can be called again for
  /// another folder: each distinct folder the user adds is kept in
  /// [localFolderPaths], so the local library can be built from several
  /// folder sources at once, not just one.
  ///
  /// Throws [LocalImportUnsupportedException] on web: `file_picker`
  /// doesn't implement folder picking there at all
  /// (`getDirectoryPath()` throws `UnimplementedError`), and there's no
  /// `dart:io` filesystem to recursively scan even if it did.
  Future<int> importLocalFolder() async {
    if (kIsWeb) {
      throw const LocalImportUnsupportedException(
        "Importing a music folder isn't supported when running Shuro in a browser — try this on Android, iOS, or desktop instead.",
      );
    }
    importingLocalFiles = true;
    notifyListeners();
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return 0;
      final added = await _rescanFolder(path);
      if (!localFolderPaths.contains(path)) localFolderPaths.add(path);
      if (added > 0) HapticFeedback.lightImpact();
      unawaited(_persistLocalFolders());
      return added;
    } finally {
      importingLocalFiles = false;
      notifyListeners();
    }
  }

  /// Recursively walks [path] and adds whatever new audio files it finds
  /// to [localSongs] (via [_buildLocalSong]'s own de-dupe) — the scan half
  /// of [importLocalFolder], pulled out so [_restoreState] can re-run it
  /// for every remembered folder on startup without going through the
  /// file picker again. Swallows a [FileSystemException] (folder moved,
  /// unmounted, or permission revoked since last picked) as "0 new files"
  /// rather than throwing, same as [importLocalFolder] always has.
  Future<int> _rescanFolder(String path) async {
    var added = 0;
    try {
      final entries = Directory(path).list(recursive: true, followLinks: false);
      await for (final entity in entries) {
        if (entity is! File || !_isAudioFile(entity.path)) continue;
        final song = _buildLocalSong(entity.path);
        if (song == null) continue;
        localSongs.add(song);
        added++;
      }
    } on FileSystemException {
      return added;
    }
    return added;
  }

  /// Removes a folder source and every local song that came from it —
  /// matched by path prefix since songs from that folder were never given
  /// any other link back to it.
  void removeLocalFolder(String path) {
    HapticFeedback.mediumImpact();
    localSongs.removeWhere((s) => s.localFilePath?.startsWith(path) ?? false);
    localFolderPaths.remove(path);
    notifyListeners();
    unawaited(_persistLocalFolders());
  }

  void removeLocalSong(String songId) {
    String? path;
    for (final s in localSongs) {
      if (s.id == songId) {
        path = s.localFilePath;
        break;
      }
    }
    localSongs.removeWhere((s) => s.id == songId);
    // If that was the last song from one of its folder sources, drop the
    // now-empty source too rather than leaving a stale entry around.
    var foldersChanged = false;
    if (path != null) {
      final before = localFolderPaths.length;
      localFolderPaths.removeWhere((folder) => path!.startsWith(folder) && !localSongs.any((s) => s.localFilePath?.startsWith(folder) ?? false));
      foldersChanged = localFolderPaths.length != before;
    }
    notifyListeners();
    if (foldersChanged) unawaited(_persistLocalFolders());
  }

  /// Opens the device image picker and returns bytes suitable for a
  /// MemoryImage (works the same on web and on-device), or null if the
  /// user cancelled *or* the picker itself failed (a denied permission, a
  /// platform hiccup) — callers treat both the same way (no image picked),
  /// which matters here specifically: without this try/catch, a thrown
  /// permission/platform exception would propagate past the `setState`
  /// that resets a caller's own loading flag, leaving avatar/playlist-art
  /// pickers stuck showing a spinner forever instead of just doing nothing.
  Future<Uint8List?> pickImageBytes() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      return result?.files.single.bytes;
    } catch (_) {
      return null;
    }
  }

  // --- Recent searches ------------------------------------------------
  final List<String> recentSearches = [];

  void addRecentSearch(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    recentSearches.remove(trimmed);
    recentSearches.insert(0, trimmed);
    if (recentSearches.length > 8) recentSearches.removeLast();
    notifyListeners();
  }

  void clearRecentSearches() {
    recentSearches.clear();
    notifyListeners();
  }

  // --- Playlists --------------------------------------------------------
  List<Playlist> playlists = [];

  Playlist createPlaylist(String name, {ImageProvider? artwork, List<String> songIds = const [], SmartPlaylistPreset? smartPreset}) {
    HapticFeedback.lightImpact();
    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      songIds: songIds,
      artwork: artwork,
      smartPreset: smartPreset,
    );
    playlists = [...playlists, playlist];
    notifyListeners();
    unawaited(_persistPlaylists());
    return playlist;
  }

  /// Pins one of ShuroPulse's live Smart Playlist presets into the
  /// playlist list. The actual track list is never stored — PlaylistDetail
  /// re-runs ShuroPulse.smartPlaylistSongs every time it's opened; the
  /// handful of song IDs saved here only seed the cover-art collage so the
  /// playlist doesn't show a blank icon before it's first opened.
  Playlist createSmartPlaylist(SmartPlaylistPreset preset) {
    final existing = playlists.where((p) => p.smartPreset == preset);
    if (existing.isNotEmpty) return existing.first;
    final previewIds = ShuroPulse.smartPlaylistSongs(preset, this).take(4).map((s) => s.id).toList();
    return createPlaylist(preset.label, smartPreset: preset, songIds: previewIds);
  }

  void updatePlaylistArtwork(String playlistId, ImageProvider? artwork, {bool clear = false}) {
    playlists = [
      for (final p in playlists)
        if (p.id == playlistId) p.copyWith(artwork: artwork, clearArtwork: clear) else p,
    ];
    notifyListeners();
  }

  void renamePlaylist(String playlistId, String newName) {
    playlists = [
      for (final p in playlists)
        if (p.id == playlistId) p.copyWith(name: newName) else p,
    ];
    notifyListeners();
    unawaited(_persistPlaylists());
  }

  void deletePlaylist(String playlistId) {
    HapticFeedback.mediumImpact();
    playlists = playlists.where((p) => p.id != playlistId).toList();
    notifyListeners();
    unawaited(_persistPlaylists());
  }

  void addSongToPlaylist(String playlistId, String songId) {
    HapticFeedback.lightImpact();
    playlists = [
      for (final p in playlists)
        if (p.id == playlistId && !p.songIds.contains(songId))
          p.copyWith(songIds: [...p.songIds, songId])
        else
          p,
    ];
    notifyListeners();
    unawaited(_persistPlaylists());
  }

  void removeSongFromPlaylist(String playlistId, String songId) {
    playlists = [
      for (final p in playlists)
        if (p.id == playlistId) p.copyWith(songIds: p.songIds.where((id) => id != songId).toList()) else p,
    ];
    notifyListeners();
    unawaited(_persistPlaylists());
  }

  // --- Playback / download settings --------------------------------------
  StreamingQuality wifiQuality = StreamingQuality.original;
  StreamingQuality mobileQuality = StreamingQuality.high;
  // A separate setting from mobileQuality — Settings -> Downloads used to
  // read and write mobileQuality under a "Download quality" label, so
  // changing one silently changed the other under a different name. Keeps
  // its own default (Original: a downloaded file is meant to be kept, so
  // it should be the real thing, not the quality picked for a live mobile
  // stream).
  StreamingQuality downloadQuality = StreamingQuality.original;
  bool downloadWifiOnly = true;
  bool gaplessPlayback = true;
  bool crossfade = false;
  bool volumeNormalization = true;
  bool replayGain = false;
  bool autoplay = true;
  bool rememberQueue = true;
  bool resumePlayback = true;
  bool dynamicColors = true;
  bool reduceAnimations = false;
  String fontFamily = 'Inter';
  LyricsProviderType lyricsProvider = LyricsProviderType.lrclib;
  ArtworkStyle artworkStyle = ArtworkStyle.rounded;
  int lyricsOffsetMs = 0;
  bool lyricsAutoScroll = true;

  void updateArtworkStyle(ArtworkStyle style) {
    artworkStyle = style;
    notifyListeners();
    unawaited(_persistSettings());
  }

  /// Positive shifts lyrics earlier (they appear sooner), negative later.
  void updateLyricsOffset(int ms) {
    lyricsOffsetMs = ms;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateLyricsAutoScroll(bool value) {
    lyricsAutoScroll = value;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateReduceAnimations(bool value) {
    reduceAnimations = value;
    reduceMotionEnabled = value;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateWifiQuality(StreamingQuality q) {
    wifiQuality = q;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateMobileQuality(StreamingQuality q) {
    mobileQuality = q;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateDownloadQuality(StreamingQuality q) {
    downloadQuality = q;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void updateLyricsProvider(LyricsProviderType provider) {
    lyricsProvider = provider;
    notifyListeners();
    unawaited(_persistSettings());
  }

  /// Applies app-wide instantly (every screen reads the font via the
  /// global `currentFontFamily`), at the cost of a full app remount so
  /// already-built screens pick it up — see main.dart.
  void updateFontFamily(String family) {
    fontFamily = family;
    currentFontFamily = family;
    notifyListeners();
    unawaited(_persistSettings());
  }

  // --- Profile photo ------------------------------------------------------
  Uint8List? userAvatarBytes;

  void updateUserAvatar(Uint8List? bytes) {
    userAvatarBytes = bytes;
    notifyListeners();
  }

  void toggleSetting(void Function() mutate) {
    HapticFeedback.selectionClick();
    mutate();
    notifyListeners();
    unawaited(_persistSettings());
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _repository?.dispose();
    super.dispose();
  }
}

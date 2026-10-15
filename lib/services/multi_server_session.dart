import 'dart:async';

import '../backend/music_repository.dart';
import '../backend/navidrome_music_repository.dart';
import '../models/download_state.dart';
import '../models/lyrics.dart';
import '../models/server_config.dart';
import '../models/song.dart';
import 'multi_server.dart';

/// Result of a combined connect attempt across the enabled servers.
class MultiConnectOutcome {
  /// The merged library (qualified ids, deduped) of every server that
  /// answered. Empty when none did.
  final MusicLibrarySnapshot merged;

  /// Each online server's raw (unqualified) snapshot â€” the cache writer and
  /// the legacy-id migration both need the per-server originals.
  final Map<String, MusicLibrarySnapshot> rawByServer;

  /// Server ids that connected and produced a library.
  final Set<String> online;

  /// Server ids that failed (down, auth, timeout). The merged library simply
  /// has no entries from them; a later retry picks them up.
  final Set<String> failed;

  /// Human-readable message of the last failure (for the error surface when
  /// NOTHING connected and there is no cache to fall back to).
  final String? lastError;

  const MultiConnectOutcome({
    required this.merged,
    required this.rawByServer,
    required this.online,
    required this.failed,
    this.lastError,
  });

  static const empty = MultiConnectOutcome(
    merged: MusicLibrarySnapshot.empty,
    rawByServer: {},
    online: {},
    failed: {},
  );
}

/// Owns one repository per enabled server and the routing that makes the
/// combined library actually work: which server a song streams from, whose
/// lyrics extension answers, whose HTTP pool gets disposed.
///
/// Failure model: servers connect in PARALLEL and independently â€” one down
/// server never blocks or empties the library from the others ("no conflict"
/// includes partial availability). The merge itself is [MultiServerLibrary].
class MultiServerSession {
  final Map<String, MusicRepository> _repos = {};

  Map<String, MusicRepository> get repositories => Map.unmodifiable(_repos);

  bool get isEmpty => _repos.isEmpty;

  /// Connects [configs] in parallel (config order = merge priority; the
  /// caller lists the active server first) and returns the merged outcome.
  /// Existing repositories are replaced; ones for servers no longer present
  /// are disposed.
  Future<MultiConnectOutcome> connectAll(List<ServerConfig> configs) async {
    if (configs.isEmpty) {
      disposeAll();
      return MultiConnectOutcome.empty;
    }

    final raws = <String, MusicLibrarySnapshot>{};
    final online = <String>{};
    final failed = <String>{};
    final fresh = <String, MusicRepository>{};
    String? lastError;

    await Future.wait(configs.map((config) async {
      final repository = NavidromeMusicRepository(
        baseUrl: config.url,
        username: config.username,
        password: config.password,
      );
      try {
        await repository.connect().timeout(const Duration(seconds: 20));
        final snapshot = await repository.fetchLibrary().timeout(const Duration(seconds: 90));
        raws[config.id] = snapshot;
        online.add(config.id);
        fresh[config.id] = repository;
      } catch (error) {
        repository.dispose();
        failed.add(config.id);
        lastError = error.toString();
      }
    }));

    // Commit: dispose repos from servers that dropped out, adopt the fresh ones.
    for (final entry in _repos.entries) {
      if (!fresh.containsKey(entry.key)) entry.value.dispose();
    }
    _repos
      ..clear()
      ..addAll(fresh);

    final merged = MultiServerLibrary.merge([
      for (final config in configs)
        if (raws.containsKey(config.id)) MapEntry(config.id, raws[config.id]!),
    ]);

    return MultiConnectOutcome(
      merged: merged,
      rawByServer: raws,
      online: online,
      failed: failed,
      lastError: lastError,
    );
  }

  /// The stream URL for [song] from the server that owns it, in the quality
  /// the caller resolved. Null when that server isn't currently connected.
  String? streamUrlFor(Song song, {required StreamingQuality quality}) {
    final serverId = MultiServerLibrary.serverIdOf(song.id);
    if (serverId == null) return null;
    final repository = _repos[serverId];
    if (repository == null) return null;
    return repository.streamUrlFor(MultiServerLibrary.localizeSong(serverId, song), quality: quality);
  }

  /// Embedded lyrics for [song] from its own server. Null when that server is
  /// offline or has nothing embedded â€” either way the lyrics UI falls through
  /// to LRCLIB, exactly as in single-server mode.
  Future<LyricsTrack?> embeddedLyrics(Song song) async {
    final serverId = MultiServerLibrary.serverIdOf(song.id);
    if (serverId == null) return null;
    final repository = _repos[serverId];
    if (repository == null) return null;
    return repository.fetchEmbeddedLyrics(MultiServerLibrary.localizeSong(serverId, song));
  }

  bool isServerOnline(String serverId) => _repos.containsKey(serverId);

  void disposeAll() {
    for (final repository in _repos.values) {
      repository.dispose();
    }
    _repos.clear();
  }
}

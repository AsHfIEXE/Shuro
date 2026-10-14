import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../backend/music_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/audio_info.dart';
import '../models/song.dart';

/// A saved server library: the [MusicLibrarySnapshot] plus when it was saved
/// and the server-side scan generation it was taken at ([lastScan], when the
/// server reports one — used to skip re-fetching an unchanged library).
class CachedLibrary {
  final MusicLibrarySnapshot snapshot;
  final DateTime savedAt;
  final int? lastScan;
  const CachedLibrary({required this.snapshot, required this.savedAt, this.lastScan});
}

/// Whole-library disk cache, one JSON file per server id.
///
/// Why: the library snapshot is plain data (songs/albums/artists/genre map)
/// and re-fetching it from the server is the slowest thing at every launch
/// (artists → every album → songs). With this cache the app renders the
/// library **instantly** on launch from disk (stale-while-revalidate) and
/// refreshes in the background — the network round-trip comes off the
/// critical path to the first screen.
///
/// Serialization notes:
///  * artwork is an `ImageProvider`, which is not serializable — what IS
///    serialized is the artwork **URL** (server songs/albums/artists all use
///    `NetworkImage(url)`). Subsonic cover URLs carry a salt+token that
///    stays valid for as long as the password is unchanged, and the
///    HTTP-level image disk cache keys covers by URL-without-auth-params,
///    so cached covers render instantly across restarts even with fresh
///    URLs after a refresh.
///  * colors are stored as 32-bit ints.
///  * everything is best-effort: a corrupt/foreign cache file is ignored and
///    rewritten on the next successful fetch.
class LibraryCache {
  LibraryCache._();

  static const int _formatVersion = 1;
  static Future<Directory>? _dirFuture;

  static Future<Directory> _dir() async {
    final existing = _dirFuture;
    if (existing != null) return existing;
    final future = () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}library_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }();
    _dirFuture = future;
    return future;
  }

  static Future<File> _fileFor(String serverId) async => File(
      '${(await _dir()).path}${Platform.pathSeparator}${_safe(serverId)}.json');

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// Loads the cached library for [serverId], or null when there is none
  /// (never throws — a broken cache reads as "no cache").
  static Future<CachedLibrary?> load(String serverId) async {
    try {
      final file = await _fileFor(serverId);
      if (!file.existsSync()) return null;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (map['v'] != _formatVersion) return null;
      final snapshot = _snapshotFromJson(map['library'] as Map<String, dynamic>);
      if (snapshot.songs.isEmpty) return null;
      return CachedLibrary(
        snapshot: snapshot,
        savedAt: DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
        lastScan: map['lastScan'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists [snapshot] for [serverId]. [lastScan] is the server-side scan
  /// generation (epoch ms) to compare against next launch. Never throws.
  static Future<void> save(String serverId, MusicLibrarySnapshot snapshot, {int? lastScan}) async {
    try {
      final file = await _fileFor(serverId);
      await file.writeAsString(jsonEncode({
        'v': _formatVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'lastScan': lastScan,
        'library': _snapshotToJson(snapshot),
      }), flush: true);
    } catch (_) {
      // Cache write failed: nothing about the app depends on it.
    }
  }

  static Future<void> clear(String serverId) async {
    try {
      final file = await _fileFor(serverId);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // --- snapshot -------------------------------------------------------------

  static Map<String, dynamic> _snapshotToJson(MusicLibrarySnapshot s) => {
        'songs': [for (final song in s.songs) _songToJson(song)],
        'albums': [for (final album in s.albums) _albumToJson(album)],
        'artists': [for (final artist in s.artists) _artistToJson(artist)],
        'genres': s.genreSongIds.map((k, v) => MapEntry(k, v)),
      };

  static MusicLibrarySnapshot _snapshotFromJson(Map<String, dynamic> map) => MusicLibrarySnapshot(
        songs: [for (final e in (map['songs'] as List<dynamic>? ?? const [])) _songFromJson(e as Map<String, dynamic>)],
        albums: [for (final e in (map['albums'] as List<dynamic>? ?? const [])) _albumFromJson(e as Map<String, dynamic>)],
        artists: [for (final e in (map['artists'] as List<dynamic>? ?? const [])) _artistFromJson(e as Map<String, dynamic>)],
        genreSongIds: (map['genres'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as List<dynamic>).cast<String>())),
      );

  // --- songs ------------------------------------------------------------------

  static Map<String, dynamic> _songToJson(Song s) => {
        'id': s.id,
        'title': s.title,
        'artist': s.artist,
        'artistId': s.artistId,
        'albumId': s.albumId,
        'durationMs': s.duration.inMilliseconds,
        'colors': [for (final c in s.gradientColors) c.toARGB32()],
        'artUrl': _artUrlOf(s.artwork),
        'filePath': s.localFilePath,
        'audio': {
          'format': s.audioInfo.format,
          'bitDepth': s.audioInfo.bitDepth,
          'sampleRate': s.audioInfo.sampleRateHz,
          'bitrate': s.audioInfo.bitrateKbps,
          'channels': s.audioInfo.channels,
        },
      };

  static Song _songFromJson(Map<String, dynamic> m) => Song(
        id: m['id'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String? ?? '',
        artistId: m['artistId'] as String? ?? '',
        albumId: m['albumId'] as String? ?? '',
        duration: Duration(milliseconds: m['durationMs'] as int? ?? 0),
        gradientColors: _colorsFromJson(m['colors']),
        artwork: _networkImage(m['artUrl'] as String?),
        localFilePath: m['filePath'] as String?,
        audioInfo: _audioInfoFromJson(m['audio'] as Map<String, dynamic>?),
      );

  // --- albums / artists ----------------------------------------------------------

  static Map<String, dynamic> _albumToJson(Album a) => {
        'id': a.id,
        'title': a.title,
        'artist': a.artist,
        'artistId': a.artistId,
        'year': a.year,
        'colors': [for (final c in a.gradientColors) c.toARGB32()],
        'artUrl': _artUrlOf(a.artwork),
        'songIds': a.songIds,
      };

  static Album _albumFromJson(Map<String, dynamic> m) => Album(
        id: m['id'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String? ?? '',
        artistId: m['artistId'] as String? ?? '',
        year: m['year'] as int? ?? 0,
        gradientColors: _colorsFromJson(m['colors']),
        artwork: _networkImage(m['artUrl'] as String?),
        songIds: (m['songIds'] as List<dynamic>? ?? const []).cast<String>(),
      );

  static Map<String, dynamic> _artistToJson(Artist a) => {
        'id': a.id,
        'name': a.name,
        'colors': [for (final c in a.gradientColors) c.toARGB32()],
        'artUrl': _artUrlOf(a.artwork),
        'albumIds': a.albumIds,
        'topSongIds': a.topSongIds,
      };

  static Artist _artistFromJson(Map<String, dynamic> m) => Artist(
        id: m['id'] as String,
        name: m['name'] as String,
        gradientColors: _colorsFromJson(m['colors']),
        artwork: _networkImage(m['artUrl'] as String?),
        albumIds: (m['albumIds'] as List<dynamic>? ?? const []).cast<String>(),
        topSongIds: (m['topSongIds'] as List<dynamic>? ?? const []).cast<String>(),
      );

  // --- shared helpers ----------------------------------------------------------

  static AudioInfo _audioInfoFromJson(Map<String, dynamic>? m) => AudioInfo(
        format: m?['format'] as String?,
        bitDepth: m?['bitDepth'] as int?,
        sampleRateHz: m?['sampleRate'] as int?,
        bitrateKbps: m?['bitrate'] as int?,
        channels: m?['channels'] as String? ?? AudioInfo.notReported,
      );

  static List<Color> _colorsFromJson(dynamic raw) => [
        if (raw is List)
          for (final value in raw) Color(value is int ? value : 0xFF6E56CF),
      ];

  static String? _artUrlOf(ImageProvider? provider) => provider is NetworkImage ? provider.url : null;

  static NetworkImage? _networkImage(String? url) => url == null ? null : NetworkImage(url);
}

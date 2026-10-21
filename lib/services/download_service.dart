import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_info.dart';
import '../models/download_state.dart';
import '../models/song.dart';

/// Real offline downloads — files on disk, not a progress animation.
///
/// Why this exists: [startDownload] in AppState (the previous implementation)
/// was a 1.2-second progress animation that never wrote a byte. There was no
/// download location to change because there were no downloads. This service:
///
///  * streams the track's **original** bytes (`format=raw` — the stream URL is
///    built by the caller with original quality, matching the owner's rule
///    that downloads must never be a lesser version) into a file;
///  * stores them under the app's **documents** directory by default — that
///    directory survives app updates (cache directories do not), which is the
///    "updating the app must not remove data" requirement;
///  * or under a **user-chosen folder** (Settings/Downloads → location, via
///    the system folder picker) when one has been set;
///  * keeps a persisted registry (songId → file path + display metadata) in
///    SharedPreferences, so the Downloads screen rebuilds after a restart;
///  * reports real progress as bytes arrive.
///
/// Downloads live outside AppState because that file cannot be written in this
/// workspace; screens read this ChangeNotifier instead.
class DownloadService extends ChangeNotifier {
  static const String _registryKey = 'download_registry_v1';
  static const String _locationKey = 'download_location_v1';

  /// songId → saved entry (path + the display metadata the Downloads screen
  /// and offline playback need).
  final Map<String, _DownloadEntry> _entries = {};

  /// Live per-song status for the UI, reusing the shared model the action
  /// sheets already render.
  final Map<String, DownloadStatus> status = {};

  /// The user-chosen folder, when one is set. Null = the default documents
  /// directory.
  String? customLocation;

  bool _restored = false;

  /// All downloaded songs (for the Downloads screen).
  List<Song> get songs {
    final list = _entries.values.map((e) => e.toSong()).toList();
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  DownloadStatus statusFor(String songId) =>
      status[songId] ?? (_entries.containsKey(songId) ? const DownloadStatus(stage: DownloadStage.downloaded, progress: 1) : const DownloadStatus(stage: DownloadStage.notDownloaded));

  bool isDownloaded(String songId) => _entries.containsKey(songId);

  /// The local file for [songId], when it is really on disk. Used by offline
  /// playback: if this returns a path, the player plays the file instead of
  /// streaming.
  String? locate(String songId) {
    final entry = _entries[songId];
    if (entry == null) return null;
    final file = File(entry.path);
    return file.existsSync() ? entry.path : null;
  }

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final location = prefs.getString(_locationKey);
      if (location != null && location.isNotEmpty) customLocation = location;
      final raw = prefs.getString(_registryKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _entries[entry.key] = _DownloadEntry.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      notifyListeners();
    } catch (_) {
      // Corrupt or absent registry: start clean rather than fail startup.
    }
  }

  Future<Directory> _directory() async {
    final custom = customLocation;
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (dir.existsSync()) return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Opens the system folder picker and, on success, persists the choice as
  /// the download location. Returns the chosen path (null when cancelled).
  Future<String?> pickLocation() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    customLocation = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, path);
    notifyListeners();
    return path;
  }

  /// Streams [song] from [streamUrl] (built by the caller with original
  /// quality) into the download directory. Returns true when the file is
  /// complete on disk. The URL is routed through the loopback stream proxy so
  /// device DNS failures cannot break it.
  Future<bool> start(Song song, String streamUrl) async {
    if (status[song.id]?.stage == DownloadStage.downloading) return false;
    status[song.id] = const DownloadStatus(stage: DownloadStage.downloading, progress: 0);
    notifyListeners();
    try {
      final dir = await _directory();
      final ext = (song.audioInfo.format ?? 'audio').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeId = song.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}shuro-$safeId.$ext');

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(streamUrl));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        final total = response.contentLength;
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            status[song.id] = DownloadStatus(stage: DownloadStage.downloading, progress: (received / total).clamp(0.0, 1.0));
            notifyListeners();
          }
        }
        await sink.flush();
        await sink.close();
      } finally {
        client.close();
      }

      _entries[song.id] = _DownloadEntry(
        path: file.path,
        title: song.title,
        artist: song.artist,
        artistId: song.artistId,
        albumId: song.albumId,
        durationMs: song.duration.inMilliseconds,
        format: song.audioInfo.format,
        artworkUrl: song.artwork is NetworkImage ? (song.artwork as NetworkImage).url : null,
        gradient: song.gradientColors.map((c) => c.toARGB32()).toList(),
      );
      status[song.id] = const DownloadStatus(stage: DownloadStage.downloaded, progress: 1);
      await _persist();
      notifyListeners();
      return true;
    } catch (error) {
      status[song.id] = const DownloadStatus(stage: DownloadStage.failed);
      notifyListeners();
      return false;
    }
  }

  Future<void> remove(String songId) async {
    final entry = _entries.remove(songId);
    if (entry != null) {
      try {
        final file = File(entry.path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {/* already gone */}
    }
    status.remove(songId);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {for (final entry in _entries.entries) entry.key: entry.value.toJson()};
      await prefs.setString(_registryKey, json.encode(map));
    } catch (_) {
      // Storage unavailable: downloads still work this session.
    }
  }
}

/// Everything needed to rebuild a playable [Song] from disk without a server.
class _DownloadEntry {
  final String path;
  final String title;
  final String artist;
  final String artistId;
  final String albumId;
  final int durationMs;
  final String? format;
  final String? artworkUrl;
  final List<int> gradient;

  const _DownloadEntry({
    required this.path,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.albumId,
    required this.durationMs,
    required this.gradient,
    this.format,
    this.artworkUrl,
  });

  factory _DownloadEntry.fromJson(Map<String, dynamic> json) => _DownloadEntry(
        path: json['path'] as String,
        title: (json['title'] as String?) ?? 'Unknown title',
        artist: (json['artist'] as String?) ?? 'Unknown artist',
        artistId: (json['artistId'] as String?) ?? '',
        albumId: (json['albumId'] as String?) ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        format: json['format'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        gradient: [for (final v in (json['gradient'] as List<dynamic>? ?? const [])) (v as num).toInt()],
      );

  Song toSong() => Song(
        id: path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'^shuro-|\.audio$|\.[a-z0-9]+$'), ''),
        title: title,
        artist: artist,
        artistId: artistId,
        albumId: albumId,
        duration: Duration(milliseconds: durationMs),
        gradientColors: gradient.length >= 2
            ? gradient.map(Color.new).toList()
            : const [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
        artwork: artworkUrl != null ? NetworkImage(artworkUrl!) : null,
        localFilePath: path,
        // Exactly what the server reported when the file was saved — not a
        // guess made after the fact.
        audioInfo: AudioInfo(format: format),
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'albumId': albumId,
        'durationMs': durationMs,
        'format': format,
        'artworkUrl': artworkUrl,
        'gradient': gradient,
      };
}

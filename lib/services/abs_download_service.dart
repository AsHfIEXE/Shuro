import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, NetworkImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../backend/audiobookshelf_api.dart';
import '../models/song.dart';
import '../models/spoken_media.dart';
import '../playback/event_log.dart';
import 'app_persistence.dart';

/// What the offline player needs to start a downloaded title without the
/// server: the local queue, where to resume, and the id progress syncs
/// under (identical to a server session's shape, so the same 15 s tick
/// PATCHes progress whenever the server is reachable).
class SpokenLocalSession {
  const SpokenLocalSession({
    required this.song,
    required this.songs,
    required this.resumeAt,
    required this.progressId,
    required this.durationSeconds,
    required this.songIds,
    required this.startOffsetById,
  });
  final Song song;
  final List<Song> songs;
  final Duration resumeAt;
  final String progressId;
  final double durationSeconds;
  final List<String> songIds;
  final Map<String, double> startOffsetById;
}

/// One downloaded title (a whole book, or a single podcast episode) for the
/// Settings -> Downloads manager.
class AbsDownloadHandle {
  const AbsDownloadHandle({
    required this.itemId,
    required this.episodeId,
    required this.title,
    required this.creator,
    required this.sizeBytes,
    required this.trackCount,
    required this.durationSeconds,
    required this.progressSeconds,
    required this.downloadedAt,
  });
  final String itemId;
  final String? episodeId;
  final String title;
  final String creator;
  final int sizeBytes;
  final int trackCount;
  final double durationSeconds;
  final double progressSeconds;
  final DateTime downloadedAt;

  /// The key every per-target map in the service is keyed by.
  String get key => episodeId == null ? itemId : '$itemId/$episodeId';
}

/// Pure song-id -> manifest match. Extracted so the id scheme is
/// unit-testable without touching the file system: ABS song ids look like
/// `abs_<itemId>`, `abs_<itemId>_<episodeId>` (episode), each optionally
/// suffixed `_t<i>` for later tracks of a multi-file title. Ids may contain
/// underscores themselves, so this is a full-prefix compare against KNOWN
/// ids from manifests — never a blind split.
/// Returns (trackIndex, matched) or null when the id is not this title's.
(int, bool)? absSongIdMatch(String songId, String itemId, String? episodeId) {
  final base = 'abs_$itemId';
  final eb = episodeId == null ? null : '${base}_$episodeId';
  final prefixes = [if (eb != null) eb, base];
  for (final prefix in prefixes) {
    if (songId == prefix) return (0, true);
    if (songId.startsWith('${prefix}_t')) {
      final track = int.tryParse(songId.substring(prefix.length + 2));
      if (track != null && track >= 0) return (track, true);
    }
  }
  return null;
}

String _extForMime(String mime) {
  final m = mime.toLowerCase();
  if (m.contains('mpeg') || m.contains('mp3')) return 'mp3';
  if (m.contains('mp4') || m.contains('m4b') || m.contains('aac')) return 'm4b';
  if (m.contains('flac')) return 'flac';
  if (m.contains('ogg') || m.contains('opus')) return 'ogg';
  if (m.contains('wav')) return 'wav';
  return 'audio';
}

class _ManifestTrack {
  const _ManifestTrack({
    required this.file,
    required this.startOffset,
    required this.duration,
    required this.mimeType,
  });
  final String file;
  final double startOffset;
  final double duration;
  final String mimeType;

  Map<String, dynamic> toJson() => {
        'file': file,
        'startOffset': startOffset,
        'duration': duration,
        'mimeType': mimeType,
      };

  static _ManifestTrack fromJson(Map<String, dynamic> json) => _ManifestTrack(
        file: json['file'] as String? ?? '',
        startOffset: (json['startOffset'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        mimeType: json['mimeType'] as String? ?? 'audio/mpeg',
      );
}

class AbsManifest {
  AbsManifest({
    required this.version,
    required this.itemId,
    required this.episodeId,
    required this.title,
    required this.creator,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.downloadedAt,
    required this.tracks,
    required this.progressSeconds,
  });

  final int version;
  final String itemId;
  final String? episodeId;
  final String title;
  final String creator;
  final double durationSeconds;
  final int sizeBytes;
  final DateTime downloadedAt;
  final List<_ManifestTrack> tracks;
  double progressSeconds;

  String get folderName =>
      episodeId == null ? itemId : '${itemId}_$episodeId';

  /// Matches the ABS progress id scheme: 'item' or 'item/episode'.
  String get progressId =>
      episodeId == null ? itemId : '$itemId/$episodeId';

  Map<String, dynamic> toJson() => {
        'version': version,
        'itemId': itemId,
        'episodeId': episodeId,
        'title': title,
        'creator': creator,
        'durationSeconds': durationSeconds,
        'sizeBytes': sizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
        'progressSeconds': progressSeconds,
        'tracks': [for (final t in tracks) t.toJson()],
      };

  static AbsManifest fromJson(Map<String, dynamic> json) => AbsManifest(
        version: (json['version'] as num?)?.toInt() ?? 1,
        itemId: json['itemId'] as String? ?? '',
        episodeId: json['episodeId'] as String?,
        title: json['title'] as String? ?? '',
        creator: json['creator'] as String? ?? '',
        durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        downloadedAt:
            DateTime.tryParse(json['downloadedAt'] as String? ?? '') ??
                DateTime.now(),
        tracks: [
          for (final row in (json['tracks'] as List<dynamic>? ?? const []))
            if (row is Map<String, dynamic>) _ManifestTrack.fromJson(row),
        ],
        progressSeconds: (json['progressSeconds'] as num?)?.toDouble() ?? 0,
      );
}

/// Offline downloads for Audiobookshelf books and podcast episodes.
///
/// One folder per target under `documents/abs_downloads/<itemId>[_<epId]/`,
/// one manifest.json per folder. Playback goes through the app's shared
/// source resolver: a downloaded ABS song id resolves to its local file
/// path, so the engine plays from disk with the same queue/seek/sync
/// machinery as a server stream — nothing about playback is special-cased.
class AbsDownloadService extends ChangeNotifier {
  static const _autoRemoveKey = 'abs_autoremove_finished_v1';

  bool autoRemoveFinished = false;
  bool _restored = false;

  /// Resolved once in [restore]; every later disk touch reuses it so no
  /// download/locate path depends on an async plugin answering.
  String? _rootPath;

  /// folderName -> manifest (books AND episode downloads).
  final Map<String, AbsManifest> _byFolder = {};
  final Map<String, double> _offlineProgress = {};
  final Map<String, double> _downloading = {};
  String? error;

  // --- queries -------------------------------------------------------------

  List<AbsDownloadHandle> get handles => [
        for (final m in _byFolder.values)
          AbsDownloadHandle(
            itemId: m.itemId,
            episodeId: m.episodeId,
            title: m.title,
            creator: m.creator,
            sizeBytes: m.sizeBytes,
            trackCount: m.tracks.length,
            durationSeconds: m.durationSeconds,
            progressSeconds: m.progressSeconds,
            downloadedAt: m.downloadedAt,
          ),
      ];

  int get totalSizeBytes =>
      _byFolder.values.fold(0, (sum, m) => sum + m.sizeBytes);

  /// 0..1 while a target downloads, null otherwise.
  double? progressOf(String key) => _downloading[key];

  String folderNameFor(String itemId, String? episodeId) =>
      episodeId == null ? itemId : '${itemId}_$episodeId';

  bool isDownloaded(String itemId, String? episodeId) =>
      _byFolder.containsKey(folderNameFor(itemId, episodeId));

  /// The local file for an ABS song id, or null when this title (or that
  /// exact track of it) is not on disk.
  String? locate(String songId) {
    if (!songId.startsWith('abs_')) return null;
    for (final m in _byFolder.values) {
      final match = absSongIdMatch(songId, m.itemId, m.episodeId);
      if (match == null || match.$2 != true) continue;
      if (match.$1 >= m.tracks.length) continue;
      final dir = _dirFor(m);
      if (dir == null) continue;
      final file = File(
          '${dir.path}${Platform.pathSeparator}${m.tracks[match.$1].file}');
      return file.existsSync() ? file.path : null;
    }
    return null;
  }

  // --- lifecycle -----------------------------------------------------------

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final store = await AppPersistence.load();
      autoRemoveFinished = store.getBool(_autoRemoveKey) ?? autoRemoveFinished;
    } catch (_) {}
    try {
      final root = await _root();
      _rootPath = root.path;
      if (!root.existsSync()) {
        notifyListeners();
        return;
      }
      for (final entry in root.listSync()) {
        if (entry is! Directory) continue;
        final manifest =
            File('${entry.path}${Platform.pathSeparator}manifest.json');
        if (!manifest.existsSync()) continue;
        try {
          final m = AbsManifest.fromJson(
              jsonDecode(await manifest.readAsString()) as Map<String, dynamic>);
          _byFolder[m.folderName] = m;
          if (m.progressSeconds > 0) {
            _offlineProgress[m.progressId] = m.progressSeconds;
          }
        } catch (_) {
          // One corrupt manifest must not take the store down.
        }
      }
      notifyListeners();
    } catch (_) {
      // No storage plugin (tests): the store just stays empty.
    }
  }

  Future<Directory> _root() async {
    final custom = _rootPath;
    if (custom != null && custom.isNotEmpty) return Directory(custom);
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}abs_downloads');
  }

  Directory? _dirFor(AbsManifest m) {
    final root = _rootPath;
    if (root == null || root.isEmpty) return null;
    return Directory('${root}${Platform.pathSeparator}${m.folderName}');
  }

  // --- download ------------------------------------------------------------

  /// Downloads a whole book (all its tracks) or one podcast episode.
  /// Progress is reported through [notifyListeners] as a 0..1 fraction.
  Future<void> downloadItem(SpokenItem item,
      {SpokenEpisode? episode, required AudiobookshelfApi api}) async {
    final key = folderNameFor(item.id, episode?.id);
    if (_downloading.containsKey(key)) return;
    error = null;
    _downloading[key] = 0.0;
    notifyListeners();

    final client = http.Client();
    try {
      // Track list: books need the FULL item fetch (the minified listing
      // usually hides media.tracks); an episode is its single audio file.
      List<AbsTrack> tracks;
      String title;
      double durationSeconds;
      if (episode != null) {
        tracks = [
          AbsTrack(
            contentUrl: '/api/items/${item.id}/file/${episode.fileIndex}',
            mimeType: 'audio/mpeg',
            startOffset: 0,
            duration: episode.duration.inMilliseconds / 1000.0,
          ),
        ];
        title = episode.title;
        durationSeconds = episode.duration.inMilliseconds / 1000.0;
      } else {
        final expanded = await api.itemExpanded(item);
        tracks = expanded.tracks.isNotEmpty
            ? expanded.tracks
            : [
                for (final t in expanded.item.tracks)
                  AbsTrack(
                    contentUrl: t.contentUrl,
                    mimeType: t.mimeType,
                    startOffset: t.startOffset,
                    duration: t.duration,
                  ),
              ];
        title = item.title;
        durationSeconds = item.duration.inMilliseconds / 1000.0;
      }
      if (tracks.isEmpty) {
        throw const AudiobookshelfApiException(
            'The server lists no audio files for this title.');
      }

      final root = await _root();
      final dir = Directory(
          '${root.path}${Platform.pathSeparator}$key');
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      if (_rootPath == null || _rootPath!.isEmpty) _rootPath = root.path;

      final saved = <_ManifestTrack>[];
      var sizeBytes = 0;
      for (var i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        final file = File(
            '${dir.path}${Platform.pathSeparator}$i.${_extForMime(track.mimeType)}');
        sizeBytes += await _fetchTrack(client, api, track, file,
            key: key, base: i / tracks.length, span: 1 / tracks.length);
        saved.add(_ManifestTrack(
          file: file.uri.pathSegments.last,
          startOffset: track.startOffset,
          duration: track.duration,
          mimeType: track.mimeType,
        ));
        _downloading[key] = (i + 1) / tracks.length;
        notifyListeners();
      }

      final manifest = AbsManifest(
        version: 1,
        itemId: item.id,
        episodeId: episode?.id,
        title: title,
        creator: item.creator,
        durationSeconds: durationSeconds,
        sizeBytes: sizeBytes,
        downloadedAt: DateTime.now(),
        tracks: saved,
        progressSeconds: 0,
      );
      await File('${dir.path}${Platform.pathSeparator}manifest.json')
          .writeAsString(jsonEncode(manifest.toJson()));
      _byFolder[manifest.folderName] = manifest;
      _downloading.remove(key);
      notifyListeners();
      PlaybackEventLog.instance.add('abs.download.done',
          {'item': item.id, 'episode': episode?.id, 'tracks': saved.length});
    } on AudiobookshelfApiException catch (e) {
      error = e.message;
      _downloading.remove(key);
      notifyListeners();
    } catch (e) {
      error = 'Download failed — ${e.toString().split('\n').first}';
      _downloading.remove(key);
      notifyListeners();
      PlaybackEventLog.instance
          .add('abs.download.fail', {'item': item.id, 'err': e.toString()});
    } finally {
      client.close();
    }
  }

  Future<int> _fetchTrack(
      http.Client client, AudiobookshelfApi api, AbsTrack track, File file,
      {required String key,
      required double base,
      required double span}) async {
    final request = http.Request('GET', Uri.parse(api.streamUrlOf(track)))
      ..headers.addAll({
        'Authorization': 'Bearer ${api.token}',
        'Accept': '*/*',
      });
    final response =
        await client.send(request).timeout(const Duration(minutes: 30));
    if (response.statusCode != 200) {
      throw AudiobookshelfApiException(
          'The server answered ${response.statusCode} for a file download.');
    }
    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    var lastNotified = 0.0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          final fraction = base + span * (received / total);
          // Rebuild sparingly: a UI ring that ticks every byte is waste.
          if (fraction - lastNotified >= 0.02) {
            lastNotified = fraction;
            _downloading[key] = fraction.clamp(0.0, 0.99);
            notifyListeners();
          }
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }
    return received;
  }

  // --- remove / progress ---------------------------------------------------

  Future<void> remove(String itemId, {String? episodeId}) async {
    final folder = folderNameFor(itemId, episodeId);
    _byFolder.remove(folder);
    notifyListeners();
    try {
      final root = await _root();
      final dir = Directory('${root.path}${Platform.pathSeparator}$folder');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
    PlaybackEventLog.instance
        .add('abs.download.remove', {'item': itemId, 'episode': episodeId});
  }

  /// Removes every download that belongs to one item (book + its episodes).
  Future<void> removeItem(String itemId) async {
    final keys = _byFolder.values
        .where((m) => m.itemId == itemId)
        .map((m) => (m.itemId, m.episodeId))
        .toList();
    for (final (itemIdKey, episodeId) in keys) {
      await remove(itemIdKey, episodeId: episodeId);
    }
  }

  /// Called by the sync tick / session close so an OFFLINE session still
  /// leaves its resume point behind for the next launch.
  Future<void> saveOfflineProgress(String progressId, double seconds) async {
    if (seconds <= 0) return;
    _offlineProgress[progressId] = seconds;
    AbsManifest? target;
    for (final m in _byFolder.values) {
      if (m.progressId == progressId) {
        target = m;
        break;
      }
    }
    if (target == null) return;
    if ((seconds - target.progressSeconds).abs() < 5) return;
    target.progressSeconds = seconds;
    try {
      final dir = _dirFor(target);
      if (dir == null) return;
      await File('${dir.path}${Platform.pathSeparator}manifest.json')
          .writeAsString(jsonEncode(target.toJson()));
    } catch (_) {}
  }

  Future<void> setAutoRemoveFinished(bool value) async {
    if (autoRemoveFinished == value) return;
    autoRemoveFinished = value;
    notifyListeners();
    try {
      final store = await AppPersistence.load();
      await store.setBool(_autoRemoveKey, value);
    } catch (_) {}
  }

  // --- offline playback ----------------------------------------------------

  /// A fully-downloaded title becomes a ready-to-play local queue, or null
  /// when (part of) it is missing — callers then fall back to the server.
  SpokenLocalSession? buildSession(SpokenItem item,
      {SpokenEpisode? episode, Uri? artwork}) {
    final folder = folderNameFor(item.id, episode?.id);
    final manifest = _byFolder[folder];
    if (manifest == null) return null;
    final dir = _dirFor(manifest);
    if (dir == null) return null;

    final baseId =
        episode == null ? 'abs_${item.id}' : 'abs_${item.id}_${episode.id}';
    final songs = <Song>[];
    final startOffsetById = <String, double>{};
    for (var i = 0; i < manifest.tracks.length; i++) {
      final t = manifest.tracks[i];
      final file = File('${dir.path}${Platform.pathSeparator}${t.file}');
      if (!file.existsSync()) return null; // partial download: play online.
      final id = i == 0 ? baseId : '${baseId}_t$i';
      startOffsetById[id] = t.startOffset;
      songs.add(Song(
        id: id,
        title: manifest.tracks.length > 1
            ? '${manifest.title} (${i + 1}/${manifest.tracks.length})'
            : manifest.title,
        artist: episode == null ? manifest.creator : manifest.title,
        artistId: '',
        albumId: '',
        duration: Duration(milliseconds: (t.duration * 1000).round()),
        gradientColors: const [Color(0xFF7C3AED), Color(0xFFFF6B9D)],
        artwork: artwork == null ? null : NetworkImage(artwork.toString()),
        localFilePath: file.path,
      ));
    }
    final seconds =
        _offlineProgress[manifest.progressId] ?? manifest.progressSeconds;
    var resumeAt = Duration(milliseconds: (seconds * 1000).round());
    if (manifest.durationSeconds > 1 &&
        resumeAt.inMilliseconds / 1000.0 > manifest.durationSeconds - 1) {
      resumeAt = Duration.zero; // sat at the end: replay from the top.
    }
    return SpokenLocalSession(
      song: songs.first,
      songs: songs,
      resumeAt: resumeAt,
      progressId: manifest.progressId,
      durationSeconds: manifest.durationSeconds,
      songIds: [for (final s in songs) s.id],
      startOffsetById: startOffsetById,
    );
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-device storage for per-song edited lyrics (roadmap #21).
///
/// One UTF-8 file per song id under `lyrics_edits/`, written atomically-ish
/// (write then the next read sees it). The directory is injectable so tests
/// run against a temp folder instead of the platform path-provider.
class LyricsEditStore {
  final Directory directory;

  LyricsEditStore(this.directory);

  /// The app's real store: `lyrics_edits/` inside the platform support
  /// directory (the same home as playlist covers).
  static Future<LyricsEditStore> open() async {
    final base = await getApplicationSupportDirectory();
    return LyricsEditStore(
        Directory('${base.path}${Platform.pathSeparator}lyrics_edits'));
  }

  File _fileFor(String songId) {
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}${Platform.pathSeparator}$safe.lrc');
  }

  Future<String?> load(String songId) async {
    try {
      final file = _fileFor(songId);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String songId, String content) async {
    await directory.create(recursive: true);
    final file = _fileFor(songId);
    if (content.trim().isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(content, flush: true);
  }

  Future<void> delete(String songId) async {
    try {
      final file = _fileFor(songId);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A missing file is the goal here; any other failure keeps the edit.
    }
  }

  Future<bool> exists(String songId) async {
    try {
      return await _fileFor(songId).exists();
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  File fileFor(String songId) => _fileFor(songId);
}

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// On-disk storage for user-picked playlist covers.
///
/// A cover is one file per playlist, replaced in place. Nothing is uploaded and
/// nothing is resized: the bytes the user picked are the bytes that are shown,
/// so a cover never looks different after a restart.
class PlaylistCoverStore {
  const PlaylistCoverStore._();

  static const _folder = 'playlist_covers';

  static Future<Directory?> _dir({bool create = true}) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_folder');
      if (create && !await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Filesystem-safe name for a cover file. Playlist ids from a server can
  /// contain anything, so everything outside letters, digits, `_` and `-`
  /// collapses to `_`; ids already made of safe characters are unchanged.
  static String safeName(String playlistId) =>
      playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Writes [bytes] for [playlistId] and returns the stored path, or null when
  /// the filesystem refused (read-only profile, no support directory). Callers
  /// must treat null as "no cover was saved" rather than optimistically
  /// updating the UI.
  static Future<String?> save(String playlistId, Uint8List bytes) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final name = safeName(playlistId);
      final file = File('${dir.path}${Platform.pathSeparator}$name.img');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Removes the stored cover for [playlistId]; missing files are fine.
  static Future<void> delete(String playlistId) async {
    final dir = await _dir(create: false);
    if (dir == null) return;
    try {
      final name = safeName(playlistId);
      final file = File('${dir.path}${Platform.pathSeparator}$name.img');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// True when a previously stored cover still exists on disk. Used at startup
  /// so a deleted file does not leave a broken image behind.
  static bool exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
      final stored = await shrink(bytes) ?? bytes;
      await file.writeAsBytes(stored, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Largest edge kept for a stored cover. The cover is drawn between about 72
  /// and 240 logical pixels, so anything bigger is wasted disk and decode
  /// memory: a camera photo is normally 4000 px wide.
  static const int maxEdge = 512;

  /// Decodes [bytes] and re-encodes them as a PNG no larger than [maxEdge].
  ///
  /// Returns null when the bytes are not a decodable image or the engine
  /// refuses; the caller then stores the original bytes rather than failing the
  /// save, so a cover the user picked is never silently dropped.
  static Future<Uint8List?> shrink(Uint8List bytes, {int edge = maxEdge}) async {
    try {
      final probe = await ui.instantiateImageCodec(bytes);
      final frame = await probe.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      probe.dispose();

      if (width <= edge && height <= edge) {
        // Already small: keep the exact bytes the user chose.
        return null;
      }

      final longest = width > height ? width : height;
      final scale = edge / longest;
      final targetWidth = (width * scale).round().clamp(1, edge);
      final targetHeight = (height * scale).round().clamp(1, edge);

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resized = await codec.getNextFrame();
      final data =
          await resized.image.toByteData(format: ui.ImageByteFormat.png);
      resized.image.dispose();
      codec.dispose();
      return data?.buffer.asUint8List();
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

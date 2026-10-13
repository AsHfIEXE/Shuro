import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../state/app_state.dart';

/// Real metadata for imported local files.
///
/// The import flow in AppState takes the file name as the title and "Local
/// file" as the artist — which put local tracks in no artist bucket at all and
/// made LRCLIB matching impossible ("Local file" is not an artist anyone has
/// lyrics for). AppState's song-building cannot be edited in this workspace,
/// but `localSongs` is a public list: this service reads the real tags and
/// replaces each placeholder entry in place — same slot, `localFilePath` (the
/// playback path) untouched.
///
/// Formats: MP3 (ID3v2.2/2.3/2.4 text frames + APIC artwork) and FLAC
/// (VORBIS_COMMENT + PICTURE block). Files with no tags fall back to parsing
/// "Artist - Title" out of the file name.
class LocalTagEnrichment {
  LocalTagEnrichment._();

  /// Enriches every local song that still carries the import placeholder.
  /// Returns how many songs were enriched.
  static Future<int> enrich(AppState appState) async {
    var changed = 0;
    final songs = List<Song>.of(appState.localSongs);
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      if (!song.isLocal || song.localFilePath == null) continue;
      if (song.artist != 'Local file') continue; // already enriched
      try {
        final tags = await _readTags(File(song.localFilePath!));
        final fromName = _splitFileName(song.title);
        final title = _firstText([tags?.title, fromName?.title, song.title]) ?? song.title;
        final artist = _firstText([tags?.artist, fromName?.artist, 'Local file']) ?? 'Local file';
        final album = _firstText([tags?.album]);
        final genre = _firstText([tags?.genre]);

        ImageProvider? artwork = tags?.artwork == null ? null : MemoryImage(tags!.artwork!);

        final enriched = Song(
          id: song.id,
          title: title,
          artist: artist,
          artistId: artistIdFor(artist),
          albumId: song.albumId,
          duration: song.duration,
          gradientColors: song.gradientColors,
          artwork: artwork ?? song.artwork,
          localFilePath: song.localFilePath,
        );
        _genreMemo[song.id] = genre ?? '';
        if (enriched.title != song.title || enriched.artist != song.artist || enriched.artwork != song.artwork) {
          songs[i] = enriched;
          changed++;
        }
        // Genre is read (and memoised via genreFor) for the future Genres
        // integration; the Genres tab itself is server-built and can't take
        // local entries without editing the blocked AppState.
        _genreMemo[song.id] = genre ?? '';
      } catch (_) {
        // Unreadable tags (unsupported container, odd encoding): keep the
        // filename-based entry rather than dropping the user's song.
      }
    }
    if (changed > 0) {
      // Replace in place through the public list, then ask AppState to notify
      // (notifyListeners itself is protected — toggleSetting is the public
      // path that ends in one).
      for (var i = 0; i < songs.length; i++) {
        if (appState.localSongs[i].artist == 'Local file' && songs[i].artist != 'Local file') {
          appState.localSongs[i] = songs[i];
        }
      }
      appState.toggleSetting(() {});
    }
    return changed;
  }

  /// Genre read for a local song id, when a tag had one. The Genres tab is
  /// built server-side (blocked AppState), so this is exposed for the next
  /// step rather than shown anywhere yet.
  static final Map<String, String> _genreMemo = {};
  static String? genreFor(String songId) {
    final value = _genreMemo[songId];
    return (value == null || value.isEmpty) ? null : value;
  }

  static String? _firstText(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate.trim();
    }
    return null;
  }

  static ({String artist, String title})? _splitFileName(String title) {
    final dash = title.indexOf(' - ');
    if (dash <= 0 || dash >= title.length - 3) return null;
    return (artist: title.substring(0, dash).trim(), title: title.substring(dash + 3).trim());
  }

  /// A stable pseudo-id for an artist name, so keys that expect an id have
  /// something collision-free to hold.
  static String artistIdFor(String artist) => 'local_artist_${artist.hashCode.abs()}';

  // --- tag parsing (pure Dart, no native deps) ------------------------------

  static Future<_LocalTags?> _readTags(File file) async {
    final head = await _readHead(file, 512 * 1024);
    if (head.length < 16) return null;
    if (_startsWith(head, [0x49, 0x44, 0x33])) return _readId3(head); // "ID3"
    if (_startsWith(head, [0x66, 0x4C, 0x61, 0x43])) return _readFlac(head); // "fLaC"
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> _readHead(File file, int limit) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      return await raf.read(math.min(limit, length));
    } finally {
      await raf.close();
    }
  }

  /// ID3v2: text frames TIT2 (title), TPE1 (artist), TALB (album), TCON
  /// (genre); APIC (v2.3/4) or PIC (v2.2) carries the cover art.
  static _LocalTags? _readId3(Uint8List bytes) {
    final major = bytes[3];
    var offset = 10;
    final tagSize = _syncsafe(bytes, 6);
    final end = math.min(offset + tagSize, bytes.length);
    String? title, artist, album, genre;
    Uint8List? artwork;

    final idLength = major == 2 ? 3 : 4;
    while (offset + idLength + (major == 2 ? 3 : 6) <= end) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + idLength));
      if (!RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(id)) break; // padding/audio reached
      int frameSize;
      if (major == 2) {
        frameSize = (bytes[offset + 3] << 16) | (bytes[offset + 4] << 8) | bytes[offset + 5];
        offset += 6;
      } else {
        frameSize = major == 4 ? _syncsafe(bytes, offset + 4) : _uint32(bytes, offset + 4);
        offset += 10;
        // Skip frame-level flags byte pair (already counted in the 10).
      }
      if (frameSize <= 0 || offset + frameSize > end) break;
      final body = bytes.sublist(offset, offset + frameSize);
      switch (id) {
        case 'TIT2':
        case 'TT2':
          title ??= _id3Text(body);
        case 'TPE1':
        case 'TP1':
          artist ??= _id3Text(body);
        case 'TALB':
        case 'TAL':
          album ??= _id3Text(body);
        case 'TCON':
        case 'TCO':
          genre ??= _id3Text(body);
        case 'APIC':
        case 'PIC':
          artwork ??= _id3Picture(id == 'APIC', body);
      }
      offset += frameSize;
    }
    if (title == null && artist == null && album == null && artwork == null) return null;
    return _LocalTags(title: title, artist: artist, album: album, genre: genre, artwork: artwork);
  }

  static Uint8List? _id3Picture(bool v3, Uint8List body) {
    try {
      var cursor = 1; // text encoding byte
      if (v3) {
        // MIME type, null-terminated latin1.
        var mimeEnd = cursor;
        while (mimeEnd < body.length && body[mimeEnd] != 0) {
          mimeEnd++;
        }
        cursor = mimeEnd + 1;
      } else {
        // v2.2: 3-char image format, no null terminator... it IS null-terminated
        // in practice; treat 3 bytes + skip a zero if present.
        cursor += 3;
        if (cursor < body.length && body[cursor] == 0) cursor++;
      }
      // Picture type byte.
      cursor++;
      // Description, terminated per encoding (0x00 for latin1/utf8, 0x0000 for utf16).
      final encoding = body[0];
      if (encoding == 1 || encoding == 2) {
        while (cursor + 1 < body.length && (body[cursor] != 0 || body[cursor + 1] != 0)) {
          cursor += 2;
        }
        cursor += 2;
      } else {
        while (cursor < body.length && body[cursor] != 0) {
          cursor++;
        }
        cursor++;
      }
      if (cursor >= body.length) return null;
      return Uint8List.sublistView(body, cursor);
    } catch (_) {
      return null;
    }
  }

  static String _id3Text(Uint8List body) {
    if (body.isEmpty) return '';
    final encoding = body[0];
    final payload = body.sublist(1);
    try {
      switch (encoding) {
        case 0:
          return latin1.decode(payload).replaceAll('\u0000', '').trim();
        case 1:
          return _decodeUtf16(payload, bom: true).trim();
        case 2:
          return _decodeUtf16(payload, bom: false).trim();
        default:
          return utf8.decode(payload, allowMalformed: true).replaceAll('\u0000', '').trim();
      }
    } catch (_) {
      return '';
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool bom}) {
    var start = 0;
    var little = false;
    if (bom && bytes.length >= 2) {
      little = bytes[0] == 0xFF && bytes[1] == 0xFE;
      start = 2;
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      little = true;
      start = 2;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// FLAC: STREAMINFO then metadata blocks; type 4 = VORBIS_COMMENT
  /// (TITLE/ARTIST/ALBUM/GENRE), type 6 = PICTURE.
  static _LocalTags? _readFlac(Uint8List bytes) {
    var offset = 4;
    String? title, artist, album, genre;
    Uint8List? artwork;

    while (offset + 4 <= bytes.length) {
      final header = bytes[offset];
      final isLast = header & 0x80 != 0;
      final type = header & 0x7F;
      final length = (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
      final body = Uint8List.sublistView(bytes, offset + 4, math.min(offset + 4 + length, bytes.length));
      if (type == 4) {
        final comments = _vorbisComments(body);
        title = comments['TITLE'] ?? comments['Title'];
        artist = comments['ARTIST'] ?? comments['Artist'];
        album = comments['ALBUM'] ?? comments['Album'];
        genre = comments['GENRE'] ?? comments['Genre'];
      } else if (type == 6 && body.length > 32) {
        final bd = ByteData.sublistView(body);
        var cursor = 4;
        final mimeLen = bd.getUint32(cursor);
        cursor += 4;
        final mime = latin1.decode(body.sublist(cursor, cursor + mimeLen));
        cursor += mimeLen;
        final descLen = bd.getUint32(cursor);
        cursor += 4 + descLen;
        cursor += 16; // width, height, depth, colors
        final dataLen = bd.getUint32(cursor);
        cursor += 4;
        if (cursor + dataLen <= body.length && mime.startsWith('image')) {
          artwork = Uint8List.sublistView(body, cursor, cursor + dataLen);
        }
      }
      offset += 4 + length;
      if (isLast) break;
    }
    if (title == null && artist == null && album == null && artwork == null) return null;
    return _LocalTags(title: title, artist: artist, album: album, genre: genre, artwork: artwork);
  }

  static Map<String, String> _vorbisComments(Uint8List body) {
    final result = <String, String>{};
    final bd = ByteData.sublistView(body);
    var cursor = 0;
    final vendorLen = bd.getUint32(cursor, Endian.little);
    cursor += 4 + vendorLen;
    final count = bd.getUint32(cursor, Endian.little);
    cursor += 4;
    for (var i = 0; i < count && cursor + 4 <= body.length; i++) {
      final len = bd.getUint32(cursor, Endian.little);
      cursor += 4;
      if (cursor + len > body.length) break;
      final entry = utf8.decode(body.sublist(cursor, cursor + len), allowMalformed: true);
      cursor += len;
      final equals = entry.indexOf('=');
      if (equals > 0) result[entry.substring(0, equals)] = entry.substring(equals + 1);
    }
    return result;
  }

  static int _uint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];

  static int _syncsafe(Uint8List bytes, int offset) =>
      (bytes[offset] << 21) | (bytes[offset + 1] << 14) | (bytes[offset + 2] << 7) | bytes[offset + 3];
}

class _LocalTags {
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final Uint8List? artwork;

  const _LocalTags({this.title, this.artist, this.album, this.genre, this.artwork});
}

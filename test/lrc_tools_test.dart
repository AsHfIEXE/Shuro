import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/lyrics.dart';
import 'package:shuro/services/lrc_tools.dart';
import 'package:shuro/services/lyrics_edit_store.dart';

void main() {
  group('LrcTools.isLrc', () {
    test('detects timestamps in the three common shapes', () {
      expect(LrcTools.isLrc('[01:23] text'), isTrue);
      expect(LrcTools.isLrc('[01:23.45] text'), isTrue);
      expect(LrcTools.isLrc('[01:23.456] text'), isTrue);
    });

    test('plain text is not LRC', () {
      expect(LrcTools.isLrc('just some words\nmore words'), isFalse);
    });
  });

  group('LrcTools.parse', () {
    test('timestamped lines become a line-synced track with your-edit source',
        () {
      final track = LrcTools.parse('[00:01.00] first\n[00:05.50] second');

      expect(track.type, LyricsSyncType.line);
      expect(track.source, LyricsSource.edited);
      expect(track.hasTiming, isTrue);
      expect(track.lines[0].plainText, 'first');
      expect(track.lines[0].start, const Duration(seconds: 1));
      expect(track.lines[1].plainText, 'second');
      expect(track.lines[1].start,
          const Duration(seconds: 5, milliseconds: 500));
    });

    test('metadata tags are skipped and never leak into lines', () {
      final track = LrcTools.parse(
          '[ar:Artist]\n[ti:Title]\n[00:01.00] real line\n[offset:+500]');

      expect(track.lines, hasLength(1));
      expect(track.lines.single.plainText, 'real line');
    });

    test('untimed text stays static and must not fake a highlight', () {
      final track = LrcTools.parse('plain\nlines');

      expect(track.type, LyricsSyncType.static_);
      expect(track.hasTiming, isFalse);
      expect(track.lines.map((l) => l.plainText), ['plain', 'lines']);
    });
  });

  group('LrcTools.shiftTimestamps', () {
    test('shifts every stamp later and keeps the text untouched', () {
      final shifted = LrcTools.shiftTimestamps(
          '[00:01.00] one\n[01:02.50] two', const Duration(seconds: 1));

      expect(shifted, '[00:02.00] one\n[01:03.50] two');
    });

    test('negative shifts clamp at zero instead of wrapping', () {
      final shifted = LrcTools.shiftTimestamps(
          '[00:00.50] early', const Duration(seconds: -2));

      expect(shifted, '[00:00.00] early');
    });

    test('a two-digit minute stamp survives a shift', () {
      final shifted = LrcTools.shiftTimestamps(
          '[10:00.00] deep', const Duration(minutes: 1, seconds: 30));

      expect(shifted, '[11:30.00] deep');
    });
  });

  group('LyricsEditStore', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('shuro_lyrics_test');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('save then load round-trips the exact text', () async {
      final store = LyricsEditStore(temp);
      await store.save('song-1', '[00:01.00] hello');

      expect(await store.load('song-1'), '[00:01.00] hello');
      expect(await store.exists('song-1'), isTrue);
    });

    test('an unsaved song reads as null', () async {
      final store = LyricsEditStore(temp);
      expect(await store.load('never-saved'), isNull);
      expect(await store.exists('never-saved'), isFalse);
    });

    test('an empty save clears the edit rather than storing blankness',
        () async {
      final store = LyricsEditStore(temp);
      await store.save('song-1', 'words');
      await store.save('song-1', '   ');

      expect(await store.load('song-1'), isNull);
    });

    test('delete removes the file and a server-style id stays filesystem-safe',
        () async {
      final store = LyricsEditStore(temp);
      const id = 's南方/..etc-pass';
      await store.save(id, 'text');

      final file = store.fileFor(id);
      expect(file.uri.pathSegments.last, matches(RegExp(r'^[A-Za-z0-9_-]+\.lrc$')));

      await store.delete(id);
      expect(await store.exists(id), isFalse);
    });
  });
}

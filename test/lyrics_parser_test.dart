import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/lyrics.dart';
import 'package:shuro/services/lyrics_parser.dart';

/// Tests for the lyrics parsing/matching rules.
///
/// These are the checks that stand between "lyrics that are right" and "lyrics
/// for a different recording of the same song" — the difference the user sees
/// as the highlight drifting further and further out of time.
void main() {
  group('parseLrc', () {
    test('reads a single timestamped line', () {
      final result = parseLrc('[00:10.00]Hello world');
      expect(result.lines, hasLength(1));
      expect(result.lines.single.start, const Duration(seconds: 10));
      expect(result.lines.single.plainText, 'Hello world');
      // No word tags in a plain LRC: the precision is line-level, and the
      // syllable timings on it are marked as an estimate by the track itself.
      expect(result.hasWordSync, isFalse);
    });

    test('keeps the syllable text reconstructing the line exactly', () {
      final line = parseLrc('[00:10.00]Never gonna give you up').lines.single;
      expect(line.plainText, 'Never gonna give you up');
      expect(line.syllables.length, 5);
      // Every word but the last carries its separating space.
      expect(line.syllables.first.text, 'Never ');
      expect(line.syllables.last.text, 'up');
    });

    test('expands one lyric repeated at several timestamps', () {
      final result = parseLrc('[00:10.00][00:40.00]Chorus line');
      expect(result.lines, hasLength(2));
      expect(result.lines[0].start, const Duration(seconds: 10));
      expect(result.lines[1].start, const Duration(seconds: 40));
      expect(result.lines.map((l) => l.plainText), everyElement('Chorus line'));
    });

    test('skips metadata tags instead of treating them as lyrics', () {
      final result = parseLrc('[ar:Some Artist]\n[ti:Some Title]\n[00:05.00]Actual lyric');
      expect(result.lines, hasLength(1));
      expect(result.lines.single.plainText, 'Actual lyric');
    });

    test('sorts out-of-order timestamps', () {
      final result = parseLrc('[00:20.00]Second\n[00:10.00]First');
      expect(result.lines[0].plainText, 'First');
      expect(result.lines[1].plainText, 'Second');
    });

    test('detects real word-level timing from inline tags', () {
      final result = parseLrc('[00:10.00]<00:10.00>Hello <00:11.00>world');
      expect(result.hasWordSync, isTrue);
      final line = result.lines.single;
      expect(line.syllables, hasLength(2));
      expect(line.syllables[0].text, 'Hello ');
      expect(line.syllables[0].start, const Duration(seconds: 10));
      expect(line.syllables[0].end, const Duration(seconds: 11));
      expect(line.syllables[1].text, 'world');
      expect(line.plainText, 'Hello world');
    });

    test('marks a syllable that continues a word instead of starting one', () {
      final line = parseLrc('[00:10.00]<00:10.00>Hel<00:10.50>lo <00:11.00>world').lines.single;
      expect(line.syllables, hasLength(3));
      expect(line.syllables[0].isPartOfWord, isFalse);
      expect(line.syllables[1].isPartOfWord, isTrue, reason: '"lo " has no space before it — it continues "Hel"');
      expect(line.syllables[2].isPartOfWord, isFalse, reason: '"world" starts after a space');
    });

    test('closes the final line at the song duration when one is known', () {
      final result = parseLrc('[00:10.00]Last line', fallbackDuration: const Duration(seconds: 12));
      expect(result.lines.single.end, const Duration(seconds: 12));
    });

    test('returns nothing for text with no timestamps at all', () {
      expect(parseLrc('Just some prose\nwith no timestamps').lines, isEmpty);
    });
  });

  group('isInstrumentalLrc', () {
    test('recognises the instrumental marker', () {
      expect(isInstrumentalLrc('[AU: instrumental]'), isTrue);
    });

    test('does not treat other tags as the marker', () {
      expect(isInstrumentalLrc('[ti: instrumental]\n[au: lyrics]'), isFalse);
    });

    test('is false once real lyric content is present', () {
      expect(isInstrumentalLrc('[au: instrumental]\n[00:01.00]actually singing'), isFalse);
    });
  });

  group('estimateSyllables', () {
    test('gives longer words proportionally more of the line', () {
      final syllables = estimateSyllables('a extraordinary', Duration.zero, const Duration(milliseconds: 1000));
      final shortWord = syllables[0].end - syllables[0].start;
      final longWord = syllables[1].end - syllables[1].start;
      expect(longWord, greaterThan(shortWord));
      expect(syllables[1].end, const Duration(milliseconds: 1000));
    });

    test('is monotonic and never leaves a syllable with no duration', () {
      final syllables = estimateSyllables('one two three four five', const Duration(seconds: 1), const Duration(seconds: 3));
      for (var i = 0; i < syllables.length; i++) {
        expect(syllables[i].end, greaterThan(syllables[i].start));
        if (i > 0) expect(syllables[i].start, greaterThanOrEqualTo(syllables[i - 1].start));
      }
    });

    test('handles a single word', () {
      final syllables = estimateSyllables('alone', const Duration(seconds: 5), const Duration(seconds: 6));
      expect(syllables, hasLength(1));
      expect(syllables.single.start, const Duration(seconds: 5));
      expect(syllables.single.end, const Duration(seconds: 6));
    });

    test('weights by syllables, not letters', () {
      final syllables = estimateSyllables('I extraordinary', Duration.zero, const Duration(seconds: 4));
      final shortWord = syllables[0].end - syllables[0].start;
      final longWord = syllables[1].end - syllables[1].start;
      // "I" is one syllable, "extraordinary" is six: the long word must get
      // several times the time, which a per-letter weighting badly understated.
      expect(longWord, greaterThan(shortWord * 3));
    });

    test('leaves a breath after clause punctuation', () {
      final syllables = estimateSyllables('Hello, world', Duration.zero, const Duration(seconds: 2));
      expect(syllables[0].end, lessThan(syllables[1].start), reason: 'the comma should create a gap before the next word');
    });

    test('keeps words adjacent when there is no punctuation', () {
      final syllables = estimateSyllables('Hello world', Duration.zero, const Duration(seconds: 2));
      expect(syllables[0].end, syllables[1].start);
    });

    test('never leaves a word with a zero or negative window', () {
      // A very short line with heavy punctuation is the worst case for the
      // pause logic: every word still needs a real window to highlight.
      final syllables = estimateSyllables('a, b, c, d, e', Duration.zero, const Duration(milliseconds: 120));
      for (final syllable in syllables) {
        expect(syllable.end, greaterThan(syllable.start));
      }
    });
  });

  group('staticLines', () {
    test('gives unsynced text no timing, rather than inventing even spacing', () {
      final lines = staticLines('First line\n\nSecond line\n   ');
      expect(lines, hasLength(2));
      for (final line in lines) {
        expect(line.start, Duration.zero);
        expect(line.end, Duration.zero);
      }
      expect(lines[1].plainText, 'Second line');
    });
  });

  group('parseLyricsfile', () {
    // Schema and units taken from LRCLIB's own server implementation and test
    // fixtures: metadata.offset_ms, lines[].start_ms/end_ms, and
    // lines[].words[].start_ms — all integer milliseconds.
    const wordSynced = '''
version: '1.0'
metadata:
  title: Test Song
  artist: Test Artist
  instrumental: false
  duration_ms: 200000
  offset_ms: -20
lines:
  - text: Hello world
    start_ms: 1000
    end_ms: 2000
    words:
      - text: "Hello "
        start_ms: 1000
      - text: world
        start_ms: 1500
  - text: Second line
    start_ms: 3000
plain: |
  Hello world
  Second line
''';

    test('parses word-level timing and applies the document offset', () {
      final data = parseLyricsfile(wordSynced);
      expect(data, isNotNull);
      expect(data!.hasWordSync, isTrue);
      expect(data.lines, hasLength(2));
      expect(data.lines[0].start, const Duration(milliseconds: 980), reason: '1000ms with a -20ms offset');
      expect(data.lines[0].end, const Duration(milliseconds: 1980));
      expect(data.lines[1].start, const Duration(milliseconds: 2980));
      expect(data.lines[1].end, const Duration(milliseconds: 8980), reason: 'last line closes 6s after its start');
      expect(data.offset, const Duration(milliseconds: -20));
    });

    test('keeps real per-word timings on the words', () {
      final line = parseLyricsfile(wordSynced)!.lines.first;
      expect(line.plainText, 'Hello world');
      expect(line.syllables, hasLength(2));
      expect(line.syllables[0].start, const Duration(milliseconds: 980));
      expect(line.syllables[1].start, const Duration(milliseconds: 1480));
    });

    test('treats a lines-only document as line-level, never as word sync', () {
      final data = parseLyricsfile('''
metadata:
  instrumental: false
lines:
  - text: First line
    start_ms: 5000
  - text: Second line
    start_ms: 8000
''');
      expect(data, isNotNull);
      expect(data!.hasWordSync, isFalse);
      expect(data.lines[0].start, const Duration(milliseconds: 5000));
      expect(data.lines[0].end, const Duration(milliseconds: 8000), reason: 'closed by the next line');
      expect(data.lines[0].plainText, 'First line');
    });

    test('reports an instrumental document as instrumental', () {
      final data = parseLyricsfile('''
metadata:
  instrumental: true
lines:
  - text: (no vocals)
    start_ms: 100
''');
      expect(data, isNotNull);
      expect(data!.instrumental, isTrue);
    });

    test('skips a block scalar without mistaking its body for keys', () {
      final data = parseLyricsfile('''
metadata:
  instrumental: false
lines:
  - text: Real line
    start_ms: 1000
plain: |
  lines:
  - text: not a real line
  metadata: nope
''');
      expect(data!.lines, hasLength(1));
      expect(data.lines.single.plainText, 'Real line');
    });

    test('returns null when there is no timed line to use', () {
      expect(parseLyricsfile('plain: |\n  just text, no timings'), isNull);
    });
  });

  group('pickBestCandidate', () {
    final records = [
      {
        'trackName': 'Right Song',
        'artistName': 'Right Artist',
        'duration': 200.0,
        'syncedLyrics': '[00:01.00]right',
        'plainLyrics': 'right',
        'instrumental': false,
      },
      {
        'trackName': 'Right Song',
        'artistName': 'Right Artist',
        'duration': 260.0,
        'syncedLyrics': '[00:01.00]different version',
        'plainLyrics': null,
        'instrumental': false,
      },
    ];

    test('picks the closest duration and trusts its timings', () {
      final best = pickBestCandidate(records, title: 'Right Song', artist: 'Right Artist', duration: const Duration(seconds: 201));
      expect(best, isNotNull);
      expect(best!.delta, const Duration(seconds: 1));
      expect(best.timingsTrustworthy, isTrue);
    });

    test('never trusts timings from a recording of a very different length', () {
      final best = pickBestCandidate(records, title: 'Right Song', artist: 'Right Artist', duration: const Duration(seconds: 300));
      expect(best!.timingsTrustworthy, isFalse);
    });

    test('prefers a close unmatched-timing record over a far synced one', () {
      final best = pickBestCandidate(
        [
          {
            'trackName': 'Right Song',
            'artistName': 'Right Artist',
            'duration': 261.0,
            'syncedLyrics': '[00:01.00]a different recording',
            'plainLyrics': null,
            'instrumental': false,
          },
          {
            'trackName': 'Right Song',
            'artistName': 'Right Artist',
            'duration': 200.5,
            'syncedLyrics': null,
            'plainLyrics': 'the right words, no timings',
            'instrumental': false,
          },
        ],
        title: 'Right Song',
        artist: 'Right Artist',
        duration: const Duration(seconds: 200),
      );
      expect(best!.delta, const Duration(milliseconds: 500));
    });

    test('matches through feat./remastered suffixes and brackets', () {
      final best = pickBestCandidate(
        [
          {
            'trackName': 'Song (Remastered 2011)',
            'artistName': 'Artist feat. Someone',
            'duration': 100.0,
            'syncedLyrics': '[00:01.00]x',
            'plainLyrics': null,
            'instrumental': false,
          },
        ],
        title: 'Song',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
      );
      expect(best, isNotNull);
      expect(best!.textPenalty, 0);
    });

    test('skips instrumental records and returns null when nothing usable is left', () {
      final best = pickBestCandidate(
        [
          {'trackName': 'Song', 'artistName': 'Artist', 'duration': 100.0, 'instrumental': true},
          {'trackName': 'Song', 'artistName': 'Artist', 'duration': 100.0, 'plainLyrics': '   ', 'syncedLyrics': null, 'instrumental': false},
        ],
        title: 'Song',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
      );
      expect(best, isNull);
    });
  });

  group('trackFromRecord', () {
    test('is null for an instrumental record', () {
      final track = trackFromRecord(
        {'instrumental': true, 'plainLyrics': 'x'},
        duration: const Duration(seconds: 100),
        source: LyricsSource.lrclib,
      );
      expect(track, isNull);
    });

    test('reports real word sync from a word-synced Lyricsfile', () {
      final track = trackFromRecord(
        {
          'instrumental': false,
          'trackName': 'Test Song',
          'artistName': 'Test Artist',
          'duration': 100.0,
          'lyricsfile': '''
metadata:
  instrumental: false
lines:
  - text: Hello world
    start_ms: 1000
    words:
      - text: "Hello "
        start_ms: 1000
      - text: world
        start_ms: 1500
''',
        },
        duration: const Duration(seconds: 100),
        source: LyricsSource.lrclib,
        matchDelta: const Duration(seconds: 1),
      );
      expect(track, isNotNull);
      expect(track!.type, LyricsSyncType.syllable);
      expect(track.hasRealWordSync, isTrue);
      expect(track.wordTimingIsEstimated, isFalse);
      expect(track.matchedTitle, 'Test Song');
    });

    test('downgrades a synced record whose length does not match to unsynced text', () {
      final track = trackFromRecord(
        {
          'instrumental': false,
          'syncedLyrics': '[00:01.00]words for another version',
          'plainLyrics': null,
          'duration': 300.0,
        },
        duration: const Duration(seconds: 200),
        source: LyricsSource.lrclib,
        matchDelta: const Duration(seconds: 100),
      );
      expect(track!.type, LyricsSyncType.static_, reason: 'timings from a 300s recording must not drive a 200s track');
      expect(track.lines.single.plainText, 'words for another version');
    });

    test('marks line-level results as having estimated word timing', () {
      final track = trackFromRecord(
        {'instrumental': false, 'syncedLyrics': '[00:01.00]one two three', 'duration': 100.0},
        duration: const Duration(seconds: 100),
        source: LyricsSource.lrclib,
        matchDelta: const Duration(seconds: 1),
      );
      expect(track!.type, LyricsSyncType.line);
      expect(track.wordTimingIsEstimated, isTrue);
      expect(track.hasRealWordSync, isFalse);
    });

    test('returns null when the record carries no usable text', () {
      final track = trackFromRecord(
        {'instrumental': false, 'duration': 100.0},
        duration: const Duration(seconds: 100),
        source: LyricsSource.lrclib,
      );
      expect(track, isNull);
    });
  });

  group('parseEmbeddedStructured', () {
    test('prefers the synced entry and reads millisecond starts', () {
      final track = parseEmbeddedStructured(
        {
          'structuredLyrics': [
            {
              'synced': false,
              'line': [
                {'value': 'unsynced a'},
                {'value': 'unsynced b'},
              ],
            },
            {
              'synced': true,
              'line': [
                {'start': 1000, 'value': 'first'},
                {'start': 3000, 'value': 'second'},
              ],
            },
          ],
        },
        songDuration: const Duration(seconds: 30),
      );
      expect(track, isNotNull);
      expect(track!.source, LyricsSource.embedded);
      expect(track.type, LyricsSyncType.line);
      expect(track.lines, hasLength(2));
      expect(track.lines[0].start, const Duration(seconds: 1));
      expect(track.lines[1].start, const Duration(seconds: 3));
    });

    test('treats an entry with no start values as unsynced text', () {
      final track = parseEmbeddedStructured(
        {
          'structuredLyrics': [
            {
              'synced': false,
              'line': [
                {'value': 'line one'},
                {'value': 'line two'},
              ],
            },
          ],
        },
        songDuration: const Duration(seconds: 30),
      );
      expect(track!.type, LyricsSyncType.static_, reason: 'OpenSubsonic omits start for unsynced lines — that must not read as 0:00');
      expect(track.lines, hasLength(2));
      expect(track.lines.first.start, Duration.zero);
    });

    test('is null when there is nothing structured to read', () {
      expect(parseEmbeddedStructured({'structuredLyrics': const []}, songDuration: const Duration(seconds: 10)), isNull);
      expect(parseEmbeddedStructured(const {}, songDuration: const Duration(seconds: 10)), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/lyrics.dart';
import 'package:shuro/services/ttml_parser.dart';

// Synthetic fixtures only - no real song lyrics.
const _wordDoc = '''<?xml version="1.0"?>
<tt xmlns="http://www.w3.org/ns/ttml">
  <body><div>
    <p begin="0:10.000" end="0:12.000">
      <span begin="0:10.000" end="0:10.500">alpha</span>
      <span begin="0:10.500" end="0:11.000">beta</span>
      <span begin="0:11.000" end="0:12.000">gamma</span>
    </p>
    <p begin="0:13.000" end="0:15.000">
      <span begin="0:13.000" end="0:14.000">delta</span>
      <span begin="0:14.000" end="0:15.000">epsilon</span>
    </p>
  </div></body>
</tt>''';

const _fragmentDoc = '''<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
<p begin="1:00.998" end="1:02.794"><span begin="1:00.998" end="1:01.293">ab</span><span begin="1:01.293" end="1:01.609">cd</span> <span begin="1:01.609" end="1:02.794">ef</span></p>
</div></body></tt>''';

const _lineOnlyDoc = '''<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
<p begin="0:05.000" end="0:08.000">just a line of text</p>
<p begin="0:09.000" end="0:12.000">and another one</p>
</div></body></tt>''';

void main() {
  group('parseTtmlTime', () {
    test('reads the supported clock forms', () {
      expect(parseTtmlTime('19.764'), const Duration(milliseconds: 19764));
      expect(parseTtmlTime('1:00.998'), const Duration(milliseconds: 60998));
      expect(parseTtmlTime('3:58.640'), const Duration(milliseconds: 238640));
      expect(parseTtmlTime('00:03:12.450'), const Duration(milliseconds: 192450));
      expect(parseTtmlTime('1500ms'), const Duration(milliseconds: 1500));
      expect(parseTtmlTime('12.5s'), const Duration(milliseconds: 12500));
    });
    test('rejects garbage', () {
      expect(parseTtmlTime(null), isNull);
      expect(parseTtmlTime('abc'), isNull);
      expect(parseTtmlTime('1:2:3:4'), isNull);
    });
  });

  group('parseTtml', () {
    test('word timing is kept and typed as word', () {
      final t = parseTtml(_wordDoc, duration: const Duration(minutes: 1))!;
      expect(t.type, LyricsSyncType.word);
      expect(t.source, LyricsSource.lrcRed);
      expect(t.hasRealWordSync, isTrue);
      expect(t.wordTimingIsEstimated, isFalse);
      expect(t.lines, hasLength(2));
      expect(t.lines[0].plainText, 'alpha beta gamma');
      expect(t.lines[0].syllables[1].start, const Duration(milliseconds: 10500));
      expect(t.lines[0].syllables[1].end, const Duration(milliseconds: 11000));
    });

    test('adjacent spans are fragments of one word but keep their timing', () {
      final t = parseTtml(_fragmentDoc)!;
      expect(t.type, LyricsSyncType.syllable);
      final s = t.lines.single.syllables;
      expect(t.lines.single.plainText, 'abcd ef');
      expect(s[0].isPartOfWord, isFalse);
      expect(s[1].isPartOfWord, isTrue);
      expect(s[2].isPartOfWord, isFalse);
      expect(s[1].start, const Duration(milliseconds: 61293));
    });

    test('line-only TTML is never labelled word synchronized', () {
      final t = parseTtml(_lineOnlyDoc)!;
      expect(t.type, LyricsSyncType.line);
      expect(t.hasRealWordSync, isFalse);
      expect(t.wordTimingIsEstimated, isTrue);
    });

    test('malformed XML and empty documents are rejected', () {
      expect(parseTtml('<tt><body>'), isNull);
      expect(parseTtml('<tt xmlns="http://www.w3.org/ns/ttml"><body/></tt>'), isNull);
    });

    test('timing far outside the recording is rejected', () {
      expect(parseTtml(_wordDoc, duration: const Duration(seconds: 3)), isNull);
    });
  });
}

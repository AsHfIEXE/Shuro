import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/lyrics_parser.dart';

/// The standard LRC `[offset:±ms]` tag shifts every timestamp in the
/// shifts every timestamp in the file. Real-world .lrc rips carry it, and
/// ignoring it misaligns the whole song by the tag's value.
void main() {
  test('positive offset delays every line', () {
    final parsed = parseLrc('[offset:+500]\n[00:01.00]First\n[00:03.00]Second');
    expect(parsed.lines.length, 2);
    expect(parsed.lines.first.start, const Duration(milliseconds: 1500));
    expect(parsed.lines[1].start, const Duration(milliseconds: 3500));
  });

  test('negative offset advances lines and clamps at zero', () {
    final parsed = parseLrc('[offset:-500]\n[00:00.20]Early\n[00:02.00]Later');
    expect(parsed.lines.first.start, Duration.zero);
    expect(parsed.lines[1].start, const Duration(milliseconds: 1500));
  });

  test('no offset tag leaves timings untouched', () {
    final parsed = parseLrc('[00:01.00]First');
    expect(parsed.lines.first.start, const Duration(seconds: 1));
  });
}

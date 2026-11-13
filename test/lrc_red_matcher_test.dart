import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/lrc_red_service.dart';

LrcRedCandidate _c(String title, String artist, int seconds, {String? album}) => LrcRedCandidate(
    isrc: 'XX0000000001', title: title, artist: artist, album: album, duration: Duration(seconds: seconds));

void main() {
  const want = Duration(seconds: 238);

  test('accepts the right recording', () {
    expect(LrcRedMatcher.accept(_c('Song A', 'Artist X', 239), title: 'Song A', artist: 'Artist X', duration: want), isTrue);
  });

  test('rejects the same title by another artist', () {
    expect(LrcRedMatcher.accept(_c('Song A', 'Someone Else', 238), title: 'Song A', artist: 'Artist X', duration: want), isFalse);
  });

  test('rejects a live version with a different length', () {
    expect(LrcRedMatcher.accept(_c('Song A', 'Artist X', 290), title: 'Song A', artist: 'Artist X', duration: want), isFalse);
  });

  test('ignores feat. and remaster suffixes when comparing', () {
    expect(LrcRedMatcher.similarity('Song A (feat. Guest)', 'Song A'), 1);
    expect(LrcRedMatcher.similarity('Song A - 2011 Remastered', 'Song A'), 1);
  });

  test('parses a bare list or a wrapped list of search hits', () {
    final item = {'isrc': 'XX1', 'title': 'T', 'artist': 'A', 'duration': 200.5};
    expect(LrcRedService.parseSearch([item]).single.duration, const Duration(milliseconds: 200500));
    expect(LrcRedService.parseSearch({'results': [item]}), hasLength(1));
    // The documented shape.
    expect(LrcRedService.parseSearch({'hits': [item], 'next': 'p24'}), hasLength(1));
    expect(LrcRedService.parseSearch(null), isEmpty);
  });
}

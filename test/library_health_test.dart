import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/services/library_health.dart';

Song song(
  String id, {
  String title = 'Track',
  String artist = 'Artist',
  String albumId = 'album-1',
  Duration duration = const Duration(minutes: 3),
  bool withArtwork = true,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    artistId: 'artist-1',
    albumId: albumId,
    duration: duration,
    gradientColors: const [Colors.black, Colors.white],
    artwork: withArtwork
        ? const NetworkImage('https://example.invalid/a.jpg')
        : null,
    audioInfo: const AudioInfo(),
  );
}

HealthIssue? issue(LibraryHealthReport report, String id) {
  for (final i in report.issues) {
    if (i.id == id) return i;
  }
  return null;
}

/// The report drives user-facing claims, so its grouping rules are pinned:
/// only prove-able problems are reported, and duplicates stay conservative.
void main() {
  test('a clean library reports nothing', () {
    final report = LibraryHealthReport.build([song('a', title: 'One'), song('b', title: 'Two')]);
    expect(report.issues, isEmpty);
    expect(report.isEmpty, isTrue);
    expect(report.totalSongs, 2);
    expect(report.totalIssues, 0);
  });

  test('an empty library is empty, not broken', () {
    final report = LibraryHealthReport.build([]);
    expect(report.totalSongs, 0);
    expect(report.issues, isEmpty);
  });

  test('flags missing artwork only when the track really has none', () {
    final report = LibraryHealthReport.build([
      song('a', withArtwork: false),
      song('b'),
    ]);
    final artwork = issue(report, 'artwork');
    expect(artwork, isNotNull);
    expect(artwork!.count, 1);
    expect(artwork.songs.single.id, 'a');
  });

  test('treats a blank or "Unknown Artist" tag as missing', () {
    final report = LibraryHealthReport.build([
      song('a', artist: ''),
      song('b', artist: 'Unknown Artist'),
      song('c', artist: 'Real Artist'),
    ]);
    expect(issue(report, 'artist')!.count, 2);
  });

  test('different mixes of the same title are not duplicates', () {
    final report = LibraryHealthReport.build([
      song('a', title: 'Song', duration: const Duration(minutes: 3)),
      song('b', title: 'Song', duration: const Duration(minutes: 4)),
    ]);
    expect(issue(report, 'duplicates'), isNull);
  });

  test('identical artist, title and length are grouped as a duplicate', () {
    final report = LibraryHealthReport.build([
      song('a', title: 'Song'),
      song('b', title: 'Song'),
    ]);
    final dupes = issue(report, 'duplicates');
    expect(dupes, isNotNull);
    expect(dupes!.count, 2, reason: 'both rows are listed so either can be kept');
  });

  test('unknown duration is its own finding, not silently dropped', () {
    final report = LibraryHealthReport.build([
      song('a', duration: Duration.zero),
      song('b'),
    ]);
    expect(issue(report, 'duration')!.count, 1);
  });

  test('totalIssues sums every check', () {
    final report = LibraryHealthReport.build([
      song('a', withArtwork: false, artist: ''),
      song('b'),
    ]);
    expect(report.totalIssues, 2);
  });
}

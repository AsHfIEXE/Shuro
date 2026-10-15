import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/backend/music_repository.dart';
import 'package:shuro/models/album.dart';
import 'package:shuro/models/artist.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/services/multi_server.dart';

Song _song(String id, String title, {String artist = 'Artist', String albumId = 'al1', String artistId = 'ar1', int seconds = 200}) => Song(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      albumId: albumId,
      duration: Duration(seconds: seconds),
      gradientColors: const [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
    );

Album _album(String id, String title, {String artist = 'Artist', String artistId = 'ar1', List<String> songIds = const []}) => Album(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      year: 2020,
      gradientColors: const [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
      songIds: songIds,
    );

Artist _artist(String id, String name, {List<String> albumIds = const []}) => Artist(
      id: id,
      name: name,
      gradientColors: const [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
      albumIds: albumIds,
      topSongIds: const [],
    );

MusicLibrarySnapshot _snapshot({List<Song> songs = const [], List<Album> albums = const [], List<Artist> artists = const [], Map<String, List<String>> genres = const {}}) =>
    MusicLibrarySnapshot(songs: songs, albums: albums, artists: artists, genreSongIds: genres);

void main() {
  group('id qualification', () {
    test('round-trips through qualify/decoders', () {
      final id = MultiServerLibrary.qualify('srv_a', '42');
      expect(id, 'srv_a::42');
      expect(MultiServerLibrary.serverIdOf(id), 'srv_a');
      expect(MultiServerLibrary.remoteIdOf(id), '42');
    });

    test('bare legacy ids decode to null server / identity remote', () {
      expect(MultiServerLibrary.serverIdOf('plainid'), isNull);
      expect(MultiServerLibrary.remoteIdOf('plainid'), 'plainid');
    });

    test('adopt leaves qualified ids untouched', () {
      expect(MultiServerLibrary.adopt('srv_a', 'srv_b::7'), 'srv_b::7');
      expect(MultiServerLibrary.adopt('srv_a', '7'), 'srv_a::7');
    });
  });

  group('merge', () {
    test('same remote id on two servers stays two distinct songs', () {
      // The core conflict case: both servers call a DIFFERENT song "42".
      final merged = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(songs: [_song('42', 'Song A')])),
        MapEntry('b', _snapshot(songs: [_song('42', 'Song B')])),
      ]);
      expect(merged.songs, hasLength(2));
      expect(merged.songs.map((s) => s.title), containsAll(['Song A', 'Song B']));
      expect(merged.songs.map((s) => s.id), containsAll(['a::42', 'b::42']));
    });

    test('same track on two servers dedupes to the first server copy', () {
      final merged = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(songs: [_song('1', 'Same Song', seconds: 200)])),
        MapEntry('b', _snapshot(songs: [_song('9', 'same song', seconds: 200)])),
      ]);
      expect(merged.songs, hasLength(1));
      expect(merged.songs.single.id, 'a::1');
    });

    test('duration within the same second dedupes, different seconds do not', () {
      final sameSecond = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(songs: [_song('1', 'X', seconds: 200)])),
        MapEntry('b', _snapshot(songs: [_song('2', 'X', seconds: 200)])),
      ]);
      expect(sameSecond.songs, hasLength(1));

      final different = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(songs: [_song('1', 'X', seconds: 200)])),
        MapEntry('b', _snapshot(songs: [_song('2', 'X', seconds: 245)])),
      ]);
      expect(different.songs, hasLength(2));
    });

    test('album songIds union through the song keep-map', () {
      final merged = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(
          songs: [_song('s1', 'One'), _song('s2', 'Two')],
          albums: [_album('al', 'Album', songIds: ['s1', 's2'])],
        )),
        MapEntry('b', _snapshot(
          // Same album, its own copy of "One" (dupe) plus a new "Three".
          songs: [_song('s1', 'One'), _song('s3', 'Three')],
          albums: [_album('al', 'Album', songIds: ['s1', 's3'])],
        )),
      ]);
      expect(merged.albums, hasLength(1));
      final album = merged.albums.single;
      expect(album.id, 'a::al');
      // "One" kept once (a::s1), "Two" from a, "Three" only on b is kept:
      // b's s3 is reachable through b's album listing. The duplicated listing
      // of "One" across both copies collapses.
      expect(album.songIds, ['a::s1', 'a::s2', 'b::s3']);
      // No dangling references: every listed id exists in the merged songs.
      final songIds = merged.songs.map((s) => s.id).toSet();
      for (final id in album.songIds) {
        expect(songIds, contains(id), reason: 'dangling album reference $id');
      }
    });

    test('song cross-references are rewritten to kept album/artist ids', () {
      final merged = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(
          songs: [_song('s1', 'One', albumId: 'al', artistId: 'ar')],
          albums: [_album('al', 'Album')],
          artists: [_artist('ar', 'Artist')],
        )),
        MapEntry('b', _snapshot(
          // Same artist/album names → deduped into a's entries; the song from
          // b must point at a's kept album/artist ids.
          songs: [_song('s9', 'Nine', albumId: 'al9', artistId: 'ar9')],
          albums: [_album('al9', 'Album')],
          artists: [_artist('ar9', 'Artist')],
        )),
      ]);
      final nine = merged.songs.firstWhere((s) => s.title == 'Nine');
      expect(nine.id, 'b::s9');
      expect(nine.albumId, 'a::al');
      expect(nine.artistId, 'a::ar');
    });

    test('genre map dedupes and rewrites onto kept songs', () {
      final merged = MultiServerLibrary.merge([
        MapEntry('a', _snapshot(
          songs: [_song('s1', 'One')],
          genres: {'Rock': ['s1']},
        )),
        MapEntry('b', _snapshot(
          songs: [_song('s1', 'One'), _song('s2', 'Two')],
          genres: {'Rock': ['s1', 's2']},
        )),
      ]);
      expect(merged.genreSongIds['Rock'], unorderedEquals(['a::s1', 'b::s2']));
    });

    test('single server passes through with qualified ids', () {
      final merged = MultiServerLibrary.merge([
        MapEntry('only', _snapshot(
          songs: [_song('s1', 'One')],
          albums: [_album('al', 'Album', songIds: ['s1'])],
          artists: [_artist('ar', 'Artist', albumIds: ['al'])],
        )),
      ]);
      expect(merged.songs.single.id, 'only::s1');
      expect(merged.albums.single.id, 'only::al');
      expect(merged.artists.single.id, 'only::ar');
      expect(merged.albums.single.songIds, ['only::s1']);
      expect(merged.artists.single.albumIds, ['only::al']);
    });
  });
}

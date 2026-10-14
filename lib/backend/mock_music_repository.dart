import '../data/mock_library.dart';
import '../models/download_state.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import 'music_repository.dart';

/// The default/demo backend: wraps the existing static [MockLibrary] data
/// behind the [MusicRepository] interface so the app has something to show
/// before anyone connects a real server, and so "connect" always works in
/// a demo/offline context.
///
/// [connect] never fails — there's nothing to reach. [streamUrlFor] always
/// returns null: the mock catalog is illustrative data with no real audio
/// files behind it, so songs from it correctly show as "no audio source"
/// once real playback is wired in. That's intentional, not a bug.
class MockMusicRepository extends MusicRepository {
  @override
  Future<void> connect() async {}

  @override
  Future<MusicLibrarySnapshot> fetchLibrary() async {
    return MusicLibrarySnapshot(
      songs: MockLibrary.songs,
      albums: MockLibrary.albums,
      artists: MockLibrary.artists,
      // MockLibrary's own map is artist-keyed demo data (one genre per
      // sample artist) — expanded to the song-ID-keyed shape every backend
      // now returns, so the Genres tab's filtering logic is identical for
      // the mock and real backends.
      genreSongIds: {
        for (final entry in MockLibrary.genreArtistIds.entries)
          entry.key: MockLibrary.songs.where((s) => entry.value.contains(s.artistId)).map((s) => s.id).toList(),
      },
    );
  }

  @override
  String? streamUrlFor(Song song, {StreamingQuality quality = StreamingQuality.original}) => null;

  @override
  Future<LyricsTrack?> fetchEmbeddedLyrics(Song song) async => null;

  @override
  void dispose() {}
}

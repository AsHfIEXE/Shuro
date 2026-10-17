import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/audio_info.dart';
import '../models/download_state.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../services/lyrics_service.dart';
import '../services/device_profile.dart';
import 'music_repository.dart';
import 'navidrome_api_client.dart';

/// The real backend: talks to a Navidrome (or any OpenSubsonic-compatible)
/// server via [NavidromeApiClient] and maps its responses onto Shuro's
/// app models.
///
/// Fetches the whole library once per [fetchLibrary] call (artists, then
/// every album, then that album's songs) and derives a genre -> song IDs
/// map client-side from each song's own genre tag. That keeps every
/// existing screen (search, genre tab, album/artist detail) working
/// unchanged against a plain in-memory snapshot — no async refactor needed
/// anywhere outside this file and [AppState].
class NavidromeMusicRepository extends MusicRepository {
  NavidromeMusicRepository({
    required String baseUrl,
    required String username,
    required String password,
  }) : _client = NavidromeApiClient(baseUrl: baseUrl, username: username, password: password);

  final NavidromeApiClient _client;

  // A fixed, pleasant palette to color artwork-less artists/albums/songs
  // deterministically (same ID always gets the same colors), matching the
  // look of the old hand-picked MockLibrary gradients.
  static const List<List<Color>> _palette = [
    [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
    [Color(0xFFE0558C), Color(0xFFFF9CBB)],
    [Color(0xFF2F9E6E), Color(0xFF7BE6B1)],
    [Color(0xFFD97B29), Color(0xFFFFC37A)],
    [Color(0xFF2E7FD9), Color(0xFF8ECBFF)],
    [Color(0xFF9E3A3A), Color(0xFFFF8A8A)],
  ];

  List<Color> _gradientFor(String id) => _palette[id.hashCode.abs() % _palette.length];

  /// Maps OpenSubsonic's `channelCount` to the short label the Audio
  /// Information panel shows — null (server didn't send it) keeps
  /// [AudioInfo]'s own "Stereo" default rather than claiming to know.
  static String _channelLabel(int? count) => switch (count) {
        null => const AudioInfo().channels,
        1 => 'Mono',
        2 => 'Stereo',
        final n => '$n ch',
      };

  @override
  Future<void> connect() => _client.ping();

  /// How many `getAlbum` requests run at once during [fetchLibrary]. One
  /// request per album, sequentially, is what made the first real-server
  /// connect feel slow on any library bigger than a handful of albums —
  /// this bounds concurrency instead of firing every request at once
  /// (which could overwhelm a small self-hosted server) or one at a time.

  @override
  Future<MusicLibrarySnapshot> fetchLibrary() async {
    // Independent requests — no reason to wait on one before starting
    // the other.
    final results = await Future.wait([_client.getArtists(), _client.getAllAlbums()]);
    final rawArtists = results[0];
    final rawAlbums = results[1];

    final artists = <Artist>[];
    final artistAlbumIds = <String, List<String>>{};
    final artistTopSongIds = <String, List<String>>{};
    for (final a in rawArtists) {
      final id = '${a['id']}';
      artists.add(Artist(
        id: id,
        name: (a['name'] as String?) ?? 'Unknown artist',
        gradientColors: _gradientFor(id),
        artwork: a['coverArt'] != null ? NetworkImage(_client.coverArtUrl('${a['coverArt']}')) : null,
        albumIds: const [],
        topSongIds: const [],
      ));
      artistAlbumIds[id] = [];
      artistTopSongIds[id] = [];
    }

    // Fetch every album's song list concurrently (bounded) instead of one
    // `await` per album in a row — this is the single biggest cost in
    // connecting to a real library, and it parallelizes cleanly since
    // each request is independent. A single album's request failing
    // (a transient blip, a corrupt entry) is swallowed to `null` rather
    // than failing the whole connect — one bad album shouldn't make an
    // otherwise-healthy library unreachable.
    final albumDetails = await _mapWithConcurrency<Map<String, dynamic>, Map<String, dynamic>?>(
      rawAlbums,
      // Profile-driven parallelism (brief §2D): 2 on Performance,
      // 4 on Balanced, 6 on Quality — profile resolved once and cached.
      await DeviceProfileService.syncConcurrency(),
      (a) async {
        try {
          return await _client.getAlbum('${a['id']}');
        } catch (_) {
          return null;
        }
      },
    );

    final albums = <Album>[];
    final songs = <Song>[];
    // Keyed by song, not by artist — an artist with songs across several
    // genres must not have every one of their songs show up under all of
    // them (that was the bug: a genre page used to show a whole artist's
    // catalog just because one of their songs matched).
    final genreSongIds = <String, Set<String>>{};

    for (var i = 0; i < rawAlbums.length; i++) {
      final a = rawAlbums[i];
      final detail = albumDetails[i];
      if (detail == null) continue; // this one album's fetch failed — skip it, keep the rest
      final albumId = '${a['id']}';
      final artistId = '${a['artistId']}';
      final rawSongs = detail['song'] as List<dynamic>? ?? const [];

      final songIds = <String>[];
      for (final s in rawSongs) {
        final song = s as Map<String, dynamic>;
        final songId = '${song['id']}';
        final durationSecs = (song['duration'] as num?)?.toInt() ?? 0;
        final mapped = Song(
          id: songId,
          title: (song['title'] as String?) ?? 'Unknown title',
          artist: (song['artist'] as String?) ?? (a['artist'] as String?) ?? 'Unknown artist',
          artistId: artistId,
          albumId: albumId,
          duration: Duration(seconds: durationSecs),
          gradientColors: _gradientFor(songId),
          artwork: song['coverArt'] != null ? NetworkImage(_client.coverArtUrl('${song['coverArt']}')) : null,
          // samplingRate/bitDepth/channelCount are OpenSubsonic extension
          // fields (confirmed present on Navidrome's song response) — read
          // straight off the probed/tagged file, not guessed. Falling back
          // to AudioInfo's own defaults only when a server doesn't send
          // them (a plain-Subsonic server, or an older Navidrome), so the
          // Audio Information panel shows what was actually served instead
          // of a hardcoded "16-bit/44.1kHz" for every track.
          audioInfo: AudioInfo(
            format: (song['suffix'] as String?)?.toUpperCase() ?? 'FLAC',
            bitrateKbps: (song['bitRate'] as num?)?.toInt() ?? 1000,
            bitDepth: (song['bitDepth'] as num?)?.toInt() ?? const AudioInfo().bitDepth,
            sampleRateHz: (song['samplingRate'] as num?)?.toInt() ?? const AudioInfo().sampleRateHz,
            channels: _channelLabel((song['channelCount'] as num?)?.toInt()),
          ),
        );
        songs.add(mapped);
        songIds.add(songId);

        final genre = song['genre'] as String?;
        if (genre != null && genre.trim().isNotEmpty) {
          genreSongIds.putIfAbsent(genre, () => {}).add(songId);
        }
      }

      albums.add(Album(
        id: albumId,
        title: (a['name'] as String?) ?? 'Unknown album',
        artist: (a['artist'] as String?) ?? 'Unknown artist',
        artistId: artistId,
        year: (a['year'] as num?)?.toInt() ?? 0,
        gradientColors: _gradientFor(albumId),
        artwork: a['coverArt'] != null ? NetworkImage(_client.coverArtUrl('${a['coverArt']}')) : null,
        songIds: songIds,
      ));

      artistAlbumIds.putIfAbsent(artistId, () => []).add(albumId);
      artistTopSongIds.putIfAbsent(artistId, () => []).addAll(songIds.take(5));
    }

    // Rebuild the artist list with albumIds/topSongIds now that albums have
    // been aggregated (Artist is immutable, so this re-creates each one
    // rather than mutating in place).
    final finishedArtists = artists
        .map((artist) => Artist(
              id: artist.id,
              name: artist.name,
              gradientColors: artist.gradientColors,
              artwork: artist.artwork,
              albumIds: artistAlbumIds[artist.id] ?? const [],
              topSongIds: (artistTopSongIds[artist.id] ?? const []).take(10).toList(),
            ))
        .toList();

    return MusicLibrarySnapshot(
      songs: songs,
      albums: albums,
      artists: finishedArtists,
      genreSongIds: genreSongIds.map((genre, ids) => MapEntry(genre, ids.toList())),
    );
  }

  @override
  String? streamUrlFor(Song song, {StreamingQuality quality = StreamingQuality.original}) {
    if (song.isLocal) return null;
    return _client.streamUrl(song.id, quality: quality);
  }

  @override
  Future<LyricsTrack?> fetchEmbeddedLyrics(Song song) async {
    final raw = await _client.getLyricsBySongId(song.id);
    if (raw == null) return null;
    try {
      return LyricsService.parseEmbedded(raw, songDuration: song.duration);
    } catch (_) {
      // Whatever came back didn't match the shape we expect — treat it
      // the same as "nothing embedded" rather than failing the whole
      // lyrics fetch over a server quirk.
      return null;
    }
  }

  @override
  void dispose() => _client.dispose();

  /// Runs [fn] over [items] with at most [concurrency] calls in flight at
  /// once, preserving input order in the result (unlike a bare
  /// `Future.wait` over the whole list, which would fire every call
  /// simultaneously regardless of [concurrency]). A fixed pool of workers
  /// each pull the next index off a shared cursor — safe without a lock
  /// since Dart's event loop never preempts between the cursor read/bump
  /// and the next `await`.
  static Future<List<R>> _mapWithConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T item) fn,
  ) async {
    if (items.isEmpty) return const [];
    final results = List<R?>.filled(items.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final i = cursor;
        if (i >= items.length) return;
        cursor++;
        results[i] = await fn(items[i]);
      }
    }

    await Future.wait(List.generate(concurrency.clamp(1, items.length), (_) => worker()));
    return results.cast<R>();
  }
}

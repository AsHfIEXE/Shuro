import '../backend/music_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';

/// Combined multi-server library — merge core.
///
/// The requirement: a user can enable ONE server (today's behaviour), SOME,
/// or ALL of their servers, and the app shows one library — no duplicate
/// entries, no id conflicts, no wrong-server routing.
///
/// The conflict-proof design, in three rules:
///
///  1. **Namespaced ids.** Every song/album/artist id becomes
///     `serverId::remoteId`. Subsonic ids are only unique *within* a server —
///     two servers may both have a song `"42"` — so every id that crosses
///     into app state (queue, favourites, history, downloads, artwork cache
///     keys) is qualified. Downstream code treats ids as opaque strings and
///     needs no changes; the two functions that need to know *which server*
///     an item lives on ([serverIdOf] / [remoteIdOf]) are the only decoders.
///
///  2. **Dedupe by identity, not by id.** The same track present on two
///     servers is ONE entry: matched on normalised (title, artist, duration).
///     Same for albums (title + artist) and artists (name). The first server
///     in the enabled order wins (the caller lists the active server first,
///     so the copy you're "already on" wins ties).
///
///  3. **Rewritten references.** After dedupe, every cross-reference —
///     song→album, song→artist, album→songs, artist→albums, the genre map —
///     is remapped through the keep-maps, so no entry ever points at a
///     dropped id. That is what makes the merge conflict-free rather than
///     "mostly works".
class MultiServerLibrary {
  MultiServerLibrary._();

  static const String separator = '::';

  static String qualify(String serverId, String remoteId) => '$serverId$separator$remoteId';

  /// The server a qualified id belongs to, or null for a bare (legacy) id.
  static String? serverIdOf(String id) {
    final index = id.indexOf(separator);
    return index <= 0 ? null : id.substring(0, index);
  }

  /// The server-side id behind a qualified id (identity for bare ids).
  static String remoteIdOf(String id) {
    final index = id.indexOf(separator);
    return index < 0 ? id : id.substring(index + separator.length);
  }

  /// Qualifies a bare id with [serverId] — used by the legacy-data migration
  /// (pre-multi-server favourites/history/queue stored bare ids).
  static String adopt(String serverId, String id) =>
      serverIdOf(id) == null ? qualify(serverId, id) : id;

  /// A repository-ready copy of [song]: ids back in the owning server's own
  /// namespace. Repositories build request URLs from `song.id` — a qualified
  /// (`server::42`) id would leak the namespace into the HTTP call. Used on
  /// the way IN to a per-server repository (stream URLs, embedded lyrics);
  /// everything crossing back out keeps qualified ids.
  static Song localizeSong(String serverId, Song song) => Song(
        id: remoteIdOf(song.id),
        title: song.title,
        artist: song.artist,
        artistId: remoteIdOf(song.artistId),
        albumId: remoteIdOf(song.albumId),
        duration: song.duration,
        gradientColors: song.gradientColors,
        artwork: song.artwork,
        audioInfo: song.audioInfo,
        localFilePath: song.localFilePath,
      );

  static String _norm(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Identity key for a track: title + artist + duration rounded to the
  /// second (encoders disagree on the last millisecond — that must not
  /// defeat the dedupe).
  static String songKey(Song song) =>
      '${_norm(song.title)}|${_norm(song.artist)}|${song.duration.inSeconds}';

  static String albumKey(Album album) => '${_norm(album.title)}|${_norm(album.artist)}';

  static String artistKey(Artist artist) => _norm(artist.name);

  /// Merges per-server snapshots (in priority order — first wins ties) into
  /// one snapshot with qualified ids, deduped entries, rewritten references.
  static MusicLibrarySnapshot merge(List<MapEntry<String, MusicLibrarySnapshot>> perServer) {
    // ---- qualify everything first (single pass, stable) --------------------
    final songs = <Song>[];
    final albums = <Album>[];
    final artists = <Artist>[];
    final genres = <String, List<String>>{};

    for (final entry in perServer) {
      final serverId = entry.key;
      for (final song in entry.value.songs) {
        songs.add(_qualifiedSong(serverId, song));
      }
      for (final album in entry.value.albums) {
        albums.add(_qualifiedAlbum(serverId, album));
      }
      for (final artist in entry.value.artists) {
        artists.add(_qualifiedArtist(serverId, artist));
      }
      entry.value.genreSongIds.forEach((genre, ids) {
        genres.putIfAbsent(genre, () => []).addAll(ids.map((id) => qualify(serverId, id)));
      });
    }

    // ---- dedupe songs (first wins) -----------------------------------------
    final songIdMap = <String, String>{}; // original qualified id -> kept id
    final keptSongs = <Song>[];
    final seenSongs = <String, String>{}; // identity key -> kept id
    for (final song in songs) {
      final key = songKey(song);
      final existing = seenSongs[key];
      if (existing != null) {
        songIdMap[song.id] = existing; // dropped — remember where it went
        continue;
      }
      seenSongs[key] = song.id;
      songIdMap[song.id] = song.id;
      keptSongs.add(song);
    }

    // ---- dedupe albums (first wins), songIds merged through the song map ----
    final albumIdMap = <String, String>{};
    final keptAlbums = <Album>[];
    final albumIndex = <String, int>{}; // identity key -> index in keptAlbums
    for (final album in albums) {
      final key = albumKey(album);
      final keptIndex = albumIndex[key];
      final mappedSongs = [
        for (final id in album.songIds)
          if (songIdMap.containsKey(id)) songIdMap[id]!
      ];
      if (keptIndex != null) {
        final kept = keptAlbums[keptIndex];
        // Order-preserving union, deduped: a song listed by BOTH copies of
        // the album must appear once.
        final union = <String>{...kept.songIds, ...mappedSongs}.toList();
        keptAlbums[keptIndex] = _albumWithSongs(kept, union);
        albumIdMap[album.id] = kept.id;
        continue;
      }
      albumIndex[key] = keptAlbums.length;
      albumIdMap[album.id] = album.id;
      keptAlbums.add(_albumWithSongs(album, mappedSongs));
    }

    // ---- dedupe artists (first wins), albumIds merged through the album map
    final artistIdMap = <String, String>{};
    final keptArtists = <Artist>[];
    final artistIndex = <String, int>{};
    for (final artist in artists) {
      final key = artistKey(artist);
      final keptIndex = artistIndex[key];
      final mappedAlbums = [
        for (final id in artist.albumIds)
          if (albumIdMap.containsKey(id)) albumIdMap[id]!
      ];
      if (keptIndex != null) {
        final kept = keptArtists[keptIndex];
        final union = <String>{...kept.albumIds, ...mappedAlbums}.toList();
        keptArtists[keptIndex] = _artistWithAlbums(kept, union);
        artistIdMap[artist.id] = kept.id;
        continue;
      }
      artistIndex[key] = keptArtists.length;
      artistIdMap[artist.id] = artist.id;
      keptArtists.add(_artistWithAlbums(artist, mappedAlbums));
    }

    // ---- rewrite song cross-references + genre map --------------------------
    final finalSongs = [
      for (final song in keptSongs) _songWithRefs(
        song,
        albumId: albumIdMap[song.albumId] ?? song.albumId,
        artistId: artistIdMap[song.artistId] ?? song.artistId,
      ),
    ];
    final finalGenres = genres.map((genre, ids) {
      final kept = <String>{for (final id in ids) if (songIdMap.containsKey(id)) songIdMap[id]!};
      return MapEntry(genre, kept.toList());
    });

    return MusicLibrarySnapshot(
      songs: finalSongs,
      albums: keptAlbums,
      artists: keptArtists,
      genreSongIds: finalGenres,
    );
  }

  // ---- copy helpers (models are immutable, no copyWith exists) --------------

  static Song _qualifiedSong(String serverId, Song s) => _songWithRefs(
        s,
        id: qualify(serverId, s.id),
        albumId: qualify(serverId, s.albumId),
        artistId: qualify(serverId, s.artistId),
      );

  static Song _songWithRefs(Song s, {String? id, String? albumId, String? artistId}) => Song(
        id: id ?? s.id,
        title: s.title,
        artist: s.artist,
        artistId: artistId ?? s.artistId,
        albumId: albumId ?? s.albumId,
        duration: s.duration,
        gradientColors: s.gradientColors,
        artwork: s.artwork,
        audioInfo: s.audioInfo,
        localFilePath: s.localFilePath,
      );

  static Album _qualifiedAlbum(String serverId, Album a) => _albumWithSongs(
        _albumWithIds(a, id: qualify(serverId, a.id), artistId: qualify(serverId, a.artistId)),
        a.songIds.map((id) => qualify(serverId, id)).toList(),
      );

  static Album _albumWithIds(Album a, {String? id, String? artistId}) => Album(
        id: id ?? a.id,
        title: a.title,
        artist: a.artist,
        artistId: artistId ?? a.artistId,
        year: a.year,
        gradientColors: a.gradientColors,
        artwork: a.artwork,
        songIds: a.songIds,
      );

  static Album _albumWithSongs(Album a, List<String> songIds) => Album(
        id: a.id,
        title: a.title,
        artist: a.artist,
        artistId: a.artistId,
        year: a.year,
        gradientColors: a.gradientColors,
        artwork: a.artwork,
        songIds: songIds,
      );

  static Artist _qualifiedArtist(String serverId, Artist a) => _artistWithAlbums(
        _artistWithIds(a, id: qualify(serverId, a.id)),
        a.albumIds.map((id) => qualify(serverId, id)).toList(),
      );

  static Artist _artistWithIds(Artist a, {String? id}) => Artist(
        id: id ?? a.id,
        name: a.name,
        gradientColors: a.gradientColors,
        artwork: a.artwork,
        albumIds: a.albumIds,
        topSongIds: a.topSongIds,
      );

  static Artist _artistWithAlbums(Artist a, List<String> albumIds) => Artist(
        id: a.id,
        name: a.name,
        gradientColors: a.gradientColors,
        artwork: a.artwork,
        albumIds: albumIds,
        topSongIds: a.topSongIds,
      );
}

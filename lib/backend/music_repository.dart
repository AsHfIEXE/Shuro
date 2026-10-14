import '../models/album.dart';
import '../models/artist.dart';
import '../models/download_state.dart';
import '../models/lyrics.dart';
import '../models/song.dart';

/// The one seam between Shuro's UI/state layer and wherever the music
/// actually lives. [AppState] only ever talks to a [MusicRepository] —
/// never to a concrete backend directly — so swapping or adding a backend
/// (Navidrome today, something else tomorrow) never touches a screen.
///
/// Design choice: this app fetches the *entire* library once, right after
/// a successful [connect], and caches it (see [fetchLibrary]). Every
/// existing screen (search, genre browsing, album/artist detail) filters
/// that cache client-side, exactly like the old [MockLibrary] did. That
/// keeps every call site in the UI layer synchronous — no FutureBuilders,
/// no async rewrite of screens that already work — which is the right
/// trade-off for a personal/self-hosted library (hundreds to low
/// thousands of tracks), not a mass streaming catalog.
abstract class MusicRepository {
  /// Verifies the backend is reachable and the credentials are valid.
  /// Throws [MusicRepositoryException] on failure. Must not throw for
  /// "it worked" — only for real failures.
  Future<void> connect();

  /// Fetches the whole library in one go. Called once, right after a
  /// successful [connect]. The result is cached by [AppState] and reused
  /// for every catalog query until the user reconnects or disconnects.
  Future<MusicLibrarySnapshot> fetchLibrary();

  /// A directly-playable URL/path for [song], or null if this repository
  /// has no audio behind that song (e.g. a demo/mock entry). Must be
  /// synchronous and cheap — it's called on every play, not cached.
  ///
  /// [quality] is the caller's requested streaming quality (Settings ->
  /// Wi-Fi/Mobile data quality, resolved by [AppState] against the
  /// device's current connection type) — [StreamingQuality.original]
  /// must mean genuinely untranscoded audio wherever the backend supports
  /// that, not just a label.
  String? streamUrlFor(Song song, {StreamingQuality quality = StreamingQuality.original});

  /// Releases any held resources (HTTP clients, sockets, etc). Safe to
  /// call multiple times.
  void dispose();

  /// Lyrics the backend already extracted from [song]'s own file tags
  /// (ID3 `USLT`/`SYLT`, Vorbis comments, etc.), if it has any and
  /// supports returning them at all. Takes the whole [Song] (not just its
  /// ID) because an unsynced embedded result still needs the track's
  /// duration to spread evenly, the same way an unsynced LRCLIB result
  /// does. [MockMusicRepository] always returns null (nothing to extract
  /// from); [NavidromeMusicRepository] calls the OpenSubsonic
  /// `getLyricsBySongId` extension. Must not throw: "nothing embedded"
  /// and "couldn't check" are both null, so a server without this
  /// extension never blocks the LRCLIB fallback in [LyricsService].
  Future<LyricsTrack?> fetchEmbeddedLyrics(Song song);
}

/// What the server says about its own library scan. Used for change
/// detection: when the reported [ScanStatusInfo.lastScan] is unchanged
/// since the cached snapshot, the library is unchanged and a full
/// re-fetch (one getAlbum per album) can be skipped. A null [lastScan]
/// means "unknown" — never treated as "unchanged".
class ScanStatusInfo {
  /// When the server last finished scanning, if it reports it.
  final DateTime? lastScan;

  /// Whether a scan is currently running (a running scan means the library
  /// may be about to change — refresh once it finishes).
  final bool scanning;

  const ScanStatusInfo({this.lastScan, this.scanning = false});
}

/// Everything a freshly-connected backend knows about the library, shaped
/// to match exactly what the UI already consumes (see MockLibrary):
/// flat song/album/artist lists, plus a genre name -> song IDs map used by
/// the Genres tab and genre detail screen. Keyed by song, not by artist —
/// an artist with songs in several genres must not have every one of
/// their songs show up under all of them.
class MusicLibrarySnapshot {
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
  final Map<String, List<String>> genreSongIds;

  const MusicLibrarySnapshot({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.genreSongIds,
  });

  static const empty = MusicLibrarySnapshot(
    songs: [],
    albums: [],
    artists: [],
    genreSongIds: {},
  );
}

/// What went wrong talking to a backend, classified so [AppState] can map
/// it onto the existing [ConnectionStatus] states without needing to know
/// anything about the specific backend's error format.
enum MusicRepositoryFailure {
  /// Couldn't reach the server at all (DNS, timeout, connection refused,
  /// wrong URL, server down).
  unreachable,

  /// Reached the server, but the username/password/token was rejected.
  invalidCredentials,

  /// Reached the server, got a response, but something about it didn't
  /// make sense (unexpected shape, unsupported version, etc).
  unknown,
}

class MusicRepositoryException implements Exception {
  final String message;
  final MusicRepositoryFailure kind;

  MusicRepositoryException(this.message, this.kind);

  @override
  String toString() => 'MusicRepositoryException($kind): $message';
}

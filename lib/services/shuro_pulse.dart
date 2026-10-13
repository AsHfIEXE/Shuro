import 'dart:math';
import '../models/build_from_mode.dart';
import '../models/smart_playlist_preset.dart';
import '../models/song.dart';
import '../state/app_state.dart';

/// Shuro Pulse — the recommendation layer behind Discover, Smart Playlists,
/// "Build with Shuro" and "Build from this".
///
/// This is a real, working heuristic engine (not hardcoded lists): every
/// method below is a pure function over the existing mock library plus the
/// signals already tracked in [AppState] (favorites, listening history,
/// per-artist feedback). There's no network call and no stored profile —
/// everything here is recomputed on the fly from data already on-device,
/// which is also why it's trivially private: nothing leaves the app.
///
/// What's deliberately NOT here: a real audio-feature model (tempo, key,
/// timbre), a trained ranking model, and a persisted session/sequencing
/// optimizer. Those are the genuine multi-week pieces described in the
/// product doc — see the architecture notes in README.md for how a real
/// Drift/SQLite-backed version of this class would slot in without
/// changing any of the call sites below (every method already takes
/// AppState + the mock library as its only inputs, which is exactly the
/// seam a real implementation would keep).
class ShuroPulse {
  ShuroPulse._();

  /// Deterministic 0..1 stand-in for an audio "energy" feature (tempo,
  /// loudness, density) a real implementation would read from the file or
  /// an analysis service. Hashed from the song id so it's stable across
  /// rebuilds without needing to store anything.
  static double _energyOf(Song song) {
    final h = song.id.hashCode & 0x7fffffff;
    return (h % 1000) / 1000.0;
  }

  /// How much this song should be weighted, combining explicit signals
  /// (favorited, per-artist like/dislike feedback) — the closest thing this
  /// mock layer has to a "taste graph" score.
  static double _affinityOf(Song song, AppState appState) {
    double score = 0;
    if (appState.isFavoriteSong(song.id)) score += 3;
    if (appState.isFavoriteArtist(song.artistId)) score += 1.5;
    score += (appState.artistAffinity[song.artistId] ?? 0);
    return score;
  }

  /// True if [song] shows up within the most recent [withinLast] plays.
  static bool _recentlyPlayed(Song song, AppState appState, {int withinLast = 15}) {
    final idx = appState.listeningHistory.indexOf(song.id);
    return idx >= 0 && idx < withinLast;
  }

  static List<Song> _allSongs(AppState appState) => appState.allSongs;

  // --- Discover: For You --------------------------------------------------

  /// A single ranked list balancing familiarity (affinity) against a little
  /// discovery (songs never played) — the Familiarity↔Discovery balance
  /// from the product doc, implemented here as a simple weighted sort
  /// rather than a tunable slider (a real version would expose that ratio
  /// as a setting feeding straight into this scoring step).
  static List<Song> forYou(AppState appState, {int limit = 12}) {
    final songs = _allSongs(appState);
    final scored = songs.map((s) {
      double score = _affinityOf(s, appState);
      if (!appState.listeningHistory.contains(s.id)) score += 0.8; // discovery nudge
      if (_recentlyPlayed(s, appState, withinLast: 6)) score -= 2; // don't just repeat what's on now
      return (song: s, score: score);
    }).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.song).take(limit).toList();
  }

  // --- Discover: Tonight's Flow -------------------------------------------

  /// A whole listening *session* rather than a ranked list — interleaves
  /// favorites, tracks from favorite artists, and everything else so the
  /// sequence doesn't front-load all the familiar songs and dump the
  /// unfamiliar ones at the end (a crude stand-in for real transition/
  /// sequence optimization).
  static List<Song> tonightsFlow(AppState appState, {int length = 20}) {
    final songs = _allSongs(appState);
    final favorites = songs.where((s) => appState.isFavoriteSong(s.id)).toList();
    final favoriteArtistTracks = songs
        .where((s) => appState.isFavoriteArtist(s.artistId) && !appState.isFavoriteSong(s.id))
        .toList();
    final everythingElse = songs
        .where((s) => !appState.isFavoriteSong(s.id) && !appState.isFavoriteArtist(s.artistId))
        .toList();

    final pools = [
      favorites,
      [...favoriteArtistTracks, ...favoriteArtistTracks],
      everythingElse,
      favorites,
      everythingElse,
    ];

    final result = <Song>[];
    final used = <String>{};
    var round = 0;
    while (result.length < length && round < 50) {
      final pool = pools[round % pools.length];
      if (pool.isNotEmpty) {
        final candidate = pool[round % pool.length];
        if (used.add(candidate.id)) result.add(candidate);
      }
      round++;
      if (used.length >= songs.length) break;
    }
    return result;
  }

  // --- Discover: Because You Like <artist> --------------------------------

  /// One row per artist you already like, each with tracks from artists
  /// that share something simple and legible (same genre bucket) — this is
  /// what the product doc calls "playlist/artist-as-signal" at its most
  /// basic: a real version would walk a similarity graph instead of a
  /// shared-genre lookup.
  static List<({String artistId, String artistName, List<Song> songs})> becauseYouLike(
    AppState appState, {
    int artistLimit = 4,
  }) {
    // "Similar artist" only means anything against the server's artist/genre
    // graph — a local-only library has neither, so there's nothing honest
    // to show here rather than fabricating rows from nothing.
    if (!appState.hasServer) return const [];
    final likedArtistIds = <String>{
      ...appState.favoriteArtistIds,
      ...appState.artistAffinity.entries.where((e) => e.value > 0).map((e) => e.key),
    };
    if (likedArtistIds.isEmpty) {
      // Fall back to whoever shows up most in listening history.
      final counts = <String, int>{};
      for (final id in appState.listeningHistory) {
        final song = appState.songById(id);
        if (song == null) continue;
        counts[song.artistId] = (counts[song.artistId] ?? 0) + 1;
      }
      final sorted = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      likedArtistIds.addAll(sorted.take(artistLimit));
    }

    final rows = <({String artistId, String artistName, List<Song> songs})>[];
    for (final artistId in likedArtistIds.take(artistLimit)) {
      final artist = appState.artistById(artistId);
      if (artist == null) continue;
      // "Similar" artists = other artists sharing a genre bucket with this one.
      final genres = appState.catalogGenres.entries.where((e) => e.value.contains(artistId));
      final similarArtistIds = <String>{
        for (final g in genres) ...g.value,
      }..remove(artistId);

      final songs = appState.catalogSongs
          .where((s) => similarArtistIds.contains(s.artistId))
          .toList();
      if (songs.isEmpty) continue;
      songs.shuffle(Random(artistId.hashCode));
      rows.add((artistId: artistId, artistName: artist.name, songs: songs.take(8).toList()));
    }
    return rows;
  }

  // --- Discover: Rediscover ------------------------------------------------

  /// Favorited (or positively-rated) songs that haven't shown up in recent
  /// listening history at all.
  static List<Song> rediscover(AppState appState, {int limit = 10}) {
    final songs = _allSongs(appState);
    final candidates = songs.where((s) {
      final liked = appState.isFavoriteSong(s.id) || (appState.artistAffinity[s.artistId] ?? 0) > 0;
      return liked && !_recentlyPlayed(s, appState, withinLast: 30);
    }).toList();
    candidates.shuffle(Random(DateTime.now().day));
    return candidates.take(limit).toList();
  }

  // --- Discover: Deep Cuts --------------------------------------------------

  /// Tracks from artists you listen to, that aren't themselves the handful
  /// of most-played tracks from that artist — a cheap stand-in for "low
  /// play-count tracks by artists you already like".
  static List<Song> deepCuts(AppState appState, {int limit = 10}) {
    // Same reasoning as becauseYouLike — "deep cuts by an artist you like"
    // needs the server's full per-artist catalog to find the less-played
    // tracks from, which a local-only library doesn't have.
    if (!appState.hasServer) return const [];
    final likedArtistIds = <String>{
      ...appState.favoriteArtistIds,
      ...appState.artistAffinity.entries.where((e) => e.value >= 0).map((e) => e.key),
      ...appState.listeningHistory.map((id) => appState.songById(id)?.artistId).whereType<String>(),
    };
    final topPlayed = appState.listeningHistory.take(10).toSet();
    final songs = appState.catalogSongs
        .where((s) => likedArtistIds.contains(s.artistId) && !topPlayed.contains(s.id) && !appState.isFavoriteSong(s.id))
        .toList();
    songs.shuffle(Random(7));
    return songs.take(limit).toList();
  }

  // --- Discover: Fresh From Your Library -----------------------------------

  static List<Song> freshFromYourLibrary(AppState appState, {int limit = 10}) {
    if (appState.hasServer) {
      return appState.recentlyAddedSongs(limit: limit);
    }
    // No server catalog to read "recently added" from — the closest local
    // equivalent is whatever was imported most recently.
    return appState.localSongs.reversed.take(limit).toList();
  }

  // --- Smart Playlists ------------------------------------------------------

  /// Re-evaluated every time a Smart Playlist is opened — never a stored
  /// list of IDs. See [SmartPlaylistPreset].
  static List<Song> smartPlaylistSongs(SmartPlaylistPreset preset, AppState appState) {
    final songs = _allSongs(appState);
    switch (preset) {
      case SmartPlaylistPreset.rediscover:
        return rediscover(appState, limit: 25);
      case SmartPlaylistPreset.deepCuts:
        return deepCuts(appState, limit: 25);
      case SmartPlaylistPreset.lateNight:
        final list = songs.where((s) => _energyOf(s) < 0.45).toList()..shuffle(Random(1));
        return list.take(25).toList();
      case SmartPlaylistPreset.favoritesMix:
        final list = songs.where((s) => appState.isFavoriteSong(s.id)).toList()..shuffle(Random(2));
        return list;
      case SmartPlaylistPreset.recentlyAdded:
        return freshFromYourLibrary(appState, limit: 25);
      case SmartPlaylistPreset.forgottenFavorites:
        final list = songs
            .where((s) => appState.isFavoriteSong(s.id) && !_recentlyPlayed(s, appState, withinLast: 20))
            .toList();
        return list;
      case SmartPlaylistPreset.highEnergy:
        final list = songs.where((s) => _energyOf(s) >= 0.6).toList()..sort((a, b) => _energyOf(b).compareTo(_energyOf(a)));
        return list.take(25).toList();
      case SmartPlaylistPreset.chill:
        final list = songs.where((s) => _energyOf(s) < 0.5).toList()..shuffle(Random(3));
        return list.take(25).toList();
      case SmartPlaylistPreset.focus:
        final list = songs.where((s) => _energyOf(s) < 0.55).toList()..sort((a, b) => _energyOf(a).compareTo(_energyOf(b)));
        return list.take(20).toList();
      case SmartPlaylistPreset.longDrive:
        return tonightsFlow(appState, length: 40);
    }
  }

  // --- Build from this ------------------------------------------------------

  /// Expands [seed] into a queue-length list according to [mode] — the
  /// per-track "Build from this" sheet.
  static List<Song> buildFrom(Song seed, BuildFromMode mode, AppState appState, {int targetLength = 15}) {
    final allSongs = _allSongs(appState);
    final sameArtist = allSongs.where((s) => s.artistId == seed.artistId && s.id != seed.id).toList();
    final genres = appState.catalogGenres.entries.where((e) => e.value.contains(seed.artistId));
    final sameGenreArtistIds = <String>{for (final g in genres) ...g.value};
    final sameGenre = allSongs.where((s) => sameGenreArtistIds.contains(s.artistId) && s.id != seed.id).toList();
    final everythingElse = allSongs.where((s) => s.id != seed.id).toList();

    List<Song> pool;
    switch (mode) {
      case BuildFromMode.similar:
        pool = [...sameArtist, ...sameGenre];
      case BuildFromMode.sameEra:
        final album = appState.albumById(seed.albumId);
        pool = album == null
            ? sameGenre
            : allSongs.where((s) {
                final a = appState.albumById(s.albumId);
                return a != null && (a.year - album.year).abs() <= 3 && s.id != seed.id;
              }).toList();
      case BuildFromMode.deeperCuts:
        final topPlayed = appState.listeningHistory.take(10).toSet();
        pool = [...sameArtist, ...sameGenre].where((s) => !topPlayed.contains(s.id)).toList();
      case BuildFromMode.surpriseMe:
        pool = everythingElse;
      case BuildFromMode.smoothContinuation:
        pool = [...sameArtist, ...sameGenre, ...everythingElse];
    }

    pool = pool.toSet().toList(); // de-dupe while preserving a stable-ish order
    pool.shuffle(Random(seed.id.hashCode ^ mode.index));

    final result = <Song>[seed];
    Duration total = seed.duration;
    final targetDuration = Duration(minutes: targetLength * 3); // ~3 min/track budget
    for (final s in pool) {
      if (result.length >= targetLength || total >= targetDuration) break;
      result.add(s);
      total += s.duration;
    }
    return result;
  }

  // --- Build with Shuro (natural-language-adjacent) -------------------------

  static final RegExp _wantsCalm = RegExp(r'\b(calm|chill|relax|mellow|slow|sleep|wind.?down|quiet)\b', caseSensitive: false);
  static final RegExp _wantsEnergy = RegExp(r'\b(energy|energetic|upbeat|hype|workout|gym|pump|fast|party)\b', caseSensitive: false);
  static final RegExp _wantsForgotten = RegExp(r'\b(forgot|old|nostalg|throwback|rediscover|used to)\b', caseSensitive: false);
  static final RegExp _wantsNew = RegExp(r'\b(new|fresh|recent|just added|discover)\b', caseSensitive: false);
  static final RegExp _wantsFavorites = RegExp(r'\b(favorite|favourites?|love|best)\b', caseSensitive: false);

  /// Turns a short free-text prompt ("something calm for studying", "high
  /// energy for a workout") into a song list — regex-based intent detection
  /// standing in for the real NL pipeline described in the product doc.
  static List<Song> songsForPrompt(String prompt, AppState appState, {int limit = 20}) {
    final wantsCalm = _wantsCalm.hasMatch(prompt);
    final wantsEnergy = _wantsEnergy.hasMatch(prompt);
    final wantsForgotten = _wantsForgotten.hasMatch(prompt);
    final wantsNew = _wantsNew.hasMatch(prompt);
    final wantsFavorites = _wantsFavorites.hasMatch(prompt);

    // Artist name mentions, matched loosely against the prompt text — only
    // meaningful against the server's named artists.
    final mentionedArtistIds = appState.hasServer
        ? appState.catalogArtists.where((a) => prompt.toLowerCase().contains(a.name.toLowerCase())).map((a) => a.id).toSet()
        : const <String>{};

    List<Song> songs = _allSongs(appState);

    if (mentionedArtistIds.isNotEmpty) {
      songs = songs.where((s) => mentionedArtistIds.contains(s.artistId)).toList();
    } else if (wantsForgotten) {
      songs = rediscover(appState, limit: limit);
    } else if (wantsNew) {
      songs = freshFromYourLibrary(appState, limit: limit);
    } else if (wantsFavorites) {
      songs = songs.where((s) => appState.isFavoriteSong(s.id)).toList();
    }

    if (wantsCalm) {
      songs = songs.where((s) => _energyOf(s) < 0.5).toList();
    } else if (wantsEnergy) {
      songs = songs.where((s) => _energyOf(s) >= 0.5).toList();
    }

    if (songs.isEmpty) songs = forYou(appState, limit: limit);

    songs = songs.toSet().toList();
    songs.sort((a, b) => _affinityOf(b, appState).compareTo(_affinityOf(a, appState)));
    return songs.take(limit).toList();
  }
}

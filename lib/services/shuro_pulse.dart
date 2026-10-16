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

  /// Session salt — generated once per app launch. Every Pulse list gets a
  /// fresh ordering per session (the core fix for "always the same songs in
  /// the same order") while staying stable *within* a session, so saving or
  /// sharing a mix doesn't rot under you mid-listen.
  static final int _sessionSalt = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  /// Day bucket — even a long-lived session drifts across midnight.
  static int _dayBucket() => DateTime.now().difference(DateTime(2024)).inDays;

  static Random _randomFor(int extra) =>
      Random(_sessionSalt ^ (_dayBucket() * 7919) ^ extra);

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
  static List<Song> forYou(AppState appState, {int limit = 12, Random? random}) {
    final rng = random ?? _randomFor(11);
    final songs = _allSongs(appState);
    final hour = DateTime.now().hour;
    final history = appState.listeningHistory;
    final historyPos = <String, int>{};
    for (var i = 0; i < history.length; i++) {
      historyPos.putIfAbsent(history[i], () => i);
    }
    // Genre-affinity graph: each genre scores as the average taste signal of
    // the songs living in it, so a genre full of favorited artists pulls its
    // lesser-known residents up too.
    final genreScoreOf = <String, double>{};
    appState.catalogGenres.forEach((genre, songIds) {
      double sum = 0;
      for (final id in songIds) {
        final s = appState.songById(id);
        if (s != null) sum += _affinityOf(s, appState);
      }
      final avg = sum / (songIds.isEmpty ? 1 : songIds.length);
      for (final id in songIds) {
        genreScoreOf[id] = (genreScoreOf[id] ?? 0) + avg;
      }
    });
    final scored = songs.map((s) {
      double score = _affinityOf(s, appState);
      score += (genreScoreOf[s.id] ?? 0) * 0.3; // taste for the genres this song lives in
      final pos = historyPos[s.id];
      if (pos != null) {
        // Recency decay: the last few plays are demoted hard, older plays
        // progressively less — you can hear it again, just not right now.
        if (pos < 20) score -= 2.6 - pos * 0.12;
      } else {
        score += 0.8; // discovery nudge for never-played tracks
      }
      // Time-of-day context: late night leans mellow, evening leans energy.
      final energy = _energyOf(s);
      if (hour >= 23 || hour < 6) {
        score += (1 - energy) * 0.6;
      } else if (hour >= 18) {
        score += energy * 0.35;
      }
      // Jitter — small per-session noise so equal-taste candidates rotate
      // instead of freezing into one eternal list.
      score += rng.nextDouble() * 1.2;
      return (song: s, score: score);
    }).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    // Artist-diversity pass: max 2 per artist until every artist had a turn.
    return _diversify(scored.map((e) => e.song).toList(), limit, perArtistCap: 2);
  }

  /// Greedy pick with a per-artist cap; over-cap tracks are deferred and
  /// only used to top up when the cap starved the list (single-artist
  /// libraries must still fill).
  static List<Song> _diversify(List<Song> ranked, int limit, {required int perArtistCap}) {
    final counts = <String, int>{};
    final picked = <Song>[];
    final deferred = <Song>[];
    for (final s in ranked) {
      if (picked.length >= limit) break;
      final c = counts[s.artistId] ?? 0;
      if (c >= perArtistCap) {
        deferred.add(s);
      } else {
        counts[s.artistId] = c + 1;
        picked.add(s);
      }
    }
    for (final s in deferred) {
      if (picked.length >= limit) break;
      picked.add(s);
    }
    return picked;
  }

  // --- Discover: Tonight's Flow -------------------------------------------

  /// A whole listening *session* rather than a ranked list — interleaves
  /// favorites, tracks from favorite artists, and everything else so the
  /// sequence doesn't front-load all the familiar songs and dump the
  /// unfamiliar ones at the end (a crude stand-in for real transition/
  /// sequence optimization).
  static List<Song> tonightsFlow(AppState appState, {int length = 20, Random? random}) {
    final rng = random ?? _randomFor(22);
    final songs = [..._allSongs(appState)]..shuffle(rng);
    final favorites = songs.where((s) => appState.isFavoriteSong(s.id)).toList();
    final favoriteArtistTracks = songs
        .where((s) => appState.isFavoriteArtist(s.artistId) && !appState.isFavoriteSong(s.id))
        .toList();
    final everythingElse = songs
        .where((s) => !appState.isFavoriteSong(s.id) && !appState.isFavoriteArtist(s.artistId))
        .toList();

    // Interleave shuffled pools in a familiar↔fresh pattern. Both the pool
    // contents AND the walking order change every session, so the flow is a
    // real mix — never the same sequence twice.
    final pools = [favorites, favoriteArtistTracks, everythingElse, favorites, everythingElse];
    final used = <String>{};
    final result = <Song>[];
    String? lastArtistId;

    Song? pickFrom(List<Song> pool) {
      Song? fallback;
      for (final s in pool) {
        if (used.contains(s.id)) continue;
        // Prefer not to place the same artist twice in a row.
        if (s.artistId == lastArtistId) {
          fallback ??= s;
          continue;
        }
        return s;
      }
      return fallback;
    }

    var round = 0;
    while (result.length < length && round < pools.length * 3) {
      final pick = pickFrom(pools[round % pools.length]);
      if (pick != null) {
        used.add(pick.id);
        result.add(pick);
        lastArtistId = pick.artistId;
      }
      round++;
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
    // Genre-affinity graph: score every genre by the taste signals of the
    // songs and artists living in it, then walk that graph — for each artist
    // you like, recommend songs from its strongest genres by artists you
    // DON'T already listen to heavily. Discovery, not an echo chamber.
    final genreAffinity = <String, double>{};
    final artistsByGenre = <String, Set<String>>{};
    appState.catalogGenres.forEach((genre, songIds) {
      double g = 0;
      final artists = <String>{};
      for (final id in songIds) {
        final s = appState.songById(id);
        if (s == null) continue;
        artists.add(s.artistId);
        g += _affinityOf(s, appState);
        if (appState.listeningHistory.contains(s.id)) g += 0.25;
      }
      genreAffinity[genre] = g;
      artistsByGenre[genre] = artists;
    });

    final likedArtistIds = <String>{
      ...appState.favoriteArtistIds,
      ...appState.artistAffinity.entries.where((e) => e.value > 0).map((e) => e.key),
    };
    final listenedArtists = <String, int>{};
    for (final id in appState.listeningHistory) {
      final song = appState.songById(id);
      if (song == null) continue;
      listenedArtists[song.artistId] = (listenedArtists[song.artistId] ?? 0) + 1;
    }
    if (likedArtistIds.isEmpty) {
      // Fall back to whoever shows up most in listening history.
      final sorted = listenedArtists.keys.toList()
        ..sort((a, b) => (listenedArtists[b] ?? 0).compareTo(listenedArtists[a] ?? 0));
      likedArtistIds.addAll(sorted.take(artistLimit));
    }

    final rows = <({String artistId, String artistName, List<Song> songs})>[];
    final rng = _randomFor(55);
    for (final artistId in likedArtistIds.take(artistLimit)) {
      final artist = appState.artistById(artistId);
      if (artist == null) continue;
      // The genres this artist lives in, strongest-affinity first.
      final seedGenres = appState.catalogGenres.entries
          .where((e) => (artistsByGenre[e.key] ?? const {}).contains(artistId))
          .toList()
        ..sort((a, b) => (genreAffinity[b.key] ?? 0).compareTo(genreAffinity[a.key] ?? 0));
      if (seedGenres.isEmpty) continue;
      // Candidate songs from those genres by OTHER artists — under-listened
      // artists first, session jitter breaking ties differently each time.
      final candidates = <Song>[];
      final seen = <String>{};
      for (final g in seedGenres) {
        for (final id in g.value) {
          final s = appState.songById(id);
          if (s == null || s.artistId == artistId || !seen.add(s.id)) continue;
          if ((listenedArtists[s.artistId] ?? 0) > 5 && rng.nextDouble() < 0.5) {
            continue; // don't echo artists you already hear constantly
          }
          candidates.add(s);
        }
        if (candidates.length >= 24) break;
      }
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final pa = (listenedArtists[a.artistId] ?? 0) + rng.nextDouble() * 2;
        final pb = (listenedArtists[b.artistId] ?? 0) + rng.nextDouble() * 2;
        return pa.compareTo(pb);
      });
      rows.add((artistId: artistId, artistName: artist.name, songs: candidates.take(8).toList()));
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
    candidates.shuffle(_randomFor(33));
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
    songs.shuffle(_randomFor(44));
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
        final list = songs.where((s) => _energyOf(s) < 0.45).toList()..shuffle(_randomFor(101));
        return list.take(25).toList();
      case SmartPlaylistPreset.favoritesMix:
        final list = songs.where((s) => appState.isFavoriteSong(s.id)).toList()..shuffle(_randomFor(102));
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
        final list = songs.where((s) => _energyOf(s) < 0.5).toList()..shuffle(_randomFor(103));
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
    pool.shuffle(_randomFor(seed.id.hashCode ^ mode.index));

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

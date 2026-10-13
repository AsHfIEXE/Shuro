import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/audio_info.dart';
import '../models/playlist.dart';
import '../models/song.dart';

/// A small in-memory "library" standing in for a real Subsonic/Navidrome
/// API response, so every screen has believable, cross-linked data to work
/// with. Swap the functions below for real API calls when you wire up a
/// Navidrome client.
class MockLibrary {
  MockLibrary._();

  static const _siaGradient = [Color(0xFFFEB722), Color(0xFFFF7A00)];
  static const _gorillazGradient = [Color(0xFFFF32C7), Color(0xFF5642DD)];
  static const _jojiGradient = [Color(0xFFFF0200), Color(0xFF580100)];
  static const _tameImpalaGradient = [Color(0xFF00C9A7), Color(0xFF0575E6)];

  static final List<Song> songs = [
    Song(
      id: 'song_unstoppable',
      title: 'Unstoppable',
      artist: 'Sia',
      artistId: 'artist_sia',
      albumId: 'album_sia',
      duration: const Duration(minutes: 3, seconds: 37),
      gradientColors: _siaGradient,
      audioInfo: const AudioInfo(format: 'FLAC', bitDepth: 24, sampleRateHz: 96000, bitrateKbps: 2847),
    ),
    Song(
      id: 'song_cheap_thrills',
      title: 'Cheap Thrills',
      artist: 'Sia',
      artistId: 'artist_sia',
      albumId: 'album_sia',
      duration: const Duration(minutes: 3, seconds: 32),
      gradientColors: _siaGradient,
    ),
    Song(
      id: 'song_alive',
      title: 'Alive',
      artist: 'Sia',
      artistId: 'artist_sia',
      albumId: 'album_sia',
      duration: const Duration(minutes: 4, seconds: 23),
      gradientColors: _siaGradient,
    ),
    Song(
      id: 'song_clint_eastwood',
      title: 'Clint Eastwood',
      artist: 'Gorillaz',
      artistId: 'artist_gorillaz',
      albumId: 'album_gorillaz',
      duration: const Duration(minutes: 5, seconds: 54),
      gradientColors: _gorillazGradient,
    ),
    Song(
      id: 'song_feel_good',
      title: 'Feel Good Inc.',
      artist: 'Gorillaz',
      artistId: 'artist_gorillaz',
      albumId: 'album_gorillaz',
      duration: const Duration(minutes: 3, seconds: 41),
      gradientColors: _gorillazGradient,
    ),
    Song(
      id: 'song_dare',
      title: 'DARE',
      artist: 'Gorillaz',
      artistId: 'artist_gorillaz',
      albumId: 'album_gorillaz',
      duration: const Duration(minutes: 4, seconds: 3),
      gradientColors: _gorillazGradient,
    ),
    Song(
      id: 'song_normal_people',
      title: 'Normal People',
      artist: 'Joji feat. rei brown',
      artistId: 'artist_joji',
      albumId: 'album_joji',
      duration: const Duration(minutes: 2, seconds: 46),
      gradientColors: _jojiGradient,
      audioInfo: const AudioInfo(format: 'AAC', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 256),
    ),
    Song(
      id: 'song_sanctuary',
      title: 'Sanctuary',
      artist: 'Joji',
      artistId: 'artist_joji',
      albumId: 'album_joji',
      duration: const Duration(minutes: 3, seconds: 37),
      gradientColors: _jojiGradient,
      audioInfo: const AudioInfo(format: 'AAC', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 256),
    ),
    Song(
      id: 'song_gimme_love',
      title: 'Gimme Love',
      artist: 'Joji',
      artistId: 'artist_joji',
      albumId: 'album_joji',
      duration: const Duration(minutes: 3, seconds: 29),
      gradientColors: _jojiGradient,
      audioInfo: const AudioInfo(format: 'AAC', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 256),
    ),
    Song(
      id: 'song_less_i_know',
      title: 'The Less I Know The Better',
      artist: 'Tame Impala',
      artistId: 'artist_tame_impala',
      albumId: 'album_currents',
      duration: const Duration(minutes: 3, seconds: 36),
      gradientColors: _tameImpalaGradient,
      audioInfo: const AudioInfo(format: 'MP3', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 320),
    ),
    Song(
      id: 'song_eventually',
      title: 'Eventually',
      artist: 'Tame Impala',
      artistId: 'artist_tame_impala',
      albumId: 'album_currents',
      duration: const Duration(minutes: 5, seconds: 19),
      gradientColors: _tameImpalaGradient,
      audioInfo: const AudioInfo(format: 'MP3', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 320),
    ),
    Song(
      id: 'song_new_person',
      title: 'New Person, Same Old Mistakes',
      artist: 'Tame Impala',
      artistId: 'artist_tame_impala',
      albumId: 'album_currents',
      duration: const Duration(minutes: 5, seconds: 44),
      gradientColors: _tameImpalaGradient,
      audioInfo: const AudioInfo(format: 'MP3', bitDepth: 16, sampleRateHz: 44100, bitrateKbps: 320),
    ),
  ];

  static final List<Album> albums = [
    Album(
      id: 'album_sia',
      title: 'This Is Acting',
      artist: 'Sia',
      artistId: 'artist_sia',
      year: 2016,
      gradientColors: _siaGradient,
      songIds: const ['song_unstoppable', 'song_cheap_thrills', 'song_alive'],
    ),
    Album(
      id: 'album_gorillaz',
      title: 'Demon Days',
      artist: 'Gorillaz',
      artistId: 'artist_gorillaz',
      year: 2005,
      gradientColors: _gorillazGradient,
      songIds: const ['song_clint_eastwood', 'song_feel_good', 'song_dare'],
    ),
    Album(
      id: 'album_joji',
      title: 'Nectar',
      artist: 'Joji',
      artistId: 'artist_joji',
      year: 2020,
      gradientColors: _jojiGradient,
      songIds: const ['song_normal_people', 'song_sanctuary', 'song_gimme_love'],
    ),
    Album(
      id: 'album_currents',
      title: 'Currents',
      artist: 'Tame Impala',
      artistId: 'artist_tame_impala',
      year: 2015,
      gradientColors: _tameImpalaGradient,
      songIds: const ['song_less_i_know', 'song_eventually', 'song_new_person'],
    ),
  ];

  static final List<Artist> artists = [
    Artist(
      id: 'artist_sia',
      name: 'Sia',
      gradientColors: _siaGradient,
      albumIds: const ['album_sia'],
      topSongIds: const ['song_unstoppable', 'song_cheap_thrills', 'song_alive'],
    ),
    Artist(
      id: 'artist_gorillaz',
      name: 'Gorillaz',
      gradientColors: _gorillazGradient,
      albumIds: const ['album_gorillaz'],
      topSongIds: const ['song_clint_eastwood', 'song_feel_good', 'song_dare'],
    ),
    Artist(
      id: 'artist_joji',
      name: 'Joji',
      gradientColors: _jojiGradient,
      albumIds: const ['album_joji'],
      topSongIds: const ['song_normal_people', 'song_sanctuary', 'song_gimme_love'],
    ),
    Artist(
      id: 'artist_tame_impala',
      name: 'Tame Impala',
      gradientColors: _tameImpalaGradient,
      albumIds: const ['album_currents'],
      topSongIds: const ['song_less_i_know', 'song_eventually', 'song_new_person'],
    ),
  ];

  static List<Playlist> seedPlaylists() => [
        const Playlist(
          id: 'playlist_chill',
          name: 'Chill Vibes',
          songIds: ['song_normal_people', 'song_sanctuary', 'song_less_i_know'],
          gradientColors: _jojiGradient,
        ),
        const Playlist(
          id: 'playlist_workout',
          name: 'Workout Mix',
          songIds: ['song_feel_good', 'song_dare', 'song_unstoppable'],
          gradientColors: _gorillazGradient,
        ),
        const Playlist(
          id: 'playlist_late_night',
          name: 'Late Night Drive',
          songIds: ['song_eventually', 'song_new_person', 'song_gimme_love'],
          gradientColors: _tameImpalaGradient,
        ),
      ];

  static const List<String> recentlyPlayedSongIds = [
    'song_unstoppable',
    'song_clint_eastwood',
    'song_normal_people',
    'song_less_i_know',
    'song_cheap_thrills',
  ];

  static const List<String> recentlyAddedSongIds = [
    'song_new_person',
    'song_gimme_love',
    'song_dare',
    'song_alive',
  ];

  static const List<String> recentlyPlayedAlbumIds = ['album_sia', 'album_gorillaz'];

  static const List<String> recentlyAddedAlbumIds = ['album_currents', 'album_joji'];

  static const List<String> recommendedSongIds = [
    'song_alive',
    'song_dare',
    'song_sanctuary',
    'song_new_person',
  ];

  static const List<String> recentSearchSeed = ['Joji', 'Gorillaz', 'Sia'];

  static const Map<String, List<String>> genreArtistIds = {
    'Pop': ['artist_sia'],
    'Alternative': ['artist_gorillaz', 'artist_tame_impala'],
    'R&B': ['artist_joji'],
    'Electronic': ['artist_gorillaz'],
  };

  static List<Song> songsForGenre(String genre) {
    final artistIds = genreArtistIds[genre] ?? const [];
    return songs.where((s) => artistIds.contains(s.artistId)).toList();
  }

  static const Set<String> favoriteSongSeed = {'song_unstoppable', 'song_feel_good'};
  static const Set<String> favoriteAlbumSeed = {'album_gorillaz'};
  static const Set<String> favoriteArtistSeed = {'artist_joji'};

  static Song? songById(String id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Album? albumById(String id) {
    for (final a in albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  static Artist? artistById(String id) {
    for (final a in artists) {
      if (a.id == id) return a;
    }
    return null;
  }

  static List<Song> songsByIds(List<String> ids) =>
      ids.map(songById).whereType<Song>().toList();

  static List<Song> songsForAlbum(String albumId) => songsByIds(albumById(albumId)?.songIds ?? const []);

  static List<Album> albumsForArtist(String artistId) =>
      albums.where((a) => a.artistId == artistId).toList();

  static List<Song> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return songs.where((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q)).toList();
  }

  static List<Album> searchAlbums(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return albums.where((a) => a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q)).toList();
  }

  static List<Artist> searchArtists(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return artists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}

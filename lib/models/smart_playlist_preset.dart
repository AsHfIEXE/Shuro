import 'package:flutter/material.dart';

/// Live-query playlist presets — "Smart Playlists" are never a fixed list of
/// song IDs; ShuroPulse.smartPlaylistSongs(preset, ...) re-evaluates them
/// against the current library/listening state every time they're opened.
enum SmartPlaylistPreset {
  rediscover,
  deepCuts,
  lateNight,
  favoritesMix,
  recentlyAdded,
  forgottenFavorites,
  highEnergy,
  chill,
  focus,
  longDrive,
}

extension SmartPlaylistPresetInfo on SmartPlaylistPreset {
  String get label => switch (this) {
        SmartPlaylistPreset.rediscover => 'Rediscover',
        SmartPlaylistPreset.deepCuts => 'Deep Cuts',
        SmartPlaylistPreset.lateNight => 'Late Night',
        SmartPlaylistPreset.favoritesMix => 'Favorites Mix',
        SmartPlaylistPreset.recentlyAdded => 'Recently Added',
        SmartPlaylistPreset.forgottenFavorites => 'Forgotten Favorites',
        SmartPlaylistPreset.highEnergy => 'High Energy',
        SmartPlaylistPreset.chill => 'Chill',
        SmartPlaylistPreset.focus => 'Focus',
        SmartPlaylistPreset.longDrive => 'Long Drive',
      };

  String get description => switch (this) {
        SmartPlaylistPreset.rediscover => "Songs you loved and haven't heard in a while",
        SmartPlaylistPreset.deepCuts => "Tracks in your library you rarely play",
        SmartPlaylistPreset.lateNight => 'A slower, mellower mix for winding down',
        SmartPlaylistPreset.favoritesMix => 'Your favorites, reshuffled',
        SmartPlaylistPreset.recentlyAdded => 'What just landed in your library',
        SmartPlaylistPreset.forgottenFavorites => "Favorites you haven't played lately",
        SmartPlaylistPreset.highEnergy => 'Upbeat tracks to keep the pace up',
        SmartPlaylistPreset.chill => 'Easygoing tracks for background listening',
        SmartPlaylistPreset.focus => 'Low-distraction tracks for getting things done',
        SmartPlaylistPreset.longDrive => 'A longer mix built to carry a whole trip',
      };

  IconData get icon => switch (this) {
        SmartPlaylistPreset.rediscover => Icons.refresh_rounded,
        SmartPlaylistPreset.deepCuts => Icons.diamond_outlined,
        SmartPlaylistPreset.lateNight => Icons.nightlight_round,
        SmartPlaylistPreset.favoritesMix => Icons.favorite_rounded,
        SmartPlaylistPreset.recentlyAdded => Icons.new_releases_rounded,
        SmartPlaylistPreset.forgottenFavorites => Icons.history_rounded,
        SmartPlaylistPreset.highEnergy => Icons.bolt_rounded,
        SmartPlaylistPreset.chill => Icons.spa_rounded,
        SmartPlaylistPreset.focus => Icons.center_focus_strong_rounded,
        SmartPlaylistPreset.longDrive => Icons.directions_car_filled_rounded,
      };
}

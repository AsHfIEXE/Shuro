import 'package:flutter/material.dart';
import 'smart_playlist_preset.dart';

class Playlist {
  final String id;
  final String name;
  final List<String> songIds;
  final List<Color> gradientColors;

  /// A user-picked cover image. When null, the UI falls back to an
  /// auto-generated collage of the playlist's own songs (see
  /// PlaylistCollageArt), and only to a plain gradient icon if it has none.
  final ImageProvider? artwork;

  /// Set only for a Smart Playlist. [songIds] is ignored for these — the
  /// track list is recomputed live by ShuroPulse.smartPlaylistSongs every
  /// time it's opened, rather than stored as a fixed list.
  final SmartPlaylistPreset? smartPreset;

  bool get isSmart => smartPreset != null;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    this.gradientColors = const [Color(0xFF7C4DFF), Color(0xFF00C9A7)],
    this.artwork,
    this.smartPreset,
  });

  Playlist copyWith({String? name, List<String>? songIds, ImageProvider? artwork, bool clearArtwork = false}) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        songIds: songIds ?? this.songIds,
        gradientColors: gradientColors,
        artwork: clearArtwork ? null : (artwork ?? this.artwork),
        smartPreset: smartPreset,
      );
}

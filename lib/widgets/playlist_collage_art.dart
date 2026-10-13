import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../state/app_state.dart';
import 'artwork_thumb.dart';

/// Cover art for a playlist: a user-picked image if set, otherwise an
/// auto-generated 2x2 collage of its own songs' artwork/gradients, falling
/// back to a plain icon only when the playlist has no songs at all.
class PlaylistCollageArt extends StatelessWidget {
  final Playlist playlist;
  final double radius;

  const PlaylistCollageArt({super.key, required this.playlist, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    if (playlist.artwork != null) {
      return ArtworkThumb(gradientColors: playlist.gradientColors, artwork: playlist.artwork, radius: radius);
    }

    final songs = context.read<AppState>().songsByIds(playlist.songIds).take(4).toList();
    if (songs.isEmpty) {
      return ArtworkThumb(gradientColors: playlist.gradientColors, radius: radius, icon: Icons.queue_music_rounded);
    }
    if (songs.length == 1) {
      return ArtworkThumb(gradientColors: songs.first.gradientColors, artwork: songs.first.artwork, radius: radius);
    }

    // Pad to 4 tiles by repeating songs so a 2- or 3-song playlist still
    // fills a clean 2x2 grid instead of leaving blank cells.
    final tiles = List.generate(4, (i) => songs[i % songs.length]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        children: [
          for (final song in tiles)
            ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, radius: 0, iconSize: 14),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/artist.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';

/// The long-press / "⋮" quick-action sheet for an artist — mirrors
/// [showAlbumActionsSheet]'s shape so every card type in the app opens a
/// consistent set of actions instead of some cards being long-press-silent.
void showArtistActionsSheet(BuildContext context, Artist artist) {
  final player = context.read<PlayerController>();
  final appState = context.read<AppState>();
  final songs = appState.catalogSongs.where((s) => s.artistId == artist.id).toList();

  showModalBottomSheet(
    context: context,
    // Tall content on a short screen (or at a large text scale) used to overflow
    // the sheet's fixed area; it can now scroll instead.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: ArtworkThumb(gradientColors: artist.gradientColors, artwork: artist.artwork, size: 48, radius: 999, icon: Icons.person_rounded),
            title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1, color: kDividerColor),
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
            title: Text('Play', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              if (songs.isNotEmpty) player.playSong(songs.first, queue: songs);
            },
          ),
          ListTile(
            leading: const Icon(Icons.shuffle_rounded, color: Colors.white70),
            title: Text('Shuffle', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              if (songs.isEmpty) return;
              player.playSong(songs.first, queue: songs);
              if (!player.shuffle) player.toggleShuffle();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_to_queue_rounded, color: Colors.white70),
            title: Text('Add to queue', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              for (final song in songs) {
                player.addToQueue(song);
              }
            },
          ),
          AnimatedBuilder(
            animation: appState,
            builder: (context, _) {
              final isFav = appState.isFavoriteArtist(artist.id);
              return ListTile(
                leading: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? artist.gradientColors.last : Colors.white70),
                title: Text(isFav ? 'Remove from favorites' : 'Add to favorites',
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
                onTap: () => appState.toggleFavoriteArtist(artist.id),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        ),
      ),
    ),
  );
}

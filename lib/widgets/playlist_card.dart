import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../services/shuro_pulse.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'playlist_actions_sheet.dart';
import 'playlist_collage_art.dart';

/// Used in Library > Playlists and the "Add to playlist" picker sheet.
class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const PlaylistCard({super.key, required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // A smart playlist only stores a 4-song preview (for its collage) — its real
    // length is generated live by ShuroPulse. Reading songIds.length made every
    // smart playlist insist it had "4 songs" no matter how many it played.
    final count = playlist.smartPreset != null
        ? ShuroPulse.smartPlaylistSongs(playlist.smartPreset!, appState).length
        : playlist.songIds.length;
    return ListTile(
      onTap: onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showPlaylistActionsSheet(context, playlist);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: SizedBox(width: 48, height: 48, child: PlaylistCollageArt(playlist: playlist, radius: 8)),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(playlist.smartPreset != null ? '$count songs · updates itself' : '$count songs',
          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
    );
  }
}

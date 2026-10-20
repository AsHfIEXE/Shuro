import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../services/shuro_pulse.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'playlist_collage_art.dart';
import 'sheet_scroll.dart';
import 'state_views.dart';

/// The long-press quick-action sheet for a playlist card — Play/Shuffle plus
/// Rename/Delete, the same two destructive actions already reachable from
/// Playlist Detail's "⋮" menu, just one tap closer from the Library list.
void showPlaylistActionsSheet(BuildContext context, Playlist playlist) {
  final player = context.read<PlayerController>();
  final appState = context.read<AppState>();
  final songs = playlist.isSmart ? ShuroPulse.smartPlaylistSongs(playlist.smartPreset!, appState) : appState.songsByIds(playlist.songIds);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetScroll(child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: SizedBox(width: 48, height: 48, child: PlaylistCollageArt(playlist: playlist, radius: 8)),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('${songs.length} songs', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
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
          if (!playlist.isSmart) ...[
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white70),
              title: Text('Rename', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final newName = await promptForRename(context, title: 'Rename playlist', currentName: playlist.name, hintText: 'Playlist name');
                if (newName != null && context.mounted) {
                  appState.renamePlaylist(playlist.id, newName);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text('Delete', style: GoogleFonts.getFont(currentFontFamily, color: Colors.redAccent, fontSize: 14)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: kCardColor,
                    title: Text('Delete "${playlist.name}"?', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
                    content: Text("This can't be undone.", style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (confirmed == true) appState.deletePlaylist(playlist.id);
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    )),
  );
}

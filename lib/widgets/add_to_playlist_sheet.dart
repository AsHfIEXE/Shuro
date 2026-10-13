import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../screens/playlist/create_playlist_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'playlist_collage_art.dart';

import 'page_transitions.dart';
/// "Add to playlist" picker opened from a song's actions sheet — lists
/// existing playlists plus a "New playlist" entry that opens the full
/// creation flow (name + cover art) with this song pre-added.
void showAddToPlaylistSheet(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _AddToPlaylistSheet(song: song),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  final Song song;
  const _AddToPlaylistSheet({required this.song});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Add "${song.title}" to playlist', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(backgroundColor: kBrandColor, child: Icon(Icons.add_rounded, color: Colors.white)),
              title: Text('New playlist', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(drillDownRoute(CreatePlaylistScreen(initialSongId: song.id)));
              },
            ),
            const Divider(height: 1, color: kDividerColor),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final playlist in appState.playlists)
                    ListTile(
                      leading: SizedBox(width: 44, height: 44, child: PlaylistCollageArt(playlist: playlist, radius: 8)),
                      title: Text(playlist.name, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
                      subtitle: Text('${playlist.songIds.length} songs', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
                      trailing: playlist.songIds.contains(song.id)
                          ? const Icon(Icons.check_circle_rounded, color: kBrandColor, size: 20)
                          : null,
                      onTap: () {
                        context.read<AppState>().addSongToPlaylist(playlist.id, song.id);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

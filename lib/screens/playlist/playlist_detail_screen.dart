import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/playlist_collage_art.dart';
import '../../widgets/sheet_scroll.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';

/// "08. Playlists > Playlist detail" — track list, Play/Shuffle, rename,
/// delete, and swipe-to-remove for "Add/remove songs".
class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  Future<void> _changeArtwork(BuildContext context, String playlistId) async {
    final appState = context.read<AppState>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SheetScroll(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.image_rounded, color: Colors.white70),
                title: Text('Choose photo',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 14)),
                onTap: () => Navigator.of(sheetContext).pop('choose'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.grid_view_rounded, color: Colors.white70),
                title: Text('Use auto collage',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 14)),
                onTap: () => Navigator.of(sheetContext).pop('collage'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == 'collage') {
      appState.updatePlaylistArtwork(playlistId, null, clear: true);
    } else if (choice == 'choose') {
      final bytes = await appState.pickImageBytes();
      if (bytes != null)
        appState.updatePlaylistArtwork(playlistId, MemoryImage(bytes));
    }
  }

  Future<void> _rename(BuildContext context) async {
    final newName = await promptForRename(context,
        title: 'Rename playlist',
        currentName: playlist.name,
        hintText: 'Playlist name');
    if (newName != null && context.mounted) {
      context.read<AppState>().renamePlaylist(playlist.id, newName);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Delete "${playlist.name}"?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text('This can\'t be undone.',
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AppState>().deletePlaylist(playlist.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-read the live playlist from AppState so renames/edits reflect immediately.
    final appState = context.watch<AppState>();
    final live = appState.playlists
        .firstWhere((p) => p.id == playlist.id, orElse: () => playlist);
    final songs = live.isSmart
        ? ShuroPulse.smartPlaylistSongs(live.smartPreset!, appState)
        : appState.songsByIds(live.songIds);
    final player = context.read<PlayerController>();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text(live.name,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            color: kCardColor,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            onSelected: (value) {
              if (value == 'rename') _rename(context);
              if (value == 'delete') _confirmDelete(context);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white, fontSize: 13))),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.redAccent, fontSize: 13))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _changeArtwork(context, live.id),
                  child: Stack(
                    children: [
                      SizedBox(
                          width: 72,
                          height: 72,
                          child:
                              PlaylistCollageArt(playlist: live, radius: 12)),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: kBrandColor, shape: BoxShape.circle),
                          child: const Icon(Icons.edit_rounded,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live.isSmart
                            ? '${songs.length} songs · Smart Playlist'
                            : '${songs.length} songs',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kMutedTextColor, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: live.gradientColors.last,
                                shape: const CircleBorder()),
                            icon: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white),
                            onPressed: songs.isEmpty
                                ? null
                                : () =>
                                    player.playSong(songs.first, queue: songs),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.shuffle_rounded,
                                color: Colors.white70),
                            onPressed: songs.isEmpty
                                ? null
                                : () {
                                    player.playSong(songs.first, queue: songs);
                                    if (!player.shuffle) player.toggleShuffle();
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? const EmptyStateView(
                    icon: Icons.queue_music_rounded,
                    title: 'No songs yet',
                    subtitle: 'Add songs from any track\'s "⋮" menu.')
                : ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final song = songs[i];
                      final tile = SongTile(
                          song: song,
                          onTap: () => player.playSong(song, queue: songs));
                      if (live.isSmart)
                        return tile; // computed live — nothing to swipe-remove
                      return Dismissible(
                        key: ValueKey('${live.id}_${song.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent),
                        ),
                        onDismissed: (_) => context
                            .read<AppState>()
                            .removeSongFromPlaylist(live.id, song.id),
                        child: tile,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';

/// "10. Queue" — current song, reorderable "Up next" list, remove/clear,
/// and saving the queue as a new playlist.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final List<Song> upNext = queue.length > player.queueIndex + 1
        ? queue.sublist(player.queueIndex + 1)
        : const [];

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('Queue',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        actions: [
          if (upNext.isNotEmpty)
            TextButton(
              onPressed: () async {
                final name = await _promptName(context);
                if (name == null || name.trim().isEmpty || !context.mounted)
                  return;
                final playlist =
                    context.read<AppState>().createPlaylist(name.trim());
                for (final song in queue) {
                  context
                      .read<AppState>()
                      .addSongToPlaylist(playlist.id, song.id);
                }
              },
              child: Text('Save as playlist',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kBrandColor, fontSize: 12)),
            ),
        ],
      ),
      body: queue.isEmpty
          ? const EmptyStateView(
              icon: Icons.queue_music_rounded, title: 'Queue is empty')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (player.currentSong != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('Now Playing',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: ArtworkThumb(
                        gradientColors: player.currentSong!.gradientColors,
                        artwork: player.currentSong!.artwork,
                        size: 46,
                        radius: 8),
                    title: Text(player.currentSong!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: player.currentSong!.gradientColors.last,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(player.currentSong!.artist,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kMutedTextColor, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A real control rather than a status glyph: the icon shows
                        // the action (pause while playing, play while paused) and
                        // does it. It used to show a *pause* symbol precisely when
                        // playback was already paused, which read as its opposite.
                        IconButton(
                          tooltip: player.isPlaying ? 'Pause' : 'Play',
                          icon: player.isBuffering
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white70))
                              : Icon(
                                  player.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color:
                                      player.currentSong!.gradientColors.last,
                                  size: 22,
                                ),
                          onPressed: player.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded,
                              color: kMutedTextColor, size: 20),
                          // Guard at tap time: the row was built while a song
                          // existed, but the queue can empty between build
                          // and tap (audit finding F3-1).
                          onPressed: () {
                            final s = player.currentSong;
                            if (s != null) showSongActionsSheet(context, s);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: kDividerColor, height: 24),
                ],
                if (upNext.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text('Up Next',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                Expanded(
                  child: upNext.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text('Nothing queued after this',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMutedTextColor, fontSize: 13)),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: upNext.length,
                          onReorder: (oldIndex, newIndex) {
                            player.reorderQueue(
                                player.queueIndex + 1 + oldIndex,
                                player.queueIndex + 1 + newIndex);
                          },
                          itemBuilder: (context, i) {
                            final song = upNext[i];
                            final queueIndex = player.queueIndex + 1 + i;
                            return ListTile(
                              key: ValueKey('queue_${queueIndex}_${song.id}'),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              leading: ArtworkThumb(
                                  gradientColors: song.gradientColors,
                                  artwork: song.artwork,
                                  size: 44,
                                  radius: 8),
                              title: Text(song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text(song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: kMutedTextColor, fontSize: 12)),
                              // A tap target rather than long-press: this row
                              // already has a long-press-to-drag gesture from
                              // ReorderableListView itself (no explicit drag
                              // handle is wired up below — the handle icon is
                              // decorative), so a second long-press listener
                              // here would fight it in the gesture arena.
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.more_vert_rounded,
                                        color: kMutedTextColor, size: 20),
                                    onPressed: () =>
                                        showSongActionsSheet(context, song),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        color: kMutedTextColor, size: 18),
                                    onPressed: () =>
                                        player.removeFromQueue(queueIndex),
                                  ),
                                  const Icon(Icons.drag_handle_rounded,
                                      color: kMutedTextColor),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (upNext.isNotEmpty)
                  // SafeArea: the button sat under the Android navigation bar
                  // (edge-to-edge app), where it was both covered and unreadable.
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: player.clearQueue,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent.shade100,
                            backgroundColor:
                                Colors.redAccent.withValues(alpha: 0.10),
                            side: BorderSide(
                                color: Colors.redAccent.shade100
                                    .withValues(alpha: 0.55)),
                          ),
                          child: const Text('Clear Queue'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

Future<String?> _promptName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kCardColor,
      title: Text('Save queue as playlist',
          style: GoogleFonts.getFont(currentFontFamily,
              color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white),
        decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: kMutedTextColor)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save')),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_ring.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/smooth_position_builder.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';
import 'now_playing_screen.dart';
import '../../widgets/click_region.dart';

/// "10. Queue" / the Queue panel board — a NOW PLAYING card up top (52 px
/// ring artwork with live progress, title/artist, prev / play / next
/// transport), then the reorderable UP NEXT list with drag handles, hover
/// rows and the violet wash on the current track.
///
/// Every action the old screen had is kept: save-the-queue-as-a-playlist,
/// per-track "⋮" menus, remove-from-queue, clear queue (with its undo),
/// drag/long-press reordering and the empty states.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  /// 0 = Up next, 1 = History.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final queue = player.queue;
    final List<Song> upNext = queue.length > player.queueIndex + 1
        ? queue.sublist(player.queueIndex + 1)
        : const [];
    final List<Song> history = player.queueIndex > 0
        ? queue.sublist(0, player.queueIndex.clamp(0, queue.length))
        : const [];
    final upNextMinutes =
        (upNext.fold<int>(0, (a, s) => a + s.duration.inSeconds) / 60).round();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        toolbarHeight: 52,
        titleSpacing: 16,
        title: Text('Queue',
                style: headingFont(color: kTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7)),
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
                  Entrance(child: _NowPlayingCard(song: player.currentSong!)),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
                  child: Row(
                    children: [
                      for (final entry in const [(0, 'Up next'), (1, 'History')])
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: ClickRegion(
                            onTap: () => setState(() => _tab = entry.$1),
                            child: Container(
                              padding: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        width: 2,
                                        color: _tab == entry.$1
                                            ? kBrandColor
                                            : Colors.transparent)),
                              ),
                              child: Text(entry.$2,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: _tab == entry.$1
                                          ? kTextColor
                                          : kStatusText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (_tab == 0 && upNext.isNotEmpty)
                        TextButton(
                          onPressed: player.clearQueue,
                          child: Text('Clear',
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: Colors.redAccent.shade100,
                                  fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                  child: Text(
                      _tab == 0
                          ? 'NEXT UP \u00b7 ${upNext.length} SONG${upNext.length == 1 ? '' : 'S'} \u00b7 $upNextMinutes MIN'
                          : 'HISTORY \u00b7 ${history.length} SONG${history.length == 1 ? '' : 'S'}',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMuted2,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                ),
                Expanded(
                  child: _tab == 1
                      ? (history.isEmpty
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                child: Text('Nothing played yet in this queue',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kMutedTextColor,
                                        fontSize: 13)),
                              ))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: history.length,
                              itemBuilder: (context, i) {
                                // Most recent first.
                                final song = history[history.length - 1 - i];
                                return _QueueRow(
                                  song: song,
                                  index: i,
                                  queue: queue,
                                  onRemove: () => player.removeFromQueue(
                                      history.length - 1 - i),
                                );
                              },
                            ))
                      : upNext.isEmpty
                      ? Align(
                          // Expanded gives tight width, so a bare Text sat at
                          // x=0 against the screen edge.
                          alignment: Alignment.topCenter,
                          child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                          child: Text('Nothing queued after this',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMutedTextColor, fontSize: 13)),
                        ))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: upNext.length,
                          // Tracked: migrate to onReorderItem (index semantics change).
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                            player.reorderQueue(
                                player.queueIndex + 1 + oldIndex,
                                player.queueIndex + 1 + newIndex);
                          },
                          itemBuilder: (context, i) {
                            final song = upNext[i];
                            final queueIndex = player.queueIndex + 1 + i;
                            return Entrance(
                              key: ValueKey(
                                  'queue_${queueIndex}_${song.id}'),
                              delay: Entrance.stagger(i),
                              enabled: i < 12,
                              child: _QueueRow(
                                song: song,
                                index: i,
                                queue: queue,
                                onRemove: () =>
                                    player.removeFromQueue(queueIndex),
                              ),
                            );
                          },
                        ),
                ),
                if (_tab == 0)
                  _AutoplaySection(
                      player: player,
                      appState: appState,
                      queue: queue),
              ],
            ),
    );
  }
}

/// The board's NOW PLAYING card: 52 px ring artwork with live progress
/// (the ring is the progress — stroke 3, knob 9), title/artist, and the
/// prev / play / next transport. Tapping the ring opens Now Playing.
class _NowPlayingCard extends StatelessWidget {
  final Song song;
  const _NowPlayingCard({required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        child: Row(
          children: [
            ClickRegion(
              onTap: () =>
                  pushRisingOnce(context, NowPlayingScreen(initialSong: song)),
              child: SmoothPositionBuilder(
                builder: (context, player, position, progress) => ArtworkRing(
                  song: song,
                  progress: progress,
                  buffered: player.bufferedFraction,
                  colors: song.gradientColors,
                  size: 52,
                  strokeWidth: NpvMetrics.ringStrokeMini,
                  knobSize: NpvMetrics.knobMini,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOW PLAYING',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMuted2,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4)),
                  const SizedBox(height: 2),
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kTextColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Transport: prev / play-pause disc / next, matching the mini
            // player's button vocabulary.
            IconButton(
              tooltip: 'Previous track',
              icon: ShuroIcon(ShuroGlyph.previous, color: kTextColor, size: 24),
              onPressed: player.previous,
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kBrandColor,
                boxShadow: [
                  BoxShadow(
                    color: kBrandColor.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: IconButton(
                tooltip: player.isPlaying ? 'Pause' : 'Play',
                onPressed: player.togglePlayPause,
                icon: player.isBuffering
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : ShuroIcon(
                        player.isPlaying
                            ? ShuroGlyph.pause
                            : ShuroGlyph.play,
                        color: Colors.white,
                        size: 24),
              ),
            ),
            IconButton(
              tooltip: 'Next track',
              icon: ShuroIcon(ShuroGlyph.next, color: kTextColor, size: 24),
              onPressed: player.next,
            ),
            SizedBox(
              width: 40,
              child: Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_vert_rounded,
                      color: kMuted2, size: 20),
                  // Guard at tap time: the row was built while a song
                  // existed, but the queue can empty between build and tap.
                  onPressed: () {
                    final s = context.read<PlayerController>().currentSong;
                    if (s == null) return;
                    if (isDesktopPlatform) {
                      showSongMenuAtAnchor(context, s, buttonContext);
                    } else {
                      showSongActionsSheet(context, s);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// One UP NEXT row: 48 px tall, hover wash on desktop, violet wash when
/// this row's track is the current one (shuffle can make any row current),
/// duration, "⋮" menu, remove and a drag handle that starts the reorder
/// immediately (the list keeps long-press-to-drag on touch as well).
class _QueueRow extends StatelessWidget {
  final Song song;
  final int index;
  final List<Song> queue;
  final VoidCallback onRemove;

  const _QueueRow({
    required this.song,
    required this.index,
    required this.queue,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final playing = player.currentSong?.id == song.id;

    return ContextMenuRegion(
      items: songContextMenuItems(context, song),
      child: Material(
        color: playing ? kBrandColor.withValues(alpha: 0.14) : Colors.transparent,
        child: InkWell(
          onTap: () => player.playSong(song, queue: queue),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ArtworkThumb(
                    gradientColors: song.gradientColors,
                    artwork: song.artwork,
                    size: 40,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: playing ? kVioletPale : kTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kStatusText, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatDuration(song.duration),
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 13)),
                  SizedBox(
                    width: 40,
                    child: Builder(
                      builder: (buttonContext) => IconButton(
                        tooltip: 'More options',
                        icon: Icon(Icons.more_vert_rounded,
                            color: kMuted2, size: 20),
                        onPressed: () {
                          if (isDesktopPlatform) {
                            showSongMenuAtAnchor(context, song, buttonContext);
                          } else {
                            showSongActionsSheet(context, song);
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      tooltip: 'Remove from queue',
                      icon:
                          Icon(Icons.close_rounded, color: kMuted2, size: 18),
                      onPressed: onRemove,
                    ),
                  ),
                  // The drag handle starts the reorder drag immediately on
                  // press (desktop-friendly); long-press anywhere on the row
                  // still drags on touch.
                  ReorderableDragStartListener(
                    index: index,
                    child: SizedBox(
                      width: 40,
                      child: Icon(Icons.drag_handle_rounded,
                          color: playing ? kVioletLight : kMuted2, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

/// "AUTOPLAY - SIMILAR TO <ARTIST>": a few tracks the autoplay provider would
/// append, plus the toggle bound to the Settings autoplay choice.
class _AutoplaySection extends StatelessWidget {
  final PlayerController player;
  final AppState appState;
  final List<Song> queue;
  const _AutoplaySection(
      {required this.player, required this.appState, required this.queue});

  @override
  Widget build(BuildContext context) {
    final current = player.currentSong;
    final provider = player.suggestionProvider;
    final queued = queue.map((s) => s.id).toSet();
    final suggestions = (current == null || provider == null)
        ? const <Song>[]
        : provider(current)
            .where((s) => !queued.contains(s.id))
            .take(3)
            .toList();
    return SafeArea(
      top: false,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: kHairline))),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (suggestions.isNotEmpty && current != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                  child: Text(
                      'AUTOPLAY \u00b7 SIMILAR TO ${current.artist.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMuted2,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                ),
                for (final song in suggestions)
                  InkWell(
                    onTap: () => player.addToQueue(song),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(children: [
                        ArtworkThumb(
                            gradientColors: song.gradientColors,
                            artwork: song.artwork,
                            size: 36,
                            radius: 6),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: kTextColor,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500)),
                              Text(song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(currentFontFamily,
                                      color: kStatusText, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Add to queue',
                          child: Icon(Icons.add_rounded,
                              color: kMuted2, size: 20),
                        ),
                      ]),
                    ),
                  ),
              ],
              SwitchListTile(
                secondary:
                    const Icon(Icons.auto_awesome_rounded, color: kBrandColor),
                title: Text('Autoplay similar songs',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor, fontSize: 14)),
                subtitle: Text('Keeps playing when the queue ends',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 12)),
                value: appState.autoplay,
                activeThumbColor: kBrandColor,
                onChanged: (v) {
                  appState.updateQueueEnd(v ? 'similar' : 'stop');
                  player.autoplay = v;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'click_region.dart';

/// The queue as a right-side drawer over a full-screen scrim
/// (board "Queue panel": scrim rgba(0,0,0,.5), 440 px panel).
///
/// Tap the scrim to close; the panel slides in from the right.
Future<void> showQueuePanel(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close queue',
    barrierColor: const Color(0x80000000), // black 50% - the board scrim
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) => const QueuePanel(),
    transitionBuilder: (dialogContext, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The 440 px drawer: NOW PLAYING card, the up-next rows and the autoplay
/// footer, all reading live from [PlayerController].
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final song = player.currentSong;
    final queue = player.queue;
    final upNext = queue.length > player.queueIndex + 1
        ? queue.sublist(player.queueIndex + 1)
        : const <Song>[];

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF10151E), // board surface
        child: Container(
          width: 440,
          height: double.infinity,
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white10),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Row(
                    children: [
                      Text('Queue',
                          style: headingFont(color: kTextColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                      const Spacer(),
                      _PanelCircle(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // NOW PLAYING card (violet 12%)
                if (song != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kBrandColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          ArtworkThumb(
                            gradientColors: song.gradientColors,
                            artwork: song.artwork,
                            size: 44,
                            radius: 8,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('NOW PLAYING',
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kVioletPale,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1)),
                                const SizedBox(height: 3),
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kStatusText, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('UP NEXT',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMuted2,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: upNext.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text('Nothing up next',
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMuted2, fontSize: 13)),
                        )
                      : ReorderableListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: upNext.length,
                          buildDefaultDragHandles: false,
                          // ignore: deprecated_member_use
                          onReorder: (oldIndex, newIndex) {
                            // The panel list is the up-next slice; translate
                            // to absolute queue indices. reorderQueue applies
                            // the standard >oldIndex adjustment itself.
                            player.reorderQueue(
                              player.queueIndex + 1 + oldIndex,
                              player.queueIndex + 1 + newIndex,
                            );
                          },
                          itemBuilder: (context, i) {
                            final s = upNext[i];
                            final absIndex = player.queueIndex + 1 + i;
                            return Container(
                              key: ValueKey('panel-row-$absIndex-${s.id}'),
                              child: Row(
                                children: [
                                  // Grip: drag here to reorder. Tapping the
                                  // row itself still plays instantly.
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 2, right: 2),
                                      child: Icon(
                                          Icons.drag_indicator_rounded,
                                          size: 18,
                                          color: Colors.white.withValues(
                                              alpha: 0.25)),
                                    ),
                                  ),
                                  Expanded(
                                    child: _QueueRow(
                                      song: s,
                                      index: absIndex,
                                      onTap: () =>
                                          player.playSong(s, queue: queue),
                                      onRemove: () => player
                                          .removeFromQueue(absIndex),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                // Autoplay footer (60% per the board)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Autoplay when the queue ends',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kTextColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ),
                      Switch(
                        value: appState.autoplay,
                        activeColor: kBrandColor,
                        onChanged: (v) => appState
                            .toggleSetting(() => appState.autoplay = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 32 px glass circle used for the panel's close button.
class _PanelCircle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PanelCircle(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClickRegion(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 18, color: Colors.white70),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueRow(
      {required this.song,
      required this.index,
      required this.onTap,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Dismissible(
        key: ValueKey('queue-panel-${song.id}-$index'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: Colors.redAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent),
        ),
        onDismissed: (_) => onRemove(),
        child: ClickRegion(
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('$index',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMuted2, fontSize: 12)),
                ),
                ArtworkThumb(
                  gradientColors: song.gradientColors,
                  artwork: song.artwork,
                  size: 36,
                  radius: 6,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 11)),
                    ],
                  ),
                ),
                Text(_clock(song.duration),
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

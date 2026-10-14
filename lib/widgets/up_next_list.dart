import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'section_header.dart';

/// Real content for the wide Now-Playing pane when there are no lyrics: the
/// next songs in the queue. Previously this half of the screen fell back to a
/// small centered message on a huge dark pane — which read as an empty/broken
/// area on TV-width screens. Tapping a row jumps to it.
///
/// The list itself stays quiet: no cards, no chrome — rows of art + text that
/// inherit the pane's backdrop, so it feels like part of the composition
/// rather than a second app bolted on.
class UpNextList extends StatelessWidget {
  final int maxRows;
  const UpNextList({super.key, this.maxRows = 7});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    if (queue.isEmpty) return const SizedBox.shrink();
    final next = <Song>[];
    for (var i = player.queueIndex + 1; i < queue.length && next.length < maxRows; i++) {
      next.add(queue[i]);
    }
    if (next.isEmpty) {
      return _EmptyPane(
        icon: Icons.done_all_rounded,
        title: 'End of queue',
        caption: 'Everything queued has played. Add more from the library.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.queue_music_rounded, size: 15, color: Colors.white54),
            const SizedBox(width: 8),
            Text(
              'UP NEXT',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: next.length,
            itemBuilder: (context, index) {
              final song = next[index];
              final isPlayingNext = index == 0;
              return _UpNextRow(
                song: song,
                highlight: isPlayingNext,
                onTap: () => player.playSong(song, queue: queue),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UpNextRow extends StatelessWidget {
  final Song song;
  final bool highlight;
  final VoidCallback onTap;

  const _UpNextRow({required this.song, required this.highlight, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 38, radius: 7),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: highlight ? kTextColor : Colors.white70,
                        fontSize: 13,
                        fontWeight: highlight ? FontWeight.w600 : FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38, fontSize: 11),
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

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _EmptyPane({required this.icon, required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: Colors.white24),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(caption,
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38, fontSize: 11.5, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

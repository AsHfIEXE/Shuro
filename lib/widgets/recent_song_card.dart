import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'song_actions_sheet.dart';

/// A single card in a horizontal song rail (Home's Recently Played /
/// Recently Added / Favorites / Recommended). Full square artwork with a
/// "now playing" badge overlaid in the corner when active — no partial banner
/// or overlapping avatar cutting into the art.
///
/// Two things this card deliberately does that it didn't before, both of them
/// about making it obvious what a tap will do:
///  - The whole card shows a ripple on press. It used to be a bare
///    [GestureDetector], so nothing on screen moved when you touched a card —
///    reading as "not a button" rather than "tappable".
///  - The card for the track that's playing shows a **pause** control instead
///    of silently restarting that track from 0:00 when tapped (see
///    [PlayerController.playOrToggle]).
class RecentSongCard extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final double width;

  const RecentSongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
    this.width = 150,
  });

  @override
  Widget build(BuildContext context) {
    // Read the live player rather than trusting the caller's flag alone, so the
    // overlay can never disagree with what is actually audible.
    final player = context.watch<PlayerController>();
    final isCurrent = player.currentSong?.id == song.id;
    final playing = isCurrent && player.isPlaying;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            showSongActionsSheet(context, song);
          },
          child: Semantics(
            button: true,
            label: '${song.title} by ${song.artist}${playing ? ', playing now' : ''}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ArtworkThumb(
                          gradientColors: song.gradientColors,
                          artwork: song.artwork,
                          radius: 14,
                          iconSize: 30,
                        ),
                      ),
                      if (isCurrent)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _NowPlayingOverlay(
                            playing: playing,
                            buffering: player.isBuffering,
                            onTap: player.togglePlayPause,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: playing ? song.gradientColors.last : Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // white60 rather than the app's 38%-white muted tone: at this
                  // size the darker tone fell below the 4.5:1 contrast bar.
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "this is the one playing" affordance: an animated equalizer while audio
/// is running (tap to pause), a progress ring while it's still loading, and a
/// play glyph when paused.
class _NowPlayingOverlay extends StatelessWidget {
  final bool playing;
  final bool buffering;
  final VoidCallback onTap;

  const _NowPlayingOverlay({required this.playing, required this.buffering, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: playing ? 'Pause' : 'Play',
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: buffering
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : playing
                      ? const _PlayingBadge()
                      : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny animated equalizer badge shown on the currently-playing card.
class _PlayingBadge extends StatefulWidget {
  const _PlayingBadge();

  @override
  State<_PlayingBadge> createState() => _PlayingBadgeState();
}

class _PlayingBadgeState extends State<_PlayingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final t = (_controller.value + i * 0.33) % 1.0;
              final height = 4 + (8 * (0.5 + 0.5 * (t < 0.5 ? t * 2 : (1 - t) * 2)));
              return Container(width: 2.4, height: height, color: Colors.white);
            }),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'shuro_icons.dart';

/// Track title + artist, flanked by shuffle/repeat — the "Música/Artista"
/// row from the design. [accent] is passed in explicitly (the track's
/// *real* artwork-derived color, resolved once by the screen that hosts
/// this — see NowPlayingScreen) rather than read off `song.gradientColors`
/// here, since that per-ID hash color has nothing to do with what the
/// cover art actually looks like.
class TrackInfoRow extends StatelessWidget {
  final Song song;
  final Color accent;
  final bool shuffleOn;
  final PlayerRepeatMode repeatMode;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;

  const TrackInfoRow({
    super.key,
    required this.song,
    required this.accent,
    required this.shuffleOn,
    required this.repeatMode,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PlayerModeButton(
            shuroIcon: ShuroGlyph.shuffle,
            modeLabel: 'Shuffle',
            active: shuffleOn,
            accent: accent,
            onTap: onShuffleToggle,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // The icon itself changes for repeat-one, so "one" and "all" are
          // different pictures — plus the badge makes it unmistakable.
          PlayerModeButton(
            materialIcon: repeatMode == PlayerRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            modeLabel: switch (repeatMode) {
              PlayerRepeatMode.off => 'Repeat off',
              PlayerRepeatMode.all => 'Repeat all',
              PlayerRepeatMode.one => 'Repeat one',
            },
            active: repeatMode != PlayerRepeatMode.off,
            badge: repeatMode == PlayerRepeatMode.one ? '1' : null,
            accent: accent,
            onTap: onRepeatToggle,
          ),
        ],
      ),
    );
  }
}

/// Previous / play-pause / next — the "Play/Pause" group from the design.
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;

  /// True while the current track's audio is still loading or refilling its
  /// buffer — the play button then shows progress instead of a play glyph, so
  /// a slow track doesn't look like an ignored tap.
  final bool isBuffering;
  final Color accentColor;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.accentColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    this.isBuffering = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Previous track',
          child: IconButton(
            icon: const ShuroIcon(ShuroGlyph.previous, size: 30, color: Colors.white),
            onPressed: onPrevious,
            tooltip: 'Previous',
          ),
        ),
        const SizedBox(width: 26),
        GestureDetector(
          onTap: onPlayPause,
          child: Semantics(
            button: true,
            label: isBuffering ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [accentColor, accentColor.withValues(alpha: 0.7)]),
                boxShadow: [
                  BoxShadow(color: accentColor.withValues(alpha: isPlaying ? 0.65 : 0.4), blurRadius: isPlaying ? 32 : 20, spreadRadius: 1),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: isBuffering
                    ? const Padding(
                        key: ValueKey('buffering'),
                        padding: EdgeInsets.all(26),
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                      )
                    : ShuroIcon(
                        isPlaying ? ShuroGlyph.pause : ShuroGlyph.play,
                        key: ValueKey(isPlaying),
                        color: Colors.white,
                        size: 34,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 26),
        Semantics(
          button: true,
          label: 'Next track',
          child: IconButton(
            icon: const ShuroIcon(ShuroGlyph.next, size: 30, color: Colors.white),
            onPressed: onNext,
            tooltip: 'Next',
          ),
        ),
      ],
    );
  }
}

/// A shuffle/repeat toggle whose state is impossible to misread.
///
/// The old versions were the same icon at one of two opacities, which read as
/// "dimmed because inactive" — there was no way to tell whether shuffle was on.
/// This one mutes the icon when off, colours it with the accent and draws a dot
/// under it when on, swaps the icon entirely for repeat-one, and states the mode
/// in words for screen readers and tooltips.
class PlayerModeButton extends StatelessWidget {
  /// Shuro's own glyph set, when the mode has one (shuffle).
  final ShuroGlyph? shuroIcon;

  /// A Material icon, for modes the glyph set doesn't cover (repeat-one).
  final IconData? materialIcon;
  final String modeLabel;
  final bool active;
  final String? badge;
  final Color accent;
  final VoidCallback onTap;

  const PlayerModeButton({
    super.key,
    required this.modeLabel,
    required this.active,
    required this.accent,
    required this.onTap,
    this.shuroIcon,
    this.materialIcon,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colour = active ? accent : Colors.white.withValues(alpha: 0.9);
    final iconWidget = materialIcon != null
        ? Icon(materialIcon, size: 22, color: colour)
        : ShuroIcon(shuroIcon!, size: 22, color: colour);

    // A dim circle behind every mode button: on Now Playing the background is
    // bright blurred artwork, and bare white54 icons disappeared into it (the
    // "shuffle button is gone" report). The circle keeps both states readable
    // over any cover; the active state adds the accent tint + the dot below.
    return Semantics(
      button: true,
      label: '$modeLabel, ${active ? 'on' : 'off'}',
      child: IconButton(
        tooltip: '$modeLabel — ${active ? 'on' : 'off'}',
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: active ? accent.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.28),
        ),
        icon: badge == null
            ? iconWidget
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  iconWidget,
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        badge!,
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800, height: 1),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

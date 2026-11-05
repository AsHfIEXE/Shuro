import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_theme.dart';
import 'progress_ring_painter.dart';

/// The circular artwork + progress ring used everywhere playback art appears:
/// the Now Playing screens (desktop + mobile), the lyrics mini transport and
/// the mini players. Geometry from the redesign (docs/02): artwork is 72% of
/// the ring, the progress arc always uses the fixed brand gradient
/// (#FF8FB8 -> #A78BFA), and the artwork casts a soft pink glow scaled to the
/// ring (blur ~ 0.12 * size). [progress] is passed in explicitly (from
/// PlayerController) rather than read off the song, since playback position
/// belongs to the player, not the track. Wrap this in a Hero (see [heroTag])
/// so the artwork morphs smoothly from the mini player into the full screen.
class ArtworkRing extends StatelessWidget {
  final Song song;
  final double progress;
  final double size;
  final Object? heroTag;

  /// Palette used for the artwork *fallback* gradient and its glow — the
  /// track's real artwork-derived palette when one's been resolved (see
  /// NowPlayingScreen). The progress arc itself is always the fixed brand
  /// gradient [kRingProgress] per the redesign.
  final List<Color> colors;

  /// Whether the progress arc is drawn. Portrait keeps it (it is the screen's
  /// only progress display there). Landscapes turn it OFF when the layout
  /// shows another progress display alongside.
  final bool showProgress;

  /// True while the user is dragging the knob — the painter grows the knob
  /// and strengthens its glow so the seek control answers the touch.
  final bool scrubbing;

  const ArtworkRing({
    super.key,
    required this.song,
    required this.progress,
    required this.colors,
    this.size = 260,
    this.heroTag,
    this.showProgress = true,
    this.scrubbing = false,
    this.strokeWidth = 4,
    this.buffered,
    this.knobSize,
  });

  /// Ring stroke width: 4 on the big Now Playing rings, 3 on the 52 px mini
  /// player ring (see NpvMetrics.ringStroke / ringStrokeMini).
  final double strokeWidth;

  /// Buffered fraction (0..1) of the track, when the host knows it. Fed
  /// through to [ProgressRingPainter]; null (or 0) draws no buffered arc.
  final double? buffered;

  /// Knob diameter (20 desktop / 18 mobile / 9 mini per NpvMetrics). Null
  /// lets [ProgressRingPainter] derive the knob from the stroke width.
  final double? knobSize;

  static const _innerRatio = 0.72;

  @override
  Widget build(BuildContext context) {
    final glow = (colors.length > 1 ? colors.last : colors.first);
    final fallbackColors = [kAccentColor, kBrandColor];
    final fallback = _OrbitFallback(size: size * _innerRatio, colors: fallbackColors);

    final artwork = Container(
      width: size * _innerRatio,
      height: size * _innerRatio,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          // Soft pink-tinted glow scaled to the ring (blur ~ 0.12 * D per
          // docs/02) so the 52 px mini ring doesn't carry a full-size halo.
          BoxShadow(
            color: glow.withValues(alpha: 0.55),
            blurRadius: size * 0.12,
            spreadRadius: size * 0.005,
          ),
        ],
      ),
      child: ClipOval(
        // Cross-fades on a track change, and only then: the switcher is keyed
        // by song id, so a progress tick or a favourite toggle leaves the
        // image alone. It sits *inside* the Hero rather than around it, which
        // keeps the hero tag unique (two children sharing one tag in a route
        // throws).
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(song.id),
            // Falls back to the brand orbit placeholder both when there's no
            // artwork and when a real one fails to load (e.g. the server went
            // unreachable mid-session) — otherwise a failed NetworkImage would
            // show Flutter's default error box right in the middle of Now
            // Playing instead of degrading gracefully.
            child: song.artwork != null
                ? Image(
                    image: song.artwork!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  )
                : fallback,
          ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showProgress)
            CustomPaint(
              size: Size(size, size),
              painter: ProgressRingPainter(
                progress: progress,
                // Fixed brand gradient — the ring is chrome, not artwork.
                gradientColors: kRingProgress,
                scrubbing: scrubbing,
                strokeWidth: strokeWidth,
                buffered: buffered,
                knobSize: knobSize,
              ),
            ),
          heroTag != null ? Hero(tag: heroTag!, child: artwork) : artwork,
        ],
      ),
    );
  }
}

/// The no-artwork placeholder from the design: a #FF6B9D -> #7C3AED diagonal
/// gradient with three orbit rings and a small dot — a stylised "planet"
/// that keeps every ring visually alive even without server artwork.
class _OrbitFallback extends StatelessWidget {
  const _OrbitFallback({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OrbitFallbackPainter(colors: colors),
    );
  }
}

class _OrbitFallbackPainter extends CustomPainter {
  const _OrbitFallbackPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    // Three concentric orbit rings (0.9 / 0.62 / 0.36 of the disc) plus a
    // dot riding the middle orbit — pure chrome, no allocated images.
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.008;
    for (final fraction in const [0.9, 0.62, 0.36]) {
      canvas.drawCircle(center, size.width * fraction / 2, ring);
    }

    final orbit = size.width * 0.62 / 2;
    canvas.drawCircle(
      Offset(center.dx + orbit, center.dy - orbit * 0.35),
      size.width * 0.03,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitFallbackPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

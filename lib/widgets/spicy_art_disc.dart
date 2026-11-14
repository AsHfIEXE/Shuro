import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'page_transitions.dart' show reduceMotionEnabled;

/// Circular cover that breathes while playing, wrapped in a progress ring
/// with a glowing dot that orbits with the position. Pure decoration —
/// no gesture handling, no control changes.
class SpicyArtDisc extends StatefulWidget {
  final Widget cover; // the screen's existing artwork widget
  final double size;
  final double progress; // 0..1
  final bool isPlaying;
  final Color accent;
  final String cacheKey; // crossfade on track change

  /// Decoration-only mode: when an interactive ring already exists
  /// (Shuro's ArtworkRing owns scrub + knob), the disc contributes
  /// just the breathing + halo around it.
  final bool showRing;

  /// False when the cover is already circular (no clip needed).
  final bool clip;

  const SpicyArtDisc({
    super.key,
    required this.cover,
    required this.size,
    required this.progress,
    required this.isPlaying,
    required this.cacheKey,
    this.accent = const Color(0xFFFF6B9D),
    this.showRing = true,
    this.clip = true,
  });

  @override
  State<SpicyArtDisc> createState() => _SpicyArtDiscState();
}

class _SpicyArtDiscState extends State<SpicyArtDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SpicyArtDisc old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_breath.isAnimating && !reduceMotionEnabled) {
      _breath.repeat(reverse: true);
    } else if (!widget.isPlaying && _breath.isAnimating) {
      _breath.stop();
      _breath.animateTo(0, duration: const Duration(milliseconds: 400));
    }
    if (old.cacheKey != widget.cacheKey) _breath.value = 0;
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          final scale = 1.0 + 0.014 * _breath.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Ambient halo behind the disc.
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent
                          .withValues(alpha: 0.28 + 0.12 * _breath.value),
                      blurRadius: 48,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const SizedBox.shrink(),
              ),
              Transform.scale(scale: scale, child: child),
              if (widget.showRing)
                CustomPaint(
                    painter: _RingPainter(
                  progress: widget.progress,
                  accent: widget.accent,
                )),
            ],
          );
        },
        child: widget.clip ? ClipOval(child: widget.cover) : widget.cover,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color accent;
  _RingPainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 2;

    canvas.drawCircle(center, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.10));

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + math.pi * 2,
          colors: [accent, const Color(0xFFFF8A3D), accent],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Orbiting glow dot.
    final a = -math.pi / 2 + sweep;
    final dot =
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
    canvas.drawCircle(dot, 6, Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
    canvas.drawCircle(dot, 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent;
}

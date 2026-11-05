import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Draws the ring seen behind the album art on the Now Playing screen and,
/// smaller, on the mini players. Layers, from the redesign spec
/// (docs/02-now-playing-ring-lyrics.md):
///
/// 1. Track: full circle, white 18%.
/// 2. Buffered arc: from 12 o'clock clockwise to the buffered fraction,
///    white 30%, round caps.
/// 3. Progress arc: 12 o'clock clockwise to the position fraction, fixed
///    brand gradient #FF8FB8 -> #A78BFA (kRingProgress), round caps.
/// 4. Knob at the progress angle — violet glow, white disc.
///
/// [buffered] and [knobSize] are optional so call sites can stay minimal;
/// null knob sizes are derived from the stroke width.
class ProgressRingPainter extends CustomPainter {
  final double progress; // 0..1
  final double? buffered; // 0..1, drawn under the progress arc
  final List<Color> gradientColors;
  final double strokeWidth;

  /// Knob DIAMETER (not radius). Defaults scale with the ring: 4px stroke
  /// -> 18-20px knob on the big rings, 3px stroke -> 9px on the mini ring.
  final double? knobSize;

  /// While the user is dragging the knob it grows and its glow strengthens —
  /// the seek control answers the touch instead of staying inert.
  final bool scrubbing;

  ProgressRingPainter({
    required this.progress,
    required this.gradientColors,
    this.buffered,
    this.strokeWidth = 4,
    this.knobSize,
    this.scrubbing = false,
  });

  /// Progress starts at the top (12 o'clock) and sweeps clockwise.
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Buffered arc — where the stream can scrub to without rebuffering.
    final buffered = this.buffered ?? 0.0;
    if (buffered > 0.002 && buffered < 0.998) {
      canvas.drawArc(
        rect,
        _startAngle,
        2 * math.pi * buffered.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    if (progress > 0) {
      // A soft glow under the crisp arc — one extra stroke, no filters, and
      // the ring reads "premium" instead of "thin wire". Violet, per spec.
      canvas.drawArc(
        rect,
        _startAngle,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = kVioletLight.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: const GradientRotation(_startAngle),
          colors: [...gradientColors, gradientColors.first],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, _startAngle, 2 * math.pi * progress.clamp(0.0, 1.0), false, progressPaint);
    }

    final knobAngle = _startAngle + 2 * math.pi * progress.clamp(0.0, 1.0);
    final knobOffset = Offset(
      center.dx + radius * math.cos(knobAngle),
      center.dy + radius * math.sin(knobAngle),
    );

    // The knob: drop shadow (lifts it off ANY artwork, light or dark),
    // violet glow (same visual language as the arc's glow), white disc,
    // hairline rim. Scale + glow strengthen while scrubbing.
    final knobRadius = (knobSize ?? strokeWidth * 4.5) / 2 * (scrubbing ? 1.22 : 1.0);

    canvas.drawCircle(
      knobOffset,
      knobRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: scrubbing ? 0.45 : 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      knobOffset,
      knobRadius * 1.75,
      Paint()
        ..color = kVioletLight.withValues(alpha: scrubbing ? 0.50 : 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(knobOffset, knobRadius, Paint()..color = Colors.white);
    canvas.drawCircle(
      knobOffset,
      knobRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.buffered != buffered ||
        oldDelegate.gradientColors != gradientColors ||
        oldDelegate.scrubbing != scrubbing ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.knobSize != knobSize;
  }
}

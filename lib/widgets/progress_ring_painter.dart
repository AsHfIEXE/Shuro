import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Draws the ring seen behind the album art on the Now Playing screen:
/// a faint full-circle track, a colored progress arc, and a knob marking
/// the current position. The arc starts at the bottom (6 o'clock) and
/// sweeps clockwise, matching the "Círculo Time" reference in the design.
class ProgressRingPainter extends CustomPainter {
  final double progress; // 0..1
  final List<Color> gradientColors;
  final double strokeWidth;

  ProgressRingPainter({
    required this.progress,
    required this.gradientColors,
    this.strokeWidth = 4,
  });

  static const double _startAngle = math.pi / 2; // bottom of the circle

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      // A soft glow under the crisp arc — one extra stroke, no filters, and
      // the ring reads "premium" instead of "thin wire".
      canvas.drawArc(
        rect,
        _startAngle,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = gradientColors.last.withValues(alpha: 0.45)
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

      canvas.drawArc(rect, _startAngle, 2 * math.pi * progress, false, progressPaint);
    }

    final knobAngle = _startAngle + 2 * math.pi * progress;
    final knobOffset = Offset(
      center.dx + radius * math.cos(knobAngle),
      center.dy + radius * math.sin(knobAngle),
    );
    canvas.drawCircle(knobOffset, strokeWidth * 2.4, Paint()..color = gradientColors.last);
    canvas.drawCircle(
      knobOffset,
      strokeWidth * 2.4,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.gradientColors != gradientColors;
  }
}

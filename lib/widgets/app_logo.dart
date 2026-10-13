import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shuro's brand mark: two rounded diagonal bars, offset into an "S" —
/// violet at top, shading to cyan at bottom. Pure vector (CustomPainter),
/// crisp at any size, no image asset to ship. This is the single source
/// of truth for the mark; every place it appears (splash, Welcome) uses
/// this widget.
///
/// [progress] (0..1) staggers the two bars in — bar one pops in first,
/// bar two follows shortly after — for the splash's entrance. Defaults to
/// 1 (fully settled) for ordinary, non-animated use elsewhere.
class AppLogo extends StatelessWidget {
  final double size;
  final double progress;
  final bool showBackground;

  const AppLogo({
    super.key,
    this.size = 96,
    this.progress = 1,
    this.showBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AppLogoPainter(progress: progress, showBackground: showBackground)),
    );
  }
}

double _remap(double t, double start, double end) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return (t - start) / (end - start);
}

class _AppLogoPainter extends CustomPainter {
  final double progress;
  final bool showBackground;

  _AppLogoPainter({required this.progress, required this.showBackground});

  static const double _rotation = -0.85; // radians, ~-49°

  @override
  void paint(Canvas canvas, Size size) {
    if (showBackground) {
      final bgRect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.22));
      canvas.drawRRect(bgRect, Paint()..color = kSurfaceColor);
    }

    final double barA = Curves.easeOutBack.transform(_remap(progress, 0.0, 0.65));
    final double barB = Curves.easeOutBack.transform(_remap(progress, 0.32, 1.0));

    final double w = size.width;
    final double barLength = w * 0.60;
    final double barThickness = w * 0.26;
    final double lengthOffset = barLength * 0.28;
    final double crossOffset = barThickness * 0.5;

    canvas.save();
    canvas.translate(w / 2, size.height / 2);
    canvas.rotate(_rotation);

    _drawBar(
      canvas,
      center: Offset(lengthOffset, -crossOffset),
      length: barLength,
      thickness: barThickness,
      colors: const [Color(0xFFA78BFA), kBrandColor],
      t: barA,
    );
    _drawBar(
      canvas,
      center: Offset(-lengthOffset, crossOffset),
      length: barLength,
      thickness: barThickness,
      colors: const [kBrandColor, kSecondaryColor],
      t: barB,
    );

    canvas.restore();
  }

  void _drawBar(
    Canvas canvas, {
    required Offset center,
    required double length,
    required double thickness,
    required List<Color> colors,
    required double t,
  }) {
    if (t <= 0) return;
    // Scale (with overshoot from easeOutBack left uncapped, for the bounce)
    // and fade the whole bar in — keeps its proportions correct throughout
    // instead of growing its width from a thin sliver, which looked like a
    // stretching blob against the fixed, fully-rounded corner radius.
    final double scale = 0.55 + 0.45 * t;
    final double opacity = t.clamp(0.0, 1.0);

    final rect = Rect.fromCenter(center: Offset.zero, width: length, height: thickness);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(thickness / 2));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.saveLayer(rect.inflate(thickness), Paint()..color = Colors.white.withOpacity(opacity));
    canvas.drawRRect(rrect, Paint()..shader = LinearGradient(colors: colors).createShader(rect));
    canvas.restore(); // saveLayer
    canvas.restore(); // translate/scale
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.showBackground != showBackground;
}

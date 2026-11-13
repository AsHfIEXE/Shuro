import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'page_transitions.dart' show reduceMotionEnabled;

/// Shuro's brand mark: two rounded diagonal bars, offset into an "S" —
/// violet at top, shading to cyan at bottom. Pure vector (CustomPainter),
/// crisp at any size, no image asset to ship. This is the single source
/// of truth for the mark; every place it appears (splash, Welcome) uses
/// this widget.
///
/// [progress] (0..1) plays the entrance from docs/03-splash-brand-motion:
/// the top pill slides in from the upper-right and the bottom pill from
/// the lower-left — each from ±0.35 × size away — fading in as it settles.
/// Windows are the spec's seconds on its 1.4 s entrance scale, so
/// progress 0..1 == 0..1.4 s: top pill 0.00-0.70 s, bottom pill
/// 0.15-0.85 s, fades complete early (by 0.45 s / 0.60 s). Defaults to 1
/// (fully settled) for ordinary, non-animated use elsewhere.
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

  // Entrance windows in progress-space = spec seconds Ã· 1.4 (the spec's
  // entrance scale). Slides run on ShuroMotion.std; each pill's fade
  // completes well before its slide does, so it is seen settling rather
  // than popping in.
  static const double _topSlideEnd = 0.70 / 1.4; // 0.50 — top settles at 0.70 s
  static const double _topFadeEnd = 0.45 / 1.4; // 0.32 — top visible by 0.45 s
  static const double _bottomStart = 0.15 / 1.4; // bottom held off until 0.15 s
  static const double _bottomSlideEnd = 0.85 / 1.4; // 0.61 — bottom settles at 0.85 s
  static const double _bottomFadeEnd = 0.60 / 1.4; // 0.43 — bottom visible by 0.60 s

  /// Slide-in distance as a fraction of size: the top pill drops in from
  /// the upper-right, the bottom pill rises in from the lower-left.
  static const double _slideDistance = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    if (showBackground) {
      final bgRect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.22));
      canvas.drawRRect(bgRect, Paint()..color = kSurfaceColor);
    }

    final double w = size.width;
    final double barLength = w * 0.60;
    final double barThickness = w * 0.26;
    final double lengthOffset = barLength * 0.28;
    final double crossOffset = barThickness * 0.5;
    final double slide = w * _slideDistance;

    _drawPill(
      canvas,
      size: size,
      center: Offset(lengthOffset, -crossOffset),
      length: barLength,
      thickness: barThickness,
      colors: const [Color(0xFFA78BFA), kBrandColor],
      slideOffset: Offset(slide, -slide),
      slideT: ShuroMotion.std.transform(_remap(progress, 0.0, _topSlideEnd)),
      opacity: Curves.easeOut.transform(_remap(progress, 0.0, _topFadeEnd)),
    );
    _drawPill(
      canvas,
      size: size,
      center: Offset(-lengthOffset, crossOffset),
      length: barLength,
      thickness: barThickness,
      colors: const [kBrandColor, kSecondaryColor],
      slideOffset: Offset(-slide, slide),
      slideT: ShuroMotion.std.transform(_remap(progress, _bottomStart, _bottomSlideEnd)),
      opacity: Curves.easeOut.transform(_remap(progress, _bottomStart, _bottomFadeEnd)),
    );
  }

  void _drawPill(
    Canvas canvas, {
    required Size size,
    required Offset center,
    required double length,
    required double thickness,
    required List<Color> colors,
    required Offset slideOffset,
    required double slideT,
    required double opacity,
  }) {
    if (opacity <= 0) return;

    final rect = Rect.fromCenter(center: Offset.zero, width: length, height: thickness);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(thickness / 2));

    canvas.save();
    // The slide offset is applied *before* the mark's rotation, so it reads
    // in screen space (from the upper-right / lower-left) rather than along
    // the bars' own axis. No clip anywhere — callers must leave the mark's
    // container unclipped (see splash_screen.dart) or this offset gets cut.
    canvas.translate(slideOffset.dx * (1 - slideT), slideOffset.dy * (1 - slideT));
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_rotation);
    canvas.translate(center.dx, center.dy);

    canvas.saveLayer(rect.inflate(thickness), Paint()..color = Colors.white.withValues(alpha: opacity));
    canvas.drawRRect(rrect, Paint()..shader = LinearGradient(colors: colors).createShader(rect));
    canvas.restore(); // saveLayer
    canvas.restore(); // slide/rotate/translate
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.showBackground != showBackground;
}

/// One-shot launch pop for the sidebar and onboarding marks (splash motion
/// spec: "a short one-shot pop with a ring on first load"). Plays once per
/// app session - the first of these widgets to mount consumes the flag -
/// then renders the plain mark everywhere else. Reduced motion: never plays.
bool _logoPopSpent = false;

class LogoPop extends StatefulWidget {
  final double size;
  final Widget child;

  const LogoPop({super.key, required this.size, required this.child});

  @override
  State<LogoPop> createState() => _LogoPopState();
}

class _LogoPopState extends State<LogoPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  bool _play = false;

  @override
  void initState() {
    super.initState();
    if (!_logoPopSpent && !reduceMotionEnabled) {
      _logoPopSpent = true;
      _play = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_play) return widget.child;
    final scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.92, end: 1.06)
              .chain(CurveTween(curve: ShuroMotion.std)),
          weight: 45),
      TweenSequenceItem(
          tween: Tween(begin: 1.06, end: 1.0)
              .chain(CurveTween(curve: ShuroMotion.spring)),
          weight: 55),
    ]).animate(_c);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) =>
                CustomPaint(painter: _LogoRingPop(_c.value)),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              Transform.scale(scale: scale.value, child: widget.child),
        ),
      ],
    );
  }
}

class _LogoRingPop extends CustomPainter {
  final double progress;

  _LogoRingPop(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide / 2;
    final radius = base * (0.7 + 0.9 * progress);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = kVioletLight.withValues(alpha: (1 - progress) * 0.55);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_LogoRingPop old) => old.progress != progress;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'page_transitions.dart' show reduceMotionEnabled;

/// The redesign's motion kit (docs/03 + the Motion board).
///
/// Every entrance here is a one-shot and every loop here is decorative —
/// all of it stands down under reduced motion (`MediaQuery.disableAnimations`
/// or [reduceMotionEnabled]): entrances render settled, loops freeze.
///
/// The vocabulary (from the boards):
///  * entrances: fade + 12-16 px rise, 280 ms std, staggered 30 ms/row
///    (max 8 rows);
///  * hover: lift -1 px (buttons) / -3 px (cards) + violet border, 200 ms;
///  * press: scale 0.97;
///  * playing rows: animated EQ bars;
///  * backdrops: three drifting mesh blobs (loop, decorative).

/// One-shot fade + rise entrance for pages, sections and list rows.
///
/// [delay] staggers rows (30 ms each, capped at 8 rows — see [stagger]).
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.offset = 12,
    this.delay = Duration.zero,
    this.enabled = true,
  });

  final Widget child;
  final Duration duration;
  final double offset;

  /// Start delay; pass [stagger] * index for lists.
  final Duration delay;

  /// False skips the animation entirely (already-visible subtrees, tests).
  final bool enabled;

  /// The boards' list stagger: 30 ms per row, capped at 8 rows.
  static Duration stagger(int index) =>
      Duration(milliseconds: 30 * index.clamp(0, 8));

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _animation = CurvedAnimation(parent: _controller, curve: ShuroMotion.std);

  @override
  void initState() {
    super.initState();
    final reduce = reduceMotionEnabled || !widget.enabled;
    if (reduce) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionEnabled || !widget.enabled;
    if (reduce || _animation.isCompleted) return widget.child;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _animation.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Hover lift + violet border for cards (Motion board `.card`): -3 px rise,
/// border to violet 50%, 200 ms std. Buttons use [lift] = 1. Press feedback
/// (scale 0.97) is included; disabled while reduced motion is on.
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.lift = 6,
    this.radius = const BorderRadius.all(Radius.circular(16)),
    this.borderColor = const Color(0x80A78BFA),
    this.enabled = true,
  });

  final Widget child;
  final double lift;
  final BorderRadius radius;
  final Color borderColor;
  final bool enabled;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final animate = widget.enabled && !reduceMotionEnabled;
    final lifted = _hover && animate;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hover = true);
      },
      onExit: (_) {
        if (!mounted) return;
        setState(() {
          _hover = false;
          _pressing = false;
        });
      },
      child: Listener(
        onPointerDown: (_) {
          if (animate) {
            setState(() => _pressing = true);
            HapticFeedback.selectionClick();
          }
        },
        onPointerUp: (_) {
          if (mounted) setState(() => _pressing = false);
        },
        onPointerCancel: (_) {
          if (mounted) setState(() => _pressing = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: ShuroMotion.std,
          transform: Matrix4.translationValues(0, lifted ? -widget.lift : 0, 0)
            ..scaleByDouble(_pressing ? 0.97 : 1.0, _pressing ? 0.97 : 1.0, _pressing ? 0.97 : 1.0, 1.0),
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            boxShadow: lifted && widget.lift >= 3
                ? const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 24,
                        offset: Offset(0, 12))
                  ]
                : null,
            border: Border.all(
              color: lifted ? widget.borderColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: widget.child),
      ),
    );
  }
}

/// The animated three-bar EQ mark for "this row is playing" (Motion board
/// `eqb`). Freezes to a static mid-height under reduced motion — the state
/// signal stays even when the loop doesn't.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    this.color = kVioletPale,
    this.size = 14,
  });

  final Color color;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotionEnabled) {
      return _bars((i) => 0.6);
    }
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        // Three bars phase-shifted by a third — reads as audio, not as a
        // spinner.
        return _bars((i) {
          final phase = (_loop.value + i / 5) % 1.0;
          return 0.25 + 0.75 * (0.5 - 0.5 * _wave(phase));
        });
      },
    );
  }

  static double _wave(double t) => -math.cos(2 * math.pi * t);

  Widget _bars(double Function(int) scaleOf) {
    final barWidth = widget.size / 9;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 5; i++)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: barWidth,
                height: widget.size * scaleOf(i).clamp(0.2, 1.0),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three drifting brand-tinted blobs for hero/now-playing backdrops (Motion
/// board `drift1..3`). Decorative: under reduced motion the blobs render
/// once and hold still.
class MeshBlobs extends StatefulWidget {
  const MeshBlobs({
    super.key,
    this.opacity = 0.13,
    this.blobs = const [
      (Color(0xFFFF6B9D), Alignment(-0.7, -0.8), 0.55),
      (Color(0xFF7C3AED), Alignment(0.8, -0.4), 0.65),
      (Color(0xFF00D4FF), Alignment(-0.2, 0.9), 0.5),
    ],
  });

  /// (color, alignment, relative size) per blob.
  final List<(Color, Alignment, double)> blobs;
  final double opacity;

  @override
  State<MeshBlobs> createState() => _MeshBlobsState();
}

class _MeshBlobsState extends State<MeshBlobs>
    with SingleTickerProviderStateMixin {
  // Phones: static wash. Repainting three full-screen radial gradients every
  // frame is what made low-end Android devices stutter on Pulse / artist /
  // onboarding pages, for a 24 px drift nobody can see. No controller is even
  // created there, so no ticker keeps requesting frames.
  static bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  AnimationController? _drift;

  @override
  void initState() {
    super.initState();
    if (!_phone) {
      _drift = AnimationController(
          vsync: this, duration: const Duration(seconds: 16))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _drift?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drift = _drift;
    if (reduceMotionEnabled || drift == null) {
      return RepaintBoundary(child: _paint(0));
    }
    // Own layer: the drift repaints only this backdrop, never the page above.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: drift,
        builder: (context, _) => _paint(drift.value),
      ),
    );
  }

  Widget _paint(double t) {
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        for (var i = 0; i < widget.blobs.length; i++)
          () {
            final (color, align, size) = widget.blobs[i];
            // Each blob drifts along its own small loop; the phase offsets
            // keep them from ever syncing into one pulse.
            final phase = t * 2 * 3.14159 + i * 2.1;
            final dx = 24 * _wave1(phase);
            final dy = 16 * _wave1(phase * 0.7 + 1.3);
            return Positioned.fill(
              child: Align(
                alignment: align,
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: _softCircle(color, size),
                ),
              ),
            );
          }(),
      ]),
    );
  }

  static double _wave1(double t) => -math.cos(2 * math.pi * t);

  Widget _softCircle(Color color, double relative) {
    return AspectRatio(
      aspectRatio: 1,
      child: FractionallySizedBox(
        widthFactor: relative,
        heightFactor: relative,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: widget.opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Press feedback from the Motion board: squashes to [scale] (92 %) on press,
/// springs back with overshoot (120 ms down, 220 ms up). Wrap play buttons and
/// cover play discs. Frozen under reduced motion.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.92});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotionEnabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: _down ? ShuroMotion.fast : const Duration(milliseconds: 220),
        curve: _down ? ShuroMotion.std : ShuroMotion.spring,
        child: widget.child,
      ),
    );
  }
}

/// Connection-test result: a spinner that resolves into a check drawn over
/// 450 ms (Motion board "Connection test"). [done] false shows the spinner.
class DrawnCheck extends StatelessWidget {
  const DrawnCheck({
    super.key,
    required this.done,
    this.size = 36,
    this.color = const Color(0xFF34D399),
  });

  final bool done;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!done) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
            strokeWidth: 3, color: kVioletPale, backgroundColor: Colors.white12),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotionEnabled ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: ShuroMotion.std,
      builder: (context, t, _) => CustomPaint(
        size: Size.square(size),
        painter: _CheckPainter(t, color),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(size.center(Offset.zero), size.width / 2, ring);
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.74, size.height * 0.34);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// Onboarding step change: the current step slides left 40 px and fades while
/// the next arrives from the right, 360 ms on the emphasized curve.
class StepSwitcher extends StatelessWidget {
  const StepSwitcher({super.key, required this.child});

  final Widget child; // give it a ValueKey per step

  @override
  Widget build(BuildContext context) {
    if (reduceMotionEnabled) return child;
    return AnimatedSwitcher(
      duration: ShuroMotion.stepSlide,
      switchInCurve: ShuroMotion.emphasized,
      switchOutCurve: ShuroMotion.emphasized,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
              .animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// Toast entrance: slides up 24 px with a fade, 220 ms.
class ToastIn extends StatelessWidget {
  const ToastIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionEnabled) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: ShuroMotion.toastIn,
      curve: ShuroMotion.std,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

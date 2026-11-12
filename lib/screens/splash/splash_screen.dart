import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/page_transitions.dart';

/// App startup, per docs/03-splash-brand-motion: the two pills of the S-mark
/// slide in along the diagonal (top from the upper-right, bottom from the
/// lower-left), the joined mark settles with a small spring pulse, then
/// wordmark, tagline and loader follow. Halo rings only start once the mark
/// is joined (>= 0.85 s) — nothing is visible before the logo itself.
///
/// One 1.5 s controller owns the entrance; a repeating 1.6 s controller owns
/// everything that loops (pulse rings, loader sweep, status cycle). When the
/// entrance finishes, a short hold, then it hands off into AuthGate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

const List<String> _kStatuses = ['Starting up…', 'Connecting to your server…', 'Loading your library…'];

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // The splash is the connect window: AppState starts the server reconnect
  // during restore, and this screen holds the stage for it. A LAN connect
  // typically finishes inside this window, so the handoff into AuthGate
  // lands on an already-loaded library — connecting feels instant.
  static const double _markSize = 108;

  late final AnimationController _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  // Mark float + halo breathe: the two 3.2 s loops from the motion spec.
  // (The old expanding pulse rings were removed per review.)
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  late final AnimationController _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  // Pills: driven *linearly* to 1 across 1.4 s of the 1.5 s controller, so
  // AppLogo's own windows (spec seconds ÷ 1.4, each with its own easing) map
  // 1:1 onto wall clock — top pill settles at 0.70 s, bottom at 0.85 s, on
  // ShuroMotion.std inside each window. Easing the drive as well would
  // double-apply the curve (std front-loads ~80% of its value into the
  // first 20%) and collapse the whole 0-0.85 s entrance into ~0.1 s.
  late final Animation<double> _logoProgress = CurvedAnimation(parent: _entrance, curve: const Interval(0.0, 1.4 / 1.5));

  // 0.85-1.50 s: whole-mark scale 1 -> 1.07 (std) -> 1 (spring).
  late final Animation<double> _markScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07).chain(CurveTween(curve: ShuroMotion.std)), weight: 25), // 0.85 -> 1.10 s
    TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0).chain(CurveTween(curve: ShuroMotion.spring)), weight: 40), // 1.10 -> 1.50 s
  ]).animate(CurvedAnimation(parent: _entrance, curve: const Interval(0.85 / 1.5, 1.0)));

  late final Animation<double> _wordmark = CurvedAnimation(parent: _entrance, curve: const Interval(0.70 / 1.5, 1.20 / 1.5, curve: Curves.easeOut));
  late final Animation<double> _tagline = CurvedAnimation(parent: _entrance, curve: const Interval(0.95 / 1.5, 1.45 / 1.5, curve: Curves.easeOut));
  // The loader arrives with the wordmark and loops until navigation.
  late final Animation<double> _loader = CurvedAnimation(parent: _entrance, curve: const Interval(0.70 / 1.5, 1.20 / 1.5, curve: Curves.easeOut));
  int _statusIndex = 0;
  Timer? _statusTimer;
  bool _reducedMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _entrance.addStatusListener((status) {
      if (status == AnimationStatus.completed) _scheduleHandoff();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reducedMotion = MediaQuery.of(context).disableAnimations;
    if (_reducedMotion) {
      // Everything settled, nothing looping: static mark, static loader
      // fill, first status line — then the same handoff.
      _entrance.value = 1;
      _scheduleHandoff();
      return;
    }
    _entrance.forward();
    _loop.repeat();
    _float.repeat();
    _halo.repeat();
    _statusTimer = Timer.periodic(
      const Duration(milliseconds: 1600),
      (_) => setState(() => _statusIndex = (_statusIndex + 1) % _kStatuses.length),
    );
  }

  void _scheduleHandoff() {
    // Short hold on the finished composition (~2.7 s all-in), then hand
    // off — by now the reconnect has usually finished too, so AuthGate
    // lands straight on the library.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pushReplacement(drillDownRoute(const AuthGate()));
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _entrance.dispose();
    _loop.dispose();
    _float.dispose();
    _halo.dispose();
    super.dispose();
  }

  Widget _buildMark() {
    return SizedBox(
      width: _markSize,
      height: _markSize,
      // Clip.none is load-bearing: the pills slide in from ±0.35 × size
      // *outside* this box (the spec calls out that these offsets were
      // clipped in an earlier build).
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Halo breathe (3.2 s): a soft violet glow behind the mark.
          if (!_reducedMotion)
            AnimatedBuilder(
              animation: _halo,
              builder: (context, _) {
                final breathe =
                    (math.sin(_halo.value * 2 * math.pi) + 1) / 2;
                return Transform.scale(
                  scale: 1.0 + 0.06 * breathe,
                  child: Opacity(
                    opacity: 0.10 + 0.08 * breathe,
                    child: Container(
                      width: _markSize * 2.1,
                      height: _markSize * 2.1,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x2E7C3AED), Color(0x001E3A8A)],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ScaleTransition(
            scale: _markScale,
            child: AnimatedBuilder(
              animation: Listenable.merge([_logoProgress, _float]),
              builder: (context, _) {
                // Mark float (3.2 s): a gentle ±4 px bob while loading.
                final bob = _reducedMotion
                    ? 0.0
                    : math.sin(_float.value * 2 * math.pi) * 4.0;
                return Transform.translate(
                  offset: Offset(0, bob),
                  child: AppLogo(
                      size: _markSize, progress: _logoProgress.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      // LayoutBuilder + an explicitly full-size SizedBox around the Stack:
      // pins the content area to the exact constraints Scaffold's body is
      // given (the full screen) rather than leaning on Stack's own
      // "be as big as possible" sizing — kept from the previous version,
      // which fixed a reported off-center logo.
      body: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            // Never clip: the mark's slide-in offsets and halo rings paint
            // outside the mark's own box (spec: they were cut off before).
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildMark(),
                    const SizedBox(height: 16),
                    _EnterSlide(
                      animation: _wordmark,
                      rise: 16,
                      child: Text(
                        'Shuro',
                        textAlign: TextAlign.center,
                        // Sora w700, -0.01em tracking (=-0.28 at 28px).
                        style: headingFont(color: kTextColor, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.28),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EnterSlide(
                      animation: _tagline,
                      rise: 12,
                      child: Text(
                        'Your music. Your server. Your sound.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _loader,
                      child: _SplashLoader(loop: _loop, reducedMotion: _reducedMotion, statusIndex: _statusIndex),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + rise entrance shared by the wordmark and tagline (spec: "fades +
/// slides in"). Settles to zero offset, so the resting layout is exact.
class _EnterSlide extends StatelessWidget {
  final Animation<double> animation;
  final double rise;
  final Widget child;

  const _EnterSlide({required this.animation, required this.rise, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, rise * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Loader under the tagline: 4 px rounded track (white 10%), brand-gradient
/// fill (#FF8FB8 -> #A78BFA -> #7C3AED) at the boards' resting 62%, a glow
/// sweep drifting across on the 1.6 s loop, and the cycling status line
/// below. Under reduced motion it is fully static (no sweep, "Starting
/// up…" stays).
class _SplashLoader extends StatelessWidget {
  final AnimationController loop;
  final bool reducedMotion;
  final int statusIndex;

  const _SplashLoader({required this.loop, required this.reducedMotion, required this.statusIndex});

  static const double _trackWidth = 220;
  static const double _sweepWidth = 60;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2), // 4 px track -> fully rounded
          child: SizedBox(
            width: _trackWidth,
            height: 4,
            // The track is the one place we DO clip: the sweep must vanish
            // at the track's ends, not run over the neighbouring text.
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.62, // resting fill from the boards
                    child: const DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [kPinkLight, kVioletLight, kBrandColor])),
                    ),
                  ),
                ),
                if (!reducedMotion)
                  AnimatedBuilder(
                    animation: loop,
                    builder: (context, _) {
                      final double t = loop.value;
                      // Soft ends so the sweep reads as passing light.
                      final double edgeFade = (t < 0.5 ? t / 0.125 : (1 - t) / 0.125).clamp(0.0, 1.0);
                      return Positioned(
                        left: -_sweepWidth + t * (_trackWidth + _sweepWidth),
                        top: 0,
                        bottom: 0,
                        width: _sweepWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.9 * edgeFade),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _kStatuses[statusIndex],
          style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// Expanding violet halo rings behind the mark — only ever painted once the
/// gate opens (>= 0.85 s, after the pills have joined). Two rings on the
/// 1.6 s loop, offset by half a period: each expands from 1x to 1.7x of the
/// base radius while its stroke fades out.
class _PulseRingsPainter extends CustomPainter {
  final double phase;
  final double gate;
  final double baseRadius;

  _PulseRingsPainter({required this.phase, required this.gate, required this.baseRadius});

  @override
  void paint(Canvas canvas, Size size) {
    if (gate <= 0) return;
    final Offset center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      // Ring i+1 trails ring i by half the loop period.
      final double t = Curves.easeOut.transform((phase + i * 0.5) % 1.0);
      final double opacity = 0.5 * (1 - t) * gate;
      if (opacity <= 0) continue;
      canvas.drawCircle(
        center,
        baseRadius * (1 + 0.7 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kVioletLight.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingsPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.gate != gate || oldDelegate.baseRadius != baseRadius;
}

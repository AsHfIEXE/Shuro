import 'package:flutter/material.dart';
import '../../app.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/page_transitions.dart';

/// App startup: the two bars of the S-mark pop in one after another, the
/// wordmark follows, then it hands off into AuthGate. One
/// AnimationController driving everything via Intervals — cheap, and
/// nothing keeps running once it's done.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  late final Animation<double> _logoProgress =
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.75, curve: Curves.linear));
  late final Animation<double> _glowOpacity =
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOut));
  late final Animation<double> _wordmarkOpacity =
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 0.9, curve: Curves.easeOut));
  late final Animation<Offset> _wordmarkOffset = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(_wordmarkOpacity);

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) Navigator.of(context).pushReplacement(drillDownRoute(const AuthGate()));
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      // LayoutBuilder + an explicitly full-size SizedBox around the Stack:
      // this pins the content area to the *exact* constraints Scaffold's
      // body is given (the full screen), rather than leaning on Stack's
      // own "be as big as possible" sizing behavior. A previous version
      // relied on that default and a width-capping wrapper up in
      // main.dart's MaterialApp.builder — neither of those actually fixed
      // the reported off-center logo (it showed up identically on a
      // native APK and in a normal-size desktop Chrome window, so it
      // wasn't a "browser is wide" issue), so both have been replaced
      // with this unambiguous version instead of layering another guess
      // on top. If this still isn't centered, it means something outside
      // this screen's own layout is involved (OS-level letterboxing, a
      // stray platform view, etc.) rather than anything here.
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                // Soft glow behind the mark, matching the radial glow used
                // on Now Playing — the same "depth" treatment throughout
                // the app. Positioned.fill + its own inner Center so its
                // centering doesn't depend on the outer Stack at all.
                Positioned.fill(
                  child: Center(
                    child: FadeTransition(
                      opacity: _glowOpacity,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [kBrandColor.withOpacity(0.22), Colors.transparent]),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _logoProgress,
                          builder: (context, _) => AppLogo(size: 108, progress: _logoProgress.value),
                        ),
                        const SizedBox(height: 22),
                        SlideTransition(
                          position: _wordmarkOffset,
                          child: FadeTransition(
                            opacity: _wordmarkOpacity,
                            child: Text(
                              'Shuro',
                              textAlign: TextAlign.center,
                              style: headingFont(color: kTextColor, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

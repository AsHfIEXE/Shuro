import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_info.dart';
import '../../models/server_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/state_views.dart';
import 'onboarding_chrome.dart';
import 'server_setup_screen.dart';

/// Step 1 of onboarding (board "Onboarding1"): the logo pop with its
/// expanding ring, the "Your music. Your server." headline over the brand
/// mesh-blob backdrop, and the two ways in — connect a server now, or use
/// the files on this device (the app's long-standing local-only path).
///
/// Previously-saved servers still get their one-tap reconnect rows: a
/// reinstall keeps working exactly as before.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Mirrors ManageServersScreen's same fix: tapping a saved server used to
  // fire switchServer() and show nothing until it either silently worked or
  // silently didn't. A spinner on the tapped row plus an error snackbar on
  // failure makes a bad saved password or an unreachable server visible.
  String? _connectingId;

  Future<void> _connect(String id) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = id);
    final appState = context.read<AppState>();
    await appState.switchServer(id);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (appState.connectionStatus != ConnectionStatus.connected &&
        context.mounted) {
      showErrorSnackBar(context,
          appState.connectionErrorMessage ?? "Couldn't reach that server.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final servers = appState.servers;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Stack(
        children: [
          const OnboardingBlobs(),
          SafeArea(
            // Scroll-safe instead of Spacer-driven: `Center` inside a
            // min-height box keeps the tall-screen centering, and scrolling
            // takes over when the content genuinely doesn't fit (landscape
            // phone, a resized desktop window).
            child: Column(
              children: [
                const OnboardingHeader(currentStep: 0),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        if (constraints.maxWidth >= 980)
                          Positioned.fill(
                            child: _FloatingSquares(size: constraints.biggest),
                          ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 40),
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 760),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Entrance(
                                      delay: const Duration(milliseconds: 50),
                                      child: _LogoPop(size: 84),
                                    ),
                                    const SizedBox(height: 24),
                                    Entrance(
                                      delay: const Duration(milliseconds: 150),
                                      child: Text(
                                        'WELCOME TO ${kAppName.toUpperCase()}',
                                        textAlign: TextAlign.center,
                                        style: onboardingBody(
                                          color: kVioletLight,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Entrance(
                                      delay: const Duration(milliseconds: 250),
                                      child: const _Headline(),
                                    ),
                                    const SizedBox(height: 24),
                                    Entrance(
                                      delay: const Duration(milliseconds: 400),
                                      child: Text(
                                        'Shuro plays straight from the servers you own. '
                                        'No accounts with us, nothing uploaded. '
                                        'Set up takes about two minutes.',
                                        textAlign: TextAlign.center,
                                        style: onboardingBody(
                                          color: kNavText,
                                          fontSize: 17,
                                          height: 1.55,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    Entrance(
                                      delay: const Duration(milliseconds: 550),
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          PrimaryPill(
                                            label: 'Get started',
                                            onPressed: () => pushDrillDownOnce(
                                                context,
                                                const ServerSetupScreen(
                                                    inOnboarding: true)),
                                          ),
                                          SecondaryPill(
                                            label: 'I use files on this device',
                                            icon: Icons.folder_rounded,
                                            onPressed: () => context
                                                .read<AppState>()
                                                .continueWithoutServer(),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (servers.isNotEmpty) ...[
                                      const SizedBox(height: 32),
                                      Entrance(
                                        delay:
                                            const Duration(milliseconds: 650),
                                        child: _SavedServers(
                                          servers: servers,
                                          connectingId: _connectingId,
                                          onConnect: _connect,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 32),
                                    Entrance(
                                      delay: const Duration(milliseconds: 700),
                                      child: const _FeatureChips(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The board headline: "Your music." in white, "Your server." as a
/// violet→cyan→pink gradient line.
class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = width >= 900
        ? 64.0
        : width >= 600
            ? 48.0
            : 34.0;
    final style = headingFont(
      color: kTextColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: fontSize * -0.035,
      height: 1.05,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your music.', textAlign: TextAlign.center, style: style),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [kVioletLight, kSecondaryColor, kPinkLight],
            stops: [0.0, 0.6, 1.0],
          ).createShader(bounds),
          child: Text(
            'Your server.',
            textAlign: TextAlign.center,
            style: style.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Previously-saved servers (reinstalls): one-tap reconnect rows, kept from
/// the pre-redesign welcome — restyled to the board's card language.
class _SavedServers extends StatelessWidget {
  const _SavedServers({
    required this.servers,
    required this.connectingId,
    required this.onConnect,
  });

  final List<ServerConfig> servers;
  final String? connectingId;
  final void Function(String id) onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kRaisedColor.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved servers',
              style: onboardingBody(
                  color: kMuted2, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final server in servers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onConnect(server.id),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kCardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kHairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: kBrandGradient),
                        ),
                        child: connectingId == server.id
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.dns_rounded,
                                color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(server.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: onboardingBody(
                                    color: kTextColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(server.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: onboardingBody(
                                    color: kMuted2, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: kMuted2, size: 20),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The three capability pills from the board. Informational only.
class _FeatureChips extends StatelessWidget {
  const _FeatureChips();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        _chip(Icons.music_note_rounded, 'Music from Navidrome'),
        _chip(Icons.menu_book_rounded, 'Audiobooks from Audiobookshelf'),
        _chip(Icons.equalizer_rounded, 'Audiophile output'),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kVioletLight),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: onboardingBody(
                  color: kTextColor, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The boards' drifting gradient squares behind the welcome content.
/// Decorative loop: static under reduced motion, hidden on narrow screens.
class _FloatingSquares extends StatefulWidget {
  const _FloatingSquares({required this.size});

  final Size size;

  @override
  State<_FloatingSquares> createState() => _FloatingSquaresState();
}

class _FloatingSquaresState extends State<_FloatingSquares>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!onboardingMotionEnabled(context)) return const SizedBox.shrink();
    final w = widget.size.width;
    final h = widget.size.height;
    final tiles = <(Rect, double, double, List<Color>)>[
      (
        Rect.fromLTWH(w * 0.07, h * 0.14, 150, 150),
        18,
        -8,
        kOnboardingArtGradients[0]
      ),
      (
        Rect.fromLTWH(w * 0.19, h * 0.05, 110, 110),
        22,
        6,
        kOnboardingArtGradients[1]
      ),
      (
        Rect.fromLTWH(w * 0.09, h * 0.42, 120, 120),
        26,
        5,
        kOnboardingArtGradients[2]
      ),
      (
        Rect.fromLTWH(w * 0.70, h * 0.12, 130, 130),
        20,
        7,
        kOnboardingArtGradients[3]
      ),
      (
        Rect.fromLTWH(w * 0.82, h * 0.32, 170, 170),
        24,
        -6,
        kOnboardingArtGradients[4]
      ),
      (
        Rect.fromLTWH(w * 0.74, h * 0.50, 115, 115),
        28,
        -3,
        kOnboardingArtGradients[5]
      ),
    ];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) => Stack(
          children: [
            for (var i = 0; i < tiles.length; i++)
              () {
                final (rect, delaySeconds, rotation, colors) = tiles[i];
                final phase = (_loop.value * 16 + delaySeconds) % 16 / 16;
                final dy = -16 * (0.5 - 0.5 * math.cos(2 * math.pi * phase));
                return Positioned(
                  left: rect.left,
                  top: rect.top + dy,
                  width: rect.width,
                  height: rect.height,
                  child: Transform.rotate(
                    angle: rotation * math.pi / 180,
                    child: GradientTile(colors: colors, radius: rect.width / 7),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}

/// First-build logo pop (docs/03, onboarding): the mark scales 0.8 -> 1 on
/// the brand spring while violet and cyan rings expand and fade behind it
/// (the board's two offset `ring` loops become two staggered one-shots).
/// One-shot (~600 ms); skipped entirely under reduced motion, which just
/// shows the settled mark.
class _LogoPop extends StatefulWidget {
  final double size;

  const _LogoPop({required this.size});

  @override
  State<_LogoPop> createState() => _LogoPopState();
}

class _LogoPopState extends State<_LogoPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _scale = Tween(begin: 0.8, end: 1.0)
      .chain(CurveTween(curve: ShuroMotion.spring))
      .animate(_controller);
  late final Animation<double> _ring =
      CurvedAnimation(parent: _controller, curve: ShuroMotion.std);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1; // settled: static mark, ring fully faded
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      // Clip.none: the ring expands past the mark's own box.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _ring,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter:
                  _PopRingPainter(progress: _ring.value, markSize: widget.size),
            ),
          ),
          ScaleTransition(scale: _scale, child: AppLogo(size: widget.size)),
        ],
      ),
    );
  }
}

/// The expanding rings behind the welcome logo: stroke grows from the mark's
/// edge outward while fading to nothing — violet on the first half of the
/// pop, cyan on the second, echoing the board's two offset ring loops.
class _PopRingPainter extends CustomPainter {
  final double progress;
  final double markSize;

  _PopRingPainter({required this.progress, required this.markSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final double t = Curves.easeOut.transform(progress);
    final violet = kVioletLight.withValues(alpha: 0.55 * (1 - t));
    if (violet.a > 0) {
      canvas.drawCircle(
        size.center(Offset.zero),
        markSize * (0.35 + 0.31 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = violet,
      );
    }
    final cyanT = Curves.easeOut.transform((progress - 0.45).clamp(0.0, 1.0));
    if (cyanT > 0 && cyanT < 1) {
      canvas.drawCircle(
        size.center(Offset.zero),
        markSize * (0.35 + 0.31 * cyanT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kSecondaryColor.withValues(alpha: 0.5 * (1 - cyanT)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PopRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

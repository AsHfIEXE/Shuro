import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart' show ConnectionStatus;
import '../../state/app_state.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import 'audiobookshelf_setup_screen.dart';
import 'onboarding_chrome.dart';
import 'server_setup_screen.dart';
import 'sound_preset_screen.dart';

/// Step 5 of onboarding (board "Onboarding5") — "You're all set". A live
/// summary of what was actually configured (server or local files,
/// Audiobookshelf, sound preset) with one primary action: enter the app.
///
/// "Open Shuro" re-uses the exact entry the flow always had — with a
/// server connected the AuthGate underneath already holds the shell, and
/// without one this calls [AppState.continueWithoutServer] so the app
/// opens in its long-standing local-only mode.
class AllSetScreen extends StatefulWidget {
  const AllSetScreen({super.key});

  @override
  State<AllSetScreen> createState() => _AllSetScreenState();
}

class _AllSetScreenState extends State<AllSetScreen> {
  Future<void> _openShuro() async {
    final appState = context.read<AppState>();
    if (appState.connectionStatus != ConnectionStatus.connected) {
      // No server was connected during onboarding: honour the local-only
      // path (the same one Welcome's skip always used) as we enter. (The
      // call itself is synchronous; it just flips + persists the mode.)
      appState.continueWithoutServer();
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Stack(
        children: [
          const OnboardingBlobs(),
          SafeArea(
            child: Column(
              children: [
                const OnboardingHeader(currentStep: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 40),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Entrance(
                                  delay: Duration(milliseconds: 50),
                                  child: _SuccessBadge(size: 120),
                                ),
                                const SizedBox(height: 24),
                                Entrance(
                                  delay: const Duration(milliseconds: 200),
                                  child: Text(
                                    "You're all set",
                                    textAlign: TextAlign.center,
                                    style: headingFont(
                                      color: kTextColor,
                                      fontSize:
                                          MediaQuery.sizeOf(context).width >=
                                                  600
                                              ? 48
                                              : 32,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Entrance(
                                  delay: const Duration(milliseconds: 300),
                                  child: Text(
                                    'Your library is syncing in the background. '
                                    'Start listening now.',
                                    textAlign: TextAlign.center,
                                    style: onboardingBody(
                                        color: kNavText,
                                        fontSize: 17,
                                        height: 1.5),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Entrance(
                                  delay: Duration(milliseconds: 400),
                                  child: _SummaryCard(),
                                ),
                                const SizedBox(height: 24),
                                Entrance(
                                  delay: const Duration(milliseconds: 550),
                                  child: PrimaryPill(
                                    label: 'Open Shuro',
                                    onPressed: _openShuro,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Entrance(
                                  delay: const Duration(milliseconds: 650),
                                  child: _TipRow(isDesktop: isDesktop),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

/// The green pop: gradient disc, a stroke-drawn check, and two expanding
/// rings on a loop (rings and draw both stand down under reduced motion).
class _SuccessBadge extends StatefulWidget {
  const _SuccessBadge({required this.size});

  final double size;

  @override
  State<_SuccessBadge> createState() => _SuccessBadgeState();
}

class _SuccessBadgeState extends State<_SuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _rings = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pop.isAnimating && !_pop.isCompleted) {
      if (onboardingMotionEnabled(context)) {
        _pop.forward();
        _rings.repeat();
      } else {
        _pop.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = onboardingMotionEnabled(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (animate)
            AnimatedBuilder(
              animation: _rings,
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPairPainter(phase: _rings.value),
              ),
            ),
          ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(parent: _pop, curve: ShuroMotion.spring)),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF34D399), Color(0xFF059669)],
                ),
              ),
              child: AnimatedBuilder(
                animation: _pop,
                builder: (context, _) => CustomPaint(
                  painter: _CheckDrawPainter(
                    progress: Curves.easeOut.transform(
                        ((_pop.value - 0.45) / 0.55).clamp(0.0, 1.0)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two soft green rings expanding out of phase, like the board's `ring`
/// loop pair.
class _RingPairPainter extends CustomPainter {
  final double phase;

  _RingPairPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final t = Curves.easeOut.transform((phase + i * 0.5) % 1.0);
      final opacity = (0.35 * (1 - t)).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      canvas.drawCircle(
        center,
        size.width * 0.5 * (1 + 0.9 * t),
        Paint()
          ..style = PaintingStyle.fill
          ..color = Color.fromARGB((opacity * 255).round(), 52, 211, 153),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPairPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

/// The check mark, drawn as a growing stroke once the pop is past 45%.
class _CheckDrawPainter extends CustomPainter {
  final double progress;

  _CheckDrawPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckDrawPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// The summary card: what's connected, what's skipped, what's set — all
/// read live from the real state, never from what the flow "should" have
/// done. Rows offer their real follow-up action (Set up / Change).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final spoken = context.watch<SpokenLibraryState>();
    final hasServer = appState.hasServer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: kRaisedColor.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.music_note_rounded,
            title: hasServer
                ? (appState.activeServer?.name ?? 'Navidrome')
                : 'Local files',
            subtitle: hasServer
                ? '${appState.activeServer?.url ?? 'Your server'} · '
                    '${appState.catalogSongs.length} songs'
                : 'No server yet — Shuro plays the files on this device.',
            trailing: hasServer
                ? const _ConnectedTag()
                : _PillAction(
                    label: 'Set up',
                    onTap: () =>
                        pushDrillDownOnce(context, const ServerSetupScreen())),
            showDivider: false,
          ),
          _SummaryRow(
            icon: Icons.menu_book_rounded,
            title: 'Audiobookshelf',
            subtitle: spoken.connection != null
                ? '${spoken.connection?.name} · ${spoken.libraries.length} libraries'
                : 'Skipped for now. Add it any time in Settings.',
            trailing: spoken.connection != null
                ? const _ConnectedTag()
                : _PillAction(
                    label: 'Set up',
                    onTap: () => pushDrillDownOnce(
                        context, const AudiobookshelfSetupScreen()),
                  ),
          ),
          _FutureSoundRow(),
        ],
      ),
    );
  }
}

class _ConnectedTag extends StatelessWidget {
  const _ConnectedTag();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_rounded, size: 15, color: kGreen),
        const SizedBox(width: 4),
        Text(
          'Connected',
          style: onboardingBody(
              color: kGreenLight, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Bordered small action (board "Set up" pill), lifted to a 44 px target.
class _PillAction extends StatelessWidget {
  const _PillAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: kTextColor,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
          minimumSize: const Size(64, 44),
        ),
        child: Text(
          label,
          style: onboardingBody(
              color: kTextColor, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The sound row reads the preset receipt written by step 4 (async prefs),
/// falling back to "defaults kept" when step 4 was skipped.
class _FutureSoundRow extends StatelessWidget {
  const _FutureSoundRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: OnboardingPrefs.soundPreset(),
      builder: (context, snapshot) {
        final preset = soundPresetById(snapshot.data);
        return _SummaryRow(
          icon: Icons.equalizer_rounded,
          title: 'Sound',
          subtitle: preset != null
              ? '${preset.label} preset · ${preset.bullets.first.toLowerCase()}'
              : 'Defaults kept — nothing changed yet.',
          trailing: _PillAction(
            label: 'Change',
            onTap: () => pushDrillDownOnce(context, const SoundPresetScreen()),
          ),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final textTheme = onboardingBody(color: kTextColor, fontSize: 15);
    return Column(
      children: [
        if (showDivider)
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                child: Icon(icon, size: 20, color: kVioletLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: textTheme.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: onboardingBody(
                          color: kStatusText, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: trailing),
            ],
          ),
        ),
      ],
    );
  }
}

/// The board's tip line — the shortcut it names is real (Ctrl+K opens the
/// command palette on desktop; long-press opens song options on touch).
class _TipRow extends StatelessWidget {
  const _TipRow({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Text('Tip: press',
              style: onboardingBody(color: kMuted2, fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Ctrl K',
                style: onboardingBody(
                    color: const Color(0xFFC9CEDB),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Text('to search everything, and right-click any song for options.',
              style: onboardingBody(color: kMuted2, fontSize: 13)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: kMuted2),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Tip: long-press any song for options, and add a music folder from Library → Local files.',
            style: onboardingBody(color: kMuted2, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

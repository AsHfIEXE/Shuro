import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/download_state.dart' show StreamingQuality;
import '../../services/playback_prefs.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import 'all_set_screen.dart';
import 'onboarding_chrome.dart';

/// Step 4 of onboarding (board "Onboarding4") — "How do you like to
/// listen?" Three starting points: Balanced / Pure / Battery saver.
///
/// There is no separate "preset" engine behind this screen: each card maps
/// onto settings that already exist and already do something —
/// [AppState]'s persisted playback settings (gapless, ReplayGain toggles,
/// streaming/download quality, Wi-Fi-only downloads) and [PlaybackPrefs]
/// (the live fade / replay-gain / skip-silence values the player reads).
/// Nothing here is final; every control also lives in Settings.
class SoundPresetScreen extends StatefulWidget {
  const SoundPresetScreen({super.key});

  @override
  State<SoundPresetScreen> createState() => _SoundPresetScreenState();
}

class _SoundPresetScreenState extends State<SoundPresetScreen> {
  String _selected = 'balanced';

  void _select(String id) => setState(() => _selected = id);

  /// Applies the picked preset using only real, existing setters. The
  /// balanced preset equals the app's defaults, so a first-run pick mostly
  /// writes the same values back — that's the point of "Balanced".
  Future<void> _applyAndContinue() async {
    final appState = context.read<AppState>();
    final playbackPrefs = context.read<PlaybackPrefs>();
    switch (_selected) {
      case 'balanced':
        appState.toggleSetting(() {
          appState.gaplessPlayback = true;
          appState.replayGain = true;
        });
        await playbackPrefs.setReplayGain(true);
        await playbackPrefs.setCrossfadeSeconds(0);
        await playbackPrefs.setSkipSilence(false);
        appState.updateWifiQuality(StreamingQuality.original);
      case 'pure':
        appState.toggleSetting(() {
          appState.gaplessPlayback = true;
          appState.replayGain = false;
          appState.volumeNormalization = false;
        });
        await playbackPrefs.setReplayGain(false);
        await playbackPrefs.setCrossfadeSeconds(0);
        await playbackPrefs.setSkipSilence(false);
        appState.updateWifiQuality(StreamingQuality.original);
        appState.updateMobileQuality(StreamingQuality.original);
      case 'battery':
        appState.toggleSetting(() {
          appState.downloadWifiOnly = true;
        });
        appState.updateMobileQuality(StreamingQuality.medium);
        appState.updateDownloadQuality(StreamingQuality.medium);
    }
    await OnboardingPrefs.saveSoundPreset(_selected);
    if (!mounted) return;
    pushDrillDownOnce(context, const AllSetScreen());
  }

  void _skip() {
    // Skip keeps whatever the current settings are; nothing is written.
    pushDrillDownOnce(context, const AllSetScreen());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardsInRow = width >= 820;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Stack(
        children: [
          const OnboardingBlobs(),
          SafeArea(
            child: Column(
              children: [
                const OnboardingHeader(currentStep: 3),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Entrance(
                              child: const StepEyebrow(
                                  label: 'STEP 4 OF 5 · SOUND'),
                            ),
                            const SizedBox(height: 12),
                            Entrance(
                              delay: const Duration(milliseconds: 80),
                              child:
                                  const StepTitle('How do you like to listen?'),
                            ),
                            const SizedBox(height: 8),
                            Entrance(
                              delay: const Duration(milliseconds: 140),
                              child: Text(
                                'Pick a starting point. Every control is still in '
                                'Settings → Audio and EQ, so nothing here is final.',
                                style: onboardingBody(
                                    color: kNavText, fontSize: 16, height: 1.5),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (cardsInRow)
                              // Stretch needs a bounded height; inside the
                              // scroll view it is infinite, so measure the
                              // tallest card instead.
                              IntrinsicHeight(
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0;
                                      i < kSoundPresets.length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(width: 16),
                                    Expanded(
                                      child: Entrance(
                                        delay: Entrance.stagger(i),
                                        child: _PresetCard(
                                          preset: kSoundPresets[i],
                                          selected:
                                              _selected == kSoundPresets[i].id,
                                          onTap: () =>
                                              _select(kSoundPresets[i].id),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              )
                            else
                              Column(
                                children: [
                                  for (var i = 0; i < kSoundPresets.length; i++)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Entrance(
                                        delay: Entrance.stagger(i),
                                        child: _PresetCard(
                                          preset: kSoundPresets[i],
                                          selected:
                                              _selected == kSoundPresets[i].id,
                                          onTap: () =>
                                              _select(kSoundPresets[i].id),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 24),
                            Entrance(
                              delay: const Duration(milliseconds: 440),
                              child: _SignalPathCard(presetId: _selected),
                            ),
                            const SizedBox(height: 24),
                            Entrance(
                              delay: const Duration(milliseconds: 500),
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const BackTextButton(),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: _skip,
                                        style: TextButton.styleFrom(
                                          foregroundColor: kMuted2,
                                          minimumSize: const Size(44, 44),
                                        ),
                                        child: Text(
                                          'Decide later — keep current settings',
                                          style: onboardingBody(
                                              color: kMuted2,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                  PrimaryPill(
                                    label: 'Continue',
                                    onPressed: _applyAndContinue,
                                  ),
                                ],
                              ),
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
        ],
      ),
    );
  }
}

/// One preset card: icon chip, title (+ RECOMMENDED badge on Balanced),
/// tagline and three check bullets. Selected = 2 px violet border on a
/// violet wash, with a springing check badge (reduced-motion: no spring).
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final SoundPresetData preset;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (preset.id) {
      case 'pure':
        return Icons.equalizer_rounded;
      case 'battery':
        return Icons.battery_saver_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      enabled: !selected,
      radius: BorderRadius.circular(20),
      child: Material(
        color: selected
            ? kBrandColor.withValues(alpha: 0.14)
            : kRaisedColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? kBrandColor
                    : Colors.white.withValues(alpha: 0.10),
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      child: Icon(_icon, size: 24, color: kVioletLight),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          preset.label,
                          style: headingFont(
                              color: kTextColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w800),
                        ),
                        if (preset.recommended)
                          Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: ShapeDecoration(
                              color: kBrandColor.withValues(alpha: 0.3),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              'RECOMMENDED',
                              style: onboardingBody(
                                color: kVioletPale,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(preset.tagline,
                        style:
                            onboardingBody(color: kStatusText, fontSize: 13)),
                    const SizedBox(height: 12),
                    for (final bullet in preset.bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: kMuted2),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                bullet,
                                style: onboardingBody(
                                    color: kNavText,
                                    fontSize: 13,
                                    height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: selected
                        ? Container(
                            key: const ValueKey('badge'),
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBrandColor,
                            ),
                            child: const Icon(Icons.check_rounded,
                                size: 14, color: Colors.white),
                          )
                        : const SizedBox(key: ValueKey('nobadge')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Signal path for this preset" card: six nodes on a line with a
/// travelling light. Node states come from what the preset actually turns
/// on, so the picture never claims processing that isn't armed.
class _SignalPathCard extends StatelessWidget {
  const _SignalPathCard({required this.presetId});

  final String presetId;

  @override
  Widget build(BuildContext context) {
    final nodes = _nodesFor(presetId);
    return GlassPanel(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.headset_rounded, size: 20, color: kVioletLight),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Signal path for this preset',
                    style: onboardingBody(
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              Text(
                'Shuro only says "bit-perfect" when your device confirms it',
                style: onboardingBody(color: kStatusText, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SignalLine(nodes: nodes),
        ],
      ),
    );
  }

  List<_SignalNodeData> _nodesFor(String presetId) {
    switch (presetId) {
      case 'pure':
        return const [
          _SignalNodeData('Stream', 'original', true),
          _SignalNodeData('Decode', 'float', true),
          _SignalNodeData('ReplayGain', 'off', false),
          _SignalNodeData('EQ', 'off', false),
          _SignalNodeData('Limiter', 'off', false),
          _SignalNodeData('Output', 'active', true),
        ];
      case 'battery':
        return const [
          _SignalNodeData('Stream', '160 kbps cap', true),
          _SignalNodeData('Decode', 'float', true),
          _SignalNodeData('ReplayGain', 'on', true),
          _SignalNodeData('EQ', 'off', false),
          _SignalNodeData('Limiter', 'off', false),
          _SignalNodeData('Output', 'active', true),
        ];
      default:
        return const [
          _SignalNodeData('Stream', 'original', true),
          _SignalNodeData('Decode', 'float', true),
          _SignalNodeData('ReplayGain', 'on', true),
          _SignalNodeData('EQ', 'off', false),
          _SignalNodeData('Limiter', 'off', false),
          _SignalNodeData('Output', 'active', true),
        ];
    }
  }
}

class _SignalNodeData {
  const _SignalNodeData(this.label, this.caption, this.active);

  final String label;
  final String caption;
  final bool active;
}

/// The nodes plus the connecting line and its travelling light. The light
/// is a decorative loop and stands still under reduced motion. Node width
/// derives from the available width (clamped to the board's 110), so the
/// six nodes never overflow a narrow window.
class _SignalLine extends StatefulWidget {
  const _SignalLine({required this.nodes});

  final List<_SignalNodeData> nodes;

  @override
  State<_SignalLine> createState() => _SignalLineState();
}

class _SignalLineState extends State<_SignalLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = onboardingMotionEnabled(context);
    // No LayoutBuilder here: the preset row sits in an IntrinsicHeight, which
    // cannot measure a LayoutBuilder (it threw and blanked the whole step).
    // The card's inner width is derived from the screen instead.
    final screen = MediaQuery.sizeOf(context).width;
    final content = (screen - 64).clamp(0.0, 1040.0);
    final inner = (screen >= 820 ? (content - 32) / 3 : content) - 40;
    {
      final nodeWidth = (inner / widget.nodes.length).clamp(44.0, 110.0);
      return SizedBox(
        height: nodeWidth < 88 ? 58 : 64,
        child: AnimatedBuilder(
          animation: animate ? _flow : const AlwaysStoppedAnimation<double>(0),
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < widget.nodes.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: _connector(
                      context,
                      active:
                          widget.nodes[i - 1].active && widget.nodes[i].active,
                      flow: _flow.value,
                      flowOn: animate,
                    ),
                  ),
                _node(context, widget.nodes[i], nodeWidth),
              ],
            ],
          ),
        ),
      );
    }
  }

  Widget _connector(BuildContext context,
      {required bool active, required double flow, required bool flowOn}) {
    return SizedBox(
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          if (flowOn && active)
            FractionallySizedBox(
              widthFactor: 1,
              child: Align(
                alignment: Alignment(-1 + flow * 2, 0),
                child: Container(
                  width: 60,
                  height: 6,
                  decoration: ShapeDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0x00A78BFA),
                      kVioletLight,
                      Color(0x00A78BFA),
                    ]),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _node(BuildContext context, _SignalNodeData node, double nodeWidth) {
    final compact = nodeWidth < 88;
    return SizedBox(
      width: nodeWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: node.active
                  ? kBrandColor
                  : Colors.white.withValues(alpha: 0.14),
              boxShadow: node.active
                  ? [
                      BoxShadow(
                        color: kBrandColor.withValues(alpha: 0.25),
                        spreadRadius: 5,
                        blurRadius: 0,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            node.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: onboardingBody(
              color: node.active ? kTextColor : kMuted3,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            node.caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: onboardingBody(color: kMuted3, fontSize: compact ? 9 : 11),
          ),
        ],
      ),
    );
  }
}

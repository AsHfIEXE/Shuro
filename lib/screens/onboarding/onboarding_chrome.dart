import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart' show reduceMotionEnabled;

/// Shared chrome for the five onboarding boards (Onboarding 1-5): the
/// 84 px brand/stepper header, the mesh-blob backdrop, and the board-level
/// buttons, fields and panels every step reuses.
///
/// Every decorative loop here stands down when the user asks for reduced
/// motion (Settings → Reduce animations *or* the platform's
/// `disableAnimations`); entrances come from [Entrance] in the motion kit.

/// Whether motion is allowed for this onboarding screen: honours both the
/// app setting (see [reduceMotionEnabled]) and the platform request.
bool onboardingMotionEnabled(BuildContext context) =>
    !reduceMotionEnabled && !MediaQuery.of(context).disableAnimations;

/// Body text helper — Inter (the user's chosen body font) with the boards'
/// sizes and colors, so onboarding matches the rest of the app's type.
TextStyle onboardingBody({
  required Color color,
  required double fontSize,
  FontWeight fontWeight = FontWeight.w400,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.getFont(
    currentFontFamily,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// The five steps, in board order. Kept as plain ints + labels so the
/// header can be used from any step screen without an import cycle.
const List<String> kOnboardingStepLabels = [
  'Welcome',
  'Navidrome',
  'Audiobookshelf',
  'Sound',
  'Ready',
];

/// Onboarding-wide backdrop: the boards' three drifting brand blobs
/// (violet top-left, cyan right, pink bottom) behind every step.
class OnboardingBlobs extends StatelessWidget {
  const OnboardingBlobs({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: MeshBlobs(
          opacity: 0.2,
          blobs: [
            (Color(0xFF7C3AED), Alignment(-0.85, -0.8), 0.62),
            (Color(0xFF00D4FF), Alignment(0.9, -0.35), 0.55),
            (Color(0xFFFF6B9D), Alignment(-0.15, 0.95), 0.6),
          ],
        ),
      ),
    );
  }
}

/// The boards' header: brand at the left, the five-step rail centred,
/// "Need help?" at the right. Below ~900 px the rail collapses to
/// "Step N of 5" so the header never overflows a phone.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.currentStep});

  /// 0-based index of the step being shown (0 = Welcome … 4 = Ready).
  final int currentStep;

  static const double height = 84;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 940;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          children: [
            _brand(context),
            Expanded(
              child: Center(
                child: wide
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _StepRail(currentStep: currentStep),
                      )
                    : Text(
                        'Step ${currentStep + 1} of ${kOnboardingStepLabels.length}',
                        style: onboardingBody(
                          color: kMuted2,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            _help(context, wide),
          ],
        ),
      ),
    );
  }

  Widget _brand(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 34),
        const SizedBox(width: 8),
        Text(
          'Shuro',
          style: headingFont(
            color: kTextColor,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.19,
          ),
        ),
      ],
    );
  }

  Widget _help(BuildContext context, bool withLabel) {
    return TextButton(
      onPressed: () => _showHelpSheet(context),
      style: TextButton.styleFrom(
        foregroundColor: kVioletLight,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.help_outline_rounded, size: 16),
          if (withLabel) ...[
            const SizedBox(width: 4),
            Text(
              'Need help?',
              style: onboardingBody(
                  color: kVioletLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What Shuro can play',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _helpRow(Icons.music_note_rounded, 'Music',
                  'From your Navidrome or any OpenSubsonic server.'),
              const SizedBox(height: 12),
              _helpRow(Icons.menu_book_rounded, 'Books and podcasts',
                  'From an Audiobookshelf server — optional.'),
              const SizedBox(height: 12),
              _helpRow(Icons.folder_rounded, 'Files on this device',
                  'No server needed. Add a folder any time.'),
              const SizedBox(height: 16),
              Text(
                'Every step except this screen is optional, and you can change all of it later in Settings.',
                style:
                    onboardingBody(color: kMuted2, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: kVioletLight),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: onboardingBody(
                      color: kTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: onboardingBody(
                      color: kMuted2, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The full five-step rail (wide windows): 24 px numbered circles with
/// 36×2 connectors. Current = violet with a soft ring; completed = violet
/// with a check; upcoming = white 10%.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < kOnboardingStepLabels.length; i++) ...[
          if (i > 0) _connector(completed: i <= currentStep),
          _step(
            context,
            index: i,
            state: i < currentStep
                ? _StepState.done
                : i == currentStep
                    ? _StepState.current
                    : _StepState.upcoming,
          ),
        ],
      ],
    );
  }

  Widget _connector({required bool completed}) {
    return Container(
      width: 36,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: ShapeDecoration(
        color: completed ? kBrandColor : Colors.white.withValues(alpha: 0.12),
        shape: const StadiumBorder(),
      ),
    );
  }

  Widget _step(BuildContext context,
      {required int index, required _StepState state}) {
    final label = kOnboardingStepLabels[index];
    final isDone = state == _StepState.done;
    final isCurrent = state == _StepState.current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isCurrent
                ? kBrandColor
                : Colors.white.withValues(alpha: 0.10),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: kBrandColor.withValues(alpha: 0.28),
                      spreadRadius: 4,
                      blurRadius: 0,
                    )
                  ]
                : null,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: onboardingBody(
                      color: isCurrent ? Colors.white : kMuted2,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: onboardingBody(
            color: isCurrent
                ? kTextColor
                : isDone
                    ? kVioletPale
                    : kMuted2,
            fontSize: 13,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

enum _StepState { done, current, upcoming }

/// The boards' eyebrow line: 12/700 with .14em tracking in violet, plus an
/// optional pill badge (e.g. "OPTIONAL" on step 3).
class StepEyebrow extends StatelessWidget {
  const StepEyebrow({super.key, required this.label, this.badge});

  final String label;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: onboardingBody(
              color: kVioletLight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.7,
            ),
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: kSecondaryColor.withValues(alpha: 0.14),
              shape: const StadiumBorder(),
            ),
            child: Text(
              badge!,
              style: onboardingBody(
                color: const Color(0xFF67E8F9),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Board headline: Sora 800 with -.03em tracking; size clamps down for
/// narrow windows so it never wraps into an overflow.
class StepTitle extends StatelessWidget {
  const StepTitle(this.text, {super.key, this.maxFontSize = 42});

  final String text;
  final double maxFontSize;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = width >= 900
        ? maxFontSize
        : width >= 600
            ? 32.0
            : 27.0;
    return Text(
      text,
      style: headingFont(
        color: kTextColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: fontSize * -0.03,
        height: 1.14,
      ),
    );
  }
}

/// Primary pill (board `.btn`): 50 high, radius 999, violet gradient.
class PrimaryPill extends StatelessWidget {
  const PrimaryPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: active ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandColor,
          disabledBackgroundColor: kGlass,
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF7F879A),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(
                    color: active ? Colors.white : const Color(0xFF7F879A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon,
                size: 18,
                color: active ? Colors.white : const Color(0xFF7F879A)),
          ],
        ),
      ),
    );
  }
}

/// Secondary pill (board `.btn` ghost): 50 high, hairline border on glass.
class SecondaryPill extends StatelessWidget {
  const SecondaryPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: kTextColor,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: kTextColor),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(
                    color: kTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet back control (board "Back"): 44+ target, muted text. Pops the
/// current step when no explicit callback is given.
class BackTextButton extends StatelessWidget {
  const BackTextButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(
          foregroundColor: kStatusText,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(44, 44),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 16),
            const SizedBox(width: 4),
            Text(
              'Back',
              style: onboardingBody(
                  color: kStatusText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled input in board style: 13/600 label, 48-high field with a
/// leading icon, #151B26 fill, hairline border, radius 12.
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.leading,
    this.trailing,
    this.obscure = false,
    this.keyboardType,
    this.helper,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? leading;
  final Widget? trailing;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? helper;
  final List<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: onboardingBody(
                color: const Color(0xFFC9CEDB),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            style: onboardingBody(color: kTextColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: onboardingBody(color: kMuted3, fontSize: 15),
              prefixIcon: leading == null
                  ? null
                  : Icon(leading, size: 18, color: kStatusText),
              suffixIcon: trailing,
              filled: true,
              fillColor: kRaisedColor.withValues(alpha: 0.9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              border: inputBorder,
              enabledBorder: inputBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kVioletLight, width: 1.4),
              ),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: onboardingBody(color: kMuted2, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// The states the board's connection status line moves through.
enum StatusPhase { idle, working, success, error }

/// The board's connection status line: idle dot / spinner / green check /
/// red alert, cross-fading between states inside a fixed 44 px slot.
class ConnectionStatusLine extends StatelessWidget {
  const ConnectionStatusLine({
    super.key,
    required this.phase,
    this.idleText = 'Not tested yet',
    this.workingText,
    this.successText,
    this.errorText,
  });

  final StatusPhase phase;
  final String idleText;
  final String? workingText;
  final String? successText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    switch (phase) {
      case StatusPhase.working:
        content = Row(
          key: const ValueKey('working'),
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: kVioletLight),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                workingText ?? 'Contacting server…',
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(
                    color: const Color(0xFFC9CEDB), fontSize: 14),
              ),
            ),
          ],
        );
      case StatusPhase.success:
        content = Row(
          key: const ValueKey('success'),
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withValues(alpha: 0.18),
              ),
              child: const Icon(Icons.check_rounded, size: 14, color: kGreen),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                successText ?? 'Connected',
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(
                    color: kGreenLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      case StatusPhase.error:
        content = Row(
          key: const ValueKey('error'),
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 20, color: Colors.redAccent),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                errorText ?? 'Connection failed',
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(
                    color: Colors.redAccent.shade100,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      case StatusPhase.idle:
        content = Row(
          key: const ValueKey('idle'),
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const ShapeDecoration(
                  color: Color(0xFF5B6378), shape: CircleBorder()),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                idleText,
                overflow: TextOverflow.ellipsis,
                style: onboardingBody(color: kMuted2, fontSize: 14),
              ),
            ),
          ],
        );
    }
    return SizedBox(
      height: 44,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
  }
}

/// The glass side panel every board uses: radius 20, #151B26 at 78%,
/// hairline border, 24 px padding.
class GlassPanel extends StatelessWidget {
  const GlassPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kRaisedColor.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: child,
    );
  }
}

/// One gradient art tile (the welcome floats / the "your library" mosaic).
class GradientTile extends StatelessWidget {
  const GradientTile({super.key, required this.colors, this.radius = 14});

  final List<Color> colors;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35), blurRadius: 24),
          ],
        ),
      ),
    );
  }
}

/// The board palette's six artwork gradients.
const List<List<Color>> kOnboardingArtGradients = [
  [Color(0xFFFF6B9D), Color(0xFF7C3AED)],
  [Color(0xFF2DD4BF), Color(0xFF0E7490)],
  [Color(0xFFF59E0B), Color(0xFFBE123C)],
  [Color(0xFF60A5FA), Color(0xFF1E3A8A)],
  [Color(0xFF34D399), Color(0xFF065F46)],
  [Color(0xFF4C1D95), Color(0xFF0B0F14)],
];

/// The sound-preset choice made during onboarding, remembered so the
/// "All set" summary (and only that) can report what was configured.
/// The preset itself is applied to real settings the moment it is picked;
/// this key is just the receipt.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const String soundPresetKey = 'shuro_onboarding_sound_preset_v1';

  static Future<void> saveSoundPreset(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(soundPresetKey, id);
    } catch (_) {
      // No storage on this platform: the summary just won't recall it.
    }
  }

  static Future<String?> soundPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(soundPresetKey);
    } catch (_) {
      return null;
    }
  }
}

/// The three board presets (Onboarding 4), as data. What each one actually
/// changes lives with the screen that applies it; this is the shared
/// vocabulary between step 4 and the step 5 summary.
class SoundPresetData {
  const SoundPresetData({
    required this.id,
    required this.label,
    required this.tagline,
    required this.bullets,
    this.recommended = false,
  });

  final String id;
  final String label;
  final String tagline;
  final List<String> bullets;
  final bool recommended;
}

const List<SoundPresetData> kSoundPresets = [
  SoundPresetData(
    id: 'balanced',
    label: 'Balanced',
    tagline: 'Great for most setups',
    recommended: true,
    bullets: [
      'Gapless playback on',
      "Loudness normalised from your server's tags",
      'Original quality on Wi-Fi',
    ],
  ),
  SoundPresetData(
    id: 'pure',
    label: 'Pure',
    tagline: 'For a DAC or good headphones',
    bullets: [
      'No loudness processing, no fades',
      'Silence skipping off',
      'Original quality on every connection',
    ],
  ),
  SoundPresetData(
    id: 'battery',
    label: 'Battery saver',
    tagline: 'For phones and long trips',
    bullets: [
      'Mobile streams capped at 160 kbps',
      'Downloads on Wi-Fi only',
      'Download quality capped to save space',
    ],
  ),
];

SoundPresetData? soundPresetById(String? id) {
  if (id == null) return null;
  for (final preset in kSoundPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

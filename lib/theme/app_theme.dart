import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shuro's brand palette — from the identity board: Primary #7C3AED,
/// Secondary #00D4FF, Accent #FF6B9D, Dark #0B0F14, Surface #1A1F2B,
/// Text #E8E8F0.
const kSurfaceColor = Color(0xFF0B0F14);
const kCardColor = Color(0xFF1A1F2B);
const kTextColor = Color(0xFFE8E8F0);
/// Muted body text. This was `Colors.white38`, which measures roughly 3.0–3.6:1
/// against the app's surface colours — under the 4.5:1 AA bar for body text,
/// and it was used for subtitles everywhere. `white54` lands at ~5.9:1 on
/// [kSurfaceColor] while still reading as secondary.
const kMutedTextColor = Colors.white54;
const kDividerColor = Colors.white12;

const kBrandColor = Color(0xFF7C3AED);
const kSecondaryColor = Color(0xFF00D4FF);
const kAccentColor = Color(0xFFFF6B9D);
const kBrandGradient = [kBrandColor, kSecondaryColor];

// --- Redesign palette (shuro-ui-handoff/tokens/new_tokens.dart) ------------
/// Sidebar surface — one step above the app background.
const kSidebarColor = Color(0xFF0E131B);
/// Raised card surface (account card, toolbar pills): #151B26.
const kRaisedColor = Color(0xFF151B26);
/// Muted text tones from the boards: #8B93A7 (labels) and #6F7890 (captions).
const kNavText = Color(0xFFB4BBCB);
const kMuted2 = Color(0xFF8B93A7);
const kMuted3 = Color(0xFF6F7890);
const kStatusText = Color(0xFF9AA3B5);
/// Brand tints used across the redesign (violet + pink families).
const kVioletLight = Color(0xFFA78BFA);
const kVioletPale = Color(0xFFC4B5FD);
const kPinkLight = Color(0xFFFF8FB8);
const kPinkPale = Color(0xFFF9A8D4);
/// Success green (quality chips, "Word-synced", completed downloads).
const kGreen = Color(0xFF34D399);
const kGreenLight = Color(0xFF6EE7B7);
/// Hairline borders (white 7%) and glass fills (white 8%).
final kHairline = Colors.white.withValues(alpha: 0.07);
final kGlass = Colors.white.withValues(alpha: 0.08);

/// Ring-scrub progress gradient (NPV, mini player ring) — fixed by design.
const kRingProgress = [kPinkLight, kVioletLight];

/// Motion curves + durations from the redesign motion pass.
class ShuroMotion {
  const ShuroMotion._();
  /// std = cubic(.2,.8,.2,1)
  static const std = Cubic(0.2, 0.8, 0.2, 1);
  /// spring = cubic(.34,1.56,.64,1)
  static const spring = Cubic(0.34, 1.56, 0.64, 1);
  static const lineChange = Duration(milliseconds: 260);
  static const autoscroll = Duration(milliseconds: 480);
}

/// Curated Google Fonts offered in Settings → Appearance → Font (body
/// text). Inter is the brand's body face and the default; Sora — the
/// brand's heading face — is also selectable if someone wants the whole
/// app in one typeface.
const List<String> kAvailableFonts = [
  'Inter',
  'Sora',
  'Poppins',
  'Roboto',
  'Montserrat',
  'Nunito',
  'Manrope',
  'Outfit',
];

/// The app's current body-font choice — every ordinary text style reads
/// this via `GoogleFonts.getFont(currentFontFamily, ...)` rather than a
/// hardcoded family, so Settings → Font applies everywhere at once. See
/// AppState.updateFontFamily, which updates this and forces a full app
/// remount so already-built widgets pick it up.
String currentFontFamily = 'Inter';

/// The brand's heading face, fixed regardless of the body-font setting —
/// used for section titles, the wordmark, and other "headline" moments,
/// via [headingFont] below. Kept separate from [currentFontFamily] on
/// purpose: Sora + a user-chosen body face is the brand's actual type
/// pairing, not an accident of the font picker.
const kHeadingFontFamily = 'Sora';

TextStyle headingFont({required Color color, required double fontSize, FontWeight fontWeight = FontWeight.w600, double? letterSpacing, double? height}) {
  return GoogleFonts.getFont(kHeadingFontFamily, color: color, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: height);
}

ThemeData buildAppTheme({String fontFamily = 'Inter'}) {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kSurfaceColor,
    textTheme: GoogleFonts.getTextTheme(fontFamily, base.textTheme),
    colorScheme: base.colorScheme.copyWith(surface: kSurfaceColor, primary: kBrandColor, secondary: kSecondaryColor),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kBrandColor : Colors.white70,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kBrandColor.withValues(alpha: 0.5) : Colors.white24,
      ),
    ),
    dividerColor: kDividerColor,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}

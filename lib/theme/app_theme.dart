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
      thumbColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.selected) ? kBrandColor : Colors.white70,
      ),
      trackColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.selected) ? kBrandColor.withOpacity(0.5) : Colors.white24,
      ),
    ),
    dividerColor: kDividerColor,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}

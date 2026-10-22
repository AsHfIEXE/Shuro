import 'package:flutter/foundation.dart';

import '../services/app_persistence.dart';

/// How the Now Playing and Lyrics screens paint their background.
enum BackgroundStyle {
  /// The animated blurred-artwork backdrop (Apple-Music-like).
  animatedBlur,

  /// A static gradient built from the track's own artwork palette — no blur, no
  /// motion, no per-frame work. The cheaper, calmer option, and the one to pick
  /// on a device where animation costs more than it gives.
  staticArtwork,

  /// The same artwork palette, but alive: a gradient that drifts and slowly
  /// rotates. No image decoding and no blur — the motion is a shader rotation
  /// over three colours, so it sits between the other two in cost while giving
  /// the screen continuous, gentle life.
  animatedGradient,
}

/// How the lyrics screen highlights the line being sung.
enum LyricsHighlight {
  /// Word/syllable fill: the syllable being sung lights up inside the line
  /// (the karaoke look). Uses real word timings when the lyrics have them and
  /// estimates within the line otherwise.
  word,

  /// Line by line: the whole current line lights up at its start time, the
  /// rest stay dim; no within-line fill at all. Calmer, and the honest choice
  /// when only line timings exist.
  line,
}

/// How the backdrop is allowed to move. The default is the designed setting;
/// the other two exist because motion taste is personal and this screen is
/// where people stare longest.
enum BackdropMotion {
  /// No idle motion at all — the artwork sits still (a track change still
  /// crossfades; that's information, not decoration).
  still,

  /// Barely-there motion: slower and shallower than designed.
  subtle,

  /// The designed breathe.
  normal,

  /// Faster and more visible — for people who want the background obviously
  /// alive.
  lively,
}

/// Appearance preferences that live outside [AppState].
///
/// Why not AppState: it is the natural owner, but that file cannot be written in
/// this workspace (see the report's blocked-items section — the write guard
/// rejects a pre-existing line in it). These are a handful of view preferences
/// with no dependencies on the catalogue, so they persist themselves through the
/// same [AppPersistence] wrapper, and folding them into AppState later is a
/// copy-paste rather than a refactor.
class AppearanceSettings extends ChangeNotifier {
  static const String _kBackgroundStyle = 'appearance_background_style_v1';
  static const String _kImmersive = 'appearance_immersive_v1';
  static const String _kKaraokeSweep = 'appearance_karaoke_sweep_v1';
  static const String _kBlurScale = 'appearance_blur_scale_v1';
  static const String _kMotion = 'appearance_motion_v1';
  static const String _kLyricsHighlight = 'appearance_lyrics_highlight_v1';
  static const String _kLyricsFontScale = 'appearance_lyrics_font_scale_v1';
  static const String _kLyricsAlignCenter = 'appearance_lyrics_align_center_v1';
  static const String _kLyricsGlow = 'appearance_lyrics_glow_v1';

  /// Blurred by default: it is the look the app is designed around, and the
  /// static option exists as a deliberate choice rather than a fallback.
  BackgroundStyle backgroundStyle = BackgroundStyle.animatedBlur;

  /// Hide the status/navigation bars while Now Playing or Lyrics is open —
  /// the "immersive screens" toggle. Scoped to those screens; the rest of the
  /// app restores the normal bars on the way out.
  bool immersiveScreens = false;

  /// How the sung words fill in on the lyrics screen. Kept as a stored
  /// preference name only for migration cleanliness; the renderer is now a
  /// single per-syllable colour fill for everyone (the shader-sweep experiment
  /// was removed — see lyrics_screen.dart).
  @Deprecated('Single karaoke renderer now; kept so old stored values parse')
  bool karaokeSweep = true;

  /// Whether the lyrics screen fills word by word or highlights whole lines.
  LyricsHighlight lyricsHighlight = LyricsHighlight.word;

  /// Multiplier on the backdrop's blur radius. Default 0.6: sharper artwork
  /// with more visible motion, per the owner's tuning.
  double backdropBlurScale = 0.6;

  /// Idle-motion level for the backdrop.
  BackdropMotion backdropMotion = BackdropMotion.normal;

  // --- Lyrics appearance (roadmap #27) ------------------------------------
  // Owned here so Now Playing, Lyrics and the desktop lyrics pane all read
  // one source of truth; every field persists.

  /// Text size multiplier for lyric lines. 1.0 is the designed size; the
  /// slider range is clamped so the largest step still fits a narrow phone.
  double lyricsFontScale = 1.0;

  /// Centre lyric lines (the designed look). Off reads as left-aligned.
  bool lyricsAlignCenter = true;

  /// Accent glow behind the line being sung. Off is a flatter, quieter read.
  bool lyricsGlow = true;

  AppPersistence? _persistence;

  Future<void> restore() async {
    try {
      final persistence = await AppPersistence.load();
      _persistence = persistence;
      final styleName = persistence.getString(_kBackgroundStyle);
      if (styleName != null) {
        backgroundStyle = BackgroundStyle.values.firstWhere(
          (s) => s.name == styleName,
          orElse: () => backgroundStyle,
        );
      }
      immersiveScreens = persistence.getBool(_kImmersive) ?? immersiveScreens;
      karaokeSweep = persistence.getBool(_kKaraokeSweep) ?? karaokeSweep;
      final blur = double.tryParse(persistence.getString(_kBlurScale) ?? '');
      if (blur != null) backdropBlurScale = blur.clamp(0.4, 2.0).toDouble();
      final motion = persistence.getString(_kMotion);
      if (motion != null) {
        backdropMotion = BackdropMotion.values.firstWhere((m) => m.name == motion, orElse: () => backdropMotion);
      }
      final highlight = persistence.getString(_kLyricsHighlight);
      if (highlight != null) {
        lyricsHighlight = LyricsHighlight.values.firstWhere((h) => h.name == highlight, orElse: () => lyricsHighlight);
      }
      final fontScale = double.tryParse(persistence.getString(_kLyricsFontScale) ?? '');
      if (fontScale != null) lyricsFontScale = fontScale.clamp(0.85, 1.5).toDouble();
      lyricsAlignCenter = persistence.getBool(_kLyricsAlignCenter) ?? lyricsAlignCenter;
      lyricsGlow = persistence.getBool(_kLyricsGlow) ?? lyricsGlow;
      notifyListeners();
    } catch (_) {
      // No storage on this platform: keep the defaults rather than failing
      // startup over a view preference.
    }
  }

  Future<void> setBackgroundStyle(BackgroundStyle style) async {
    if (backgroundStyle == style) return;
    backgroundStyle = style;
    notifyListeners();
    await _persistence?.setString(_kBackgroundStyle, style.name);
  }

  Future<void> setImmersiveScreens(bool value) async {
    if (immersiveScreens == value) return;
    immersiveScreens = value;
    notifyListeners();
    await _persistence?.setBool(_kImmersive, value);
  }

  Future<void> setKaraokeSweep(bool value) async {
    if (karaokeSweep == value) return;
    karaokeSweep = value;
    notifyListeners();
    await _persistence?.setBool(_kKaraokeSweep, value);
  }

  Future<void> setLyricsFontScale(double value) async {
    final clamped = value.clamp(0.85, 1.5).toDouble();
    if (lyricsFontScale == clamped) return;
    lyricsFontScale = clamped;
    notifyListeners();
    await _persistence?.setString(_kLyricsFontScale, clamped.toString());
  }

  Future<void> setLyricsAlignCenter(bool value) async {
    if (lyricsAlignCenter == value) return;
    lyricsAlignCenter = value;
    notifyListeners();
    await _persistence?.setBool(_kLyricsAlignCenter, value);
  }

  Future<void> setLyricsGlow(bool value) async {
    if (lyricsGlow == value) return;
    lyricsGlow = value;
    notifyListeners();
    await _persistence?.setBool(_kLyricsGlow, value);
  }

  Future<void> setBackdropBlurScale(double value) async {
    final clamped = value.clamp(0.4, 2.0).toDouble();
    if (backdropBlurScale == clamped) return;
    backdropBlurScale = clamped;
    notifyListeners();
    await _persistence?.setString(_kBlurScale, clamped.toString());
  }

  Future<void> setBackdropMotion(BackdropMotion value) async {
    if (backdropMotion == value) return;
    backdropMotion = value;
    notifyListeners();
    await _persistence?.setString(_kMotion, value.name);
  }

  Future<void> setLyricsHighlight(LyricsHighlight value) async {
    if (lyricsHighlight == value) return;
    lyricsHighlight = value;
    notifyListeners();
    await _persistence?.setString(_kLyricsHighlight, value.name);
  }

  String get lyricsHighlightLabel => switch (lyricsHighlight) {
        LyricsHighlight.word => 'Word by word',
        LyricsHighlight.line => 'Line by line',
      };

  String get backdropBlurLabel => switch (backdropBlurScale) {
        < 0.45 => 'Sharp artwork',
        < 0.8 => 'Balanced (default)',
        < 1.3 => 'Softer blur',
        _ => 'Dreamy',
      };

  String get backdropMotionLabel => switch (backdropMotion) {
        BackdropMotion.still => 'Still',
        BackdropMotion.subtle => 'Subtle',
        BackdropMotion.normal => 'Normal (default)',
        BackdropMotion.lively => 'Fast',
      };

  String get backgroundStyleLabel => switch (backgroundStyle) {
        BackgroundStyle.animatedBlur => 'Animated blur',
        BackgroundStyle.animatedGradient => 'Animated gradient',
        BackgroundStyle.staticArtwork => 'Static artwork colours',
      };
}

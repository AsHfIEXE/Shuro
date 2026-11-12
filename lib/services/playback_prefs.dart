import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playback preferences that map onto real player behaviour:
///
///  * **Fade between songs** — a volume fade over the last seconds of a track
///    (an honest fade transition; true overlapping crossfade needs a second
///    player and is a documented next step);
///  * **Replay gain** — per-track loudness normalisation from the server's own
///    `replayGain.trackGain` tag, applied as playback volume;
///  * **Playback speed** — 0.75×–2×;
///  * **Skip silence** — the engine's own silence-skipping (Android).
///
/// Persisted in SharedPreferences; the player reads the live values via
/// listeners wired in app.dart.
class PlaybackPrefs extends ChangeNotifier {
  static const String _kCrossfade = 'playback_crossfade_seconds_v1';
  static const String _kReplayGain = 'playback_replay_gain_v1';
  static const String _kSpeed = 'playback_speed_v1';
  static const String _kSkipSilence = 'playback_skip_silence_v1';
  static const String _kAppVolume = 'playback_app_volume_v1';

  /// 0 = off. Otherwise the fade length in seconds (2/4/6 in the picker).
  int crossfadeSeconds = 0;

  /// Normalise loudness from the server's ReplayGain tag. On by default: the
  /// owner planned this, and the server already ships the tags.
  bool replayGain = true;

  double playbackSpeed = 1.0;

  bool skipSilence = false;

  /// Shuro's own output level. This is deliberately separate from the OS
  /// media volume: desktop users can lower Shuro without changing the volume
  /// of other applications.
  double appVolume = 1.0;

  static const String _kRgMode = 'playback_rg_mode_v1';
  static const String _kRgPreamp = 'playback_rg_preamp_untagged_v1';
  static const String _kFadePause = 'playback_fade_on_pause_v1';

  /// 'track' or 'album' when [replayGain] is on. The player reads track gain
  /// today; album mode is stored for the engine hook.
  String replayGainMode = 'album';

  /// Pre-amp (dB, -12..+12) for files with no ReplayGain tags. Stored only
  /// until the player applies it.
  double untaggedPreampDb = 0.0;

  /// Short fade when pausing/resuming. Stored only until the player reads it.
  bool fadeOnPause = true;

  bool _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      crossfadeSeconds = prefs.getInt(_kCrossfade) ?? crossfadeSeconds;
      replayGain = prefs.getBool(_kReplayGain) ?? replayGain;
      playbackSpeed = prefs.getDouble(_kSpeed) ?? playbackSpeed;
      skipSilence = prefs.getBool(_kSkipSilence) ?? skipSilence;
      appVolume = (prefs.getDouble(_kAppVolume) ?? appVolume).clamp(0.0, 1.0);
      replayGainMode = prefs.getString(_kRgMode) ?? replayGainMode;
      untaggedPreampDb = prefs.getDouble(_kRgPreamp) ?? untaggedPreampDb;
      fadeOnPause = prefs.getBool(_kFadePause) ?? fadeOnPause;
      notifyListeners();
    } catch (_) {
      // No storage: defaults.
    }
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    if (crossfadeSeconds == seconds) return;
    crossfadeSeconds = seconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCrossfade, seconds);
  }

  Future<void> setReplayGain(bool value) async {
    if (replayGain == value) return;
    replayGain = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReplayGain, value);
  }

  Future<void> setPlaybackSpeed(double value) async {
    if (playbackSpeed == value) return;
    playbackSpeed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSpeed, value);
  }

  Future<void> setSkipSilence(bool value) async {
    if (skipSilence == value) return;
    skipSilence = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSkipSilence, value);
  }

  /// 'off', 'track' or 'album'. 'off' switches [replayGain] off; the mode is
  /// remembered so turning it back on restores the last choice.
  Future<void> setReplayGainMode(String mode) async {
    if (mode != 'off') replayGainMode = mode;
    await setReplayGain(mode != 'off');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRgMode, replayGainMode);
  }

  Future<void> setUntaggedPreampDb(double value) async {
    final next = value.clamp(-12.0, 12.0);
    if (untaggedPreampDb == next) return;
    untaggedPreampDb = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRgPreamp, next);
  }

  Future<void> setFadeOnPause(bool value) async {
    if (fadeOnPause == value) return;
    fadeOnPause = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFadePause, value);
  }

  Future<void> setAppVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    if (appVolume == next) return;
    appVolume = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAppVolume, next);
  }
}

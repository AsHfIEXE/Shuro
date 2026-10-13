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

  /// 0 = off. Otherwise the fade length in seconds (2/4/6 in the picker).
  int crossfadeSeconds = 0;

  /// Normalise loudness from the server's ReplayGain tag. On by default: the
  /// owner planned this, and the server already ships the tags.
  bool replayGain = true;

  double playbackSpeed = 1.0;

  bool skipSilence = false;

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
}

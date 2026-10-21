import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the platform equalizer (Android) and its persisted state.
///
/// Audio is processed by Android's own `AudioEffect` chain attached to the
/// player's `AudioPipeline`, so the effect runs before the mixer — the same
/// class of DSP an audiophile player uses, not a software gain on top of the
/// output. Every value here is applied to the engine and persisted; when the
/// platform has no equalizer (iOS, web, desktop) [supported] is false and the
/// UI says so instead of showing dead sliders.
class EqualizerService extends ChangeNotifier {
  EqualizerService._();

  static final EqualizerService instance = EqualizerService._();

  static const String _kEnabled = 'shuro_eq_enabled_v1';
  static const String _kGains = 'shuro_eq_gains_v1';

  AndroidEqualizer? _effect;
  AndroidEqualizerParameters? _parameters;
  bool _enabled = false;
  final Map<int, double> _gains = {};

  bool get supported => _effect != null;
  bool get enabled => _enabled;
  double gainOf(int band) => _gains[band] ?? 0.0;

  /// Called once when the player is constructed on Android.
  void attach(AndroidEqualizer effect) {
    _effect = effect;
    // Restore HERE, not from main(): main() runs before the PlayerController
    // (and so this effect) exists, so a restore started there saw no effect
    // and returned immediately — saved bands were never loaded or applied.
    unawaited(restore());
  }

  /// Band layout (count, centre frequencies, permitted dB range). Null while
  /// the platform has not answered or when unsupported.
  Future<AndroidEqualizerParameters?> parameters() async {
    final effect = _effect;
    if (effect == null) return null;
    if (_parameters != null) return _parameters;
    try {
      _parameters = await effect.parameters;
      return _parameters;
    } catch (_) {
      return null;
    }
  }

  /// Restores the persisted state and applies it to the engine. Safe to call
  /// before the player has activated: `parameters` waits on the platform.
  Future<void> restore() async {
    if (_effect == null) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    final raw = prefs.getString(_kGains);
    if (raw != null) {
      for (final part in raw.split(',')) {
        final bits = part.split(':');
        if (bits.length != 2) continue;
        final index = int.tryParse(bits[0]);
        final db = double.tryParse(bits[1]);
        if (index != null && db != null) _gains[index] = db;
      }
    }
    notifyListeners();
    final params = await parameters();
    if (params == null) return;
    try {
      await _effect?.setEnabled(_enabled);
      for (final band in params.bands) {
        final db = _gains[band.index] ?? 0.0;
        if (db != 0.0) await band.setGain(db);
      }
    } catch (_) {
      // A missing effect must never take the player down.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      await _effect?.setEnabled(value);
    } catch (_) {}
    await _persist();
  }

  /// Applies a band gain. While a slider is dragged pass `persist: false`
  /// (the engine follows live) and call [commit] on release — otherwise every
  /// drag tick wrote to SharedPreferences.
  Future<void> setGain(int index, double decibels, {bool persist = true}) async {
    _gains[index] = decibels;
    notifyListeners();
    try {
      final params = await parameters();
      if (params != null) {
        // Only the band that was asked for — never fall back to another band.
        for (final band in params.bands) {
          if (band.index == index) {
            await band.setGain(decibels);
            break;
          }
        }
      }
    } catch (_) {}
    if (persist) await _persist();
  }

  /// Persists the current state (call when a slider drag ends).
  Future<void> commit() => _persist();

  Future<void> resetBands() async {
    final params = await parameters();
    if (params == null) return;
    for (final band in params.bands) {
      await setGain(band.index, 0.0, persist: false);
    }
    await commit();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, _enabled);
      final raw = _gains.entries.map((e) => '${e.key}:${e.value}').join(',');
      await prefs.setString(_kGains, raw);
    } catch (_) {}
  }
}

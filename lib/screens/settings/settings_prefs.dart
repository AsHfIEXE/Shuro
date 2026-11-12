import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that belong to the redesigned Settings pages and have no home in
/// [AppState] / [PlaybackPrefs] yet: the new-audio-engine preview controls,
/// per-device audio profiles, Audiobookshelf preferences, per-server flags and
/// desktop window habits.
///
/// Everything is persisted as one JSON document (`settings_extras_v1`). Where
/// the player or a service does not read a value yet, the Settings page says so
/// next to the control; nothing here pretends to change audio on its own.
class SettingsExtras extends ChangeNotifier {
  SettingsExtras._();

  static final SettingsExtras instance = SettingsExtras._();

  static const String _key = 'settings_extras_v1';

  bool _restored = false;
  Future<void>? _restoring;

  // --- Audio engine preview ------------------------------------------------
  /// 'match' or a rate in Hz as text ('44100', '48000', ...).
  String sampleRate = 'match';

  /// 'auto', '16', '24' or '32f'.
  String sampleFormat = 'auto';

  /// Send AC-3 / DTS bitstreams to a receiver untouched.
  bool surroundPassthrough = false;

  /// Lower the pre-amp by the largest EQ boost so peaks do not clip.
  bool autoHeadroom = true;

  /// Safety limiter at -0.1 dBFS.
  bool limiter = true;

  /// Pre-amp applied to tagged files, -24..+12 dB in 0.1 dB steps.
  double rgPreampDb = 0.0;

  /// Name of the EQ preset last loaded or imported ('' = none).
  String eqPresetName = '';

  /// Saved EQ presets: name -> gains by band index, in dB.
  final Map<String, List<double>> eqPresets = {};

  /// 'pure', 'balanced', 'warm' or 'custom'.
  String enginePreset = 'custom';

  /// 'default' or a device name the user pinned (output device row).
  String outputDevice = 'default';

  /// 'system', 'match' or 'exclusive' (Windows only; stored, no engine yet).
  String outputMode = 'system';

  /// Equalizer: master switch, 'graphic' or 'parametric', 10 band gains (dB)
  /// for slots A and B, the slot being edited and the AutoEq pre-amp.
  bool eqOn = false;
  String eqMode = 'graphic';
  String eqSlot = 'a';
  List<double> eqGainsA = List<double>.filled(10, 0.0);
  List<double> eqGainsB = List<double>.filled(10, 0.0);
  double eqPreampDb = 0.0;

  /// Use a separate quality cap on mobile data (else mobile follows Wi-Fi).
  bool mobileCapDifferent = false;

  List<double> get eqGains => eqSlot == 'b' ? eqGainsB : eqGainsA;

  // --- Per-device profiles -------------------------------------------------
  bool profileSwitching = true;

  /// Output device label -> {preset, eqEnabled, preampDb, rgMode}.
  final Map<String, Map<String, dynamic>> deviceProfiles = {};

  // --- Streaming -----------------------------------------------------------
  /// 'opus', 'mp3' or 'aac'. Used only when a cap is set.
  String transcodeFormat = 'opus';

  /// Always request the untouched file on Wi-Fi, whatever the cap says.
  bool preferOriginalOnWifi = false;

  // --- Servers -------------------------------------------------------------
  /// Servers on which self-signed certificates are accepted.
  final Set<String> selfSignedServerIds = {};

  /// Play music stored on this device next to the server library.
  bool showLocalFiles = true;

  // --- Audiobookshelf ------------------------------------------------------
  bool absShowAudiobooks = true;
  bool absShowPodcasts = true;
  bool absSyncProgress = true;
  double absSpeed = 1.0;
  int absSkipBackSeconds = 15;
  int absSkipForwardSeconds = 30;

  // --- Desktop -------------------------------------------------------------
  bool closeToTray = true;
  bool startMinimized = false;

  /// Resolves once the stored values are loaded. Safe to call repeatedly.
  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      sampleRate = map['sampleRate'] as String? ?? sampleRate;
      sampleFormat = map['sampleFormat'] as String? ?? sampleFormat;
      surroundPassthrough =
          map['surroundPassthrough'] as bool? ?? surroundPassthrough;
      autoHeadroom = map['autoHeadroom'] as bool? ?? autoHeadroom;
      limiter = map['limiter'] as bool? ?? limiter;
      rgPreampDb = (map['rgPreampDb'] as num?)?.toDouble() ?? rgPreampDb;
      eqPresetName = map['eqPresetName'] as String? ?? eqPresetName;
      final presets = map['eqPresets'];
      if (presets is Map) {
        eqPresets
          ..clear()
          ..addAll(presets.map((k, v) => MapEntry(k.toString(),
              [for (final g in (v as List)) (g as num).toDouble()])));
      }
      enginePreset = map['enginePreset'] as String? ?? enginePreset;
      outputDevice = map['outputDevice'] as String? ?? outputDevice;
      outputMode = map['outputMode'] as String? ?? outputMode;
      eqOn = map['eqOn'] as bool? ?? eqOn;
      eqMode = map['eqMode'] as String? ?? eqMode;
      eqSlot = map['eqSlot'] as String? ?? eqSlot;
      eqPreampDb = (map['eqPreampDb'] as num?)?.toDouble() ?? eqPreampDb;
      mobileCapDifferent =
          map['mobileCapDifferent'] as bool? ?? mobileCapDifferent;
      for (final (key, target) in [
        ('eqGainsA', eqGainsA),
        ('eqGainsB', eqGainsB)
      ]) {
        final raw = map[key];
        if (raw is List && raw.length == target.length) {
          for (var i = 0; i < target.length; i++) {
            target[i] = (raw[i] as num).toDouble();
          }
        }
      }
      profileSwitching = map['profileSwitching'] as bool? ?? profileSwitching;
      final profiles = map['deviceProfiles'];
      if (profiles is Map) {
        deviceProfiles
          ..clear()
          ..addAll(profiles.map((k, v) => MapEntry(
              k.toString(), Map<String, dynamic>.from(v as Map))));
      }
      transcodeFormat = map['transcodeFormat'] as String? ?? transcodeFormat;
      preferOriginalOnWifi =
          map['preferOriginalOnWifi'] as bool? ?? preferOriginalOnWifi;
      selfSignedServerIds
        ..clear()
        ..addAll(((map['selfSignedServerIds'] as List?) ?? const [])
            .whereType<String>());
      showLocalFiles = map['showLocalFiles'] as bool? ?? showLocalFiles;
      absShowAudiobooks = map['absShowAudiobooks'] as bool? ?? absShowAudiobooks;
      absShowPodcasts = map['absShowPodcasts'] as bool? ?? absShowPodcasts;
      absSyncProgress = map['absSyncProgress'] as bool? ?? absSyncProgress;
      absSpeed = (map['absSpeed'] as num?)?.toDouble() ?? absSpeed;
      absSkipBackSeconds = map['absSkipBackSeconds'] as int? ?? absSkipBackSeconds;
      absSkipForwardSeconds =
          map['absSkipForwardSeconds'] as int? ?? absSkipForwardSeconds;
      closeToTray = map['closeToTray'] as bool? ?? closeToTray;
      startMinimized = map['startMinimized'] as bool? ?? startMinimized;
      notifyListeners();
    } catch (_) {
      // No storage or an old shape: keep the defaults.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'sampleRate': sampleRate,
          'sampleFormat': sampleFormat,
          'surroundPassthrough': surroundPassthrough,
          'autoHeadroom': autoHeadroom,
          'limiter': limiter,
          'rgPreampDb': rgPreampDb,
          'eqPresetName': eqPresetName,
          'eqPresets': eqPresets,
          'enginePreset': enginePreset,
          'outputDevice': outputDevice,
          'outputMode': outputMode,
          'eqOn': eqOn,
          'eqMode': eqMode,
          'eqSlot': eqSlot,
          'eqGainsA': eqGainsA,
          'eqGainsB': eqGainsB,
          'eqPreampDb': eqPreampDb,
          'mobileCapDifferent': mobileCapDifferent,
          'profileSwitching': profileSwitching,
          'deviceProfiles': deviceProfiles,
          'transcodeFormat': transcodeFormat,
          'preferOriginalOnWifi': preferOriginalOnWifi,
          'selfSignedServerIds': selfSignedServerIds.toList(),
          'showLocalFiles': showLocalFiles,
          'absShowAudiobooks': absShowAudiobooks,
          'absShowPodcasts': absShowPodcasts,
          'absSyncProgress': absSyncProgress,
          'absSpeed': absSpeed,
          'absSkipBackSeconds': absSkipBackSeconds,
          'absSkipForwardSeconds': absSkipForwardSeconds,
          'closeToTray': closeToTray,
          'startMinimized': startMinimized,
        }),
      );
    } catch (_) {}
  }

  /// Applies [mutate], notifies and persists. [persist] false is for slider
  /// drags: call again with persist true on release.
  void update(VoidCallback mutate, {bool persist = true}) {
    mutate();
    notifyListeners();
    if (persist) _save();
  }

  void setServerSelfSigned(String serverId, bool on) => update(() {
        if (on) {
          selfSignedServerIds.add(serverId);
        } else {
          selfSignedServerIds.remove(serverId);
        }
      });
}

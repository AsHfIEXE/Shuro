import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'event_log.dart';

/// Owns the one-time choice of audio platform on Android/iOS.
///
/// `JustAudioBackground.init` swaps `JustAudioPlatform.instance` for its own
/// plugin BEFORE it waits for the audio service to answer. If that wait fails
/// or never ends (slow cold start, stale service, OEM restrictions), the app
/// used to carry on "without system media controls" — but the platform stayed
/// swapped to a plugin whose handler never came up, so every later load hung
/// with no engine state at all (the 40 s "load.start with no engine.state"
/// pattern in the diagnostics log). Here a failure or a hard timeout restores
/// the original platform, so playback keeps working without the notification.
class AudioBackend {
  AudioBackend._();

  static final Completer<void> _ready = Completer<void>();
  static bool _started = false;
  static bool _mediaSession = false;

  /// True when the system media session (notification, lock screen) is live.
  static bool get hasMediaSession => _mediaSession;

  /// Completes once the platform is settled. Completes immediately when
  /// [start] was never called (desktop, web, tests).
  static Future<void> get ready => _started ? _ready.future : Future.value();

  static void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Runs [initMediaSession] (normally `JustAudioBackground.init`). Returns
  /// after at most [softWait] so the UI can start; a watchdog keeps running
  /// and falls back to the plain engine after [hardWait] in total.
  static Future<void> start({
    required Future<void> Function() initMediaSession,
    Duration softWait = const Duration(seconds: 8),
    Duration hardWait = const Duration(seconds: 25),
  }) async {
    _started = true;
    final original = JustAudioPlatform.instance;
    var settled = false;

    void fallback(String why) {
      if (settled) return;
      settled = true;
      JustAudioPlatform.instance = original;
      _mediaSession = false;
      PlaybackEventLog.instance.add('backend.fallback', {'why': why});
      debugPrint('[audio] media session unavailable ($why) — plain engine');
      _markReady();
    }

    final init = initMediaSession();
    init.then((_) {
      if (settled) return;
      settled = true;
      _mediaSession = true;
      PlaybackEventLog.instance.add('backend.ready');
      _markReady();
    }, onError: (Object error) {
      fallback('init failed: ${error.runtimeType}');
    });
    Timer(hardWait, () => fallback('init pending ${hardWait.inSeconds}s'));

    try {
      await _ready.future.timeout(softWait);
    } on TimeoutException {
      // Keep going: the UI starts now, loads wait for [ready].
    }
  }
}

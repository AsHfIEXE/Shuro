import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb, VoidCallback;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/event_log.dart';

/// System-wide (global) playback shortcuts on desktop: the media keys plus
/// guaranteed Ctrl+Alt+Space / Ctrl+Alt+arrows fallbacks. Persisted as a
/// single on/off preference.
class GlobalHotkeys {
  GlobalHotkeys._();

  static final GlobalHotkeys instance = GlobalHotkeys._();
  static const _prefKey = 'global_hotkeys_enabled';

  /// UI-observable state (Settings -> Desktop -> Global shortcuts).
  final ValueNotifier<bool> enabled = ValueNotifier(false);

  bool _registered = false;

  Future<void> restore({
    required VoidCallback toggle,
    required VoidCallback next,
    required VoidCallback previous,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_prefKey) ?? false;
      enabled.value = v;
      if (v) await _register(toggle, next, previous);
    } catch (_) {
      // No persistence on this platform: stays off until toggled.
    }
  }

  Future<void> setEnabled(
    bool v, {
    required VoidCallback toggle,
    required VoidCallback next,
    required VoidCallback previous,
  }) async {
    enabled.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey, v);
    } catch (_) {}
    if (v) {
      await _register(toggle, next, previous);
    } else {
      await _unregister();
    }
  }

  Future<void> _register(
      VoidCallback toggle, VoidCallback next, VoidCallback previous) async {
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    if (_registered) return;
    await hotKeyManager.unregisterAll();
    Future<void> reg(LogicalKeyboardKey key, List<HotKeyModifier> mods,
        VoidCallback fn) async {
      try {
        await hotKeyManager.register(
          HotKey(key: key, modifiers: mods),
          keyDownHandler: (_) => fn(),
        );
      } catch (_) {
        // Key unsupported on this OS: skip.
      }
    }

    // System-wide media keys.
    await reg(LogicalKeyboardKey.mediaPlayPause, const [], toggle);
    await reg(LogicalKeyboardKey.mediaTrackNext, const [], next);
    await reg(LogicalKeyboardKey.mediaTrackPrevious, const [], previous);
    // Guaranteed fallback combos on every desktop OS.
    await reg(LogicalKeyboardKey.space,
        const [HotKeyModifier.control, HotKeyModifier.alt], toggle);
    await reg(LogicalKeyboardKey.arrowRight,
        const [HotKeyModifier.control, HotKeyModifier.alt], next);
    await reg(LogicalKeyboardKey.arrowLeft,
        const [HotKeyModifier.control, HotKeyModifier.alt], previous);
    _registered = true;
    PlaybackEventLog.instance.add('hotkeys', {'on': true});
  }

  Future<void> _unregister() async {
    if (kIsWeb || !_registered) return;
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
    _registered = false;
    PlaybackEventLog.instance.add('hotkeys', {'on': false});
  }
}

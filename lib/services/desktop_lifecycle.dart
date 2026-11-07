import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the native Windows/Linux app lifetime.
///
/// Closing a music player must not silently stop a playing queue.  On desktop
/// the close affordance hides Shuro to the system tray; the explicit Quit item
/// remains available at all times.  Mobile and web deliberately do not import
/// this behaviour at runtime.
class DesktopLifecycle with WindowListener, TrayListener {
  DesktopLifecycle._();

  static final DesktopLifecycle instance = DesktopLifecycle._();

  /// True once the native title bar has been hidden; the shell then draws its
  /// own bar (drag area + minimise/maximise/close) so the window looks like a
  /// Windows 11 app instead of a default frame around a web-style page.
  static final ValueNotifier<bool> customChrome = ValueNotifier<bool>(false);

  bool _initialized = false;
  bool _quitting = false;
  bool _trayAvailable = false;

  /// Set by the app shell to let the tray control playback without
  /// depending on Provider or the player directly.
  static void Function(String action)? playbackCallback;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    _initialized = true;

    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      // Restore the last window size and position (phase 6 ask: the window
      // should reopen where the user left it, like a native desktop app).
      Map<String, double>? savedBounds;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('desktop_window_v1');
        if (raw != null) {
          savedBounds =
              (jsonDecode(raw) as Map<String, dynamic>).cast<String, double>();
        }
      } catch (_) {}
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: Size(savedBounds?['w'] ?? 1280, savedBounds?['h'] ?? 800),
          minimumSize: const Size(960, 640),
          center: savedBounds == null,
          backgroundColor: const Color(0xFF0B0F14),
          title: 'Shuro',
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          // WindowOptions has no position in window_manager 0.5.x — set it
          // before the window becomes visible.
          if (savedBounds != null &&
              savedBounds['x'] != null &&
              savedBounds['y'] != null) {
            try {
              await windowManager.setPosition(
                  Offset(savedBounds['x']!, savedBounds['y']!));
            } catch (_) {}
          }
          await windowManager.show();
          await windowManager.focus();
        },
      );
      customChrome.value = true;
      debugPrint('[desktop] custom title bar on');
      try {
        _trayAvailable = await _installTray();
        debugPrint('[desktop] tray ready');
      } catch (error) {
        _trayAvailable = false;
        debugPrint('[desktop] tray unavailable: $error');
      }
      // Do not hide the only window unless the user has a real, reachable
      // tray entry to bring it back. This matters on Linux shells without a
      // StatusNotifier host.
      if (_trayAvailable) await windowManager.setPreventClose(true);
    } catch (error) {
      // A desktop compositor or tray host may decline these optional desktop
      // integrations.  The music player itself must still start and play.
      debugPrint('[desktop] setup failed: $error');
      // The native title bar may already be hidden by now; without our own
      // bar the window could not be dragged, minimised or closed.
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      } catch (_) {}
      customChrome.value = true;
    }
  }

  Timer? _boundsDebounce;

  void _scheduleBoundsSave() {
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_saveWindowBounds());
    });
  }

  Future<void> _saveWindowBounds() async {
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isMinimized()) {
        return; // maximized state is not a size worth restoring
      }
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'desktop_window_v1',
          jsonEncode({
            'w': size.width,
            'h': size.height,
            'x': pos.dx,
            'y': pos.dy,
          }));
    } catch (_) {}
  }

  @override
  void onWindowMove() => _scheduleBoundsSave();

  @override
  void onWindowResize() => _scheduleBoundsSave();

  Future<bool> _installTray() async {
    // An installed app's working directory is not the exe's directory, and
    // the loose .ico is not shipped beside the exe — a relative path broke
    // the tray on every real install. Resolve the bundled asset absolutely
    // from the executable instead.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final assets = '$exeDir${sep}data${sep}flutter_assets$sep';
    final iconPath = defaultTargetPlatform == TargetPlatform.windows
        ? '${assets}windows${sep}runner${sep}resources${sep}app_icon.ico'
        : '${assets}_assets${sep}icon_512.png';
    debugPrint('[desktop] tray icon $iconPath exists=${File(iconPath).existsSync()}');
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Shuro');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Shuro'),
          MenuItem(key: 'hide', label: 'Hide Shuro'),
          MenuItem.separator(),
          // Transport from the tray: the playbackCallback bridge has existed
          // since the tray landed, but no menu item ever invoked it — the
          // tray could only show/hide/quit.
          MenuItem(key: 'play_pause', label: 'Play / Pause'),
          MenuItem(key: 'previous', label: 'Previous track'),
          MenuItem(key: 'next', label: 'Next track'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit Shuro'),
        ],
      ),
    );
    trayManager.addListener(this);
    return true;
  }

  Future<void> showWindow() async {
    if (!supported) return;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!supported) return;
    await windowManager.hide();
  }

  @override
  void onWindowClose() {
    if (_trayAvailable && !_quitting) unawaited(hideWindow());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
      case 'hide':
        unawaited(hideWindow());
      case 'play_pause':
      case 'previous':
      case 'next':
        playbackCallback?.call(menuItem.key!);
      case 'quit':
        unawaited(quitApplication());
    }
  }

  /// Unlike the window close button, this is an explicit listener decision and
  /// ends libmpv playback and the process.
  Future<void> quitApplication() async {
    if (_quitting) return;
    _quitting = true;
    try {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (error) {
      debugPrint('Unable to quit desktop window cleanly: $error');
    }
  }
}

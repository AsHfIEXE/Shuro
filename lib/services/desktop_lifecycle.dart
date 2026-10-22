import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
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

  bool _initialized = false;
  bool _quitting = false;
  bool _trayAvailable = false;

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
      windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(1280, 800),
          minimumSize: Size(960, 640),
          center: true,
          backgroundColor: Color(0xFF0B0F14),
          title: 'Shuro',
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
      _trayAvailable = await _installTray();
      // Do not hide the only window unless the user has a real, reachable
      // tray entry to bring it back. setIcon succeeds even on Linux shells
      // with no StatusNotifier host (GNOME), where a hidden window could not
      // be recovered — so close-to-tray is Windows-only; Linux's close button
      // simply closes the app.
      if (_trayAvailable && defaultTargetPlatform == TargetPlatform.windows) {
        await windowManager.setPreventClose(true);
      }
    } catch (error) {
      // A desktop compositor or tray host may decline these optional desktop
      // integrations.  The music player itself must still start and play.
      debugPrint('Desktop lifecycle setup unavailable: $error');
    }
  }

  Future<bool> _installTray() async {
    final iconPath = defaultTargetPlatform == TargetPlatform.windows
        ? 'windows/runner/resources/app_icon.ico'
        : '_assets/icon_512.png';
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Shuro');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Shuro'),
          MenuItem(key: 'hide', label: 'Hide Shuro'),
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
    if (_trayAvailable &&
        !_quitting &&
        defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(hideWindow());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  /// tray_manager does not open the context menu by itself on Windows — without
  /// this the Quit item existed but could never be reached, and with
  /// close-to-tray the only way to stop playback was Task Manager.
  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
      case 'hide':
        unawaited(hideWindow());
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
      // destroy() goes through the same close path that preventClose blocks.
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (error) {
      debugPrint('Unable to quit desktop window cleanly: $error');
    }
  }
}

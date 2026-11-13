import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Minimise / maximise / close for the immersive screens (Now Playing,
/// Lyrics) that cover the shell's title bar. Windows/Linux only — the
/// platforms where Shuro draws its own window chrome.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  /// True on the desktop platforms whose windows Shuro manages itself.
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    try {
      if (_maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionButton(
            tooltip: 'Minimise',
            icon: Icons.remove_rounded,
            onPressed: () async {
              try {
                await windowManager.minimize();
              } catch (_) {}
            },
          ),
          _CaptionButton(
            tooltip: _maximized ? 'Restore' : 'Maximise',
            icon: _maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _maximized ? 13 : 15,
            onPressed: _toggleMaximize,
          ),
          _CaptionButton(
            tooltip: 'Close',
            icon: Icons.close_rounded,
            hoverColor: const Color(0xFFE81123),
            onPressed: () async {
              try {
                await windowManager.close();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

/// One 46 x 36 caption cell, styled like the shell's title-bar buttons.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 16,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final double iconSize;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hover = widget.hoverColor ?? Colors.white.withValues(alpha: 0.08);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 36,
            alignment: Alignment.center,
            color: _hovering ? hover : Colors.transparent,
            child: Icon(widget.icon,
                size: widget.iconSize,
                color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}

/// Drag handle for immersive screens: wraps a passive area so the window can
/// still be moved when the shell's title bar is covered. Null on platforms
/// where Shuro does not manage the window.
Widget immersiveDragArea(BuildContext context, Widget child) {
  if (!WindowCaptionButtons.supported) return child;
  return DragToMoveArea(child: child);
}

/// Small label used by callers that want the reserved caption width.
const double kWindowCaptionWidth = 152;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';

/// Keyboard focus ring: 2 px brand violet, drawn 2 px OUTSIDE the child
/// (DesktopTokens.focusRingWidth / focusRingOffset), paint-only — it never
/// shifts layout, appears only for real focus (Tab / D-pad / keyboard
/// traversal), and matches the redesign's a11y pass.
///
/// Wrap the interactive card itself; [FocusableActionDetector] puts the
/// child into focus traversal, so Tab reaches every card, row and control
/// it wraps.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(12)),
  });

  final Widget child;
  final BorderRadius radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final offset = DesktopTokens.focusRingOffset;
    return FocusableActionDetector(
      onFocusChange: (value) => setState(() => _focused = value),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          // Painted outside the child's bounds; ignores pointer so it never
          // steals a tap or a right-click from the card underneath.
          Positioned.fill(
            left: -offset,
            top: -offset,
            right: -offset,
            bottom: -offset,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: widget.radius,
                  border: Border.all(
                    width: DesktopTokens.focusRingWidth,
                    color:
                        kBrandColor.withValues(alpha: _focused ? 1.0 : 0.0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/appearance_settings.dart';

/// Hides the system bars while [child] is on screen, when Settings → Appearance
/// → "Immersive screens" is on.
///
/// Scoped deliberately: it is wrapped around the two screens that benefit (Now
/// Playing and Lyrics) rather than set globally, because the rest of the app
/// needs the status bar (section headers scroll under it) and a globally
/// immersive app is a trap — if any screen forgets to restore the bars, the user
/// has no clock and no back affordance.
///
/// `immersiveSticky` is used rather than plain `immersive`: sticky lets a swipe
/// reveal the bars temporarily and then hides them again, which is what a media
/// screen wants. On the way out the mode returns to `edgeToEdge`, the app's
/// normal state.
class ImmersiveScope extends StatefulWidget {
  final Widget child;
  const ImmersiveScope({super.key, required this.child});

  @override
  State<ImmersiveScope> createState() => _ImmersiveScopeState();
}

class _ImmersiveScopeState extends State<ImmersiveScope> {
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: reading Provider in initState is only safe via
    // read(), but applying the mode before the route is on screen can be
    // overridden by the route transition on some platforms.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyIfEnabled());
  }

  void _applyIfEnabled() {
    if (!mounted) return;
    final enabled = context.read<AppearanceSettings>().immersiveScreens;
    if (!enabled) return;
    _applied = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Only undo what this scope actually changed — otherwise closing a
    // non-immersive screen would also kick the device out of a mode some other
    // scope set.
    if (_applied) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

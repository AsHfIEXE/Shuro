import 'dart:async';

import 'package:flutter/material.dart';

/// Premium immersive fade for the Now Playing screen: after [hideAfter] of no
/// interaction, the screen's *chrome* (header, transport, actions) slowly
/// dissolves — a long, quiet ease — while the artwork, backdrop and lyrics
/// stay. Any pointer event wakes the chrome with a short, lively fade back.
///
/// Design notes:
///  * fade OUT is deliberately slow (~1.2 s, ease-in-out) — a control that
///    vanishes quickly reads as a glitch; one that breathes away reads as
///    intentional;
///  * fade IN is quick (~0.3 s) — the user asked for the control, they want
///    it now;
///  * while hidden (or mid-fade-out) an invisible full-screen barrier sits on
///    top, so the first tap *reveals* controls instead of firing an invisible
///    button underneath — the video-player convention;
///  * auto-hide only runs while [enabled] (the player is actually playing) —
///    a paused user is reading the controls, not admiring the artwork.
///
/// Usage: wrap the screen body in [IdleFade], then wrap each chrome section
/// in [IdleFadeChrome]. The scope rebuilds only the chrome sections that
/// animate (FadeTransition + IgnorePointer), never the whole subtree.
class IdleFade extends StatefulWidget {
  /// Auto-hide is allowed (pass `player.isPlaying`).
  final bool enabled;

  /// Idle time before the chrome starts dissolving.
  final Duration hideAfter;

  final Widget child;

  const IdleFade({
    super.key,
    required this.enabled,
    this.hideAfter = const Duration(seconds: 4),
    required this.child,
  });

  static _IdleFadeState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IdleFadeScope>()!.state;

  @override
  State<IdleFade> createState() => _IdleFadeState();
}

class _IdleFadeState extends State<IdleFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1, // fully visible
    duration: const Duration(milliseconds: 320), // fade in
    reverseDuration: const Duration(milliseconds: 1200), // slow fade out
  );

  /// 1.0 = chrome visible, 0.0 = dissolved. This IS the fade opacity.
  Animation<double> get opacity => _controller.view;

  bool get _interacting => _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(IdleFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Play/pause toggled: a paused user wants the controls; a playing one
    // restarts the idle countdown.
    if (oldWidget.enabled != widget.enabled) {
      if (!widget.enabled) {
        _hideTimer?.cancel();
        _controller.forward();
      } else {
        _scheduleHide();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.enabled) return;
    _hideTimer = Timer(widget.hideAfter, _controller.reverse);
  }

  /// Any interaction: wake the chrome and restart the countdown.
  void poke() {
    if (!_interacting) _controller.forward();
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return _IdleFadeScope(
      state: this,
      child: Listener(
        // Pointer-level so it sees drags/taps anywhere — including on the
        // artwork ring — without needing every child to forward events.
        onPointerDown: (_) => poke(),
        onPointerMove: (_) => poke(),
        child: AnimatedBuilder(
          animation: opacity,
          builder: (context, child) => Stack(
            children: [
              child!,
              // Reveal barrier: once the fade-out has begun, an invisible
              // layer on top turns the next tap into "wake up" instead of
              // hitting a half-visible button.
              if (opacity.value < 0.999)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: poke,
                  ),
                ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _IdleFadeScope extends InheritedWidget {
  final _IdleFadeState state;
  const _IdleFadeScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_IdleFadeScope oldWidget) => false;
}

/// A chrome section that follows the idle fade: opacity fades out slowly,
/// and while effectively invisible it also stops accepting hits.
class IdleFadeChrome extends StatelessWidget {
  final Widget child;
  const IdleFadeChrome({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final fade = IdleFade.of(context);
    return AnimatedBuilder(
      animation: fade.opacity,
      child: child,
      builder: (context, child) => IgnorePointer(
        ignoring: fade.opacity.value < 0.05,
        child: FadeTransition(opacity: fade.opacity, child: child),
      ),
    );
  }
}

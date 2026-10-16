import 'package:flutter/material.dart';

/// Mirrors Settings → Appearance → Reduce animations. Read when a route is
/// created, so it takes effect for the very next navigation.
bool reduceMotionEnabled = false;

/// One deliberate transition style used everywhere a screen "rises up" over
/// what's already on screen (mini player → Now Playing, Now Playing →
/// Lyrics/Queue) — a combined fade + gentle upward slide. Kept to a single
/// shared curve/duration rather than a different animation per screen, and
/// built on Flutter's own PageRouteBuilder (no extra animation packages,
/// nothing running once the transition finishes).
PageRouteBuilder<T> risingRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 320),
    reverseTransitionDuration: reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Destination currently animating in (its widget type name), or null.
String? _risingInFlight;

/// Pushes [page] with the rising transition unless a copy of the same
/// destination is already animating in on top of the current route, or the
/// current route is already covered by something else. Guards every rise
/// push site against the fast double-tap that used to stack two copies of
/// Now Playing / Queue / Lyrics (audit findings F4-1 … F4-5).
void pushRisingOnce(BuildContext context, Widget page) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return; // already covered
  final key = page.runtimeType.toString();
  if (_risingInFlight == key) return; // same destination still animating in
  final nav = Navigator.of(context);
  final r = risingRoute<Object?>(page);
  _risingInFlight = key;
  // ignore: discarded_futures
  r.completed.whenComplete(() {
    if (_risingInFlight == key) _risingInFlight = null;
  });
  nav.push(r);
}

/// The second (and only other) transition style: a subtle slide-in from the
/// right + fade, for regular "drill down" navigation — Album/Artist/
/// Playlist detail, Search results, Settings sub-screens. Deliberately the
/// same duration/curve family as [risingRoute] so the whole app reads as
/// one consistent motion language rather than a different animation per
/// screen; only the direction differs, matching the "coming from a list"
/// vs. "rising over what's playing" mental models.
Route<T> drillDownRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 280),
    reverseTransitionDuration: reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

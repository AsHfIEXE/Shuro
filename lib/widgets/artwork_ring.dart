import 'package:flutter/material.dart';
import '../models/song.dart';
import 'progress_ring_painter.dart';

/// The big circular artwork + progress ring in the middle of the Now
/// Playing screen. Mirrors the "Artista" / "Círculo Time" group in the
/// Figma file (ring ~296px on a 375-wide screen, artwork ~210px — a
/// ~0.71 inner ratio) — [size] scales responsively, everything else keeps
/// that ratio. [progress] is passed in explicitly (from PlayerController)
/// rather than read off the song, since playback position belongs to the
/// player, not the track. Wrap this in a Hero (see [heroTag]) so the
/// artwork morphs smoothly from the mini player into the full screen.
class ArtworkRing extends StatelessWidget {
  final Song song;
  final double progress;
  final double size;
  final Object? heroTag;

  /// The ring/glow color to use — the track's *real* artwork-derived
  /// palette when one's been resolved (see NowPlayingScreen), falling
  /// back to [Song.gradientColors] only until that resolves or when
  /// there's no real artwork to extract from. Required rather than
  /// defaulted so every call site has to make that choice explicitly.
  final List<Color> colors;

  /// Whether the progress arc is drawn. Portrait keeps it (it is the screen's
  /// only progress display there). Landscapes turn it OFF: the wide layout has
  /// a linear seek bar under the artwork, and two progress indicators for one
  /// track was reported as redundant clutter.
  final bool showProgress;

  /// True while the user is dragging the knob — the painter grows the knob
  /// and strengthens its glow so the seek control answers the touch.
  final bool scrubbing;

  const ArtworkRing({
    super.key,
    required this.song,
    required this.progress,
    required this.colors,
    this.size = 260,
    this.heroTag,
    this.showProgress = true,
    this.scrubbing = false,
  });

  static const _innerRatio = 0.72;

  @override
  Widget build(BuildContext context) {
    final accent = colors.last;
    final artwork = Container(
      width: size * _innerRatio,
      height: size * _innerRatio,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 44, spreadRadius: 2),
        ],
      ),
      child: ClipOval(
        // Cross-fades on a track change, and only then: the switcher is keyed
        // by song id, so a progress tick or a favourite toggle leaves the
        // image alone. It sits *inside* the Hero rather than around it, which
        // keeps the hero tag unique (two children sharing one tag in a route
        // throws).
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(song.id),
            // Falls back to the same gradient placeholder both when there's no
            // artwork and when a real one fails to load (e.g. the server went
            // unreachable mid-session) — otherwise a failed NetworkImage would
            // show Flutter's default error box right in the middle of Now
            // Playing instead of degrading gracefully.
            child: song.artwork != null
            ? Image(
                image: song.artwork!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Center(child: Icon(Icons.music_note_rounded, color: Colors.white70, size: size * 0.2)),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Center(child: Icon(Icons.music_note_rounded, color: Colors.white70, size: size * 0.2)),
              ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showProgress)
            CustomPaint(
              size: Size(size, size),
              painter: ProgressRingPainter(progress: progress, gradientColors: colors, scrubbing: scrubbing),
            ),
          heroTag != null ? Hero(tag: heroTag!, child: artwork) : artwork,
        ],
      ),
    );
  }
}

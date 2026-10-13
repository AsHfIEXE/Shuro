import 'package:flutter/material.dart';
import '../theme/dynamic_theme.dart';

/// Rounded gradient thumbnail used as artwork placeholder anywhere a real
/// image isn't provided. Pass [size] for a fixed-size usage (list rows, the
/// mini player); leave it null to let the thumb fill whatever box its
/// parent gives it (e.g. wrapped in AspectRatio inside a grid cell).
///
/// Honors Settings → Appearance automatically: [gradientColors] falls back
/// to the fixed brand gradient when Dynamic colors is off, and [radius]
/// is overridden by the Artwork style setting — unless [radius] is already
/// 999+ (this widget's own convention for "force a circle", used for
/// artist portraits, which stay circular regardless of that setting).
class ArtworkThumb extends StatelessWidget {
  final List<Color> gradientColors;
  final ImageProvider? artwork;
  final double? size;
  final double radius;
  final IconData icon;
  final double iconSize;

  const ArtworkThumb({
    super.key,
    required this.gradientColors,
    this.artwork,
    this.size,
    this.radius = 10,
    this.icon = Icons.music_note_rounded,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colors = songColors(context, gradientColors);
    final effectiveRadius = radius >= 999 ? radius : artworkRadius(context, radius);

    // Same gradient+icon placeholder either way: when there's no artwork
    // at all, and as the fallback if a real NetworkImage fails to load
    // (server unreachable, cover art 404, a LAN connection dropping) —
    // without errorBuilder, a failed network image renders Flutter's
    // default red/grey error box instead, which happens often on a
    // self-hosted server that isn't always reachable.
    Widget placeholder() => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Center(child: Icon(icon, color: Colors.white70, size: iconSize)),
        );

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: artwork != null
          ? Image(
              image: artwork!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder(),
            )
          : placeholder(),
    );
    if (size == null) return content;
    return SizedBox(width: size, height: size, child: content);
  }
}

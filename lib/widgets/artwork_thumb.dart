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

    // Decode — and, for Subsonic cover URLs, DOWNLOAD — at the drawn size. A
    // row thumb is ~44-56 dp; it used to fetch the 500 px source and only
    // shrink it after the transfer. Now Playing (large artwork) keeps 500.
    Widget imageAt(double logical) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final px = (logical * dpr).round().clamp(32, 1200);
      return Image(
        // ResizeImage (Image has no cacheWidth param for arbitrary
        // providers): decode at the drawn size instead of the source size.
        image: ResizeImage(_sizedForTransfer(artwork!, px), width: px, policy: ResizeImagePolicy.fit),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => placeholder(),
      );
    }

    Widget image() {
      if (size != null) return imageAt(size!);
      // No fixed size (grid cells): measure the box the parent gives us.
      return LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        if (w <= 0) return Image(image: artwork!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (c, e, s) => placeholder());
        return imageAt(w);
      });
    }

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: artwork != null ? image() : placeholder(),
    );
    if (size == null) return content;
    return SizedBox(width: size, height: size, child: content);
  }
}

/// For a Subsonic `getCoverArt` URL, asks the server for a smaller image when
/// the thumb is drawn small. Sizes snap to 150/300/500 so the on-disk image
/// cache (keyed by URL) is shared between rows of similar size instead of
/// holding one copy per pixel width. Never upsizes, and leaves any other
/// provider (file, MusicBrainz, artist portraits) untouched.
ImageProvider _sizedForTransfer(ImageProvider provider, int neededPx) {
  if (provider is! NetworkImage) return provider;
  final uri = Uri.tryParse(provider.url);
  if (uri == null || !uri.path.contains('getCoverArt')) return provider;
  final current = int.tryParse(uri.queryParameters['size'] ?? '');
  if (current == null) return provider;
  final bucket = neededPx <= 150 ? 150 : (neededPx <= 300 ? 300 : 500);
  if (bucket >= current) return provider;
  final params = Map<String, String>.of(uri.queryParameters)..['size'] = '$bucket';
  return NetworkImage(
    uri.replace(queryParameters: params).toString(),
    scale: provider.scale,
    headers: provider.headers,
  );
}

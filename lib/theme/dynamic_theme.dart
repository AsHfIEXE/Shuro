import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../models/artwork_style.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

/// Accent colors for something that has its own palette (a song, album,
/// playlist...). With Settings → Dynamic colors on, that palette is used;
/// off, everything falls back to the fixed Shuro brand gradient.
/// Call from a build method — it subscribes the widget to the setting.
List<Color> songColors(BuildContext context, List<Color> palette) {
  final useDynamic = context.select<AppState, bool>((s) => s.dynamicColors);
  return useDynamic ? palette : kBrandGradient;
}

Color accentColor(BuildContext context, List<Color> palette) => songColors(context, palette).last;

/// Corner radius for artwork given the user's Artwork style setting.
double artworkRadius(BuildContext context, double baseRadius) {
  final style = context.select<AppState, ArtworkStyle>((s) => s.artworkStyle);
  if (style == ArtworkStyle.square) return 0;
  if (style == ArtworkStyle.circle) return 999;
  return baseRadius;
}

/// Extracts the real colors out of a track's own cover art, so Now Playing
/// and Lyrics can theme themselves on what the artwork actually looks like
/// instead of [Song.gradientColors]' deterministic-but-arbitrary per-ID
/// hash color (that hash is still the right choice for list rows/cards —
/// cheap, stable, no image decode — just not for the one screen that's
/// supposed to feel like it's reacting to *this* cover).
///
/// Cached per artwork URL/asset key so switching back to a recently-seen
/// track doesn't redecode the image, and results never regress to
/// nothing: every call either returns a real 2-color gradient or the
/// [fallback] passed in, never throws.
class ArtworkPalette {
  ArtworkPalette._();

  static final Map<String, List<Color>> _cache = {};

  /// Clears cached palettes — exposed for completeness (e.g. a future
  /// "clear cache" debug action); nothing in the app calls this today,
  /// since artwork for a given song/album ID never changes underneath us.
  static void clearCache() => _cache.clear();

  static Future<List<Color>> extract(ImageProvider? artwork, List<Color> fallback, String cacheKey) async {
    if (artwork == null) return fallback;
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    try {
      final generator = await PaletteGenerator.fromImageProvider(
        artwork,
        size: const Size(128, 128),
        maximumColorCount: 16,
      );
      // Prefer a vibrant/dark-vibrant pair for a glow-and-accent look that
      // still reads against a dark background; fall back through the
      // generator's other swatches, and only all the way to [fallback] if
      // the image genuinely didn't yield anything usable (e.g. a flat
      // single-color placeholder image).
      final primary = generator.vibrantColor?.color ?? generator.dominantColor?.color ?? generator.lightVibrantColor?.color;
      if (primary == null) return fallback;
      final secondary = generator.darkVibrantColor?.color ?? generator.dominantColor?.color ?? primary;
      final result = [primary, secondary];
      _cache[cacheKey] = result;
      return result;
    } catch (_) {
      return fallback;
    }
  }
}

/// Resolves the real accent/background colors for [artwork], honoring
/// Settings → Dynamic colors (off => the fixed brand gradient, same as
/// [songColors]) and falling back to [fallback] — typically the track's
/// own deterministic [Song.gradientColors] — instantly on first build and
/// while extraction is still running, so nothing ever flashes blank.
/// [cacheKey] should uniquely identify the artwork (e.g. the song or
/// album ID) so the extraction cache works across rebuilds.
class ArtworkPaletteBuilder extends StatefulWidget {
  final ImageProvider? artwork;
  final List<Color> fallback;
  final String cacheKey;
  final Widget Function(BuildContext context, List<Color> colors) builder;

  const ArtworkPaletteBuilder({
    super.key,
    required this.artwork,
    required this.fallback,
    required this.cacheKey,
    required this.builder,
  });

  @override
  State<ArtworkPaletteBuilder> createState() => _ArtworkPaletteBuilderState();
}

class _ArtworkPaletteBuilderState extends State<ArtworkPaletteBuilder> {
  List<Color>? _resolved;
  String? _resolvedFor;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtworkPaletteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) _resolve();
  }

  void _resolve() {
    final key = widget.cacheKey;
    ArtworkPalette.extract(widget.artwork, widget.fallback, key).then((colors) {
      if (!mounted || widget.cacheKey != key) return;
      setState(() {
        _resolved = colors;
        _resolvedFor = key;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final useDynamic = context.select<AppState, bool>((s) => s.dynamicColors);
    if (!useDynamic) return widget.builder(context, kBrandGradient);
    final colors = _resolvedFor == widget.cacheKey ? _resolved : null;
    return widget.builder(context, colors ?? widget.fallback);
  }
}

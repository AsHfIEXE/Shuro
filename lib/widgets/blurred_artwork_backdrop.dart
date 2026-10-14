import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/appearance_settings.dart';
import '../theme/app_theme.dart';
import 'page_transitions.dart' show reduceMotionEnabled;

/// How loudly the backdrop should present itself, per screen.
enum BlurBackdropStyle {
  /// Now Playing: artwork clearly visible through the blur, colour wash strong,
  /// scrim light enough to let the cover's own palette lead.
  nowPlaying,

  /// Lyrics: the same artwork, pushed much further back — heavier blur, heavier
  /// scrim. Lyrics are long passages of small text and must stay comfortably
  /// readable, so legibility wins over atmosphere here.
  lyrics,
}

/// The adaptive backdrop, Apple-Music style: a **mesh gradient** built from the
/// track's palette with slowly drifting colour nodes, the **pre-blurred
/// artwork** composited over it, and the wash/scrim stack on top.
///
/// Why this architecture (the previous version lagged): it re-filtered a
/// blurred subtree every animation frame — a full `ImageFiltered` re-raster
/// 60×/second, which is exactly the kind of work that stutters on low-end
/// GPUs. Here the expensive part happens **once per track**:
///
///  1. the artwork is decoded, downscaled to a ~160 px tile and blurred into a
///     cached `ui.Image` (`_blurredCopy`) — one-off cost per track change;
///  2. every frame afterwards only *draws* that texture (a blit) and paints
///     four radial-gradient fills for the mesh — both are cheap;
///  3. the idle motion therefore animates a transform over a cached texture,
///     which stays smooth even on a 4 GB phone.
///
/// Layers, bottom → top: surface → mesh → pre-blurred artwork → colour wash →
/// scrim. The wash and scrim sit above the crossfade so text contrast never
/// dips mid-transition.
class BlurredArtworkBackdrop extends StatelessWidget {
  final ImageProvider? artwork;

  /// Palette to tint with when there is no artwork, and the colour source for
  /// the mesh gradient nodes.
  final List<Color> palette;

  /// Changes when the track changes — this is what triggers the crossfade.
  final String cacheKey;

  final BlurBackdropStyle style;

  const BlurredArtworkBackdrop({
    super.key,
    required this.artwork,
    required this.palette,
    required this.cacheKey,
    this.style = BlurBackdropStyle.nowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();

    // Static choice: one flat gradient from the same palette, nothing per frame.
    if (appearance.backgroundStyle == BackgroundStyle.staticArtwork) {
      return _StaticPaletteBackdrop(palette: palette, style: style);
    }

    final animated = appearance.backgroundStyle == BackgroundStyle.animatedGradient;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: kSurfaceColor),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: _MeshBackdropLayer(
            key: ValueKey(cacheKey),
            // Gradient mode = pure mesh; blur mode = mesh + the artwork plate.
            artwork: animated ? null : artwork,
            palette: palette,
            style: style,
            blurScale: appearance.backdropBlurScale,
            motion: appearance.backdropMotion,
          ),
        ),
        _ColourWash(palette: palette, style: style),
        _Scrim(style: style),
      ],
    );
  }
}

/// The static alternative: the same palette painted once as a gradient, no
/// motion, no per-frame work.
class _StaticPaletteBackdrop extends StatelessWidget {
  final List<Color> palette;
  final BlurBackdropStyle style;

  const _StaticPaletteBackdrop({required this.palette, required this.style});

  @override
  Widget build(BuildContext context) {
    final colors = palette.length >= 2 ? palette : kBrandGradient;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(colors.first, kSurfaceColor, 0.35) ?? colors.first,
                kSurfaceColor,
                Color.lerp(colors.last, kSurfaceColor, 0.55) ?? colors.last,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.1,
              colors: [colors.last.withValues(alpha: 0.30), Colors.transparent],
            ),
          ),
        ),
        _Scrim(style: style),
      ],
    );
  }
}

/// Mesh + (optionally) the pre-blurred artwork plate. One controller drives
/// both the mesh node drift and the artwork breathe so they never fall out of
/// phase; `BackdropMotion` sets its speed (or stops it).
class _MeshBackdropLayer extends StatefulWidget {
  final ImageProvider? artwork;
  final List<Color> palette;
  final BlurBackdropStyle style;
  final double blurScale;
  final BackdropMotion motion;

  const _MeshBackdropLayer({
    super.key,
    required this.artwork,
    required this.palette,
    required this.style,
    required this.blurScale,
    required this.motion,
  });

  @override
  State<_MeshBackdropLayer> createState() => _MeshBackdropLayerState();
}

class _MeshBackdropLayerState extends State<_MeshBackdropLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 30));

  ui.Image? _blurredImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  int _generation = 0;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _applyMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolving an image needs an ImageConfiguration from MediaQuery, and
    // MediaQuery can't be read from initState ("called before initState
    // completed" — the red screen this produced). didChangeDependencies is
    // the standard first safe moment; later artwork changes re-resolve via
    // didUpdateWidget.
    if (!_resolving) {
      _resolving = true;
      _resolveArtwork();
    }
  }

  @override
  void didUpdateWidget(covariant _MeshBackdropLayer old) {
    super.didUpdateWidget(old);
    if (old.artwork != widget.artwork) _resolveArtwork();
    if (old.motion != widget.motion) _applyMotion();
    if (old.blurScale != widget.blurScale) _resolveArtwork(); // re-blur at the new strength
  }
  @override
  void dispose() {
    if (_imageListener != null) _imageStream?.removeListener(_imageListener!);
    _blurredImage?.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _applyMotion() {
    switch (widget.motion) {
      case BackdropMotion.still:
        _clock.stop();
      case BackdropMotion.subtle:
        _clock.duration = const Duration(seconds: 36);
        if (!(_clock.isAnimating)) _clock.repeat();
      case BackdropMotion.normal:
        // The owner's default: clearly alive — 18 s cycle, shallower blur so
        // the artwork itself reads, motion carries the atmosphere.
        _clock.duration = const Duration(seconds: 18);
        if (!_clock.isAnimating) _clock.repeat();
      case BackdropMotion.lively:
        _clock.duration = const Duration(seconds: 10);
        if (!_clock.isAnimating) _clock.repeat();
    }
  }

  void _resolveArtwork() {
    _generation++;
    if (_imageListener != null) {
      _imageStream?.removeListener(_imageListener!);
      _imageListener = null;
      _imageStream = null;
    }
    final provider = widget.artwork;
    if (provider == null) {
      if (_blurredImage != null) setState(() => _blurredImage = null);
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(this.context, size: const Size(220, 391)));
    final listener = ImageStreamListener((info, synchronousCall) async {
      final generation = _generation;
      // Clone so the framework can recycle its own handle while we work.
      final source = info.image.clone();
      final blurred = await _blurredCopy(source);
      source.dispose();
      if (!mounted || generation != _generation) {
        blurred.dispose();
        return;
      }
      setState(() {
        _blurredImage?.dispose();
        _blurredImage = blurred;
      });
    }, onError: (error, stack) {
      // No artwork plate — the mesh alone still reads as this track's colours.
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  /// Downscale + blur the artwork **once** into a small cached texture. The
  /// sigma is scaled by the user's Background blur setting.
  ///
  /// Edge hygiene (the "sharp cut" fix): the art is drawn LARGER than the
  /// canvas (overscan) before blurring, so the blur filter always has real
  /// pixels to sample at the tile borders — clamped edge sampling is what
  /// streaked into a hard rectangular cut, amplified by the tile→screen
  /// upscale, and it was worst at low blur strengths. More overscan at heavier
  /// blur (the filter reaches further out).
  Future<ui.Image> _blurredCopy(ui.Image source) async {
    const tileW = 240.0;
    final tileH = (tileW * source.height / source.width).clamp(1.0, 960.0);
    // Cover-crop the source so the tile's aspect matches without distortion.
    final destAspect = tileW / tileH;
    final srcAspect = source.width / source.height;
    late final Rect srcRect;
    if (srcAspect > destAspect) {
      final cropW = source.height * destAspect;
      srcRect = Rect.fromLTWH((source.width - cropW) / 2, 0, cropW, source.height.toDouble());
    } else {
      final cropH = source.width / destAspect;
      srcRect = Rect.fromLTWH(0, (source.height - cropH) / 2, source.width.toDouble(), cropH);
    }

    final baseSigma = widget.style == BlurBackdropStyle.lyrics ? 40.0 : 22.0;
    final sigma = (baseSigma * widget.blurScale).clamp(4.0, 80.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, tileW, tileH));
    final overscan = 1.30 + (sigma / 80.0).clamp(0.0, 1.0) * 0.40;
    final drawn = Rect.fromCenter(
      center: Offset(tileW / 2, tileH / 2),
      width: tileW * overscan,
      height: tileH * overscan,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma * 0.5, sigmaY: sigma * 0.5, tileMode: ui.TileMode.clamp);
    canvas.drawImageRect(source, srcRect, drawn, paint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(tileW.toInt(), tileH.toInt());
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final osReduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final still = widget.motion == BackdropMotion.still || reduceMotionEnabled || osReduceMotion;
    final amplitude = switch (widget.motion) {
      BackdropMotion.subtle => 0.03,
      BackdropMotion.lively => 0.085,
      _ => 0.065,
    };
    final showPlate = widget.style == BlurBackdropStyle.nowPlaying && _blurredImage != null;

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        // One phase drives everything: the mesh nodes drift with it, the
        // artwork breathes with it — sin gives a smooth continuous loop with
        // no reverse seam.
        final t = still ? 0.18 : _clock.value;
        final phase = t * 2 * math.pi;
        final breathe = still ? 0.0 : amplitude * math.sin(phase);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _MeshGradientPainter(palette: widget.palette, phase: phase),
            ),
            if (showPlate)
              Transform.scale(
                // Breathing a *drawn texture* is the cheap part — this is what
                // keeps the motion smooth where the old version stuttered.
                scale: 1.16 + breathe,
                // The dissolve: the plate's alpha fades to zero toward every
                // edge, so the artwork melds into the mesh gradient instead
                // of ending at a boundary — smooth at ALL blur strengths,
                // including near-sharp ones.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => ui.Gradient.linear(
                    Offset(0, 0),
                    Offset(0, bounds.height),
                    [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 1.0),
                      Colors.white.withValues(alpha: 1.0),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    const [0.0, 0.16, 0.84, 1.0],
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => ui.Gradient.linear(
                      Offset.zero,
                      Offset(bounds.width, 0),
                      [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 1.0),
                        Colors.white.withValues(alpha: 1.0),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      const [0.0, 0.16, 0.84, 1.0],
                    ),
                    child: CustomPaint(
                      painter: _BlurredPlatePainter(image: _blurredImage!),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Four to five radial colour nodes from the track's palette, their centres
/// drifting on independent slow orbits — the mesh-gradient look. Each node is
/// one radial fill; the whole painter is a handful of gradient fills per frame.
class _MeshGradientPainter extends CustomPainter {
  final List<Color> palette;
  final double phase;

  _MeshGradientPainter({required this.palette, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kSurfaceColor);

    final colors = palette.length >= 2 ? palette : kBrandGradient;
    final diag = size.shortestSide;
    final count = math.min(colors.length, 5);
    for (var i = 0; i < count; i++) {
      final color = Color.lerp(colors[i], kSurfaceColor, 0.30) ?? colors[i];
      final speed = 0.5 + (i % 3) * 0.21;
      final offsetAngle = i * 2.399; // golden-angle spread
      final orbit = 0.16 + (i % 2) * 0.09;
      final center = Offset(
        size.width * (0.5 + orbit * math.cos(phase * speed + offsetAngle)),
        size.height * (0.42 + orbit * math.sin(phase * speed * 0.8 + offsetAngle)),
      );
      final radius = diag * (0.55 + 0.12 * math.sin(phase * speed + i));
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [color.withValues(alpha: 0.85), color.withValues(alpha: 0.0)],
          [0.0, 1.0],
          ui.TileMode.clamp,
        );
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  @override
  bool shouldRepaint(_MeshGradientPainter old) => old.phase != phase || old.palette != palette;
}

/// Draws the cached pre-blurred artwork tile, cover-fitted. A plain texture
/// blit — this is cheap to run at 60 fps, unlike re-filtering.
class _BlurredPlatePainter extends CustomPainter {
  final ui.Image image;

  _BlurredPlatePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final destAspect = size.width / size.height;
    final srcAspect = image.width / image.height;
    late final Rect srcRect;
    if (srcAspect > destAspect) {
      final cropW = image.height * destAspect;
      srcRect = Rect.fromLTWH((image.width - cropW) / 2, 0, cropW, image.height.toDouble());
    } else {
      final cropH = image.width / destAspect;
      srcRect = Rect.fromLTWH(0, (image.height - cropH) / 2, image.width.toDouble(), cropH);
    }
    // Slightly transparent so the mesh beneath still contributes colour.
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawImageRect(image, srcRect, Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BlurredPlatePainter old) => old.image != image;
}

/// Tints the backdrop with the palette so the colour reads as *this* track's,
/// and adds a soft vignette for depth.
class _ColourWash extends StatelessWidget {
  final List<Color> palette;
  final BlurBackdropStyle style;

  const _ColourWash({required this.palette, required this.style});

  @override
  Widget build(BuildContext context) {
    final primary = palette.isNotEmpty ? palette.first : kBrandColor;
    final secondary = palette.length > 1 ? palette.last : kSecondaryColor;
    final strength = style == BlurBackdropStyle.lyrics ? 0.22 : 0.28;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: strength),
              Colors.transparent,
              secondary.withValues(alpha: strength * 0.8),
            ],
            stops: const [0.0, 0.50, 1.0],
          ),
        ),
      ),
    );
  }
}

/// The legibility layer: vertical gradient (darker top and bottom, where chrome
/// and transport sit), a flat scrim, then a vignette.
class _Scrim extends StatelessWidget {
  final BlurBackdropStyle style;

  const _Scrim({required this.style});

  @override
  Widget build(BuildContext context) {
    final isLyrics = style == BlurBackdropStyle.lyrics;
    final flat = isLyrics ? 0.40 : 0.16;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: isLyrics ? 0.48 : 0.30),
                  Colors.black.withValues(alpha: isLyrics ? 0.20 : 0.06),
                  kSurfaceColor.withValues(alpha: isLyrics ? 0.84 : 0.88),
                ],
                stops: isLyrics ? const [0.0, 0.40, 1.0] : const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: flat)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.95,
                colors: [Colors.transparent, isLyrics ? const Color(0x59000000) : const Color(0x4D000000)],
                stops: isLyrics ? const [0.50, 1.0] : const [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

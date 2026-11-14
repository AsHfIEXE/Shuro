import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/appearance_settings.dart';
import '../theme/app_theme.dart';
import 'blurred_artwork_backdrop.dart' show BlurBackdropStyle;
import 'page_transitions.dart' show reduceMotionEnabled;

/// Spicy-Lyrics-style backdrop: one heavily blurred artwork plate that
/// slowly Ken-Burns (drift + breathe), a saturation-boosted glow copy
/// bleeding warm colour at the edges, palette wash, heavy vignette.
///
/// Drop-in replacement for BlurredArtworkBackdrop — identical params:
///   SpicyBackdrop(artwork: ..., palette: ..., cacheKey: ...,
///                 style: BlurBackdropStyle.lyrics)
///
/// Cost model (same as the existing plate): blur is baked ONCE per track
/// into a small ui.Image; every frame is two texture blits + gradient fills.
/// Web falls back to drifting palette blobs (CanvasKit offscreen-blur
/// artifacts).
class SpicyBackdrop extends StatelessWidget {
  final ImageProvider? artwork;
  final List<Color> palette;
  final String cacheKey;
  final BlurBackdropStyle style;

  const SpicyBackdrop({
    super.key,
    required this.artwork,
    required this.palette,
    required this.cacheKey,
    this.style = BlurBackdropStyle.nowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();

    if (appearance.backgroundStyle == BackgroundStyle.staticArtwork) {
      return _StaticWash(palette: palette, style: style);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: kSurfaceColor),
        RepaintBoundary(
          child: AnimatedSwitcher(
            duration: kIsWeb ? Duration.zero : const Duration(milliseconds: 700),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            layoutBuilder: (c, prev) =>
                Stack(fit: StackFit.expand, children: [...prev, if (c != null) c]),
            child: _SpicyPlate(
              key: ValueKey('$cacheKey|${appearance.backdropBlurScale}'),
              artwork: artwork,
              palette: palette,
              style: style,
              blurScale: appearance.backdropBlurScale,
              motion: appearance.backdropMotion,
            ),
          ),
        ),
        _Wash(palette: palette, style: style),
        _Veil(style: style),
      ],
    );
  }
}

class _SpicyPlate extends StatefulWidget {
  final ImageProvider? artwork;
  final List<Color> palette;
  final BlurBackdropStyle style;
  final double blurScale;
  final BackdropMotion motion;

  const _SpicyPlate({
    super.key,
    required this.artwork,
    required this.palette,
    required this.style,
    required this.blurScale,
    required this.motion,
  });

  @override
  State<_SpicyPlate> createState() => _SpicyPlateState();
}

class _SpicyPlateState extends State<_SpicyPlate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 34));

  ui.Image? _blurred;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _applyMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _SpicyPlate old) {
    super.didUpdateWidget(old);
    if (old.artwork != widget.artwork || old.blurScale != widget.blurScale) {
      _resolve();
    }
    if (old.motion != widget.motion) _applyMotion();
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _blurred?.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _applyMotion() {
    switch (widget.motion) {
      case BackdropMotion.still:
        _clock.stop();
      case BackdropMotion.subtle:
        _clock.duration = const Duration(seconds: 60);
        if (!_clock.isAnimating) _clock.repeat();
      case BackdropMotion.normal:
        _clock.duration = const Duration(seconds: 34);
        if (!_clock.isAnimating) _clock.repeat();
      case BackdropMotion.lively:
        _clock.duration = const Duration(seconds: 18);
        if (!_clock.isAnimating) _clock.repeat();
    }
  }

  void _resolve() {
    _gen++;
    if (_listener != null) {
      _stream?.removeListener(_listener!);
      _listener = null;
      _stream = null;
    }
    final provider = widget.artwork;
    if (provider == null || kIsWeb) {
      if (_blurred != null) setState(() => _blurred = null);
      return;
    }
    final stream = provider.resolve(
        createLocalImageConfiguration(context, size: const Size(256, 256)));
    final listener = ImageStreamListener((info, _) async {
      final gen = _gen;
      final src = info.image.clone();
      final baked = await _bake(src);
      src.dispose();
      if (!mounted || gen != _gen) {
        baked.dispose();
        return;
      }
      setState(() {
        _blurred?.dispose();
        _blurred = baked;
      });
    }, onError: (_, __) {});
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  Future<ui.Image> _bake(ui.Image source) async {
    const w = 256.0;
    final h = (w * source.height / source.width).clamp(1.0, 1024.0);
    final sigma = ((widget.style == BlurBackdropStyle.lyrics ? 46.0 : 34.0) *
            widget.blurScale)
        .clamp(6.0, 90.0);

    // Cover-crop so the tile matches the screen aspect without stretching.
    final destAspect = w / h;
    final srcAspect = source.width / source.height;
    late final Rect src;
    if (srcAspect > destAspect) {
      final cw = source.height * destAspect;
      src = Rect.fromLTWH(
          (source.width - cw) / 2, 0, cw, source.height.toDouble());
    } else {
      final ch = source.width / destAspect;
      src = Rect.fromLTWH(
          0, (source.height - ch) / 2, source.width.toDouble(), ch);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    // Overscan so blur samples real pixels at the tile borders (no hard cut).
    final over = 1.35 + (sigma / 90.0).clamp(0.0, 1.0) * 0.35;
    final drawn = Rect.fromCenter(
        center: Offset(w / 2, h / 2), width: w * over, height: h * over);
    canvas.drawImageRect(
      source,
      src,
      drawn,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma * 0.5,
            sigmaY: sigma * 0.5,
            tileMode: ui.TileMode.clamp),
    );
    return (await recorder.endRecording().toImage(w.toInt(), h.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final osReduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final still =
        widget.motion == BackdropMotion.still || reduceMotionEnabled || osReduce;

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final phase = still ? 0.25 : _clock.value * 2 * math.pi;
        return CustomPaint(
          painter: _SpicyPainter(
            image: _blurred,
            palette: widget.palette,
            phase: phase,
            still: still,
            style: widget.style,
          ),
        );
      },
    );
  }
}

class _SpicyPainter extends CustomPainter {
  final ui.Image? image;
  final List<Color> palette;
  final double phase;
  final bool still;
  final BlurBackdropStyle style;

  _SpicyPainter({
    required this.image,
    required this.palette,
    required this.phase,
    required this.still,
    required this.style,
  });

  static final ColorFilter _saturate = ColorFilter.matrix(_sat(1.5));

  static List<double> _sat(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final inv = 1 - s;
    return [
      r * inv + s, g * inv, b * inv, 0, 0,
      r * inv, g * inv + s, b * inv, 0, 0,
      r * inv, g * inv, b * inv + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kSurfaceColor);

    final img = image;
    if (img == null) {
      _fallbackBlobs(canvas, size);
      return;
    }

    final center = size.center(Offset.zero);
    // Integer-multiple drift only -> the loop wrap is invisible.
    final amp = still ? 0.0 : 1.0;
    final dx = size.width * 0.035 * amp * math.cos(phase);
    final dy = size.height * 0.030 * amp * math.sin(phase * 2);
    final breathe = 1.16 + (still ? 0.0 : 0.045 * math.sin(phase));

    // 1) Base plate — Ken-Burns cover.
    _drawCover(
        canvas,
        img,
        Rect.fromCenter(
            center: center.translate(dx, dy),
            width: size.longestSide * breathe,
            height: size.longestSide * breathe),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(
              alpha: style == BlurBackdropStyle.lyrics ? 0.80 : 0.92));

    // 2) Glow copy — slightly rotated, screen-blended, saturated:
    //    the warm bleed that reads as "alive" without moving fast.
    canvas.save();
    canvas.translate(center.dx - dx * 1.5, center.dy - dy * 1.5);
    canvas.rotate(still ? 0.0 : 0.10 * math.sin(phase));
    final g = size.longestSide * breathe * 1.35;
    _drawCover(canvas, img, Rect.fromCenter(center: Offset.zero, width: g, height: g),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.screen
          ..colorFilter = _saturate
          ..color = Colors.white.withValues(
              alpha: style == BlurBackdropStyle.lyrics ? 0.22 : 0.30));
    canvas.restore();
  }

  /// Cover-fit drawImageRect (no distortion, no letterbox gaps).
  void _drawCover(Canvas canvas, ui.Image img, Rect dest, Paint paint) {
    final dAspect = dest.width / dest.height;
    final sAspect = img.width / img.height;
    late final Rect crop;
    if (sAspect > dAspect) {
      final cw = img.height * dAspect;
      crop =
          Rect.fromLTWH((img.width - cw) / 2, 0, cw, img.height.toDouble());
    } else {
      final ch = img.width / dAspect;
      crop = Rect.fromLTWH(
          0, (img.height - ch) / 2, img.width.toDouble(), ch);
    }
    canvas.drawImageRect(img, crop, dest, paint);
  }

  void _fallbackBlobs(Canvas canvas, Size size) {
    final colors = palette.length >= 2 ? palette : kBrandGradient;
    final amp = still ? 0.0 : 1.0;
    for (var i = 0; i < colors.length.clamp(1, 3); i++) {
      final c = Color.lerp(colors[i], kSurfaceColor, 0.25)!;
      final orbit = 0.14 * amp;
      final cx =
          size.width * (0.5 + orbit * math.cos(phase * (1 + i) + i * 2.4));
      final cy =
          size.height * (0.45 + orbit * math.sin(phase * (2 + i) + i * 1.7));
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            size.shortestSide * (0.55 + 0.10 * math.sin(phase + i)),
            [c.withValues(alpha: 0.55), c.withValues(alpha: 0)],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_SpicyPainter old) =>
      old.phase != phase || old.image != image || old.still != still;
}

/// Palette wash so the colour always reads as *this* track's.
class _Wash extends StatelessWidget {
  final List<Color> palette;
  final BlurBackdropStyle style;
  const _Wash({required this.palette, required this.style});

  @override
  Widget build(BuildContext context) {
    final primary = palette.isNotEmpty ? palette.first : kBrandColor;
    final secondary = palette.length > 1 ? palette.last : kSecondaryColor;
    final s = style == BlurBackdropStyle.lyrics ? 0.20 : 0.26;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: s),
              Colors.transparent,
              secondary.withValues(alpha: s * 0.8)
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Spicy's signature: deep vignette top/bottom, clear middle, dark edges.
class _Veil extends StatelessWidget {
  final BlurBackdropStyle style;
  const _Veil({required this.style});

  @override
  Widget build(BuildContext context) {
    final isLyrics = style == BlurBackdropStyle.lyrics;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: isLyrics ? 0.58 : 0.42),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: isLyrics ? 0.46 : 0.34),
              kSurfaceColor.withValues(alpha: isLyrics ? 0.88 : 0.85),
            ],
            stops: isLyrics
                ? const [0.0, 0.28, 0.45, 0.78, 1.0]
                : const [0.0, 0.26, 0.44, 0.80, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.05,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: isLyrics ? 0.40 : 0.30)
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticWash extends StatelessWidget {
  final List<Color> palette;
  final BlurBackdropStyle style;
  const _StaticWash({required this.palette, required this.style});

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
                Color.lerp(colors.first, kSurfaceColor, 0.35)!,
                kSurfaceColor,
                Color.lerp(colors.last, kSurfaceColor, 0.55)!,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        _Veil(style: style),
      ],
    );
  }
}

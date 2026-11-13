import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../theme/app_theme.dart';

/// Home banner looks. [auto] rotates through the others by day of year, so the
/// home screen feels fresh without the user choosing.
enum HomeBannerStyle {
  auto('Auto (changes daily)', 'A different banner each day'),
  classic('Classic discs', 'Violet wash with three gradient discs'),
  aurora('Aurora', 'Soft drifting colour clouds'),
  vinyl('Vinyl', 'A spinning-record look using the song colours'),
  sunset('Sunset', 'Warm gradient with a low sun and stripes'),
  equalizer('Equalizer', 'Glowing level bars along the base'),
  cover('Cover art', 'Blurred artwork with a tilted cover'),
  minimal('Minimal', 'Quiet card with a single ring');

  const HomeBannerStyle(this.label, this.description);
  final String label;
  final String description;

  /// The concrete look to draw (resolves [auto]).
  HomeBannerStyle resolve([DateTime? now]) {
    if (this != auto) return this;
    const pool = [aurora, vinyl, sunset, equalizer, cover, classic, minimal];
    final d = now ?? DateTime.now();
    final dayOfYear = d.difference(DateTime(d.year)).inDays;
    return pool[dayOfYear % pool.length];
  }

  HomeBannerStyle get next =>
      HomeBannerStyle.values[(index + 1) % HomeBannerStyle.values.length];
}

/// Decorative layer for a non-classic banner. Never interactive.
class HeroBackdrop extends StatelessWidget {
  final HomeBannerStyle style;
  final Song song;
  final bool wide;
  const HeroBackdrop(
      {super.key, required this.style, required this.song, required this.wide});

  @override
  Widget build(BuildContext context) {
    final c = song.gradientColors;
    final a = c.isNotEmpty ? c.first : kBrandColor;
    final b = c.length > 1 ? c.last : kSecondaryColor;
    return IgnorePointer(
      child: switch (style) {
        HomeBannerStyle.aurora => _aurora(a, b),
        HomeBannerStyle.vinyl => _vinyl(a, b),
        HomeBannerStyle.sunset => _sunset(),
        HomeBannerStyle.equalizer => _equalizer(a, b),
        HomeBannerStyle.cover => _cover(a, b),
        HomeBannerStyle.minimal => _minimal(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _blob(Color color, Alignment at, double radius) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
                center: at,
                radius: radius,
                colors: [color, Colors.transparent]),
          ),
        ),
      );

  Widget _aurora(Color a, Color b) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0E1220))),
        _blob(kBrandColor.withValues(alpha: 0.55), const Alignment(-0.7, -0.8), 1.0),
        _blob(kSecondaryColor.withValues(alpha: 0.35), const Alignment(0.2, 1.0), 1.0),
        _blob(kAccentColor.withValues(alpha: 0.40), const Alignment(1.0, -0.4), 0.9),
        _blob(a.withValues(alpha: 0.25), const Alignment(0.6, 0.6), 0.7),
      ]);

  Widget _vinyl(Color a, Color b) {
    final size = wide ? 380.0 : 220.0;
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(a, Colors.black, 0.72)!,
                  const Color(0xFF0B0F14)
                ]),
          ),
        ),
      ),
      Positioned(
        right: wide ? 70 : -70,
        top: wide ? 10 : -20,
        bottom: wide ? 10 : null,
        child: Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _VinylPainter(a, b)),
          ),
        ),
      ),
    ]);
  }

  Widget _sunset() => Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1B0F3D),
                    Color(0xFF7C3AED),
                    Color(0xFFEC4899),
                    Color(0xFFF59E0B)
                  ],
                  stops: [0, 0.45, 0.78, 1]),
            ),
          ),
        ),
        Positioned(
          right: wide ? 120 : -40,
          bottom: wide ? -120 : -80,
          child: Container(
            width: wide ? 340 : 200,
            height: wide ? 340 : 200,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFDE68A), Color(0xFFF97316)]),
              boxShadow: [BoxShadow(color: Color(0x66F59E0B), blurRadius: 90)],
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _StripePainter())),
      ]);

  Widget _equalizer(Color a, Color b) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0B0F1A))),
        _blob(kBrandColor.withValues(alpha: 0.30), const Alignment(0.8, 1.0), 1.2),
        Positioned(
          left: wide ? 340 : 0,
          right: 0,
          bottom: 0,
          height: wide ? 260 : 110,
          child: CustomPaint(painter: _BarsPainter(kAccentColor, kBrandColor)),
        ),
      ]);

  Widget _cover(Color a, Color b) {
    final art = song.artwork;
    final size = wide ? 280.0 : 150.0;
    return Stack(children: [
      Positioned.fill(
        child: art != null
            ? ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Image(image: art, fit: BoxFit.cover),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [a, b]))),
      ),
      Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.55))),
      Positioned(
        right: wide ? 90 : 16,
        top: wide ? null : 16,
        bottom: wide ? 0 : null,
        child: wide
            ? Center(child: _tile(art, a, b, size))
            : _tile(art, a, b, size),
      ),
    ]);
  }

  Widget _tile(ImageProvider? art, Color a, Color b, double size) =>
      Transform.rotate(
        angle: 0.07,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: art == null ? LinearGradient(colors: [a, b]) : null,
            image: art == null
                ? null
                : DecorationImage(image: art, fit: BoxFit.cover),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24))
            ],
          ),
        ),
      );

  Widget _minimal() => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF111723))),
        Positioned(
          right: wide ? 80 : -60,
          top: wide ? 40 : -40,
          child: Container(
            width: wide ? 300 : 180,
            height: wide ? 300 : 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: kBrandColor.withValues(alpha: 0.55), width: 2),
            ),
          ),
        ),
        Positioned(
          right: wide ? 130 : -20,
          top: wide ? 90 : 10,
          child: Container(
            width: wide ? 200 : 100,
            height: wide ? 200 : 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
          ),
        ),
      ]);
}

class _VinylPainter extends CustomPainter {
  final Color a, b;
  _VinylPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
                  colors: [Color(0xFF1A1F2B), Color(0xFF07090D)])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 1; i < 16; i++) {
      canvas.drawCircle(c, r * (0.38 + i * 0.039), groove);
    }
    // Light sheen.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.08),
            Colors.transparent
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
    // Label.
    canvas.drawCircle(
        c,
        r * 0.30,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [a, b])
              .createShader(Rect.fromCircle(center: c, radius: r * 0.3)));
    canvas.drawCircle(c, r * 0.035, Paint()..color = const Color(0xFF0B0F14));
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.a != a || old.b != b;
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.10);
    var y = size.height * 0.62;
    var h = 3.0;
    while (y < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), p);
      y += h + 7;
      h += 1.2;
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => false;
}

class _BarsPainter extends CustomPainter {
  final Color top, bottom;
  _BarsPainter(this.top, this.bottom);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 28;
    final gap = 6.0;
    final w = (size.width - gap * (n - 1)) / n;
    final paint = Paint()
      ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top.withValues(alpha: 0.9), bottom.withValues(alpha: 0.15)])
          .createShader(Offset.zero & size);
    for (var i = 0; i < n; i++) {
      final f = 0.25 +
          0.75 * ((math.sin(i * 0.55) + math.sin(i * 1.3 + 1.2) + 2) / 4);
      final h = size.height * f;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(i * (w + gap), size.height - h, w, h),
              const Radius.circular(5)),
          paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => false;
}

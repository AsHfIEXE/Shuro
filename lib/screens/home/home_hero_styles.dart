import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/album.dart';
import '../../models/song.dart';
import '../../theme/app_theme.dart';

/// Home banner looks. [auto] rotates through the others by day of year, so the
/// home screen feels fresh without the user choosing.
enum HomeBannerStyle {
  auto('Auto (changes daily)', 'A different banner each day'),
  spotlight('Album spotlight', 'Your albums, one at a time, with the cover up front'),
  wall('Album wall', 'A tilted wall of your real album covers that keeps changing'),
  vinyl('Vinyl', 'A spinning-record look using the song colours'),
  equalizer('Equalizer', 'Glowing level bars along the base'),
  cover('Cover art', 'Blurred artwork with a tilted cover'),
  minimal('Minimal', 'Quiet card with a single ring');

  const HomeBannerStyle(this.label, this.description);
  final String label;
  final String description;

  /// The concrete look to draw (resolves [auto]).
  HomeBannerStyle resolve([DateTime? now]) {
    if (this != auto) return this;
    const pool = [spotlight, wall, cover, vinyl, equalizer, minimal];
    final d = now ?? DateTime.now();
    final dayOfYear = d.difference(DateTime(d.year)).inDays;
    return pool[dayOfYear % pool.length];
  }

  HomeBannerStyle get next =>
      HomeBannerStyle.values[(index + 1) % HomeBannerStyle.values.length];
}

/// Decorative layer for a banner. Never interactive.
class HeroBackdrop extends StatelessWidget {
  final HomeBannerStyle style;
  final Song song;
  final bool wide;

  /// Real albums from the library (recently played first). The album styles
  /// cycle through these; other styles ignore them.
  final List<Album> albums;
  final void Function(Album album)? onOpenAlbum;
  const HeroBackdrop(
      {super.key,
      required this.style,
      required this.song,
      required this.wide,
      this.albums = const [],
      this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    final c = song.gradientColors;
    final a = c.isNotEmpty ? c.first : kBrandColor;
    final b = c.length > 1 ? c.last : kSecondaryColor;
    if (style == HomeBannerStyle.spotlight && albums.isNotEmpty) {
      return _AlbumSpotlight(
          albums: albums, wide: wide, onOpenAlbum: onOpenAlbum);
    }
    if (style == HomeBannerStyle.wall && albums.length >= 4) {
      return IgnorePointer(child: _AlbumWall(albums: albums, wide: wide));
    }
    return IgnorePointer(
      child: switch (style) {
        HomeBannerStyle.vinyl => _vinyl(a, b),
        HomeBannerStyle.spotlight || HomeBannerStyle.wall => _cover(a, b),
        HomeBannerStyle.equalizer => _equalizer(a, b),
        HomeBannerStyle.cover => _cover(a, b),
        HomeBannerStyle.minimal => _minimal(),
        _ => const SizedBox.shrink(),
      },
    );
  }

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

  Widget _equalizer(Color a, Color b) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0B0F1A))),
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

bool _reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

Widget _albumArt(Album album, {double? radius, BoxFit fit = BoxFit.cover}) {
  final art = album.artwork;
  final c = album.gradientColors;
  return DecoratedBox(
    key: ValueKey(album.id),
    decoration: BoxDecoration(
      borderRadius: radius == null ? null : BorderRadius.circular(radius),
      gradient: art == null
          ? LinearGradient(colors: c.length > 1 ? c : [kBrandColor, kSecondaryColor])
          : null,
      image: art == null ? null : DecorationImage(image: art, fit: fit),
    ),
    child: const SizedBox.expand(),
  );
}

/// One real album at a time: blurred cover as the backdrop, the cover itself
/// up front with its title, swapping every few seconds. Tap opens the album.
class _AlbumSpotlight extends StatefulWidget {
  final List<Album> albums;
  final bool wide;
  final void Function(Album album)? onOpenAlbum;
  const _AlbumSpotlight(
      {required this.albums, required this.wide, this.onOpenAlbum});

  @override
  State<_AlbumSpotlight> createState() => _AlbumSpotlightState();
}

class _AlbumSpotlightState extends State<_AlbumSpotlight> {
  int _i = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (!_reduceMotion(context) && widget.albums.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.albums.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.albums[_i % widget.albums.length];
    final size = widget.wide ? 260.0 : 130.0;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            child: SizedBox.expand(
              key: ValueKey('bg-${album.id}'),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: _albumArt(album),
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
          child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.58)))),
      Positioned(
        right: widget.wide ? 70 : 16,
        top: widget.wide ? 0 : 16,
        bottom: widget.wide ? 0 : null,
        child: Align(
          alignment: widget.wide ? Alignment.centerRight : Alignment.topRight,
          child: GestureDetector(
            onTap: widget.onOpenAlbum == null
                ? null
                : () => widget.onOpenAlbum!(album),
            child: MouseRegion(
              cursor: widget.onOpenAlbum == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 40,
                            offset: Offset(0, 20))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        child: _albumArt(album),
                      ),
                    ),
                  ),
                  if (widget.wide) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size),
                      child: Text(
                        '${album.title} · ${album.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// A tilted wall of real album covers; one tile at a time swaps to another
/// album, so the banner keeps changing without a big motion.
class _AlbumWall extends StatefulWidget {
  final List<Album> albums;
  final bool wide;
  const _AlbumWall({required this.albums, required this.wide});

  @override
  State<_AlbumWall> createState() => _AlbumWallState();
}

class _AlbumWallState extends State<_AlbumWall> {
  static const int _cols = 4, _rows = 3;
  late final List<int> _slot =
      List.generate(_cols * _rows, (i) => i % widget.albums.length);
  int _next = 0;
  int _cursor = _cols * _rows;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (!_reduceMotion(context) && widget.albums.length > _cols * _rows ~/ 2) {
      _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
        if (!mounted) return;
        setState(() {
          _slot[_next] = _cursor % widget.albums.length;
          _cursor++;
          _next = (_next + 5) % (_cols * _rows);
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = widget.wide ? 132.0 : 78.0;
    const gap = 12.0;
    final w = _cols * tile + (_cols - 1) * gap;
    final h = _rows * tile + (_rows - 1) * gap;
    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: Color(0xFF0B0F14))),
      Positioned(
        right: widget.wide ? -20 : -40,
        top: widget.wide ? 20 : -10,
        child: Transform.rotate(
          angle: -0.14,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              for (var i = 0; i < _cols * _rows; i++)
                Positioned(
                  left: (i % _cols) * (tile + gap),
                  top: (i ~/ _cols) * (tile + gap),
                  width: tile,
                  height: tile,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      child: _albumArt(widget.albums[_slot[i]]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      // Scrim so the copy on the left stays readable over the covers.
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                const Color(0xFF0B0F14),
                const Color(0xFF0B0F14).withValues(alpha: 0.82),
                Colors.transparent
              ],
              stops: [0.0, widget.wide ? 0.42 : 0.55, 1.0],
            ),
          ),
        ),
      ),
    ]);
  }
}

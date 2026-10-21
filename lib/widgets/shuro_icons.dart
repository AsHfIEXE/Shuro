import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shuro's own icon language — hand-drawn vector glyphs (CustomPainter,
/// like [AppLogo]; no SVG asset, nothing to bundle) for the controls and
/// cards people look at the most, instead of the stock Material icon for
/// the same action. Everything is drawn inside a 24x24 logical box scaled
/// to [size], so a [ShuroIcon] drops in anywhere an [Icon] would.
enum ShuroGlyph {
  play,
  pause,
  previous,
  next,
  shuffle,
  repeat,
  heartOutline,
  heartFilled,
  playlistAdd,
  queueAdd,
  download,
  // Genre glyphs — one abstract mark per common genre family, used big
  // and semi-transparent on genre cards (see library_screen.dart).
  genreNote,
  genreDoubleNote,
  genreStar,
  genreBolt,
  genreWaves,
  genreMic,
  genreLeaf,
}

class ShuroIcon extends StatelessWidget {
  final ShuroGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  const ShuroIcon(this.glyph, {super.key, this.size = 24, this.color = Colors.white, this.strokeWidth = 1.8});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShuroIconPainter(glyph: glyph, color: color, strokeWidth: strokeWidth)),
    );
  }
}

class _ShuroIconPainter extends CustomPainter {
  final ShuroGlyph glyph;
  final Color color;
  final double strokeWidth;

  _ShuroIconPainter({required this.glyph, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is drawn in a 24x24 logical box, then scaled —
    // keeps every glyph's proportions identical regardless of the
    // widget's actual pixel size.
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale, scale);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (glyph) {
      case ShuroGlyph.play:
        _play(canvas, fill);
      case ShuroGlyph.pause:
        _pause(canvas, fill);
      case ShuroGlyph.previous:
        _previous(canvas, fill);
      case ShuroGlyph.next:
        _next(canvas, fill);
      case ShuroGlyph.shuffle:
        _shuffle(canvas, stroke, fill);
      case ShuroGlyph.repeat:
        _repeat(canvas, stroke, fill);
      case ShuroGlyph.heartOutline:
        _heart(canvas, stroke, filled: false);
      case ShuroGlyph.heartFilled:
        _heart(canvas, fill, filled: true);
      case ShuroGlyph.playlistAdd:
        _playlistAdd(canvas, fill);
      case ShuroGlyph.queueAdd:
        _queueAdd(canvas, fill);
      case ShuroGlyph.download:
        _download(canvas, stroke, fill);
      case ShuroGlyph.genreNote:
        _note(canvas, fill);
      case ShuroGlyph.genreDoubleNote:
        _doubleNote(canvas, fill);
      case ShuroGlyph.genreStar:
        _star(canvas, fill);
      case ShuroGlyph.genreBolt:
        _bolt(canvas, fill);
      case ShuroGlyph.genreWaves:
        _waves(canvas, stroke);
      case ShuroGlyph.genreMic:
        _mic(canvas, fill, stroke);
      case ShuroGlyph.genreLeaf:
        _leaf(canvas, fill, stroke);
    }

    canvas.restore();
  }

  // A small rightward nudge on the play triangle — its visual centroid
  // sits left of a true geometric center, so an unshifted triangle always
  // reads as off-center to the eye.
  void _play(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(7.5, 4.5)
      ..lineTo(19.5, 12)
      ..lineTo(7.5, 19.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _pause(Canvas canvas, Paint paint) {
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5.5, 4.5, 4.5, 15), const Radius.circular(2)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 4.5, 4.5, 15), const Radius.circular(2)), paint);
  }

  void _previous(Canvas canvas, Paint paint) {
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4.5, 3, 15), const Radius.circular(1.5)), paint);
    final tri = Path()
      ..moveTo(19, 4.8)
      ..lineTo(19, 19.2)
      ..lineTo(8.3, 12)
      ..close();
    canvas.drawPath(tri, paint);
  }

  void _next(Canvas canvas, Paint paint) {
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16.5, 4.5, 3, 15), const Radius.circular(1.5)), paint);
    final tri = Path()
      ..moveTo(5, 4.8)
      ..lineTo(5, 19.2)
      ..lineTo(15.7, 12)
      ..close();
    canvas.drawPath(tri, paint);
  }

  // Two crossing diagonals with a small arrowhead where each exits —
  // reads as "shuffle" without copying the stock glyph's exact shape.
  void _shuffle(Canvas canvas, Paint stroke, Paint fill) {
    final p1 = Path()
      ..moveTo(4, 6)
      ..lineTo(9.5, 6)
      ..cubicTo(13, 6, 13, 18, 16.5, 18)
      ..lineTo(19, 18);
    final p2 = Path()
      ..moveTo(4, 18)
      ..lineTo(9.5, 18)
      ..cubicTo(13, 18, 13, 6, 16.5, 6)
      ..lineTo(19, 6);
    canvas.drawPath(p1, stroke);
    canvas.drawPath(p2, stroke);
    _arrowHead(canvas, fill, tip: const Offset(20.6, 18), angle: 0);
    _arrowHead(canvas, fill, tip: const Offset(20.6, 6), angle: 0);
  }

  void _arrowHead(Canvas canvas, Paint fill, {required Offset tip, required double angle}) {
    const double s = 3.2;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - s, tip.dy - s * 0.62)
      ..lineTo(tip.dx - s, tip.dy + s * 0.62)
      ..close();
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    canvas.translate(-tip.dx, -tip.dy);
    canvas.drawPath(path, fill);
    canvas.restore();
  }

  // A loop made of two horizontal runs joined by two half-circle arcs,
  // with one arrowhead — the familiar "repeat" shape, simplified to arcs
  // + lines rather than a traced icon-font glyph.
  void _repeat(Canvas canvas, Paint stroke, Paint fill) {
    final path = Path()
      ..moveTo(7, 5.5)
      ..lineTo(15, 5.5)
      ..arcToPoint(const Offset(15, 12.5), radius: const Radius.circular(3.5), clockwise: true)
      ..lineTo(15, 12.5);
    canvas.drawPath(path, stroke);
    final path2 = Path()
      ..moveTo(17, 18.5)
      ..lineTo(9, 18.5)
      ..arcToPoint(const Offset(9, 11.5), radius: const Radius.circular(3.5), clockwise: true);
    canvas.drawPath(path2, stroke);
    _arrowHead(canvas, fill, tip: const Offset(17.4, 5.5), angle: math.pi / 2);
    _arrowHead(canvas, fill, tip: const Offset(6.6, 18.5), angle: -math.pi / 2);
  }

  void _heart(Canvas canvas, Paint paint, {required bool filled}) {
    final path = Path()
      ..moveTo(12, 19)
      ..cubicTo(3.5, 13, 3, 8.2, 6.2, 6)
      ..cubicTo(9, 4.1, 11.3, 6, 12, 7.6)
      ..cubicTo(12.7, 6, 15, 4.1, 17.8, 6)
      ..cubicTo(21, 8.2, 20.5, 13, 12, 19)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _bars(Canvas canvas, Paint fill, List<double> widths) {
    const double y0 = 6, gap = 5, h = 2.4, x = 4;
    for (var i = 0; i < widths.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y0 + i * gap, widths[i], h), const Radius.circular(1.2)),
        fill,
      );
    }
  }

  void _plusBadge(Canvas canvas, Paint fill, Offset center) {
    canvas.drawCircle(center, 5, fill);
    final h = Path()
      ..moveTo(center.dx - 2.4, center.dy)
      ..lineTo(center.dx + 2.4, center.dy);
    final v = Path()
      ..moveTo(center.dx, center.dy - 2.4)
      ..lineTo(center.dx, center.dy + 2.4);
    final plusStroke = Paint()
      ..color = const Color(0xFF121214)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(h, plusStroke);
    canvas.drawPath(v, plusStroke);
  }

  void _playlistAdd(Canvas canvas, Paint fill) {
    _bars(canvas, fill, [13, 10, 7]);
    _plusBadge(canvas, fill, const Offset(17.5, 18));
  }

  void _queueAdd(Canvas canvas, Paint fill) {
    _bars(canvas, fill, [15, 15, 9]);
    _plusBadge(canvas, fill, const Offset(18, 18.5));
  }

  void _download(Canvas canvas, Paint stroke, Paint fill) {
    final shaft = Path()
      ..moveTo(12, 3.5)
      ..lineTo(12, 14.5);
    canvas.drawPath(shaft, stroke);
    final head = Path()
      ..moveTo(7, 11)
      ..lineTo(12, 16)
      ..lineTo(17, 11);
    canvas.drawPath(head, stroke);
    final tray = Path()
      ..moveTo(4.5, 17)
      ..lineTo(4.5, 19.5)
      ..lineTo(19.5, 19.5)
      ..lineTo(19.5, 17);
    canvas.drawPath(tray, stroke);
  }

  // --- genre glyphs --------------------------------------------------

  void _note(Canvas canvas, Paint fill) {
    canvas.drawOval(const Rect.fromLTWH(5, 15, 6.5, 5), fill);
    final stem = Path()
      ..moveTo(11.3, 17.2)
      ..lineTo(11.3, 4.5)
      ..lineTo(18.5, 3)
      ..lineTo(18.5, 14)
      ..lineTo(16.8, 14)
      ..lineTo(16.8, 5.3)
      ..lineTo(13, 6.1)
      ..lineTo(13, 17.2)
      ..close();
    canvas.drawPath(stem, fill);
  }

  void _doubleNote(Canvas canvas, Paint fill) {
    canvas.drawOval(const Rect.fromLTWH(2.5, 15.5, 5.5, 4.4), fill);
    canvas.drawOval(const Rect.fromLTWH(12.5, 13, 5.5, 4.4), fill);
    final beam = Path()
      ..moveTo(7.6, 17.6)
      ..lineTo(7.6, 5)
      ..lineTo(17.6, 3)
      ..lineTo(17.6, 15.1)
      ..lineTo(16, 15.1)
      ..lineTo(16, 5.9)
      ..lineTo(9.2, 7.3)
      ..lineTo(9.2, 17.6)
      ..close();
    canvas.drawPath(beam, fill);
  }

  void _star(Canvas canvas, Paint fill) {
    const cx = 12.0, cy = 12.2, outerR = 9.0, innerR = 3.6;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
  }

  void _bolt(Canvas canvas, Paint fill) {
    final path = Path()
      ..moveTo(13.2, 2)
      ..lineTo(5, 13.5)
      ..lineTo(10.6, 13.5)
      ..lineTo(9.4, 22)
      ..lineTo(19, 9.5)
      ..lineTo(13, 9.5)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _waves(Canvas canvas, Paint stroke) {
    for (var i = 0; i < 3; i++) {
      final r = 4.0 + i * 4.2;
      canvas.drawArc(Rect.fromCircle(center: const Offset(4, 22), radius: r), -math.pi / 2, math.pi / 2, false, stroke);
    }
  }

  void _mic(Canvas canvas, Paint fill, Paint stroke) {
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(9, 2.5, 6, 11), const Radius.circular(3)), fill);
    final stand = Path()..moveTo(6, 11)..arcToPoint(const Offset(18, 11), radius: const Radius.circular(6), clockwise: false);
    canvas.drawPath(stand, stroke);
    canvas.drawLine(const Offset(12, 17), const Offset(12, 20.5), stroke);
    canvas.drawLine(const Offset(8, 20.5), const Offset(16, 20.5), stroke);
  }

  void _leaf(Canvas canvas, Paint fill, Paint stroke) {
    final path = Path()
      ..moveTo(19, 4)
      ..cubicTo(19, 13, 13, 19, 4, 19)
      ..cubicTo(4.5, 10, 10, 4.5, 19, 4)
      ..close();
    canvas.drawPath(path, fill);
    final vein = Path()
      ..moveTo(17, 6)
      ..cubicTo(12, 9, 8, 13, 5.5, 17.5);
    canvas.drawPath(vein, stroke..color = stroke.color.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _ShuroIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Maps a free-text genre name to one of the glyphs above, by loose
/// keyword match — good enough for a decorative card mark, not meant to
/// be an authoritative genre taxonomy. Anything unmatched gets the plain
/// single-note mark rather than a blank card.
ShuroGlyph glyphForGenre(String genre) {
  final g = genre.toLowerCase();
  bool any(List<String> words) => words.any(g.contains);

  if (any(['rock', 'metal', 'punk', 'grunge'])) return ShuroGlyph.genreBolt;
  if (any(['pop', 'dance', 'disco'])) return ShuroGlyph.genreStar;
  if (any(['electro', 'edm', 'house', 'techno', 'trance', 'dubstep', 'drum'])) return ShuroGlyph.genreWaves;
  if (any(['hip hop', 'hip-hop', 'rap', 'r&b', 'rnb', 'trap'])) return ShuroGlyph.genreMic;
  if (any(['jazz', 'classical', 'orchestra', 'instrumental', 'soundtrack'])) return ShuroGlyph.genreDoubleNote;
  if (any(['folk', 'acoustic', 'country', 'indie', 'singer'])) return ShuroGlyph.genreLeaf;
  return ShuroGlyph.genreNote;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import 'abs_widgets.dart';

/// Audiobook player. Desktop: ring + cover on the left, chapter list on the
/// right. Android: cover, scrubber, transport, speed/chapters row.
class AbsPlayerScreen extends StatelessWidget {
  const AbsPlayerScreen({super.key, required this.item});
  final SpokenItem item;

  static const _speeds = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          return StreamBuilder<Duration>(
            stream: p.smoothPositionStream,
            initialData: p.position,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final total = item.duration > Duration.zero ? item.duration : p.duration;
              final frac = total.inMilliseconds == 0
                  ? 0.0
                  : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
              final curIdx = item.chapters.lastIndexWhere((ch) => ch.start <= pos.inSeconds);
              final chapter = curIdx >= 0 ? item.chapters[curIdx] : null;

              final stage = _Stage(
                item: item, p: p, pos: pos, total: total, frac: frac,
                chapterLine: chapter == null
                    ? ''
                    : 'Chapter ${curIdx + 1} of ${item.chapters.length} · ${chapter.title}',
                wide: wide,
              );
              if (!wide) return stage;
              return Row(children: [
                SizedBox(width: 560, child: stage),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 48, 40, 0),
                    child: _Chapters(item: item, current: curIdx, p: p),
                  ),
                ),
              ]);
            },
          );
        }),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.item, required this.p, required this.pos, required this.total,
      required this.frac, required this.chapterLine, required this.wide});
  final SpokenItem item;
  final PlayerController p;
  final Duration pos, total;
  final double frac;
  final String chapterLine;
  final bool wide;

  void _skip(int s) {
    final t = pos + Duration(seconds: s);
    p.seekTo(t < Duration.zero ? Duration.zero : (t > total ? total : t));
  }

  @override
  Widget build(BuildContext context) {
    final size = wide ? 420.0 : 280.0;
    return Column(children: [
      if (!wide)
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kTextColor, size: 30)),
        ),
      SizedBox(height: wide ? 56 : 8),
      SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          if (wide)
            CustomPaint(size: Size.square(size), painter: _RingPainter(frac)),
          wide
              ? ClipOval(
                  child: SizedBox(
                      width: size * 0.72,
                      height: size * 0.72,
                      child: Center(child: AbsCover(item, width: 148, height: 222, radius: 8))))
              : AbsCover(item, width: size * 0.66, height: size, radius: 14),
        ]),
      ),
      SizedBox(height: wide ? 28 : 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: absHeading(wide ? 28 : 22, ls: -0.6)),
          const SizedBox(height: 6),
          Text(item.creator, style: absText(15, color: kVioletLight, w: FontWeight.w600)),
          if (chapterLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(chapterLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: absText(13, color: kMuted2)),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: kBrandColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: frac,
              onChanged: (v) => p.seekTo(Duration(milliseconds: (v * total.inMilliseconds).round())),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(absClock(pos), style: absText(12, color: kMuted2, tabular: true)),
            Text('-${absClock(total - pos)}', style: absText(12, color: kMuted2, tabular: true)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(iconSize: 32, tooltip: 'Back 15 s',
            onPressed: () => _skip(-15), icon: const Icon(Icons.replay_10_rounded, color: kTextColor)),
        const SizedBox(width: 12),
        SizedBox(
          width: 72, height: 72,
          child: FilledButton(
            onPressed: p.togglePlayPause,
            style: FilledButton.styleFrom(
                backgroundColor: kBrandColor, shape: const CircleBorder(), padding: EdgeInsets.zero),
            child: Icon(p.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 40, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(iconSize: 32, tooltip: 'Forward 30 s',
            onPressed: () => _skip(30), icon: const Icon(Icons.forward_30_rounded, color: kTextColor)),
      ]),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Pill(
          label: '${p.playbackSpeed}×',
          onTap: () {
            final i = AbsPlayerScreen._speeds.indexOf(p.playbackSpeed);
            p.playbackSpeed = AbsPlayerScreen._speeds[(i + 1) % AbsPlayerScreen._speeds.length];
            p.applyPlaybackTweaksNow();
          },
        ),
        if (!wide) ...[
          const SizedBox(width: 10),
          _Pill(
            label: 'Chapters',
            icon: Icons.format_list_bulleted_rounded,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: kRaisedColor,
              showDragHandle: true,
              builder: (_) => SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: _Chapters(
                    item: item,
                    current: item.chapters.lastIndexWhere((ch) => ch.start <= pos.inSeconds),
                    p: p),
              ),
            ),
          ),
        ],
      ]),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: kNavText), const SizedBox(width: 6)],
            Text(label, style: absText(13, w: FontWeight.w600, tabular: true)),
          ]),
        ),
      );
}

class _Chapters extends StatelessWidget {
  const _Chapters({required this.item, required this.current, required this.p});
  final SpokenItem item;
  final int current;
  final PlayerController p;
  @override
  Widget build(BuildContext context) {
    if (item.chapters.isEmpty) {
      return Center(child: Text('No chapters', style: absText(14, color: kMuted2)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Text('CHAPTERS', style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.9)),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: item.chapters.length,
          itemBuilder: (_, i) {
            final ch = item.chapters[i];
            final cur = i == current;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => p.seekTo(Duration(seconds: ch.start.round())),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                    color: cur ? kBrandColor.withValues(alpha: 0.12) : null,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  SizedBox(
                      width: 40,
                      child: Center(
                          child: cur
                              ? const Icon(Icons.graphic_eq_rounded, size: 18, color: kVioletPale)
                              : Text('${i + 1}', style: absText(13, color: kMuted2, tabular: true)))),
                  Expanded(
                      child: Text(ch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: absText(14, w: FontWeight.w600, color: cur ? kVioletPale : kTextColor))),
                  Text(absClock(Duration(seconds: (ch.end - ch.start).round())),
                      style: absText(13, color: kMuted2, tabular: true)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac);
  final double frac;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 14;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = Colors.white.withValues(alpha: 0.12));
    final sweep = 6.2831853 * frac;
    canvas.drawArc(
        rect, -1.5707963, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(colors: [kAccentColor, kVioletLight]).createShader(rect));
    final a = -1.5707963 + sweep;
    canvas.drawCircle(Offset(c.dx + r * _cos(a), c.dy + r * _sin(a)), 10, Paint()..color = Colors.white);
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);
  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac;
}

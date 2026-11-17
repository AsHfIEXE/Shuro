import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/abs_stats.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';

/// Listening stats for Audiobookshelf: today / week / streak / all-time,
/// minutes-per-day bars with a goal line, weekday averages, most-listened
/// items and recent sessions. One responsive layout: >= 900 dp wide uses the
/// desktop arrangement, narrower is the single-column Android one.
///
/// Open with `Navigator.push(context, MaterialPageRoute(builder: (_) =>
/// const AbsStatsScreen()))`.
class AbsStatsScreen extends StatefulWidget {
  const AbsStatsScreen({super.key, this.goalMinutes = 45});

  /// Daily goal drawn as the dashed line.
  final int goalMinutes;

  @override
  State<AbsStatsScreen> createState() => _AbsStatsScreenState();
}

class _AbsStatsScreenState extends State<AbsStatsScreen> {
  late Future<AbsListeningStats?> _future;
  int _range = 14; // 14 | 30 | 90

  @override
  void initState() {
    super.initState();
    _future = context.read<SpokenLibraryState>().loadStats();
  }

  Future<void> _reload() async {
    final f = context.read<SpokenLibraryState>().loadStats();
    setState(() => _future = f);
    await f.catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        child: FutureBuilder<AbsListeningStats?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return _Message(
                title: "Couldn't load your stats",
                body: 'Check the Audiobookshelf connection and try again.',
                onRetry: _reload,
              );
            }
            final stats = snap.data!;
            if (stats.days.isEmpty && stats.totalSeconds <= 0) {
              return const _Message(
                title: 'No listening yet',
                body: 'Play a book or an episode and your stats appear here.',
              );
            }
            return RefreshIndicator(
              onRefresh: _reload,
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                return ListView(
                  padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 8, wide ? 40 : 16, 32),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: DesktopTokens.contentStandard),
                        child: _Body(
                          stats: stats,
                          wide: wide,
                          range: _range,
                          goalMinutes: widget.goalMinutes,
                          onRange: (v) => setState(() => _range = v),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

TextStyle _t(double size, Color color,
        [FontWeight w = FontWeight.w400, bool tabular = false]) =>
    GoogleFonts.getFont(currentFontFamily,
        fontSize: size,
        color: color,
        fontWeight: w,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null);

String _dur(double seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r m';
}

class _Body extends StatelessWidget {
  final AbsListeningStats stats;
  final bool wide;
  final int range;
  final int goalMinutes;
  final ValueChanged<int> onRange;
  const _Body({
    required this.stats,
    required this.wide,
    required this.range,
    required this.goalMinutes,
    required this.onRange,
  });

  @override
  Widget build(BuildContext context) {
    final today = stats.today();
    final yesterday = stats.lastDays(2).first.seconds;
    final week = stats.secondsInLast(7);
    final streak = stats.streak();

    final tiles = [
      _Tile('Today', _dur(today), _delta(today, yesterday)),
      _Tile('This week', _dur(week), 'Goal ${_dur(goalMinutes * 60.0 * 7)}'),
      _Tile('Streak', '$streak ${streak == 1 ? 'day' : 'days'}',
          'Best: ${stats.bestStreak}'),
      _Tile('All time', _dur(stats.totalSeconds), '${stats.top.length} titles'),
    ];

    final chart = _Card(
      title: 'Minutes per day',
      trailing: 'Goal $goalMinutes min',
      child: SizedBox(
        height: wide ? 220 : 160,
        child: CustomPaint(
          painter: _BarsPainter(
            days: stats.lastDays(range),
            goalMinutes: goalMinutes,
          ),
          size: Size.infinite,
        ),
      ),
    );

    final avg = stats.weekdayAverages();
    final maxAvg = avg.fold<double>(0, (a, b) => b > a ? b : a);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final bestIdx = maxAvg <= 0 ? -1 : avg.indexOf(maxAvg);
    final weekday = _Card(
      title: 'By weekday',
      subtitle: bestIdx < 0 ? null : '${names[bestIdx]} is your longest day',
      child: Column(
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 36, child: Text(names[i], style: _t(13, kNavText))),
                Expanded(
                  child: _Meter(
                    value: maxAvg <= 0 ? 0 : avg[i] / maxAvg,
                    color: i == bestIdx
                        ? kVioletPale
                        : kVioletLight.withValues(alpha: 0.55),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(_dur(avg[i]),
                      textAlign: TextAlign.right,
                      style: _t(12, kMuted2, FontWeight.w400, true)),
                ),
              ]),
            ),
        ],
      ),
    );

    final maxTop = stats.top.isEmpty ? 1.0 : stats.top.first.seconds;
    final top = _Section(
      title: 'Most listened',
      children: [
        for (final t in stats.top.take(5))
          _Row(
            title: t.title,
            meter: maxTop <= 0 ? 0 : t.seconds / maxTop,
            trailing: _dur(t.seconds),
          ),
      ],
    );
    final recent = _Section(
      title: 'Recent sessions',
      children: [
        for (final s in stats.recent.take(5))
          _Row(title: s.title, subtitle: _when(s.at), trailing: _dur(s.seconds)),
      ],
    );

    final rangePicker = _Segmented(
      value: range,
      options: const [(14, '14 days'), (30, '30 days'), (90, '90 days')],
      onChanged: onRange,
    );

    final header = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _Title()),
              rangePicker,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_Title(), const SizedBox(height: 14), rangePicker],
          );

    final tileBlock = Container(
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(wide ? 18 : 16),
        border: Border.all(color: kHairline),
      ),
      child: wide
          ? Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) Container(width: 1, height: 84, color: kHairline),
                Expanded(child: tiles[i]),
              ],
            ])
          : Column(children: [
              Row(children: [Expanded(child: tiles[0]), Container(width: 1, height: 76, color: kHairline), Expanded(child: tiles[1])]),
              Divider(height: 1, color: kHairline),
              Row(children: [Expanded(child: tiles[2]), Container(width: 1, height: 76, color: kHairline), Expanded(child: tiles[3])]),
            ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 24),
        tileBlock,
        const SizedBox(height: 24),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 17, child: chart),
            const SizedBox(width: 24),
            Expanded(flex: 10, child: weekday),
          ])
        else ...[chart, const SizedBox(height: 16), weekday],
        const SizedBox(height: 24),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: top),
            const SizedBox(width: 24),
            Expanded(child: recent),
          ])
        else ...[top, const SizedBox(height: 16), recent],
      ],
    );
  }

  static String _delta(double today, double yesterday) {
    final d = ((today - yesterday) / 60).round();
    if (d == 0) return 'Same as yesterday';
    return '${d > 0 ? '+' : '-'}${d.abs()} min vs yesterday';
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(at.year, at.month, at.day))
        .inDays;
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    if (days <= 0) return 'Today, $hm';
    if (days == 1) return 'Yesterday, $hm';
    return '${at.day}/${at.month}, $hm';
  }
}

class _Title extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: kTextColor),
            ),
            Text('BOOKS & PODCASTS',
                style: _t(12, kVioletLight, FontWeight.w700).copyWith(letterSpacing: 1.68)),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text('Listening stats',
                style: DesktopTokens.pageTitle(_t(36, Colors.white))),
          ),
        ],
      );
}

class _Tile extends StatelessWidget {
  final String label, value, note;
  const _Tile(this.label, this.value, this.note);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _t(13, kMuted2)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: _t(26, Colors.white, FontWeight.w800, true)
                      .copyWith(letterSpacing: -0.5)),
            ),
            const SizedBox(height: 4),
            Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(12, kMuted2, FontWeight.w400, true)),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget child;
  const _Card({required this.title, required this.child, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: kRaisedColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(title, style: _t(15, kTextColor, FontWeight.w700))),
                if (trailing != null) Text(trailing!, style: _t(12, kMuted2)),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: _t(12, kMuted2)),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _t(15, kTextColor, FontWeight.w700)),
          const SizedBox(height: 8),
          Divider(height: 1, color: kHairline),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Nothing yet', style: _t(13, kMuted2)),
            ),
          ...children,
        ],
      );
}

class _Row extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double? meter;
  final String trailing;
  const _Row({required this.title, required this.trailing, this.subtitle, this.meter});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kHairline))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(14, kTextColor, FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!, style: _t(13, kMuted2)),
                if (meter != null) ...[
                  const SizedBox(height: 6),
                  _Meter(value: meter!, color: kBrandColor, height: 3),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(trailing, style: _t(13, kNavText, FontWeight.w400, true)),
        ]),
      );
}

class _Meter extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const _Meter({required this.value, required this.color, this.height = 8});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => Stack(children: [
          Container(
            height: height,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(height / 2)),
          ),
          AnimatedContainer(
            duration: ShuroMotion.standard,
            curve: ShuroMotion.std,
            height: height,
            width: c.maxWidth * value.clamp(0.0, 1.0),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(height / 2)),
          ),
        ]),
      );
}

class _Segmented extends StatelessWidget {
  final int value;
  final List<(int, String)> options;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            GestureDetector(
              onTap: () => onChanged(v),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: ShuroMotion.fast,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? kBrandColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: _t(13, v == value ? Colors.white : kNavText, FontWeight.w600)),
                ),
              ),
            ),
        ]),
      );
}

class _Message extends StatelessWidget {
  final String title, body;
  final Future<void> Function()? onRetry;
  const _Message({required this.title, required this.body, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insights_rounded, size: 48, color: kMuted3),
            const SizedBox(height: 12),
            Text(title, style: _t(16, kTextColor, FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: _t(13, kMuted2)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: kBrandColor),
                child: const Text('Try again'),
              ),
            ],
          ]),
        ),
      );
}

/// Minutes-per-day bars: faint grid, dashed goal line, today in pale
/// violet, quiet days as thin stubs. Drawn to one scale (0..axisMax).
class _BarsPainter extends CustomPainter {
  final List<({DateTime day, double seconds})> days;
  final int goalMinutes;
  _BarsPainter({required this.days, required this.goalMinutes});

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 30.0, bottom = 20.0;
    final plot = Rect.fromLTWH(labelW, 0, size.width - labelW, size.height - bottom);
    final maxMin = days.fold<double>(0, (a, d) => d.seconds / 60 > a ? d.seconds / 60 : a);
    final axisMax = ((maxMin > goalMinutes ? maxMin : goalMinutes.toDouble()) * 1.15 / 30).ceil() * 30.0;
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.07)..strokeWidth = 1;

    void label(String s, Offset at, {TextAlign align = TextAlign.right}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: GoogleFonts.getFont(currentFontFamily, fontSize: 11, color: kMuted3)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(align == TextAlign.right ? at.dx - tp.width : at.dx - tp.width / 2, at.dy - tp.height / 2));
    }

    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      label('${(axisMax * i / 3).round()}', Offset(labelW - 6, y));
    }

    final n = days.length;
    final gap = n > 30 ? 2.0 : 6.0;
    final bw = (plot.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final m = days[i].seconds / 60;
      final h = m <= 0 ? 2.0 : (m / axisMax * plot.height).clamp(2.0, plot.height);
      final x = plot.left + i * (bw + gap);
      final isToday = i == n - 1;
      final p = Paint()
        ..color = (isToday ? kVioletPale : kBrandColor).withValues(alpha: m <= 0 ? 0.25 : 1);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, plot.bottom - h, bw, h),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        p,
      );
      if (isToday) {
        label('Today', Offset(x + bw / 2, size.height - 6), align: TextAlign.center);
      } else if (n <= 14 ? i % 2 == 0 : i % 7 == 0) {
        label('${days[i].day.day}', Offset(x + bw / 2, size.height - 6), align: TextAlign.center);
      }
    }

    final gy = plot.bottom - plot.height * (goalMinutes / axisMax);
    final dash = Paint()..color = kVioletPale.withValues(alpha: 0.5)..strokeWidth = 1;
    for (var x = plot.left; x < plot.right; x += 8) {
      canvas.drawLine(Offset(x, gy), Offset((x + 4).clamp(0, plot.right), gy), dash);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.days != days || o.goalMinutes != goalMinutes;
}

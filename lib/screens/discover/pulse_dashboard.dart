import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/artist.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/click_region.dart';

/// The Shuro Pulse board: period chips (Week / Month / Year / All time), four
/// stat cards, listening time by day, top artists and mixes. Every figure is
/// computed from [AppState.plays] (the timestamped play log) — nothing is
/// invented, and the deltas compare against the previous period of the same
/// length.
const Color _cardColor = Color(0xFF111723);
const Color _good = Color(0xFF34D399);
const Color _warn = Color(0xFFFBBF24);

enum PulsePeriod {
  week('Week', 7, 'last week'),
  month('Month', 30, 'last month'),
  year('Year', 365, 'last year'),
  all('All time', null, '');

  const PulsePeriod(this.label, this.days, this.versus);
  final String label;
  final int? days;
  final String versus;
}

class PulseMix {
  const PulseMix({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.songs,
  });

  final String title;
  final String subtitle;
  final List<Color> colors;
  final List<Song> songs;
}

class PulseDashboard extends StatefulWidget {
  const PulseDashboard({
    super.key,
    required this.appState,
    required this.mixes,
    required this.onPlayMix,
    required this.onOpenArtist,
  });

  final AppState appState;
  final List<PulseMix> mixes;
  final void Function(PulseMix mix) onPlayMix;
  final void Function(Artist artist) onOpenArtist;

  @override
  State<PulseDashboard> createState() => _PulseDashboardState();
}

class _PulseData {
  _PulseData({
    required this.listened,
    required this.plays,
    required this.prevListened,
    required this.prevPlays,
    required this.byWeekday,
    required this.topArtists,
    required this.streak,
    required this.bestStreak,
    required this.topGenre,
    required this.topGenreShare,
  });

  final Duration listened;
  final int plays;
  final Duration prevListened;
  final int prevPlays;
  final List<Duration> byWeekday; // Monday first
  final List<({Artist artist, Duration time})> topArtists;
  final int streak;
  final int bestStreak;
  final String? topGenre;
  final double topGenreShare; // 0..1 of the period's plays
}

class _PulseDashboardState extends State<PulseDashboard> {
  PulsePeriod _period = PulsePeriod.week;
  int? _hoverDay;

  _PulseData _compute() {
    final app = widget.appState;
    final now = DateTime.now();
    final days = _period.days;
    final start = days == null ? null : now.subtract(Duration(days: days));
    final prevStart =
        days == null ? null : now.subtract(Duration(days: days * 2));

    var listened = Duration.zero;
    var plays = 0;
    var prevListened = Duration.zero;
    var prevPlays = 0;
    final byDay = List<Duration>.filled(7, Duration.zero);
    final byArtist = <String, Duration>{};
    final playDays = <DateTime>{};
    // song id -> genre, from the catalogue's genre index.
    final genreOf = <String, String>{};
    app.catalogGenres.forEach((genre, ids) {
      for (final id in ids) {
        genreOf.putIfAbsent(id, () => genre);
      }
    });
    final byGenre = <String, int>{};

    for (final entry in app.plays) {
      final song = app.songById(entry.songId);
      final dur = song?.duration ?? Duration.zero;
      playDays.add(DateTime(entry.at.year, entry.at.month, entry.at.day));
      final inPeriod = start == null || entry.at.isAfter(start);
      if (inPeriod) {
        plays++;
        listened += dur;
        byDay[entry.at.weekday - 1] += dur;
        final g = genreOf[entry.songId];
        if (g != null) byGenre[g] = (byGenre[g] ?? 0) + 1;
        if (song != null) {
          byArtist[song.artistId] =
              (byArtist[song.artistId] ?? Duration.zero) + dur;
        }
      } else if (prevStart != null && entry.at.isAfter(prevStart)) {
        prevPlays++;
        prevListened += dur;
      }
    }

    final ranked = byArtist.keys.toList()
      ..sort((a, b) => byArtist[b]!.compareTo(byArtist[a]!));
    final top = <({Artist artist, Duration time})>[];
    for (final id in ranked) {
      final artist = app.artistById(id);
      if (artist != null) top.add((artist: artist, time: byArtist[id]!));
      if (top.length == 5) break;
    }

    String? topGenre;
    var topGenreCount = 0;
    byGenre.forEach((g, c) {
      if (c > topGenreCount) {
        topGenre = g;
        topGenreCount = c;
      }
    });

    // Streak: consecutive calendar days with a play, ending today (or
    // yesterday, so the streak does not read 0 before the first play of the
    // day). Best streak scans every logged day.
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    if (!playDays.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (playDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var best = 0;
    var run = 0;
    final sorted = playDays.toList()..sort();
    DateTime? prev;
    for (final d in sorted) {
      if (prev != null && d.difference(prev).inHours <= 36) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }

    return _PulseData(
      listened: listened,
      plays: plays,
      prevListened: prevListened,
      prevPlays: prevPlays,
      byWeekday: byDay,
      topArtists: top,
      streak: streak,
      bestStreak: best,
      topGenre: topGenre,
      topGenreShare: plays == 0 ? 0 : topGenreCount / plays,
    );
  }

  static String fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} m';
    return '$m min';
  }

  static String _signed(Duration d) {
    final neg = d.isNegative;
    final abs = neg ? -d : d;
    return '${neg ? '−' : '+'}${fmt(abs)}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _compute();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final hasVersus = _period != PulsePeriod.all;

    final delta = data.listened - data.prevListened;
    final playDelta = data.plays - data.prevPlays;

    final stats = <Widget>[
      _StatCard(
        label: 'LISTENING TIME',
        value: fmt(data.listened),
        note: hasVersus
            ? '${_signed(delta)} vs ${_period.versus}'
            : 'Since you started',
        noteColor: !hasVersus
            ? kStatusText
            : (delta.isNegative ? kStatusText : _good),
      ),
      _StatCard(
        label: 'SONGS PLAYED',
        value: '${data.plays}',
        note: hasVersus
            ? '${playDelta < 0 ? '−' : '+'}${playDelta.abs()} vs ${_period.versus}'
            : 'Since you started',
        noteColor: !hasVersus
            ? kStatusText
            : (playDelta < 0 ? kStatusText : _good),
      ),
      _StatCard(
        label: 'TOP GENRE',
        value: data.topGenre ?? '—',
        note: data.topGenre == null
            ? 'Play something to find out'
            : '${(data.topGenreShare * 100).round()}% of your plays',
        noteColor: kStatusText,
      ),
      _StatCard(
        label: 'STREAK',
        value: '${data.streak} ${data.streak == 1 ? 'day' : 'days'}',
        note: 'Best: ${data.bestStreak} ${data.bestStreak == 1 ? 'day' : 'days'}',
        noteColor: _warn,
      ),
    ];

    final chart = _DayChart(
      key: ValueKey('chart-${_period.name}'),
      values: data.byWeekday,
      hovered: _hoverDay,
      onHover: (d) => setState(() => _hoverDay = d),
    );
    final artists = _TopArtists(
      key: ValueKey('artists-${_period.name}'),
      items: data.topArtists,
      onOpen: widget.onOpenArtist,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period chips.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in PulsePeriod.values)
                _PeriodChip(
                  label: p.label,
                  selected: p == _period,
                  onTap: () => setState(() {
                    _period = p;
                    _hoverDay = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Stat cards: 4 across on wide windows, 2x2 otherwise.
          LayoutBuilder(builder: (context, c) {
            final cols = wide ? 4 : 2;
            const gap = 16.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, card) in stats.indexed)
                  _Rise(
                    key: ValueKey('stat-$i-${_period.name}'),
                    delay: Duration(milliseconds: 40 * i),
                    child: SizedBox(width: w, child: card),
                  ),
              ],
            );
          }),
          const SizedBox(height: 20),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 700, child: chart),
                const SizedBox(width: 24),
                Expanded(flex: 412, child: artists),
              ],
            )
          else ...[
            chart,
            const SizedBox(height: 16),
            artists,
          ],
          if (widget.mixes.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('MIXES FOR YOU',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMuted2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final cols = wide ? 4 : 2;
              const gap = 16.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (i, mix) in widget.mixes.indexed)
                    _Rise(
                      delay: Duration(milliseconds: 120 + 50 * i),
                      child: SizedBox(
                        width: w,
                        child: _MixCard(
                            mix: mix, onPlay: () => widget.onPlayMix(mix)),
                      ),
                    ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Fade + 12 px rise on first build, optionally delayed — the boards' list
/// entrance. Settles instantly when the platform asks for reduced motion.
class _Rise extends StatefulWidget {
  const _Rise({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - curve.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Drives a 0..1 value after [delay]; used for bars that grow in.
class _Grow extends StatefulWidget {
  const _Grow({
    super.key,
    required this.builder,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 560),
  });

  final Widget Function(BuildContext context, double t) builder;
  final Duration delay;
  final Duration duration;

  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.builder(context, 1);
    }
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => widget.builder(context, curve.value),
    );
  }
}

class _PeriodChip extends StatefulWidget {
  const _PeriodChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PeriodChip> createState() => _PeriodChipState();
}

class _PeriodChipState extends State<_PeriodChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClickRegion(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel
                ? kBrandColor
                : Colors.white.withValues(alpha: _hover ? 0.1 : 0.06),
            borderRadius: BorderRadius.circular(16),
            border: sel
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(widget.label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: sel ? Colors.white : kNavText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(22)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.note,
    required this.noteColor,
  });

  final String label;
  final String value;
  final String note;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(19, 17, 19, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMuted2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kTextColor,
                  fontSize: 26,
                  height: 32 / 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text(note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: noteColor, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DayChart extends StatelessWidget {
  const _DayChart(
      {super.key,
      required this.values,
      required this.hovered,
      required this.onHover});

  final List<Duration> values;
  final int? hovered;
  final ValueChanged<int?> onHover;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _full = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const double _plot = 200;

  @override
  Widget build(BuildContext context) {
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (values[i] > values[best]) best = i;
    }
    final maxV = values[best].inSeconds == 0 ? 1 : values[best].inSeconds;
    final active = hovered ?? best;
    final hasData = values[best] > Duration.zero;

    return _Card(
      padding: const EdgeInsets.fromLTRB(23, 21, 23, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LISTENING TIME BY DAY',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMuted2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(
              hasData
                  ? 'Best day: ${_full[best]} · ${_PulseDashboardState.fmt(values[best])}'
                  : 'No plays in this period yet',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMuted2, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            height: _plot + 56,
            child: Stack(
              children: [
                // Gridlines.
                for (final y in const [60.0, 120.0, 180.0])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 40 + y - 60,
                    child: Container(
                        height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => onHover(i),
                            onExit: (_) => onHover(null),
                            child: _Grow(
                              delay: Duration(milliseconds: 60 * i),
                              builder: (context, t) {
                                final frac = values[i].inSeconds / maxV;
                                final h = (_plot * frac * t).clamp(4.0, _plot);
                                final isActive = i == active && hasData;
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Tooltip over the active bar.
                                    SizedBox(
                                      height: 28,
                                      child: AnimatedOpacity(
                                        duration:
                                            const Duration(milliseconds: 140),
                                        opacity: isActive ? 1 : 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1B2335),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: kBrandColor.withValues(
                                                    alpha: 0.6)),
                                          ),
                                          child: Text(
                                              _PulseDashboardState.fmt(
                                                  values[i]),
                                              style: GoogleFonts.getFont(
                                                  currentFontFamily,
                                                  color: kTextColor,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 160),
                                      width: 52,
                                      height: h,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: isActive
                                            ? const LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                    kVioletLight,
                                                    kBrandColor
                                                  ])
                                            : null,
                                        color: isActive
                                            ? null
                                            : kBrandColor.withValues(
                                                alpha: 0.4),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(_names[i],
                                        style: GoogleFonts.getFont(
                                            currentFontFamily,
                                            color: isActive
                                                ? kTextColor
                                                : kMuted2,
                                            fontSize: 12,
                                            fontWeight: isActive
                                                ? FontWeight.w700
                                                : FontWeight.w400)),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopArtists extends StatelessWidget {
  const _TopArtists({super.key, required this.items, required this.onOpen});

  final List<({Artist artist, Duration time})> items;
  final void Function(Artist artist) onOpen;

  @override
  Widget build(BuildContext context) {
    final maxSecs = items.isEmpty
        ? 1
        : (items.first.time.inSeconds == 0 ? 1 : items.first.time.inSeconds);
    return _Card(
      padding: const EdgeInsets.fromLTRB(23, 21, 23, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOP ARTISTS',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMuted2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Play some music and your artists show up here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 12.5)),
              ),
            ),
          for (final (i, it) in items.indexed)
            _ArtistRow(
              rank: i + 1,
              artist: it.artist,
              time: it.time,
              fraction: it.time.inSeconds / maxSecs,
              delay: Duration(milliseconds: 70 * i),
              onTap: () => onOpen(it.artist),
            ),
        ],
      ),
    );
  }
}

class _ArtistRow extends StatefulWidget {
  const _ArtistRow({
    required this.rank,
    required this.artist,
    required this.time,
    required this.fraction,
    required this.delay,
    required this.onTap,
  });

  final int rank;
  final Artist artist;
  final Duration time;
  final double fraction;
  final Duration delay;
  final VoidCallback onTap;

  @override
  State<_ArtistRow> createState() => _ArtistRowState();
}

class _ArtistRowState extends State<_ArtistRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.artist;
    final colors = a.gradientColors.length >= 2
        ? a.gradientColors
        : [kVioletLight, const Color(0xFF312E81)];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClickRegion(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 52,
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.04) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text('${widget.rank}',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: widget.rank == 1 ? kVioletPale : kMuted2,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors.take(2).toList()),
                  image: a.artwork != null
                      ? DecorationImage(image: a.artwork!, fit: BoxFit.cover)
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _Grow(
                      delay: widget.delay,
                      builder: (context, t) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            Container(
                                height: 4,
                                color: Colors.white.withValues(alpha: 0.08)),
                            FractionallySizedBox(
                              widthFactor:
                                  (widget.fraction * t).clamp(0.02, 1.0),
                              child: Container(height: 4, color: kVioletLight),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(_PulseDashboardState.fmt(widget.time),
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixCard extends StatefulWidget {
  const _MixCard({required this.mix, required this.onPlay});

  final PulseMix mix;
  final VoidCallback onPlay;

  @override
  State<_MixCard> createState() => _MixCardState();
}

class _MixCardState extends State<_MixCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.mix;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClickRegion(
        onTap: widget.onPlay,
        child: AnimatedScale(
          scale: _hover ? 1.015 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Container(
            height: 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: m.colors),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x8C000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 76,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(m.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: const Color(0xFFF1F5F9),
                              fontSize: 12,
                              height: 16 / 12)),
                    ],
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: AnimatedScale(
                    scale: _hover ? 1.08 : 1,
                    duration: const Duration(milliseconds: 140),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Color(0xFF0B0F14), size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

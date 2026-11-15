import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/palette_fix.dart';
import '../artist/artist_detail_screen.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/pulse_kit.dart';

/// Shuro Pulse, redesigned on the pulse kit: real listening statistics from
/// the play log (listening time, plays, top genre, streak, weekday chart,
/// top artists) plus real self-building mixes from the recommendation
/// engine. No mock data anywhere - an empty library shows an honest empty
/// state instead of invented numbers.
class ShuroPulseScreen extends StatefulWidget {
  const ShuroPulseScreen({super.key});

  @override
  State<ShuroPulseScreen> createState() => _ShuroPulseScreenState();
}

class _PeriodStat {
  final Duration listened, prevListened;
  final int plays, prevPlays;
  final List<Duration> byWeekday; // Monday first
  final List<({String artistId, String artistName, Duration time, List<Color> colors})> topArtists;
  final int streak, bestStreak;
  final String? topGenre;
  final double topGenreShare; // 0..1
  const _PeriodStat({
    required this.listened,
    required this.prevListened,
    required this.plays,
    required this.prevPlays,
    required this.byWeekday,
    required this.topArtists,
    required this.streak,
    required this.bestStreak,
    required this.topGenre,
    required this.topGenreShare,
  });
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _periodDurations = {'Week': 7, 'Month': 30, 'Year': 365};

class _ShuroPulseScreenState extends State<ShuroPulseScreen> {
  String _period = 'Week';
  int _hoverBar = -1;

  _PeriodStat _compute(AppState app, String period) {
    final days = _periodDurations[period];
    final now = DateTime.now();
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
    final top = <({String artistId, String artistName, Duration time, List<Color> colors})>[];
    for (final id in ranked) {
      final artist = app.artistById(id);
      if (artist != null) {
        top.add((
          artistId: id,
          artistName: artist.name,
          time: byArtist[id]!,
          colors: artist.gradientColors,
        ));
      }
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

    return _PeriodStat(
      listened: listened,
      prevListened: prevListened,
      plays: plays,
      prevPlays: prevPlays,
      byWeekday: byDay,
      topArtists: top,
      streak: streak,
      bestStreak: best,
      topGenre: topGenre,
      topGenreShare: plays > 0 && topGenreCount > 0 ? topGenreCount / plays : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final p = _compute(app, _period);
    final hasData = app.plays.isNotEmpty;

    return Container(
      color: PC.bg,
      child: PScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Shuro Pulse', style: pts(30, w: FontWeight.w800)),
              const Spacer(),
              _outlineBtn(Icons.auto_awesome_rounded, 'Build with Shuro',
                  () => pToast(context, 'Opening Build with Shuro…')),
            ]),
            const SizedBox(height: 20),
            if (!hasData) ...[
              PCard(
                child: Column(children: [
                  const Icon(Icons.graphic_eq_rounded,
                      color: PC.violetLight, size: 42),
                  const SizedBox(height: 14),
                  Text('Your Pulse starts with your first play',
                      style: pts(16, w: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      'Listening time, top artists, genres and streaks land here as you listen.',
                      style: pts(13, c: PC.muted),
                      textAlign: TextAlign.center),
                ]),
              ),
            ] else ...[
              Row(children: [
                for (final k in ['Week', 'Month', 'Year', 'All time']) ...[
                  PChip(
                      label: k,
                      active: _period == k,
                      onTap: () => setState(() => _period = k)),
                  const SizedBox(width: 8),
                ]
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, c) {
                final n = c.maxWidth > 1100 ? 4 : (c.maxWidth > 620 ? 2 : 1);
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: n,
                  mainAxisSpacing: 21,
                  crossAxisSpacing: 21,
                  childAspectRatio: 268 / 108,
                  children: [
                    _stat('LISTENING TIME', hm(p.listened.inMinutes),
                        _deltaTime(p), PC.green),
                    _stat('SONGS PLAYED', '${p.plays}', _deltaPlays(p), PC.green),
                    _stat(
                        'TOP GENRE',
                        p.topGenre ?? '—',
                        p.topGenre != null
                            ? '${(p.topGenreShare * 100).round()}% of your plays'
                            : 'Play something to find out',
                        PC.muted),
                    _stat('STREAK', '${p.streak} day${p.streak == 1 ? '' : 's'}',
                        'Best: ${p.bestStreak} days', PC.amber),
                  ],
                );
              }),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 1000;
                final chart = _chart(p);
                final artists = _topArtists(p);
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 700, child: chart),
                    const SizedBox(width: 24),
                    Expanded(flex: 412, child: artists),
                  ]);
                }
                return Column(children: [chart, const SizedBox(height: 20), artists]);
              }),
            ],
            const SizedBox(height: 26),
            const PSection('Mixes for you'),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final n = c.maxWidth > 1100 ? 4 : (c.maxWidth > 620 ? 2 : 1);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: n,
                mainAxisSpacing: 21,
                crossAxisSpacing: 21,
                childAspectRatio: 268 / 128,
                children: [for (final m in _mixes(app)) _mix(m, player)],
              );
            }),
          ],
        ),
      ),
    );
  }

  // --- real deltas ----------------------------------------------------------

  String _deltaTime(_PeriodStat p) {
    if (p.prevListened == Duration.zero) return 'since you started tracking';
    final d = p.listened - p.prevListened;
    final sign = d.isNegative ? '−' : '+';
    final abs = d.isNegative ? -d : d;
    return '$sign${hm(abs.inMinutes)} vs last $_period.toLowerCase()';
  }

  String _deltaPlays(_PeriodStat p) {
    if (p.prevPlays == 0) return 'all plays';
    final d = p.plays - p.prevPlays;
    final sign = d.isNegative ? '−' : '+';
    return '$sign${d.abs()} vs last ${_period.toLowerCase()}';
  }

  // --- widgets --------------------------------------------------------------

  Widget _outlineBtn(IconData i, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: PC.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: PC.violet.withValues(alpha: 0.5))),
          child: Row(children: [
            Icon(i, size: 15, color: PC.violetPale),
            const SizedBox(width: 7),
            Text(label, style: pts(12, w: FontWeight.w600, c: PC.violetPale)),
          ]),
        ),
      );

  Widget _stat(String label, String value, String sub, Color subColor) => PCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: pts(11, w: FontWeight.w700, c: PC.faint, ls: 1)),
          const SizedBox(height: 6),
          Text(value,
              style: pts(26, w: FontWeight.w800, ls: -0.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const Spacer(),
          Text(sub, style: pts(12, w: FontWeight.w500, c: subColor)),
        ]),
      );

  Widget _chart(_PeriodStat p) {
    final minutes = [for (final d in p.byWeekday) d.inMinutes];
    final maxV = minutes.reduce((a, b) => a > b ? a : b);
    final best = minutes.indexOf(maxV);
    final totalWeek = p.byWeekday.fold<int>(0, (a, b) => a + b.inMinutes);
    return PCard(
      child: SizedBox(
        height: 272,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LISTENING TIME BY DAY',
              style: pts(11, w: FontWeight.w700, c: PC.faint, ls: 1)),
          const SizedBox(height: 4),
          Text(
              totalWeek == 0 ? 'No plays this ${_period.toLowerCase()} yet' : 'Best day: ${_days[best]} · ${hm(minutes[best])}',
              style: pts(12, c: PC.faint)),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              return Stack(children: [
                for (var i = 1; i <= 3; i++)
                  Positioned(
                      left: 0,
                      right: 0,
                      top: c.maxHeight * i / 4,
                      child: Container(height: 1, color: PC.borderSoft)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoverBar = i),
                          onExit: (_) => setState(() => _hoverBar = -1),
                          child: GestureDetector(
                            onTap: () =>
                                pToast(context, '${_days[i]} · ${hm(minutes[i])}'),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_hoverBar == i)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: PC.tooltip,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: PC.violet
                                                .withValues(alpha: 0.6))),
                                    child: Text(hm(minutes[i]),
                                        style: pts(12, w: FontWeight.w700)),
                                  ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                  width: 52,
                                  height: maxV == 0
                                      ? 4.0
                                      : (c.maxHeight - 40) * (minutes[i] / maxV),
                                  decoration: BoxDecoration(
                                    gradient: i == best && maxV > 0
                                        ? const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [PC.violetLight, PC.violet])
                                        : null,
                                    color: i == best && maxV > 0
                                        ? null
                                        : PC.violet.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(_days[i],
                                    style: pts(12,
                                        w: i == best
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        c: i == best ? PC.text : PC.faint)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _topArtists(_PeriodStat p) {
    final maxV = p.topArtists.isNotEmpty ? p.topArtists.first.time : Duration.zero;
    return PCard(
      child: SizedBox(
        height: 272,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOP ARTISTS',
              style: pts(11, w: FontWeight.w700, c: PC.faint, ls: 1)),
          const SizedBox(height: 14),
          if (p.topArtists.isEmpty)
            Center(
                child: Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Text('No plays yet',
                        style: pts(13, c: PC.faint))))
          else
            for (var i = 0; i < p.topArtists.length; i++)
              Expanded(
                child: PHover(
                  lift: false,
                  onTap: () => _openArtist(p.topArtists[i].artistId),
                  child: Row(children: [
                    SizedBox(
                        width: 18,
                        child: Text('${i + 1}',
                            style: pts(13,
                                w: FontWeight.w700,
                                c: i == 0 ? PC.violetPale : PC.faint))),
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: spicyPalette(
                                    p.topArtists[i].colors)))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.topArtists[i].artistName,
                                style: pts(14, w: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            PTrack(value: maxV == Duration.zero
                                ? 0.0
                                : p.topArtists[i].time.inMilliseconds /
                                    maxV.inMilliseconds),
                          ]),
                    ),
                    const SizedBox(width: 14),
                    Text(hm(p.topArtists[i].time.inMinutes),
                        style: pts(12, w: FontWeight.w500, c: PC.muted)),
                  ]),
                ),
              ),
        ]),
      ),
    );
  }

  void _openArtist(String artistId) {
    final app = context.read<AppState>();
    final artist = app.artistById(artistId);
    if (artist == null) {
      pToast(context, 'Artist not in your library');
      return;
    }
    Navigator.of(context)
        .push(drillDownRoute(ArtistDetailScreen(artist: artist)));
  }

  // --- real mixes -------------------------------------------------------------

  List<(String, String, List<Color>, List<Song>)> _mixes(AppState app) => [
        (
          'Tonight\'s Flow',
          'A continuous mix built from what you play',
          const [PC.pink, PC.violet],
          ShuroPulse.tonightsFlow(app, length: 24),
        ),
        (
          'For You',
          'Fresh picks from your taste',
          const [PC.teal, PC.tealDeep],
          ShuroPulse.forYou(app, limit: 24),
        ),
        (
          'Rediscover',
          'Songs you haven\'t played in a while',
          const [PC.amberDeep, PC.rose],
          ShuroPulse.rediscover(app, limit: 24),
        ),
        (
          'Deep Cuts',
          'Deeper into the artists you love',
          const [PC.blue, PC.blueDeep],
          ShuroPulse.deepCuts(app, limit: 24),
        ),
      ];

  Widget _mix((String, String, List<Color>, List<Song>) m, PlayerController player) {
    final hasSongs = m.$4.isNotEmpty;
    return PHover(
      onTap: () => hasSongs ? _playMix(m, player) : pToast(context, 'Listen a little first — this mix needs history'),
      child: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: m.$3),
            borderRadius: BorderRadius.circular(20)),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55)
                      ])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(m.$1, style: pts(17, w: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${m.$2} · ${m.$4.length} songs',
                      style: pts(12, c: const Color(0xFFF1F5F9)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
          ),
          Positioned(
              right: 18,
              bottom: 18,
              child: PPlay(
                  size: 40,
                  bg: Colors.white,
                  fg: PC.violet,
                  shadow: false,
                  onTap: () => hasSongs ? _playMix(m, player) : null)),
        ]),
      ),
    );
  }

  void _playMix((String, String, List<Color>, List<Song>) m, PlayerController player) {
    player.playSong(m.$4.first, queue: m.$4);
    pToast(context, 'Playing ${m.$1}');
  }
}

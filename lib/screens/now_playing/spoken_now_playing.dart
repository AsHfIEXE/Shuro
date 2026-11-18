import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../abs/abs_book_screen.dart';
import '../abs/abs_widgets.dart';

/// Now playing for audiobooks and podcast episodes. Music keeps its own
/// screens; both of them hand over to this one when
/// [SpokenLibraryState.resolveSong] recognises the current song.
///
/// >= 900 dp: transport on the left, tabbed list on the right (chapters +
/// more by the author for a book, episodes + show notes for a podcast).
/// Narrower: transport on top and the same tabs in a draggable sheet.
class SpokenNowPlaying extends StatefulWidget {
  const SpokenNowPlaying({
    super.key,
    required this.song,
    required this.item,
    this.episode,
    this.onClose,
  });
  final Song song;
  final SpokenItem item;
  final SpokenEpisode? episode;
  final VoidCallback? onClose;

  @override
  State<SpokenNowPlaying> createState() => _SpokenNowPlayingState();
}

class _SpokenNowPlayingState extends State<SpokenNowPlaying> {
  static const _speeds = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0];
  int _tab = 0;
  double? _drag; // fraction while the scrubber is held

  void _setDrag(double? v) => setState(() => _drag = v);

  @override
  void initState() {
    super.initState();
    // The routing row may have handed us the listing copy (no chapters /
    // episodes yet) — ask the state for the full item; when it lands, its
    // notifyListeners rebuilds the caller, which re-resolves and hands us
    // the complete item.
    final needsFull = widget.episode == null
        ? widget.item.chapters.isEmpty
        : widget.item.episodes.isEmpty;
    if (needsFull) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SpokenLibraryState>().expandShow(widget.item);
      });
    }
  }

  bool get _book => widget.episode == null;
  List<String> get _tabs =>
      _book ? const ['Chapters', 'More books', 'Notes'] : const ['Episodes', 'Show notes'];
  Duration get _total => widget.episode?.duration ?? widget.item.duration;

  /// Seeks inside the current file when the target is in it; otherwise
  /// reopens the session at that point (multi-file books).
  void _seekTo(Duration target) {
    final p = context.read<PlayerController>();
    final offset = context.read<SpokenLibraryState>().trackOffsetFor(widget.song.id);
    final local = target - Duration(milliseconds: (offset * 1000).round());
    if (local >= Duration.zero && local <= widget.song.duration) {
      p.seekTo(local);
    } else {
      AbsActions.play(context, widget.item, episode: widget.episode, startAt: target);
    }
  }

  void _skip(Duration pos, int seconds) {
    final t = pos + Duration(seconds: seconds);
    _seekTo(t < Duration.zero ? Duration.zero : (t > _total ? _total : t));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final (bg, _) = AbsCover.colorsFor(widget.item.title);
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.2),
            colors: [bg.withValues(alpha: 0.5), kSurfaceColor],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            return StreamBuilder<Duration>(
              stream: p.smoothPositionStream,
              initialData: p.position,
              builder: (context, snap) {
                final s = context.watch<SpokenLibraryState>();
                final offset = Duration(
                    milliseconds: (s.trackOffsetFor(widget.song.id) * 1000).round());
                final pos = offset + (snap.data ?? Duration.zero);
                final main = _Transport(
                  state: this,
                  p: p,
                  pos: pos,
                  wide: wide,
                );
                if (wide) {
                  return Row(children: [
                    SizedBox(width: 520, child: main),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 48, 48, 0),
                        child: _panel(context, pos, wide: true),
                      ),
                    ),
                  ]);
                }
                return Stack(children: [
                  Positioned.fill(child: main),
                  DraggableScrollableSheet(
                    initialChildSize: 0.3,
                    minChildSize: 0.3,
                    maxChildSize: 0.92,
                    snap: true,
                    builder: (context, controller) => Container(
                      decoration: BoxDecoration(
                        color: kRaisedColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _panel(context, pos, wide: false, controller: controller),
                    ),
                  ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }

  // ── Right pane / bottom sheet ────────────────────────────────────────────
  Widget _panel(BuildContext context, Duration pos,
      {required bool wide, ScrollController? controller}) {
    final tabs = Row(children: [
      _Segmented(
          labels: _tabs, value: _tab, onChanged: (i) => setState(() => _tab = i)),
      const Spacer(),
      Text(_headline(), style: absText(12, color: kMuted2, tabular: true)),
    ]);
    final body = _body(context, pos, wide);
    if (wide) {
      return ListView(children: [
        SizedBox(height: 40, child: tabs),
        const SizedBox(height: 12),
        ...body,
        const SizedBox(height: 32),
      ]);
    }
    return ListView(controller: controller, padding: EdgeInsets.zero, children: [
      Center(
        child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(2)),
        ),
      ),
      tabs,
      const SizedBox(height: 8),
      ...body,
      const SizedBox(height: 32),
    ]);
  }

  String _headline() {
    if (_book) {
      final n = widget.item.chapters.length;
      return n == 0 ? '' : '$n chapters';
    }
    final n = widget.item.episodes.length;
    final fresh = widget.item.episodes.where(_isNew).length;
    return '$n episodes${fresh > 0 ? ' · $fresh new' : ''}';
  }

  bool _isNew(SpokenEpisode e) =>
      e.progressSeconds == 0 &&
      e.publishedAt != null &&
      DateTime.now().difference(e.publishedAt!).inDays < 7;

  List<Widget> _body(BuildContext context, Duration pos, bool wide) {
    final item = widget.item;
    if (_book) {
      switch (_tab) {
        case 0:
          final cur = item.chapters.lastIndexWhere((c) => c.start <= pos.inSeconds);
          return [
            if (item.chapters.isEmpty)
              _Empty('This book has no chapters.')
            else
              for (var i = 0; i < item.chapters.length; i++)
                _ListRow(
                  lead: '${i + 1}',
                  title: item.chapters[i].title,
                  trail: absClock(Duration(
                      seconds: (item.chapters[i].end - item.chapters[i].start).round())),
                  current: i == cur,
                  dim: i < cur,
                  onTap: () => _seekTo(Duration(seconds: item.chapters[i].start.round())),
                ),
            if (wide) ..._moreBooks(context, shelf: true),
          ];
        case 1:
          return _moreBooks(context, shelf: false);
        default:
          return [_Notes(item.description)];
      }
    }
    if (_tab == 1) return [_Notes(widget.episode!.description.isNotEmpty
        ? widget.episode!.description
        : item.description)];
    final s = context.watch<SpokenLibraryState>();
    final eps = [...item.episodes]..sort((a, b) =>
        (b.publishedAt ?? DateTime(0)).compareTo(a.publishedAt ?? DateTime(0)));
    String date(DateTime? d) => d == null ? '' : '${d.day}/${d.month}/${d.year}';
    return [
      for (final e in eps)
        Builder(builder: (_) {
          final prog = s.liveProgressSecondsFor(item, episode: e) ?? e.progressSeconds;
          final done = e.duration.inSeconds > 0 && prog >= e.duration.inSeconds - 30;
          final isCur = e.id == widget.episode!.id;
          return _ListRow(
            lead: '',
            title: e.title,
            subtitle: '${date(e.publishedAt)} · ${absClock(e.duration)}',
            trail: done ? 'Played' : (prog > 0 ? '${absClock(e.duration - Duration(seconds: prog.round()))} left' : ''),
            current: isCur,
            dim: done && !isCur,
            isNew: _isNew(e),
            onTap: isCur ? null : () => AbsActions.play(context, item, episode: e),
            onLongPress: () => AbsActions.play(context, item, episode: e, queue: true),
          );
        }),
    ];
  }

  /// Other books by the same author, series mates first.
  List<Widget> _moreBooks(BuildContext context, {required bool shelf}) {
    final s = context.read<SpokenLibraryState>();
    final item = widget.item;
    final others = s.bookItems.where((b) => b.id != item.id).toList()
      ..sort((a, b) {
        int rank(SpokenItem x) =>
            x.seriesNames.any(item.seriesNames.contains) ? 0 : (x.creator == item.creator ? 1 : 2);
        return rank(a).compareTo(rank(b));
      });
    final byAuthor = others.where((b) => b.creator == item.creator).toList();
    final list = shelf ? byAuthor : others;
    if (list.isEmpty) return shelf ? const [] : [_Empty('No other books yet.')];
    final rail = SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final b = list[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => AbsBookScreen(item: b))),
            child: SizedBox(
              width: 112,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AbsCover(b, width: 112, height: 112, radius: 8),
                const SizedBox(height: 8),
                Text(b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(13, w: FontWeight.w600)),
                Text(absClock(b.duration), style: absText(12, color: kMuted2)),
              ]),
            ),
          );
        },
      ),
    );
    if (shelf) {
      return [
        const SizedBox(height: 20),
        Divider(height: 1, color: kHairline),
        const SizedBox(height: 24),
        Text('MORE BY ${item.creator.toUpperCase()}',
            style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.9)),
        const SizedBox(height: 14),
        rail,
      ];
    }
    return [
      for (final b in list)
        _ListRow(
          lead: '',
          title: b.title,
          subtitle: b.creator,
          trail: absClock(b.duration),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => AbsBookScreen(item: b))),
        ),
    ];
  }
}

// ── Left pane / top block ───────────────────────────────────────────────────
class _Transport extends StatelessWidget {
  const _Transport({required this.state, required this.p, required this.pos, required this.wide});
  final _SpokenNowPlayingState state;
  final PlayerController p;
  final Duration pos;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final total = state._total;
    final frac = total.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
    final shown = state._drag ?? frac;
    final shownPos = Duration(milliseconds: (shown * total.inMilliseconds).round());

    final book = state._book;
    final chIdx = w.item.chapters.lastIndexWhere((c) => c.start <= pos.inSeconds);
    final title = book ? w.item.title : w.episode!.title;
    final sub = book ? w.item.creator : w.item.title;
    final meta = book
        ? (chIdx >= 0 ? 'Chapter ${chIdx + 1} of ${w.item.chapters.length} · ${w.item.chapters[chIdx].title}' : '')
        : (w.episode!.publishedAt == null ? '' : 'Episode · ${w.episode!.publishedAt!.day}/${w.episode!.publishedAt!.month}');

    final ticks = book && total.inSeconds > 0
        ? [for (final c in w.item.chapters) c.start / total.inSeconds]
        : const <double>[];

    final speed = p.playbackSpeed;
    final speedLabel = '${speed == speed.roundToDouble() ? speed.toStringAsFixed(1) : speed}×';

    final size = wide ? 300.0 : 224.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 48 : 24, wide ? 48 : 8, wide ? 48 : 24, 0),
      child: Column(children: [
        SizedBox(
          height: 40,
          child: Row(children: [
            IconButton(
              tooltip: 'Close',
              onPressed: w.onClose ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: kTextColor),
            ),
            Expanded(
                child: Center(
                    child: Text(book ? 'AUDIOBOOK' : 'PODCAST',
                        style: absText(12, color: kVioletLight, w: FontWeight.w700, ls: 1.4)))),
            const SizedBox(width: 48),
          ]),
        ),
        SizedBox(height: wide ? 24 : 12),
        AbsCover(w.item, width: size, height: size, radius: 16),
        SizedBox(height: wide ? 28 : 18),
        Text(title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: absHeading(book ? (wide ? 28 : 22) : (wide ? 24 : 20), ls: -0.5).copyWith(height: 1.2)),
        const SizedBox(height: 6),
        Text(sub, style: absText(15, color: kVioletLight, w: FontWeight.w600)),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: absText(13, color: kMuted2)),
        ],
        SizedBox(height: wide ? 24 : 14),
        _Scrubber(
          value: shown,
          ticks: ticks,
          onChanged: state._setDrag,
          onEnd: (v) {
            state._setDrag(null);
            state._seekTo(Duration(milliseconds: (v * total.inMilliseconds).round()));
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(absClock(shownPos), style: absText(12, color: kMuted2, tabular: true)),
            Text('-${absClock(total - shownPos)}', style: absText(12, color: kMuted2, tabular: true)),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(iconSize: 32, tooltip: 'Back 15 s',
              onPressed: () => state._skip(pos, -15),
              icon: const Icon(Icons.replay_10_rounded, color: kTextColor)),
          const SizedBox(width: 12),
          SizedBox(
            width: 68, height: 68,
            child: FilledButton(
              onPressed: p.togglePlayPause,
              style: FilledButton.styleFrom(
                  backgroundColor: kBrandColor, shape: const CircleBorder(), padding: EdgeInsets.zero),
              child: Icon(p.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 38, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(iconSize: 32, tooltip: 'Forward 30 s',
              onPressed: () => state._skip(pos, 30),
              icon: const Icon(Icons.forward_30_rounded, color: kTextColor)),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          _Pill(
            label: speedLabel,
            strong: true,
            onTap: () {
              final i = _SpokenNowPlayingState._speeds.indexOf(speed);
              p.playbackSpeed = _SpokenNowPlayingState._speeds[(i + 1) % _SpokenNowPlayingState._speeds.length];
              p.applyPlaybackTweaksNow();
              context.read<SpokenLibraryState>().saveSpeedFor(
                  w.episode == null ? w.item.id : '${w.item.id}/${w.episode!.id}', p.playbackSpeed);
            },
          ),
          _SleepPill(p: p),
          if (book)
            _Pill(
              label: 'Bookmark',
              icon: Icons.bookmark_border_rounded,
              onTap: () async {
                final s = context.read<SpokenLibraryState>();
                final messenger = ScaffoldMessenger.of(context);
                await s.addBookmark(w.item.id,
                    time: pos.inSeconds.toDouble(),
                    title: chIdx >= 0 ? w.item.chapters[chIdx].title : absClock(pos));
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                      content: Text('Bookmarked ${absClock(pos)}', style: absText(13)),
                      backgroundColor: kRaisedColor,
                      behavior: SnackBarBehavior.floating));
              },
            )
          else
            _Pill(
              label: 'Mark played',
              icon: Icons.done_all_rounded,
              onTap: () => context
                  .read<SpokenLibraryState>()
                  .markPlayed(w.item, episode: w.episode),
            ),
        ]),
      ]),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.value, required this.ticks, required this.onChanged, required this.onEnd});
  final double value;
  final List<double> ticks;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(alignment: Alignment.center, children: [
            // Chapter ticks sit behind the slider track.
            for (final t in ticks)
              Positioned(
                left: 8 + (c.maxWidth - 16) * t.clamp(0.0, 1.0).toDouble(),
                child: Container(width: 2, height: 8, color: Colors.white.withValues(alpha: 0.28)),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: kBrandColor,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(value: value.clamp(0.0, 1.0).toDouble(), onChanged: onChanged, onChangeEnd: onEnd),
            ),
          ]);
        }),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.icon, this.strong = false});
  final String label;
  final IconData? icon;
  final bool strong;
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
            if (icon != null) ...[Icon(icon, size: 16, color: kNavText), const SizedBox(width: 6)],
            Text(label,
                style: absText(13,
                    w: strong ? FontWeight.w700 : FontWeight.w600,
                    color: strong ? kTextColor : kNavText,
                    tabular: true)),
          ]),
        ),
      );
}

class _SleepPill extends StatelessWidget {
  const _SleepPill({required this.p});
  final PlayerController p;
  @override
  Widget build(BuildContext context) {
    final until = p.sleepUntil;
    final left = until == null ? null : until.difference(DateTime.now());
    return PopupMenuButton<int>(
      tooltip: 'Sleep timer',
      color: kRaisedColor,
      onSelected: (m) => m == 0 ? p.cancelSleepTimer() : p.startSleepTimer(Duration(minutes: m)),
      itemBuilder: (_) => [
        for (final m in const [15, 30, 45, 60])
          PopupMenuItem(value: m, child: Text('$m minutes', style: absText(14))),
        if (until != null) PopupMenuItem(value: 0, child: Text('Turn off', style: absText(14))),
      ],
      child: IgnorePointer(
        child: _Pill(
          label: left == null || left.isNegative ? 'Sleep' : '${left.inMinutes + 1} min',
          icon: Icons.bedtime_outlined,
          onTap: () {},
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.labels, required this.value, required this.onChanged});
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: ShuroMotion.fast,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: i == value ? kBrandColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(labels[i],
                    style: absText(13,
                        w: FontWeight.w600, color: i == value ? Colors.white : kNavText)),
              ),
            ),
        ]),
      );
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.lead,
    required this.title,
    required this.trail,
    this.subtitle,
    this.current = false,
    this.dim = false,
    this.isNew = false,
    this.onTap,
    this.onLongPress,
  });
  final String lead, title, trail;
  final String? subtitle;
  final bool current, dim, isNew;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: BoxConstraints(minHeight: subtitle == null ? 48 : 60),
            padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
            decoration: BoxDecoration(
              color: current ? kBrandColor.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Container(
                  width: 3, height: 28,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                      color: current ? kBrandColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(2))),
              if (lead.isNotEmpty || current)
                SizedBox(
                  width: 36,
                  child: Center(
                      child: current
                          ? const Icon(Icons.graphic_eq_rounded, size: 18, color: kVioletPale)
                          : Text(lead, style: absText(13, color: kMuted2, tabular: true))),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: absText(14,
                              w: FontWeight.w600, color: current ? kVioletPale : kTextColor)),
                    ),
                    if (isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: kGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text('NEW', style: absText(11, color: kGreenLight, w: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: absText(12, color: kMuted2, tabular: true)),
                    ),
                ]),
              ),
              if (trail.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(trail, style: absText(13, color: kMuted2, tabular: true)),
              ],
            ]),
          ),
        ),
      );
}

class _Notes extends StatelessWidget {
  const _Notes(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text.isEmpty ? 'No description.' : text,
            style: absText(14, color: kNavText, h: 1.6)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(text, style: absText(13, color: kMuted2))),
      );
}

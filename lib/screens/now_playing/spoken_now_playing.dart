import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/audiobookshelf_api.dart';
import '../../models/song.dart';
import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../abs/abs_book_screen.dart';
import '../abs/abs_podcast_screen.dart';
import '../abs/abs_widgets.dart';
import 'audio_info_sheet.dart';
import 'now_playing_screen.dart';

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
  // Show notes / description tabs dropped: server notes rendered broken
  // (raw HTML, empty bodies) and the chapter list already tells the story.
  List<String> get _tabs => _book
      ? const ['Chapters', 'Series', 'Notes']
      : const ['Episodes', 'Notes'];
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

  /// The ⋯ menu: details, audio info, mark-played. Everything else already
  /// has a dedicated control on this screen.
  void _showMoreSheet() {
    final s = context.read<SpokenLibraryState>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kRaisedColor,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_book)
            ListTile(
              leading: const Icon(Icons.menu_book_rounded, color: kNavText),
              title: Text('Open book details', style: absText(14)),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AbsBookScreen(item: widget.item)));
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.podcasts_rounded, color: kNavText),
              title: Text('Open show page', style: absText(14)),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AbsPodcastScreen(show: widget.item)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.graphic_eq_rounded, color: kNavText),
            title: Text('Audio information', style: absText(14)),
            onTap: () {
              Navigator.pop(sheetContext);
              showAudioInfoSheet(context, widget.song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.done_all_rounded, color: kNavText),
            title: Text(
                _book ? 'Mark book as played' : 'Mark episode as played',
                style: absText(14)),
            onTap: () {
              Navigator.pop(sheetContext);
              if (_book) {
                s.markPlayed(widget.item);
              } else {
                s.markPlayed(widget.item, episode: widget.episode);
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final (bg, _) = AbsCover.colorsFor(widget.item.title);
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          // ~160° wash from the cover's own palette, gone by ~60% — the
          // mock's backdrop.
          gradient: LinearGradient(
            begin: const Alignment(-0.35, -1),
            end: const Alignment(0.25, 0.45),
            colors: [bg.withValues(alpha: 0.5), kSurfaceColor],
            stops: const [0, 0.6],
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
                  // On big windows the transport pane floats centred between
                  // two equal flex spaces, so the COVER sits on the window's
                  // centreline instead of hugging the left; the reading pane
                  // gets a centred 780 dp column rather than edge-to-edge rows.
                  final centred = c.maxWidth >= 1200;
                  return Row(children: [
                    // A touch more room on the right than the left puts the
                    // cover a little LEFT of the centreline, which reads
                    // better with the reading pane beside it.
                    if (centred) const Spacer(flex: 4),
                    SizedBox(width: 520, child: main),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 48, 48, 0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: _panel(context, pos, wide: true),
                          ),
                        ),
                      ),
                    ),
                  ]);
                }
                // Keep the transport in the area ABOVE the sheet's rest
                // position so none of its buttons hide behind it.
                return LayoutBuilder(builder: (context, sheetBox) {
                  final sheetH = sheetBox.maxHeight * 0.3;
                  return Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: sheetH),
                      child: main,
                    ),
                  ),
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
                });
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
      if (_tabs.length > 1) ...[
        _Segmented(
            labels: _tabs, value: _tab, onChanged: (i) => setState(() => _tab = i)),
        const Spacer(),
      ],
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
          return _seriesList(context);
        case 2:
          return [_Notes(_cleanNotes(item.description))];
        default:
          return _moreBooks(context, shelf: false);
      }
    }
    if (_tab == 1) {
      final notes = widget.episode!.description.isNotEmpty
          ? widget.episode!.description
          : item.description;
      return [_Notes(_cleanNotes(notes))];
    }
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
  List<Widget> _moreBooks(BuildContext context, {required bool shelf}) {    final s = context.read<SpokenLibraryState>();
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
                Text(_shelfMeta(s, b, item), style: absText(12, color: kMuted2)),              ]),
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
        Row(children: [
          Expanded(
              child: Text('MORE BY ${item.creator.toUpperCase()}',
                  style:
                      absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.9))),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _tab = 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('See all',
                  style:
                      absText(13, color: kVioletPale, w: FontWeight.w600)),
            ),
          ),
        ]),
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

  /// Series tab: every book sharing one of this book's series, with the
  /// shared series named under the title.
  List<Widget> _seriesList(BuildContext context) {
    final s = context.read<SpokenLibraryState>();
    final item = widget.item;
    if (item.seriesNames.isEmpty) return [_Empty('Not part of a series.')];
    final mates = s.bookItems
        .where((b) =>
            b.id != item.id &&
            b.seriesNames.any(item.seriesNames.contains))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    if (mates.isEmpty) {
      return [_Empty('No other books in this series yet.')];
    }
    return [
      for (final b in mates)
        _ListRow(
          lead: '',
          title: b.title,
          subtitle: b.seriesNames.where(item.seriesNames.contains).join(' · '),
          trail: absClock(b.duration),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AbsBookScreen(item: b))),
        ),
    ];
  }

  /// Server notes are HTML in the wild — strip tags and entities before they
  /// reach a Text widget, or the tab reads like markup soup.
  static String _cleanNotes(String raw) => raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'&nbsp;|&amp;|&quot;|&lt;|&gt;|&#\d+;'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// The mock's rail meta: "Book 3 · 14 h" / "Standalone · 9 h" / "Finished".
  String _shelfMeta(SpokenLibraryState s, SpokenItem b, SpokenItem item) {
    final shared = b.seriesNames.where(item.seriesNames.contains).toList();
    if (s.isFinishedFor(b)) {
      return shared.isEmpty ? 'Finished' : '${shared.first} · Finished';
    }
    final dur = absLength(b.duration);
    return shared.isEmpty ? 'Standalone · $dur' : '${shared.first} · $dur';
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
    // Center the whole transport block in its pane (it used to hug the top
    // left corner) and scroll instead of overflowing on short windows.
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 48 : 24, wide ? 48 : 8, wide ? 48 : 24, 0),
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 40,
          child: Row(children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: w.onClose ?? () => Navigator.maybePop(context),
                  child: const Icon(Icons.arrow_back_rounded,
                      size: 24, color: kTextColor),
                ),
              ),
            ),
            Expanded(
                child: Center(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(book ? 'AUDIOBOOK' : 'PODCAST',
                            style: absText(12,
                                color: kVioletLight,
                                w: FontWeight.w700,
                                ls: 1.4))))),
            Row(mainAxisSize: MainAxisSize.min, children: [
              OutputChip(width: wide ? 148 : 128, height: wide ? 40 : 36),
              const SizedBox(width: 8),
              _GlassCircle(
                  icon: Icons.speaker_rounded,
                  tooltip: 'Audio information',
                  onTap: () => showAudioInfoSheet(context, w.song)),
              const SizedBox(width: 8),
              _GlassCircle(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'More options',
                  onTap: state._showMoreSheet),
            ]),
          ]),
        ),
        SizedBox(height: wide ? 24 : 12),
        // Books are 2:3, shows square — honour the natural shape instead of
        // cropping a portrait cover into a square tile.
        AbsCover(w.item,
            width: book ? size * 2 / 3 : size,
            height: size,
            radius: 16),
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
          _SkipArc(
              seconds: 15, forward: false, onSkip: () => state._skip(pos, -15)),
          const SizedBox(width: 16),
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
          const SizedBox(width: 16),
          _SkipArc(
              seconds: 30, forward: true, onSkip: () => state._skip(pos, 30)),
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
                try {
                  await s.addBookmark(w.item.id,
                      time: pos.inSeconds.toDouble(),
                      title:
                          chIdx >= 0 ? w.item.chapters[chIdx].title : absClock(pos));
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                        content: Text('Bookmarked ${absClock(pos)}',
                            style: absText(13)),
                        backgroundColor: kRaisedColor,
                        behavior: SnackBarBehavior.floating));
                } on AudiobookshelfApiException catch (e) {
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                        content: Text('Bookmark failed — ${e.message}',
                            style: absText(13)),
                        backgroundColor: kRaisedColor,
                        behavior: SnackBarBehavior.floating));
                }
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
        ),
      ),
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

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(text, style: absText(13, color: kMuted2))),
      );
}

/// 32 dp glass circle for the ABS now-playing header (audio info, ⋯) — the
/// same affordance the music header uses, sized to its row.
class _GlassCircle extends StatelessWidget {
  const _GlassCircle(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: Colors.white.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Icon(icon, size: 16, color: kNavText),
              ),
            ),
          ),
        ),
      );
}

/// The mock's 48 dp skip control: the arc arrow with the seconds overlaid at
/// its foot ("15" / "30"), instead of a material icon that spells its own
/// number.
class _SkipArc extends StatelessWidget {
  const _SkipArc(
      {required this.seconds, required this.forward, required this.onSkip});
  final int seconds;
  final bool forward;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Skip ${forward ? 'forward' : 'back'} $seconds seconds',
        child: Tooltip(
          message: '${forward ? 'Forward' : 'Back'} $seconds s',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onSkip,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                    size: const Size(30, 30),
                    painter: _SkipArcPainter(forward: forward)),
                Positioned(
                  bottom: 1,
                  child: Text('$seconds',
                      style: absText(10, color: kTextColor, w: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Draws the mock's arc-arrow path ("M12 5V2L7 6l5 4V7a5 5 0 1 1-5 5" and
/// its mirror) on a 24-unit grid scaled to the widget.
class _SkipArcPainter extends CustomPainter {
  const _SkipArcPainter({required this.forward});
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (forward) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final s = size.width / 24;
    canvas.scale(s, s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = kTextColor;
    // The arc: from (12,7) sweeping the long way around to (7,12).
    final arc = Path()
      ..moveTo(12, 7)
      ..arcToPoint(const Offset(7, 12),
          radius: const Radius.circular(5), largeArc: true, clockwise: true);
    canvas.drawPath(arc, stroke);
    // The arrow chevron: (12,5)→(12,2)→(7,6)→(12,10)→(12,7).
    final head = Path()
      ..moveTo(12, 5)
      ..lineTo(12, 2)
      ..lineTo(7, 6)
      ..lineTo(12, 10)
      ..lineTo(12, 7);
    canvas.drawPath(head, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkipArcPainter oldDelegate) =>
      oldDelegate.forward != forward;
}

/// Show notes / book description — HTML stripped before it hits a Text.
class _Notes extends StatelessWidget {
  const _Notes(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text.isEmpty ? 'No notes.' : text,
            style: absText(14, color: kNavText, h: 1.6)),
      );
}

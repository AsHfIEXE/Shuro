import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../state/spoken_library_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (from the Figma CSS)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF0B0F14);
  static const card = Color(0xFF111723);
  static const raised = Color(0xFF161F2E);
  static const border = Color(0x14FFFFFF); // white 8%
  static const borderSoft = Color(0x0DFFFFFF); // white 5%
  static const text = Color(0xFFE8E8F0);
  static const textSoft = Color(0xFFB4BBCB);
  static const muted = Color(0xFF9AA3B5);
  static const faint = Color(0xFF8B93A7);
  static const violet = Color(0xFF7C3AED);
  static const violetLight = Color(0xFFA78BFA);
  static const violetPale = Color(0xFFC4B5FD);
  static const cyan = Color(0xFF00D4FF);
  static const cyanText = Color(0xFF67E8F9);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFBE123C);
  static const blue = Color(0xFF60A5FA);
  static const blueDeep = Color(0xFF1E3A8A);
  static const teal = Color(0xFF2DD4BF);
  static const tealDeep = Color(0xFF0E7490);
  static const indigo = Color(0xFF312E81);
  static const plum = Color(0xFF4C1D95);
  static const pink = Color(0xFFFF6B9D);
  static const pinkSoft = Color(0xFFF9A8D4);
  static const greenDeep = Color(0xFF065F46);

  /// Deterministic gradient pairs keyed by the item id, so every book/episode
  /// keeps its cover colours across rebuilds.
  static const List<List<Color>> _pairs = [
    [violet, indigo],
    [pink, violet],
    [teal, tealDeep],
    [blue, blueDeep],
    [amber, rose],
    [pinkSoft, plum],
    [green, greenDeep],
    [cyan, blueDeep],
  ];
}

List<Color> _coverFor(String id) {
  var hash = 0;
  for (final c in id.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return _C._pairs[hash % _C._pairs.length];
}

TextStyle _ts(double size,
        {FontWeight w = FontWeight.w400,
        Color c = _C.text,
        double? ls,
        double? h}) =>
    GoogleFonts.inter(
        fontSize: size, fontWeight: w, color: c, letterSpacing: ls, height: h);

LinearGradient _grad(List<Color> colors,
        {Alignment begin = Alignment.topLeft,
        Alignment end = Alignment.bottomRight}) =>
    LinearGradient(begin: begin, end: end, colors: colors);

String _hoursLabel(Duration d) {
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} m';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String _relativeDate(DateTime? date) {
  if (date == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'Last week';
  return 'Last month';
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen — Figma visuals over the real Audiobookshelf state.
// ─────────────────────────────────────────────────────────────────────────────
class BooksPodcastsScreen extends StatefulWidget {
  const BooksPodcastsScreen({super.key});

  @override
  State<BooksPodcastsScreen> createState() => _BooksPodcastsScreenState();
}

class _BooksPodcastsScreenState extends State<BooksPodcastsScreen> {
  final ScrollController _scroll = ScrollController();
  String _filter = 'All';
  bool _showAll = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: _ts(13)),
        backgroundColor: _C.raised,
        behavior: SnackBarBehavior.floating,
        width: 440,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _C.border)),
        duration: const Duration(seconds: 2),
      ));
  }

  /// Plays a book or an episode through the normal player, resuming from the
  /// server-known position. Same plumbing the previous screen used.
  void _play(SpokenItem item, {SpokenEpisode? episode}) {
    final state = context.read<SpokenLibraryState>();
    final player = context.read<PlayerController>();
    final song = state.songFor(item, episode: episode);
    if (song == null) {
      _toast('Not ready — refresh libraries and try again.');
      return;
    }
    final at = state.resumeAt(item, episode: episode);
    final queue = [
      for (final b in state.bookItems) state.songFor(b) ?? song,
    ];
    player.playSong(song,
        startAt: at > Duration.zero ? at : null,
        queue: queue.isNotEmpty ? queue : [song]);
    _toast('Playing ${song.title}');
  }

  Future<void> _connect() async {
    final url = TextEditingController();
    final token = TextEditingController();
    final name = TextEditingController(text: 'Audiobookshelf');
    final values = await showDialog<(String, String, String)>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: _C.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _C.border)),
              title: Text('Connect Audiobookshelf', style: _ts(18, w: FontWeight.w700)),
              content: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        style: _ts(14),
                        decoration: const InputDecoration(labelText: 'Connection name')),
                    TextField(
                        controller: url,
                        style: _ts(14),
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://books.example.com')),
                    TextField(
                        controller: token,
                        style: _ts(14),
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'API token',
                            helperText: 'Stored in secure device storage.')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        dialogContext, (name.text, url.text, token.text)),
                    child: const Text('Connect')),
              ],
            ));
    url.dispose();
    token.dispose();
    name.dispose();
    if (values == null || !mounted) return;
    await context
        .read<SpokenLibraryState>()
        .connect(name: values.$1, url: values.$2, token: values.$3);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SpokenLibraryState>();
    final player = context.watch<PlayerController>();
    final playingId = player.currentSong?.id;

    if (state.connection == null) {
      return _ConnectState(onConnect: _connect);
    }

    final books = state.bookItems;
    final shows = state.podcastShows;
    final nothingToShow = !state.loading &&
        books.isEmpty &&
        shows.isEmpty &&
        state.error == null;
    final inProgress = [
      ...books.where((b) => b.progress > 0 && b.progress < 1),
      for (final show in shows)
        for (final ep in show.episodes)
          if (ep.progressSeconds > 0 &&
              show.duration > Duration.zero &&
              ep.progressSeconds / show.duration.inSeconds < 1)
            (show, ep),
    ];

    final showBooks = _filter == 'All' || _filter == 'Audiobooks';
    final showPods = _filter == 'All' || _filter == 'Podcasts';

    return Container(
      color: _C.bg,
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(_C.violet.withValues(alpha: 0.45)),
          trackColor: WidgetStateProperty.all(_C.borderSoft),
          thickness: WidgetStateProperty.all(8),
          radius: const Radius.circular(4),
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(state),
                if (state.loading) ...[
                  const SizedBox(height: 14),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _C.violet)),
                    const SizedBox(width: 12),
                    Flexible(
                        child: Text(
                            state.progress ?? 'Fetching libraries…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _ts(12, c: _C.muted))),
                  ]),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _C.rose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _C.rose.withValues(alpha: 0.4))),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          color: _C.pink, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(state.error!,
                              style: _ts(12, c: _C.textSoft))),
                    ]),
                  ),
                ],
                if (nothingToShow) ...[
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                        color: _C.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _C.border)),
                    child: Column(children: [
                      const Icon(Icons.library_books_rounded,
                          color: _C.violetLight, size: 36),
                      const SizedBox(height: 12),
                      Text('No audiobooks or podcasts found',
                          style: _ts(15, w: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          'The server connected, but its libraries came back empty. Add items in Audiobookshelf (or check the library type) and refresh.',
                          textAlign: TextAlign.center,
                          style: _ts(13, c: _C.muted, h: 1.5)),
                      const SizedBox(height: 14),
                      _Hover(
                        onTap: state.loading ? null : state.refresh,
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                              color: _C.violet.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                  color: _C.violet.withValues(alpha: 0.6))),
                          child: Text('Refresh',
                              style: _ts(12,
                                  w: FontWeight.w700, c: _C.violetPale)),
                        ),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 22),
                _chips(state),
                const SizedBox(height: 26),
                if (inProgress.isNotEmpty && _filter != 'Podcasts') ...[
                  _section('Continue listening'),
                  const SizedBox(height: 14),
                  _continueRow(inProgress.take(2).toList(), playingId),
                  const SizedBox(height: 30),
                ],
                if (showBooks) ...[
                  _section('Audiobooks',
                      trailing: books.length > 8
                          ? _link(
                              _showAll ? 'Show less' : 'Show all ${books.length}',
                              () => setState(() => _showAll = !_showAll))
                          : null),
                  const SizedBox(height: 14),
                  _audiobookShelf(books, playingId),
                  const SizedBox(height: 30),
                ],
                if (showPods && shows.isNotEmpty) ...[
                  _section('Podcasts'),
                  const SizedBox(height: 14),
                  ...[
                    for (final show in shows) ...[
                      _section(show.title),
                      const SizedBox(height: 10),
                      _episodeList(show, playingId),
                      const SizedBox(height: 24),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(SpokenLibraryState state) => Row(
        children: [
          Text('Books & podcasts',
              style: _ts(32, w: FontWeight.w800, ls: -0.6)),
          const Spacer(),
          _iconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh libraries',
            onTap: state.loading ? null : state.refresh,
          ),
        ],
      );

  Widget _iconButton(
          {required IconData icon,
          required String tooltip,
          required VoidCallback? onTap}) =>
      Tooltip(
        message: tooltip,
        child: _Hover(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: Icon(icon, size: 17, color: _C.textSoft),
          ),
        ),
      );

  // ── Chips ─────────────────────────────────────────────────────────────────
  Widget _chips(SpokenLibraryState state) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in const ['All', 'Audiobooks', 'Podcasts'])
            _chip(f, state),
        ],
      );

  Widget _chip(String label, SpokenLibraryState state) {
    final active = _filter == label;
    return _Hover(
      onTap: () => setState(() => _filter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _C.violet : const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? Colors.transparent : _C.border, width: 1),
        ),
        child: Text(label,
            style: _ts(13,
                w: FontWeight.w600, c: active ? Colors.white : _C.textSoft)),
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _section(String title, {Widget? trailing}) => Row(
        children: [
          Text(title.toUpperCase(),
              style: _ts(11, w: FontWeight.w700, c: _C.faint, ls: 1)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );

  Widget _link(String label, VoidCallback onTap) => _Hover(
        onTap: onTap,
        child: Text(label,
            style: _ts(12, w: FontWeight.w600, c: _C.violetLight)),
      );

  // ── Continue listening ────────────────────────────────────────────────────
  Widget _continueRow(
      List<dynamic> entries, String? playingId) {
    final cards = <Widget>[
      for (final entry in entries)
        () {
          final SpokenItem item = entry is SpokenItem ? entry : entry.$1 as SpokenItem;
          final SpokenEpisode? ep = entry is SpokenItem ? null : entry.$2 as SpokenEpisode;
          final id = ep == null ? 'abs_${item.id}' : 'abs_${item.id}_${ep.id}';
          final playing = playingId == id;
          final progress = ep == null
              ? item.progress
              : (ep.duration > Duration.zero
                  ? (ep.progressSeconds / ep.duration.inSeconds).clamp(0.0, 1.0)
                  : 0.0);
          final total = ep?.duration ?? item.duration;
          final left = total -
              Duration(
                  seconds:
                      (ep?.progressSeconds ?? item.progressSeconds).round());
          return _continueCard(
            item: item,
            episode: ep,
            playing: playing,
            progress: progress,
            meta:
                '${(progress * 100).round()}% · ${_hoursLabel(left)} left',
          );
        }(),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    if (cards.length == 1) return cards.first;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      if (wide) {
        return Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 24),
          Expanded(child: cards[1]),
        ]);
      }
      return Column(children: [
        cards[0],
        const SizedBox(height: 16),
        cards[1],
      ]);
    });
  }

  Widget _continueCard({
    required SpokenItem item,
    required SpokenEpisode? episode,
    required bool playing,
    required double progress,
    required String meta,
  }) {
    return _Hover(
      onTap: () => _play(item, episode: episode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 148,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: _grad([
            _C.violet.withValues(alpha: playing ? 0.30 : 0.18),
            _C.card,
          ], begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: playing
                  ? _C.violetLight.withValues(alpha: 0.6)
                  : _C.border),
        ),
        child: Row(children: [
          _cover(w: 116, h: 116, r: 12, colors: _coverFor(item.id)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(episode?.title ?? item.title,
                    style: _ts(18, w: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                    episode == null ? item.creator : 'Podcast · ${item.title}',
                    style: _ts(13, c: _C.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 18),
                _rail(value: progress, height: 4),
                const SizedBox(height: 8),
                Text(meta,
                    style: _ts(12, w: FontWeight.w500, c: _C.violetPale)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _playButton(
            size: 48,
            playing: playing,
            onTap: () => _play(item, episode: episode),
          ),
        ]),
      ),
    );
  }

  // ── Audiobooks ────────────────────────────────────────────────────────────
  Widget _audiobookShelf(List<SpokenItem> books, String? playingId) {
    if (_showAll || _filter == 'Audiobooks') {
      return LayoutBuilder(builder: (context, c) {
        final n = (c.maxWidth / 140).floor().clamp(2, 8);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: n,
          mainAxisSpacing: 22,
          crossAxisSpacing: 22,
          childAspectRatio: 118 / 226,
          children: [for (final b in books) _bookCard(b, playingId)],
        );
      });
    }
    return SizedBox(
      height: 226,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length.clamp(0, 8),
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (_, i) => _bookCard(books[i], playingId),
      ),
    );
  }

  Widget _bookCard(SpokenItem b, String? playingId) {
    final playing = playingId == 'abs_${b.id}';
    return SizedBox(
      width: 118,
      child: _Hover(
        onTap: () => _openBook(b),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: playing
                      ? _C.violet.withValues(alpha: 0.45)
                      : Colors.black.withValues(alpha: 0.4),
                  blurRadius: playing ? 22 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _cover(w: 118, h: 168, r: 10, colors: _coverFor(b.id)),
          ),
          const SizedBox(height: 4),
          _rail(
              value: b.progress,
              height: 3,
              color: b.progress >= 1 ? _C.green : _C.violetLight),
          const SizedBox(height: 7),
          Text(b.title,
              style: _ts(13, w: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(b.creator,
              style: _ts(12, c: _C.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ── Episodes ──────────────────────────────────────────────────────────────
  Widget _episodeList(SpokenItem show, String? playingId) => Container(
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.border),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          for (var i = 0; i < show.episodes.length; i++)
            _episodeRow(show, show.episodes[i], i < show.episodes.length - 1,
                playingId),
        ]),
      );

  Widget _episodeRow(
      SpokenItem show, SpokenEpisode e, bool divider, String? playingId) {
    final playing = playingId == 'abs_${show.id}_${e.id}';
    return Column(children: [
      _Hover(
        onTap: () => _play(show, episode: e),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: playing
                ? _C.violet.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final compact = c.maxWidth < 640;
            final isNew = e.publishedAt != null &&
                DateTime.now().difference(e.publishedAt!).inDays <= 7 &&
                !DateTime.now().isBefore(e.publishedAt!);
            return Row(children: [
              _cover(w: 40, h: 40, r: 8, colors: _coverFor(show.id), shadow: false),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        style: _ts(14, w: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(show.title,
                        style: _ts(12, c: _C.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (isNew)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _C.cyan.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text('NEW',
                      style: _ts(10,
                          w: FontWeight.w700, c: _C.cyanText, ls: 0.6)),
                ),
              if (!compact) ...[
                SizedBox(
                    width: 90,
                    child: Text(_relativeDate(e.publishedAt),
                        style: _ts(13, c: _C.faint))),
                SizedBox(
                    width: 70,
                    child: Text(_hoursLabel(e.duration),
                        style: _ts(13, c: _C.faint))),
              ],
              _playButton(
                size: 36,
                playing: playing,
                subtle: true,
                onTap: () => _play(show, episode: e),
              ),
              const SizedBox(width: 6),
            ]);
          }),
        ),
      ),
      if (divider)
        Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: _C.borderSoft),
    ]);
  }

  // ── Shared primitives ─────────────────────────────────────────────────────
  Widget _cover(
          {required double w,
          required double h,
          required double r,
          required List<Color> colors,
          bool shadow = true}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: _grad(colors),
          borderRadius: BorderRadius.circular(r),
          boxShadow: shadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
      );

  Widget _rail(
          {required double value,
          double height = 4,
          Color color = _C.violetLight}) =>
      Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      );

  Widget _playButton(
          {required double size,
          required VoidCallback onTap,
          bool playing = false,
          bool subtle = false}) =>
      _Hover(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: subtle ? const Color(0x14FFFFFF) : _C.violet,
            shape: BoxShape.circle,
            boxShadow: subtle
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * 0.44,
            color: subtle ? _C.text : Colors.white,
          ),
        ),
      );

  // ── Book detail sheet (real data: progress, duration, description) ────────
  void _openBook(SpokenItem b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: _C.border),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _C.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _cover(w: 96, h: 136, r: 10, colors: _coverFor(b.id)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, style: _ts(22, w: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${b.creator} · ${_hoursLabel(b.duration)}',
                        style: _ts(13, c: _C.muted)),
                    const SizedBox(height: 14),
                    _rail(value: b.progress),
                    const SizedBox(height: 8),
                    Text(
                      b.progress >= 1
                          ? 'Finished'
                          : '${(b.progress * 100).round()}% complete',
                      style: _ts(12, w: FontWeight.w500, c: _C.violetPale),
                    ),
                    const SizedBox(height: 16),
                    _Hover(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _play(b);
                      },
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: _C.violet,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_arrow_rounded,
                              size: 18, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(b.progress > 0 ? 'Resume' : 'Play',
                              style:
                                  _ts(13, w: FontWeight.w700, c: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            if (b.description.isNotEmpty) ...[
              const SizedBox(height: 24),
              _section('About'),
              const SizedBox(height: 8),
              Text(b.description,
                  style: _ts(13, c: _C.textSoft, h: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect / hover
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectState extends StatelessWidget {
  const _ConnectState({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, color: _C.violetLight, size: 42),
            const SizedBox(height: 14),
            Text('Connect Audiobookshelf',
                style: _ts(16, w: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                'Your audiobooks and podcasts live on your own Audiobookshelf server. Connect it to browse and play them here.',
                textAlign: TextAlign.center,
                style: _ts(13, c: _C.muted, h: 1.5)),
            const SizedBox(height: 18),
            _Hover(
              onTap: onConnect,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _C.violet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: _C.violet.withValues(alpha: 0.6)),
                ),
                child: Text('Connect',
                    style: _ts(13, w: FontWeight.w700, c: _C.violetPale)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Hover({required this.child, this.onTap});
  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hover = false, _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            scale: _down ? 0.98 : (_hover ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

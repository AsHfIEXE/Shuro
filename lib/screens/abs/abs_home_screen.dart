import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../books/abs_stats_screen.dart';
import 'abs_book_screen.dart';
import 'abs_podcast_screen.dart';
import 'abs_widgets.dart';

/// Books & podcasts home: Continue listening card, audiobook rail, podcast
/// rail. >= 900 dp = desktop layout, narrower = Android.
///
/// Loads on open when the shelves are still empty, and renders the state
/// class's error / loading / empty outcomes explicitly — a silent blank page
/// with no retry read like a broken feature (the connection lives on another
/// machine, so "server down" is a normal state here, not an edge case).
class AbsHomeScreen extends StatefulWidget {
  const AbsHomeScreen({super.key});
  @override
  State<AbsHomeScreen> createState() => _AbsHomeScreenState();
}

class _AbsHomeScreenState extends State<AbsHomeScreen> {
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    // First open in a session where the restore-refresh already ran, the
    // shelves are populated and this is free. If the server was unreachable
    // at app start, this is the moment the user actually looks at the page —
    // try again instead of showing yesterday's nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<SpokenLibraryState>();
      if (s.connection == null || s.loading || s.error != null) return;
      if (s.bookItems.isEmpty && s.podcastShows.isEmpty) s.refresh();
    });
  }

  void _open(SpokenItem i) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => i.isBook ? AbsBookScreen(item: i) : AbsPodcastScreen(show: i)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SpokenLibraryState>();
    final books = s.bookItems;
    final shows = s.podcastShows;
    final inProgress = books
        .where((b) => (s.liveProgressSecondsFor(b) ?? b.progressSeconds) > 0 &&
            !s.isFinishedFor(b))
        .toList()
      ..sort((a, b) => s.lastProgressAt(b.id).compareTo(s.lastProgressAt(a.id)));
    final current = inProgress.isEmpty ? null : inProgress.first;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final pad = wide ? 40.0 : 16.0;
          final showBooks = _filter == 'All' || _filter == 'Audiobooks';
          final showPods = _filter == 'All' || _filter == 'Podcasts';
          return RefreshIndicator(
            onRefresh: s.refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(pad, wide ? 32 : 12, pad, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: DesktopTokens.contentStandard),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            child: Text('Books & podcasts',
                                style: absHeading(wide ? 36 : 28, ls: -0.9))),
                        AbsGhostButton('Stats',
                            icon: Icons.insights_rounded,
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const AbsStatsScreen()))),
                      ]),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final f in const ['All', 'Audiobooks', 'Podcasts'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: AbsChip(f,
                                  selected: _filter == f,
                                  onTap: () => setState(() => _filter = f)),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 28),
                      if (s.connection == null)
                        _StateCard(
                          icon: Icons.link_off_rounded,
                          title: 'Audiobookshelf is not connected',
                          body:
                              'Connect your server under Settings → Servers, then come back — your audiobooks and podcasts appear here.',
                        )
                      else if (s.error != null)
                        _StateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not reach the server',
                          body: '${s.error} Check that the Audiobookshelf machine is on and reachable, then try again.',
                          action: AbsPrimaryButton('Try again',
                              onTap: s.loading ? null : s.refresh),
                        )
                      else if (s.loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 72),
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const CircularProgressIndicator(color: kBrandColor),
                              if (s.progress != null) ...[
                                const SizedBox(height: 16),
                                Text(s.progress!, style: absText(13, color: kMuted2)),
                              ],
                            ]),
                          ),
                        )
                      else if (books.isEmpty && shows.isEmpty)
                        _StateCard(
                          icon: Icons.library_books_rounded,
                          title: 'No books or podcasts here yet',
                          body:
                              'The server answered, but this user sees no audiobook or podcast libraries. Give the user access to at least one library in Audiobookshelf (Users → permissions), or pull down to refresh.',
                          action: AbsGhostButton('Refresh',
                              icon: Icons.refresh_rounded, onTap: s.refresh),
                        )
                      else ...[
                        if (current != null && showBooks) ...[
                          _Continue(
                              item: current,
                              wide: wide,
                              onOpen: () => _open(current)),
                          const SizedBox(height: 32),
                        ],
                        if (showBooks && inProgress.length > 1) ...[
                          // Every book mid-flight, most recent first — the
                          // featured card above is just the newest one.
                          _Rail(
                              title: 'Continue listening',
                              items: inProgress,
                              wide: wide,
                              onOpen: _open),
                          const SizedBox(height: 32),
                        ],
                        if (showBooks && books.isNotEmpty)
                          _Rail(
                              title: 'Audiobooks',
                              items: books,
                              wide: wide,
                              onOpen: _open),
                        if (showPods && shows.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          _Rail(title: 'Podcasts', items: shows, wide: wide, onOpen: _open),
                        ],
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Full-width state card: an actual explanation plus the action that fixes
/// it — never a bare "nothing here" over a silent failure.
class _StateCard extends StatelessWidget {
  const _StateCard(
      {required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      padding: EdgeInsets.all(wide ? 24 : 16),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 28, color: kVioletLight),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: absHeading(wide ? 20 : 17, ls: -0.4))),
        ]),
        const SizedBox(height: 10),
        Text(body, style: absText(14, color: kNavText, h: 1.5)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class _Continue extends StatelessWidget {
  const _Continue({required this.item, required this.wide, required this.onOpen});
  final SpokenItem item;
  final bool wide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.read<SpokenLibraryState>();
    final at = s.liveProgressSecondsFor(item) ?? item.progressSeconds;
    final left = item.duration - Duration(seconds: at.round());
    final chapter = item.chapters.lastWhere((c) => c.start <= at,
        orElse: () => item.chapters.isEmpty
            ? const SpokenChapter(id: 0, start: 0, end: 0, title: '')
            : item.chapters.first);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('CONTINUE LISTENING',
            style: absText(12, color: kVioletLight, w: FontWeight.w700, ls: 1.68)),
        const SizedBox(height: 8),
        Text(item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: absHeading(wide ? 32 : 24, ls: -0.8)),
        const SizedBox(height: 6),
        Text(item.creator, style: absText(15, color: kVioletLight, w: FontWeight.w600)),
        if (chapter.title.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(chapter.title, style: absText(13, color: kMuted2)),
        ],
        const SizedBox(height: 12),
        AbsProgressBar(item.progress),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${absClock(Duration(seconds: at.round()))} listened',
              style: absText(12, color: kMuted2, tabular: true)),
          Text('${absClock(left)} left', style: absText(12, color: kMuted2, tabular: true)),
        ]),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 8, children: [
          AbsPrimaryButton('Resume', onTap: () => AbsActions.play(context, item)),
          AbsGhostButton('Book details', onTap: onOpen),
        ]),
      ],
    );

    return Container(
      padding: EdgeInsets.all(wide ? 24 : 16),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: wide
          ? Row(children: [
              AbsCover(item, width: 140, radius: 10),
              const SizedBox(width: 28),
              Expanded(child: info),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AbsCover(item, width: 96, radius: 8),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CONTINUE LISTENING',
                      style: absText(11, color: kVioletLight, w: FontWeight.w700, ls: 1.4)),
                  const SizedBox(height: 6),
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: absHeading(20, ls: -0.4)),
                  const SizedBox(height: 4),
                  Text(item.creator,
                      style: absText(13, color: kVioletLight, w: FontWeight.w600)),
                ])),
              ]),
              const SizedBox(height: 16),
              AbsProgressBar(item.progress),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${absClock(Duration(seconds: at.round()))} listened',
                    style: absText(12, color: kMuted2, tabular: true)),
                Text('${absClock(left)} left',
                    style: absText(12, color: kMuted2, tabular: true)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: AbsPrimaryButton('Resume',
                    onTap: () => AbsActions.play(context, item))),
                const SizedBox(width: 10),
                AbsGhostButton('Details', onTap: onOpen),
              ]),
            ]),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.items, required this.wide, required this.onOpen});
  final String title;
  final List<SpokenItem> items;
  final bool wide;
  final ValueChanged<SpokenItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final w = wide ? 168.0 : 132.0;
    final h = w * (title == 'Podcasts' ? 1.0 : 1.5);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: absText(wide ? 24 : 20, w: FontWeight.w800)),
      const SizedBox(height: 16),
      SizedBox(
        height: h + 70,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => SizedBox(width: wide ? 24 : 14),
          itemBuilder: (_, i) {
            final it = items[i];
            final prog = context.read<SpokenLibraryState>().liveProgressSecondsFor(it);
            final p = it.isBook && it.duration.inSeconds > 0
                ? ((prog ?? it.progressSeconds) / it.duration.inSeconds)
                : 0.0;
            return SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onOpen(it),
                    child: AbsCover(it, width: w, height: h),
                  ),
                  // Direct play: the disc starts it now, the rest of the
                  // cover opens the detail page. A rail that only opens
                  // pages read as "can't play" to anyone used to tapping
                  // a shelf to listen.
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Semantics(
                      button: true,
                      label: 'Play ${it.title}',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => AbsActions.play(context, it),
                          child: Tooltip(
                            message: 'Play ${it.title}',
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: kBrandColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.25)),
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  size: 28, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                if (p > 0 && p < 1) ...[AbsProgressBar(p, height: 3), const SizedBox(height: 8)],
                InkWell(
                  onTap: () => onOpen(it),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: absText(14, w: FontWeight.w600)),
                    Text(it.creator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: absText(13, color: kMuted2)),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

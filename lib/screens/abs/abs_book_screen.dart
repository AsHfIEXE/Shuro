import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import 'abs_player_screen.dart';
import 'abs_widgets.dart';

/// Book detail: cover + title block, progress, Resume / Bookmarks, summary
/// and the chapter list (tap a chapter to start from it).
///
/// The library listing hides book chapters, so when the handed row has none
/// this screen fetches the full item (`expandShow`) instead of rendering a
/// chapter-less page forever.
class AbsBookScreen extends StatefulWidget {
  const AbsBookScreen({super.key, required this.item});
  final SpokenItem item;

  @override
  State<AbsBookScreen> createState() => _AbsBookScreenState();
}

class _AbsBookScreenState extends State<AbsBookScreen> {
  Future<SpokenItem?>? _expand;

  @override
  void initState() {
    super.initState();
    if (widget.item.chapters.isEmpty) {
      _expand = context.read<SpokenLibraryState>().expandShow(widget.item);
    }
  }

  /// Best copy of the book: fetched with chapters > a state copy that gained
  /// chapters > the listing row it was handed.
  SpokenItem _resolve(AsyncSnapshot<SpokenItem?> snap, SpokenLibraryState s) {
    var item = widget.item;
    if (snap.hasData && snap.data!.chapters.isNotEmpty) return snap.data!;
    if (item.chapters.isEmpty) {
      for (final x in s.bookItems) {
        if (x.id == item.id && x.chapters.isNotEmpty) return x;
      }
    }
    return item;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SpokenLibraryState>();
    return FutureBuilder<SpokenItem?>(
      future: _expand,
      builder: (context, snap) {
        final item = _resolve(snap, s);
        final waitingChapters = item.chapters.isEmpty && _expand != null && !snap.hasData;
        final at = s.liveProgressSecondsFor(item) ?? item.progressSeconds;
        final left = item.duration - Duration(seconds: at.round());
        final curIdx = item.chapters.lastIndexWhere((c) => c.start <= at);
        final series = item.seriesNames.isEmpty ? '' : ' · SERIES';

        return Scaffold(
          backgroundColor: kSurfaceColor,
          body: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final pad = wide ? 40.0 : 16.0;

            final facts = [
              if (item.seriesNames.isNotEmpty) item.seriesNames.first,
              absClock(item.duration),
              if (item.chapters.isNotEmpty) '${item.chapters.length} chapters',
            ].join(' · ');

            final progress = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(
                  child: Text(curIdx >= 0 ? item.chapters[curIdx].title : 'Not started',
                      overflow: TextOverflow.ellipsis,
                      style: absText(13, color: kNavText)),
                ),
                Text('${(item.progress * 100).round()}% · ${absClock(left)} left',
                    style: absText(13, color: kMuted2, tabular: true)),
              ]),
              const SizedBox(height: 10),
              AbsProgressBar(at / (item.duration.inSeconds == 0 ? 1 : item.duration.inSeconds)),
            ]);

            final actions = Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AbsPrimaryButton(at > 0 ? 'Resume' : 'Play', onTap: () {
                AbsActions.play(context, item);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AbsPlayerScreen(item: item)));
              }),
              AbsGhostButton('Bookmarks',
                  icon: Icons.bookmark_border_rounded, onTap: () => _bookmarks(context)),
              IconButton(
                  tooltip: 'Mark as played',
                  onPressed: () => s.markPlayed(item),
                  icon: const Icon(Icons.done_all_rounded, color: kNavText)),
            ]);

            final head = wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AbsCover(item, width: 260, height: 390, radius: 14),
                    const SizedBox(width: 40),
                    Expanded(child: _meta(item, series, facts, progress, actions, true)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Center(child: AbsCover(item, width: 200, height: 300, radius: 12)),
                    const SizedBox(height: 24),
                    _meta(item, series, facts, progress, actions, false),
                  ]);

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.6, -1),
                  end: Alignment.bottomRight,
                  colors: [kBrandColor.withValues(alpha: 0.18), kSurfaceColor],
                  stops: const [0, 0.7],
                ),
              ),
              child: SafeArea(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded, color: kTextColor)),
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: DesktopTokens.contentStandard),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          head,
                          if (item.chapters.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            Text('CHAPTERS',
                                style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.9)),
                            const SizedBox(height: 8),
                            for (var i = 0; i < item.chapters.length; i++)
                              _ChapterRow(
                                n: i + 1,
                                chapter: item.chapters[i],
                                current: i == curIdx,
                                onTap: () => AbsActions.play(context, item,
                                    startAt: Duration(seconds: item.chapters[i].start.round())),
                              ),
                          ] else if (waitingChapters) ...[
                            const SizedBox(height: 24),
                            Row(children: [
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kBrandColor)),
                              const SizedBox(width: 10),
                              Text('Loading chapters…', style: absText(13, color: kMuted2)),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _meta(SpokenItem item, String series, String facts, Widget progress, Widget actions,
          bool wide) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('AUDIOBOOK$series',
            style: absText(12, color: kVioletLight, w: FontWeight.w700, ls: 1.68)),
        const SizedBox(height: 8),
        Text(item.title, style: absHeading(wide ? 44 : 30, ls: -1.2).copyWith(height: 1.1)),
        const SizedBox(height: 12),
        Text(item.creator, style: absText(16, color: kVioletLight, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(facts, style: absText(13, color: kMuted2, tabular: true)),
        const SizedBox(height: 24),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: progress),
        const SizedBox(height: 24),
        actions,
        if (item.description.isNotEmpty) ...[
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(item.description,
                maxLines: wide ? 5 : 6,
                overflow: TextOverflow.ellipsis,
                style: absText(14, color: kNavText, h: 1.6)),
          ),
        ],
      ]);

  Future<void> _bookmarks(BuildContext context) async {
    final s = context.read<SpokenLibraryState>();
    final marks = await s.bookmarksFor(widget.item.id);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kRaisedColor,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: marks.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No bookmarks yet.', style: absText(14, color: kMuted2)))
            : ListView(shrinkWrap: true, children: [
                for (final m in marks)
                  ListTile(
                    title: Text('${m['title'] ?? 'Bookmark'}', style: absText(14, w: FontWeight.w600)),
                    trailing: Text(absClock(Duration(seconds: ((m['time'] as num?) ?? 0).round())),
                        style: absText(13, color: kMuted2, tabular: true)),
                    onTap: () {
                      Navigator.pop(context);
                      AbsActions.play(context, widget.item,
                          startAt: Duration(seconds: ((m['time'] as num?) ?? 0).round()));
                    },
                  ),
              ]),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.n, required this.chapter, required this.current, required this.onTap});
  final int n;
  final SpokenChapter chapter;
  final bool current;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: current ? kBrandColor.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            SizedBox(
              width: 40,
              child: Center(
                  child: current
                      ? const Icon(Icons.graphic_eq_rounded, size: 18, color: kVioletPale)
                      : Text('$n', style: absText(13, color: kMuted2, tabular: true))),
            ),
            Expanded(
                child: Text(chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(14, w: FontWeight.w600, color: current ? kVioletPale : kTextColor))),
            Text(absClock(Duration(seconds: (chapter.end - chapter.start).round())),
                style: absText(13, color: kMuted2, tabular: true)),
          ]),
        ),
      );
}

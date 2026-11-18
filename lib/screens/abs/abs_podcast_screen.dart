import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../state/player_controller.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import 'abs_widgets.dart';

/// Podcast show: hero + episode list. Desktop shows a table
/// (episode / date / time), Android a two-line list. Played episodes dim,
/// the playing one gets the violet edge, unplayed recent ones a NEW chip.
///
/// The library listing hides a show's episodes, so this screen fetches the
/// full item itself (`expandShow`: item GET, then the podcast endpoint as
/// the source of truth) instead of trusting the row it was handed.
class AbsPodcastScreen extends StatefulWidget {
  const AbsPodcastScreen({super.key, required this.show});
  final SpokenItem show;

  @override
  State<AbsPodcastScreen> createState() => _AbsPodcastScreenState();
}

class _AbsPodcastScreenState extends State<AbsPodcastScreen> {
  Future<SpokenItem?>? _expand;
  bool _expandFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.show.episodes.isEmpty) _startExpand();
  }

  void _startExpand() {
    setState(() => _expandFailed = false);
    _expand = context
        .read<SpokenLibraryState>()
        .expandShow(widget.show)
        .then((item) {
      if (item == null || item.episodes.isEmpty) _expandFailed = true;
      return item;
    });
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }

  /// Best copy of the show: fetched with episodes > listing with episodes >
  /// a state copy that gained episodes (a play cached it) > the listing row.
  SpokenItem _resolve(AsyncSnapshot<SpokenItem?> snap, SpokenLibraryState s) {
    final listed = widget.show;
    if (snap.hasData && snap.data!.episodes.isNotEmpty) return snap.data!;
    if (listed.episodes.isNotEmpty) return listed;
    for (final x in s.podcastShows) {
      if (x.id == listed.id && x.episodes.isNotEmpty) return x;
    }
    return listed;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SpokenLibraryState>();
    return FutureBuilder<SpokenItem?>(
      future: _expand,
      builder: (context, snap) {
        final show = _resolve(snap, s);
        final playingId = context.watch<PlayerController>().currentSong?.id ?? '';
        final eps = [...show.episodes]..sort((a, b) =>
            (b.publishedAt ?? DateTime(0)).compareTo(a.publishedAt ?? DateTime(0)));
        final now = DateTime.now();
        final loadingEps = show.episodes.isEmpty && _expand != null && !snap.hasData;

        double progressOf(SpokenEpisode e) =>
            s.liveProgressSecondsFor(show, episode: e) ?? e.progressSeconds;
        bool played(SpokenEpisode e) =>
            e.duration.inSeconds > 0 && progressOf(e) >= e.duration.inSeconds - 30;
        bool isNew(SpokenEpisode e) =>
            !played(e) && progressOf(e) == 0 &&
            e.publishedAt != null && now.difference(e.publishedAt!).inDays < 7;
        final newCount = eps.where(isNew).length;

        return Scaffold(
          backgroundColor: kSurfaceColor,
          body: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final pad = wide ? 40.0 : 16.0;

            final actions = Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AbsPrimaryButton('Play latest',
                  onTap: eps.isEmpty ? null : () => AbsActions.play(context, show, episode: eps.first)),
              AbsGhostButton('Mark all played', onTap: eps.isEmpty ? null : () async {
                for (final e in eps.where((e) => !played(e))) {
                  await s.markPlayed(show, episode: e);
                }
              }),
            ]);

            final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PODCAST', style: absText(12, color: kVioletLight, w: FontWeight.w700, ls: 1.68)),
              const SizedBox(height: 8),
              Text(show.title, style: absHeading(wide ? 48 : 30, ls: -1.4).copyWith(height: 1.1)),
              const SizedBox(height: 12),
              Text(show.creator, style: absText(15, color: kVioletLight, w: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('${eps.length} episodes${newCount > 0 ? ' · $newCount new' : ''}',
                  style: absText(13, color: kMuted2, tabular: true)),
              const SizedBox(height: 24),
              actions,
            ]);

            final hero = wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    AbsCover(show, width: 232, height: 232, radius: 16),
                    const SizedBox(width: 32),
                    Expanded(child: info),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Center(child: AbsCover(show, width: 180, height: 180, radius: 14)),
                    const SizedBox(height: 20),
                    info,
                  ]);

            Widget row(SpokenEpisode e) {
              final cur = playingId.contains(e.id);
              final done = played(e);
              final prog = e.duration.inSeconds == 0 ? 0.0 : progressOf(e) / e.duration.inSeconds;
              final title = Row(children: [
                Flexible(
                  child: Text(e.title,
                      maxLines: wide ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: absText(14, w: FontWeight.w600, color: cur ? kVioletPale : kTextColor)),
                ),
                if (isNew(e)) ...[
                  const SizedBox(width: 8),
                  Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                    child: Text('NEW', style: absText(11, color: kGreen, w: FontWeight.w700)),
                  ),
                ],
              ]);
              final remaining = e.duration - Duration(seconds: progressOf(e).round());
              return Opacity(
                opacity: done && !cur ? 0.55 : 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => AbsActions.play(context, show, episode: e),
                  onLongPress: () => AbsActions.play(context, show, episode: e, queue: true),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 76),
                    padding: EdgeInsets.fromLTRB(wide ? 14 : 8, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: cur ? kBrandColor.withValues(alpha: 0.12) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      if (cur)
                        Container(width: 3, height: 40, margin: const EdgeInsets.only(right: 11),
                            decoration: BoxDecoration(color: kBrandColor, borderRadius: BorderRadius.circular(2))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          title,
                          if (!wide) ...[
                            const SizedBox(height: 4),
                            Text('${_date(e.publishedAt)} · ${absClock(prog > 0 && !done ? remaining : e.duration)}${prog > 0 && !done ? ' left' : ''}',
                                style: absText(13, color: kMuted2, tabular: true)),
                          ],
                          if (prog > 0 && !done) ...[
                            const SizedBox(height: 8),
                            SizedBox(width: wide ? 320 : double.infinity, child: AbsProgressBar(prog, height: 3)),
                          ],
                        ]),
                      ),
                      if (wide) ...[
                        SizedBox(width: 120, child: Text(_date(e.publishedAt), style: absText(13, color: kMuted2))),
                        SizedBox(
                            width: 80,
                            child: Text(absClock(e.duration),
                                textAlign: TextAlign.right,
                                style: absText(13, color: kNavText, tabular: true))),
                      ],
                      IconButton(
                        tooltip: 'Add to queue',
                        icon: const Icon(Icons.playlist_add_rounded, color: kNavText),
                        onPressed: () => AbsActions.play(context, show, episode: e, queue: true),
                      ),
                    ]),
                  ),
                ),
              );
            }

            final episodesBlock = show.episodes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: loadingEps
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                              const CircularProgressIndicator(color: kBrandColor),
                              const SizedBox(height: 14),
                              Text('Loading episodes…', style: absText(13, color: kMuted2)),
                            ])
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_expandFailed ? Icons.cloud_off_rounded : Icons.podcasts_rounded,
                                  size: 32, color: kMuted3),
                              const SizedBox(height: 10),
                              Text(
                                _expandFailed
                                    ? 'Could not load episodes'
                                    : 'No episodes on the server for this show',
                                style: absText(15, w: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(
                                _expandFailed
                                    ? 'The library answered but this show did not. Check the server is reachable and try again.'
                                    : 'Add episodes in Audiobookshelf, then pull down to refresh.',
                                textAlign: TextAlign.center,
                                style: absText(13, color: kMuted2)),
                              const SizedBox(height: 14),
                              Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                                if (_expandFailed)
                                  AbsGhostButton('Try again',
                                      icon: Icons.refresh_rounded, onTap: _startExpand),
                                // The session machinery carries its own
                                // fallbacks (direct tracks, file probes) —
                                // a show whose episode list will not load
                                // can still be playable through it.
                                AbsGhostButton('Play anyway',
                                    onTap: () => AbsActions.play(context, show)),
                              ]),
                            ]),
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (wide)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kHairline))),
                        child: Row(children: [
                          Expanded(child: Text('EPISODE', style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.8))),
                          SizedBox(width: 120, child: Text('DATE', style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.8))),
                          SizedBox(width: 80, child: Text('TIME', textAlign: TextAlign.right, style: absText(12, color: kMuted2, w: FontWeight.w700, ls: 0.8))),
                          const SizedBox(width: 48),
                        ]),
                      ),
                    for (final e in eps) row(e),
                  ]);

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.6, -1),
                  end: Alignment.bottomRight,
                  colors: [kBrandColor.withValues(alpha: 0.16), kSurfaceColor],
                  stops: const [0, 0.8],
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
                          hero,
                          const SizedBox(height: 24),
                          episodesBlock,
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
}

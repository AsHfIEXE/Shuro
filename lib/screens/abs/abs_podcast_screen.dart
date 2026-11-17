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
class AbsPodcastScreen extends StatelessWidget {
  const AbsPodcastScreen({super.key, required this.show});
  final SpokenItem show;

  static String _date(DateTime? d) {
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SpokenLibraryState>();
    final playingId = context.watch<PlayerController>().currentSong?.id ?? '';
    final eps = [...show.episodes]..sort((a, b) =>
        (b.publishedAt ?? DateTime(0)).compareTo(a.publishedAt ?? DateTime(0)));
    final now = DateTime.now();

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
          AbsGhostButton('Mark all played', onTap: () async {
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
                        Text('${_date(e.publishedAt)} · ${absLength(prog > 0 && !done ? remaining : e.duration)}${prog > 0 && !done ? ' left' : ''}',
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
                        child: Text(absLength(e.duration),
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
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

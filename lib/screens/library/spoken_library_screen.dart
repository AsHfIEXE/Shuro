import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/spoken_media.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/motion.dart';

/// Separate books/podcasts workspace (Books-and-podcasts board). It
/// deliberately does not flatten a show into a playable row: only whole
/// books and episode rows are playable. Progress, episode dates and
/// durations all come from the Audiobookshelf data the state already holds.
enum _SpokenFilter { all, audiobooks, podcasts }

class SpokenLibraryScreen extends StatefulWidget {
  const SpokenLibraryScreen({super.key});

  @override
  State<SpokenLibraryScreen> createState() => _SpokenLibraryScreenState();
}

class _SpokenLibraryScreenState extends State<SpokenLibraryScreen> {
  _SpokenFilter _filter = _SpokenFilter.all;

  Future<void> _connect(BuildContext context) async {
    final url = TextEditingController();
    final token = TextEditingController();
    final name = TextEditingController(text: 'Audiobookshelf');
    final values = await showDialog<(String, String, String)>(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: kCardColor,
              title: const Text('Connect Audiobookshelf'),
              content: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'Connection name')),
                    TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://books.example.com')),
                    TextField(
                        controller: token,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'API token',
                            helperText: 'Stored in secure device storage.')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        context, (name.text, url.text, token.text)),
                    child: const Text('Connect'))
              ],
            ));
    url.dispose();
    token.dispose();
    name.dispose();
    if (values == null || !context.mounted) return;
    await context
        .read<SpokenLibraryState>()
        .connect(name: values.$1, url: values.$2, token: values.$3);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SpokenLibraryState>();
    return Scaffold(
        backgroundColor: kSurfaceColor,
        appBar: AppBar(
            backgroundColor: kSurfaceColor,
            toolbarHeight: 52,
            titleSpacing: 16,
            title: Text('Books & podcasts',
                style: headingFont(color: kTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7)),
            actions: [
              IconButton(
                  tooltip: 'Refresh libraries',
                  onPressed: state.connection == null || state.loading
                      ? null
                      : state.refresh,
                  icon: const Icon(Icons.refresh_rounded)),
            ]),
        body: state.connection == null
            ? _ConnectState(onConnect: () => _connect(context))
            : RefreshIndicator(
                onRefresh: state.refresh,
                // Text lists are designed for 960 px (design doc): on a wide
                // window the extra width becomes margin, never stretched rows.
                child: DesktopContentFrame(
                    maxWidth: DesktopTokens.contentText,
                    child: Builder(builder: (context) {
                      final libraries = switch (_filter) {
                        _SpokenFilter.all => state.libraries,
                        _SpokenFilter.audiobooks => state.bookLibraries,
                        _SpokenFilter.podcasts => state.podcastLibraries,
                      };
                      final books = [
                        for (final library in state.bookLibraries)
                          ...(state.itemsByLibrary[library.id] ??
                              const <SpokenItem>[])
                      ];
                      final inProgress = books
                          .where((b) => b.progress > 0 && b.progress < 1)
                          .toList()
                        ..sort((a, b) => b.progressSeconds.compareTo(a.progressSeconds));
                      final latestEpisodes = _latestEpisodes(state);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Text(state.connection!.name,
                              style: headingFont(
                                  color: kTextColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                              'Books retain a whole-book timeline. Podcast episodes retain independent progress.',
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kMutedTextColor, height: 1.4)),
                          if (state.loading) ...[
                            const SizedBox(height: 16),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kBrandColor)),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                    state.progress ?? 'Fetching libraries…',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kMutedTextColor,
                                        fontSize: 12)),
                              ),
                            ]),
                          ],
                          if (state.error != null) _ErrorBanner(message: state.error!),
                          const SizedBox(height: 12),
                          _FilterChipRow(
                            filter: _filter,
                            bookCount: state.bookLibraries.length,
                            podcastCount: state.podcastLibraries.length,
                            onChanged: (f) => setState(() => _filter = f),
                          ),
                          if (_filter != _SpokenFilter.podcasts &&
                              inProgress.isNotEmpty) ...[
                            _BoardLabel('Continue listening'),
                            Entrance(
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 560,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 132,
                                ),
                                itemCount: inProgress.length,
                                itemBuilder: (context, i) => _ContinueCard(item: inProgress[i]),
                              ),
                            ),
                          ],
                          for (final library in libraries)
                            _LibrarySection(
                              library: library,
                              items: state.itemsByLibrary[library.id] ?? const [],
                            ),
                          if (_filter != _SpokenFilter.audiobooks &&
                              latestEpisodes.isNotEmpty) ...[
                            _BoardLabel('Podcasts · Latest episodes'),
                            Entrance(
                              child: _EpisodesCard(episodes: latestEpisodes),
                            ),
                          ],
                        ],
                      );
                    })),
              ));
  }

  /// Latest episodes across every podcast show, newest first. Only rows the
  /// data supports: a NEW badge from the publish date, a relative date and
  /// the episode's real duration.
  static List<({SpokenItem show, SpokenEpisode episode})> _latestEpisodes(
      SpokenLibraryState state) {
    final rows = <({SpokenItem show, SpokenEpisode episode})>[];
    for (final library in state.podcastLibraries) {
      for (final item in state.itemsByLibrary[library.id] ?? const <SpokenItem>[]) {
        for (final episode in item.episodes) {
          rows.add((show: item, episode: episode));
        }
      }
    }
    rows.sort((a, b) {
      final ad = a.episode.publishedAt;
      final bd = b.episode.publishedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return rows.take(6).toList();
  }
}

/// The board's small uppercase section label (11/Bold #8B93A7, tracked).
class _BoardLabel extends StatelessWidget {
  const _BoardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(text.toUpperCase(),
          style: GoogleFonts.getFont(currentFontFamily,
              color: kMuted2,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1)),
    );
  }
}

/// Board chip row: All / Audiobooks / Podcasts, filtering over the
/// libraries the server actually reported.
class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.filter,
    required this.bookCount,
    required this.podcastCount,
    required this.onChanged,
  });

  final _SpokenFilter filter;
  final int bookCount;
  final int podcastCount;
  final ValueChanged<_SpokenFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, entry) in <(_SpokenFilter, String, int)>[
            (_SpokenFilter.all, 'All', bookCount + podcastCount),
            (_SpokenFilter.audiobooks, 'Audiobooks', bookCount),
            (_SpokenFilter.podcasts, 'Podcasts', podcastCount),
          ].indexed)
            Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
              child: _BoardChip(
                label: entry.$2,
                count: entry.$3,
                active: filter == entry.$1,
                onTap: () => onChanged(entry.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? kBrandColor : kGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active ? BorderSide.none : BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: active ? Colors.white : kNavText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('$count',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: active ? kVioletPale : kMuted3, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient cover with the server's cover image layered on top when it can
/// load (Audiobookshelf serves covers behind the API token, so the gradient
/// placeholder is the honest default).
class _SpokenCover extends StatelessWidget {
  const _SpokenCover({
    required this.item,
    required this.icon,
    required this.radius,
    this.iconSize = 24,
  });

  final SpokenItem item;
  final IconData icon;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: item.isBook
                  ? const [kAccentColor, kBrandColor]
                  : kBrandGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.white70, size: iconSize),
        ),
        if (item.coverUrl != null)
          Image.network(
            item.coverUrl!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Auth-required covers 401: fall back to the gradient quietly.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
      ]),
    );
  }
}

/// A whole-book progress hairline under a cover: violet while in progress,
/// green when finished.
class _CoverProgressLine extends StatelessWidget {
  const _CoverProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(children: [
        Container(height: 3, color: kGlass),
        FractionallySizedBox(
          widthFactor: progress.clamp(0, 1),
          child: Container(height: 3, color: done ? kGreen : kVioletLight),
        ),
      ]),
    );
  }
}

/// "CONTINUE LISTENING" card: cover, title, creator, a real progress bar
/// and the exact percent + time left, all from the server's progress data.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item});

  final SpokenItem item;

  @override
  Widget build(BuildContext context) {
    final left = item.duration - Duration(seconds: item.progressSeconds.round());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Row(
        children: [
          SizedBox(width: 96, height: 96, child: _SpokenCover(item: item, icon: Icons.menu_book_rounded, radius: 12)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: headingFont(
                        color: kTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${item.creator} · ${_hoursLabel(item.duration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 13)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(children: [
                    Container(height: 4, color: kGlass),
                    FractionallySizedBox(
                      widthFactor: item.progress.clamp(0, 1),
                      child: Container(height: 4, color: kVioletLight),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(
                    '${(item.progress * 100).round()}% · ${_hoursLabel(left)} left',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kVioletPale,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One library's items, board style: audiobooks become a cover grid with
/// progress lines; podcasts stay listable shows (whole shows are not
/// playable — their episodes are).
class _LibrarySection extends StatelessWidget {
  const _LibrarySection({required this.library, required this.items});
  final SpokenLibrary library;
  final List<SpokenItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _BoardLabel(
          '${library.name} · ${library.type == SpokenMediaType.book ? 'Audiobooks' : 'Podcasts'}'),
      if (items.isEmpty)
        Text('No items found in this library.',
            style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor))
      else if (library.type == SpokenMediaType.book)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 118 / 226,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => Entrance(
            delay: Entrance.stagger(i),
            child: _BookCoverTile(item: items[i]),
          ),
        )
      else
        Entrance(
          child: Container(
            decoration: BoxDecoration(
              color: kRaisedColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kHairline),
            ),
            child: Column(
              children: [
                for (final (i, item) in items.indexed) ...[
                  _PodcastShowRow(item: item),
                  if (i < items.length - 1) Container(height: 1, color: kHairline),
                ],
              ],
            ),
          ),
        ),
    ]);
  }
}

class _BookCoverTile extends StatelessWidget {
  const _BookCoverTile({required this.item});

  final SpokenItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _SpokenCover(item: item, icon: Icons.menu_book_rounded, radius: 10, iconSize: 28)),
        const SizedBox(height: 4),
        _CoverProgressLine(progress: item.progress),
        const SizedBox(height: 4),
        Text(item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.getFont(currentFontFamily,
                color: kTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(item.creator,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.getFont(currentFontFamily, color: kStatusText, fontSize: 12)),
      ],
    );
  }
}

class _PodcastShowRow extends StatelessWidget {
  const _PodcastShowRow({required this.item});

  final SpokenItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(width: 40, height: 40, child: _SpokenCover(item: item, icon: Icons.podcasts_rounded, radius: 8, iconSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                    '${item.creator} · ${item.episodes.length} ${item.episodes.length == 1 ? 'episode' : 'episodes'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: kMuted2, size: 20),
        ],
      ),
    );
  }
}

/// Latest episodes across shows: NEW badge from the publish date, relative
/// date and real duration. Rows stay informational — spoken playback keeps
/// its whole-book/whole-episode model rather than a pretend play button.
class _EpisodesCard extends StatelessWidget {
  const _EpisodesCard({required this.episodes});

  final List<({SpokenItem show, SpokenEpisode episode})> episodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        children: [
          for (final (i, row) in episodes.indexed) ...[
            _EpisodeRow(show: row.show, episode: row.episode),
            if (i < episodes.length - 1) Container(height: 1, color: kHairline),
          ],
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.show, required this.episode});

  final SpokenItem show;
  final SpokenEpisode episode;

  bool get _isNew {
    final published = episode.publishedAt;
    if (published == null) return false;
    final age = DateTime.now().difference(published);
    return age.inDays <= 7 && !age.isNegative;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(width: 40, height: 40, child: _SpokenCover(item: show, icon: Icons.podcasts_rounded, radius: 8, iconSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(show.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 12)),
              ],
            ),
          ),
          if (_isNew) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kSecondaryColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('NEW',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kSecondaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 88,
            child: Text(_relativeDate(episode.publishedAt),
                textAlign: TextAlign.right,
                style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(_minutesLabel(episode.duration),
                textAlign: TextAlign.right,
                style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

String _hoursLabel(Duration d) {
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} m';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String _minutesLabel(Duration d) {
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} m';
  return '${d.inMinutes} min';
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

class _ConnectState extends StatelessWidget {
  const _ConnectState({required this.onConnect});
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.menu_book_rounded, size: 52, color: kBrandColor),
            const SizedBox(height: 16),
            Text('Bring your spoken library together',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Connect an Audiobookshelf server for audiobooks and podcasts. Music stays in its own Navidrome workspace.',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, height: 1.45)),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect Audiobookshelf'))
          ])));
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
          color: Colors.red.withValues(alpha: .16),
          child: ListTile(
              leading: const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent),
              title: Text(message))));
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/click_region.dart';
import '../../widgets/loading_skeletons.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import 'library_controls.dart';

enum _GenreSort { az, mostPlayed, songCount }

const _genreSortLabels = <_GenreSort, String>{
  _GenreSort.az: 'A to Z',
  _GenreSort.mostPlayed: 'Most played',
  _GenreSort.songCount: 'Song count',
};

const _genreGradients = [
  kBrandGradient,
  [Color(0xFFFF32C7), Color(0xFF5642DD)],
  [Color(0xFFFEB722), Color(0xFFFF7A00)],
  [Color(0xFF00C9A7), Color(0xFF0575E6)],
  [Color(0xFF34D399), Color(0xFF065F46)],
  [Color(0xFFF472B6), Color(0xFF7C3AED)],
];

class _GenreInfo {
  final String name;
  final List<String> songIds;
  final int plays;
  final int colorIndex;
  const _GenreInfo(this.name, this.songIds, this.plays, this.colorIndex);
  int get count => songIds.length;
}

/// Library > Genres (board "Library - Genres"): toolbar, a "Most played"
/// row of three large gradient cards and an "All genres" grid. Tapping a
/// card opens the genre's song list; the hover play button plays it.
class GenresTab extends StatefulWidget {
  const GenresTab({super.key});

  @override
  State<GenresTab> createState() => _GenresTabState();
}

class _GenresTabState extends State<GenresTab> {
  final TextEditingController _filter = TextEditingController();
  _GenreSort _sort = _GenreSort.az;
  LibraryView _view = LibraryView.grid;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<_GenreInfo> _build(AppState appState) {
    final plays = <String, int>{
      for (final s in appState.catalogSongs) s.id: s.playCount
    };
    final out = <_GenreInfo>[];
    var i = 0;
    // Colours follow the alphabetical order so a genre keeps its colour
    // whatever the sort or filter.
    final names = appState.catalogGenres.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      final ids = appState.catalogGenres[name] ?? const <String>[];
      var total = 0;
      for (final id in ids) {
        total += plays[id] ?? 0;
      }
      out.add(_GenreInfo(name, ids, total, i % _genreGradients.length));
      i++;
    }
    return out;
  }

  int _byMostPlayed(_GenreInfo a, _GenreInfo b) {
    final c = b.plays.compareTo(a.plays);
    return c != 0 ? c : b.count.compareTo(a.count);
  }

  List<_GenreInfo> _sorted(List<_GenreInfo> genres) {
    final list = List<_GenreInfo>.of(genres);
    switch (_sort) {
      case _GenreSort.az:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _GenreSort.mostPlayed:
        list.sort(_byMostPlayed);
      case _GenreSort.songCount:
        list.sort((a, b) => b.count.compareTo(a.count));
    }
    return list;
  }

  void _open(_GenreInfo g) => Navigator.of(context)
      .push(drillDownRoute(GenreSongsScreen(genre: g.name)));

  void _play(_GenreInfo g) {
    final songs = context.read<AppState>().songsByIds(g.songIds);
    if (songs.isEmpty) return;
    context.read<PlayerController>().playSong(songs.first, queue: songs);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final all = _build(appState);
    if (all.isEmpty) {
      if (appState.connectionStatus == ConnectionStatus.connecting) {
        return const GenreGridSkeleton();
      }
      return const EmptyStateView(
        icon: Icons.category_rounded,
        title: 'No genres yet',
        subtitle: 'Connect a Navidrome server to browse by genre here.',
      );
    }
    final query = _filter.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all.where((g) => g.name.toLowerCase().contains(query)).toList();
    final sorted = _sorted(filtered);
    // "Most played" row: the three top genres by plays (then song count),
    // only when browsing the unfiltered grid and there is more to show.
    final showMostPlayed =
        _view == LibraryView.grid && query.isEmpty && all.length > 3;
    final top = showMostPlayed
        ? (List<_GenreInfo>.of(all)..sort(_byMostPlayed)).take(3).toList()
        : const <_GenreInfo>[];
    final topNames = {for (final g in top) g.name};
    final rest = showMostPlayed
        ? sorted.where((g) => !topNames.contains(g.name)).toList()
        : sorted;

    final allSongs = <Song>[];
    void playAll() {
      final seen = <String>{};
      for (final g in sorted) {
        for (final s in appState.songsByIds(g.songIds)) {
          if (seen.add(s.id)) allSongs.add(s);
        }
      }
      if (allSongs.isEmpty) return;
      context.read<PlayerController>().playSong(allSongs.first, queue: allSongs);
    }

    return DesktopContentFrame(
      maxWidth: DesktopTokens.contentTable,
      child: Column(
        children: [
          LibraryToolbar(
            countLabel: query.isEmpty
                ? '${all.length} genres'
                : '${filtered.length} of ${all.length} genres',
            filterController: _filter,
            filterHint: 'Filter genres',
            onFilterChanged: () => setState(() {}),
            trailing: [
              LibrarySortMenu<_GenreSort>(
                  value: _sort,
                  options: _genreSortLabels,
                  onSelected: (s) => setState(() => _sort = s)),
              LibraryViewToggle(
                  value: _view, onChanged: (v) => setState(() => _view = v)),
              LibraryPill(
                  label: 'Play all',
                  icon: Icons.play_arrow_rounded,
                  onTap: filtered.isEmpty ? null : playAll),
            ],
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No genres match',
                    subtitle:
                        'Nothing matches "${_filter.text.trim()}" · clear the filter to see all ${all.length} genres.')
                : _view == LibraryView.list
                    ? _list(sorted)
                    : _grid(top, rest),
          ),
        ],
      ),
    );
  }

  Widget _list(List<_GenreInfo> genres) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: genres.length,
      itemBuilder: (context, i) {
        final g = genres[i];
        return Entrance(
          key: ValueKey('genre-row-${g.name}'),
          delay: Entrance.stagger(i),
          child: _GenreRow(
              info: g, onTap: () => _open(g), onPlay: () => _play(g)),
        );
      },
    );
  }

  Widget _grid(List<_GenreInfo> top, List<_GenreInfo> rest) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth - 40;
      final wide = width >= 700;
      final columns = width >= 1000 ? 5 : (width >= 700 ? 4 : (width >= 420 ? 3 : 2));
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (top.isNotEmpty) ...[
            const LibrarySectionLabel('MOST PLAYED'),
            if (wide)
              Row(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(
                      child: Entrance(
                        key: ValueKey('genre-top-${top[i].name}'),
                        delay: Entrance.stagger(i),
                        child: SizedBox(
                          height: 168,
                          child: _GenreCard(
                              info: top[i],
                              large: true,
                              onTap: () => _open(top[i]),
                              onPlay: () => _play(top[i])),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 130,
                    child: _GenreCard(
                        info: top[i],
                        large: true,
                        onTap: () => _open(top[i]),
                        onPlay: () => _play(top[i])),
                  ),
                ),
            const SizedBox(height: 20),
          ],
          if (rest.isNotEmpty) ...[
            LibrarySectionLabel(top.isEmpty ? 'GENRES' : 'ALL GENRES'),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.6,
              ),
              itemCount: rest.length,
              itemBuilder: (context, i) {
                final g = rest[i];
                return Entrance(
                  key: ValueKey('genre-${g.name}'),
                  delay: Entrance.stagger(i),
                  child: _GenreCard(
                      info: g,
                      large: false,
                      onTap: () => _open(g),
                      onPlay: () => _play(g)),
                );
              },
            ),
          ],
        ],
      );
    });
  }
}

/// Gradient genre card: name + song count bottom-left, two tilted artwork
/// tiles top-right, round white play button on hover.
class _GenreCard extends StatefulWidget {
  final _GenreInfo info;
  final bool large;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _GenreCard({
    required this.info,
    required this.large,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_GenreCard> createState() => _GenreCardState();
}

class _GenreCardState extends State<_GenreCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final large = widget.large;
    final gradient = _genreGradients[info.colorIndex];
    final appState = context.read<AppState>();
    // Up to two songs supply the tilted artwork tiles.
    final sample = <Song>[];
    for (final id in info.songIds) {
      final s = appState.songById(id);
      if (s != null) sample.add(s);
      if (sample.length == 2) break;
    }
    final tile = large ? 64.0 : 40.0;
    final pad = large ? 20.0 : 14.0;

    Widget art(int i) {
      final s = i < sample.length ? sample[i] : null;
      return Container(
        width: tile,
        height: tile,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(large ? 12 : 8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: s != null
            ? ArtworkThumb(
                gradientColors: s.gradientColors,
                artwork: s.artwork,
                size: tile - 2,
                radius: large ? 11 : 7,
                iconSize: large ? 20 : 14)
            : ClipRRect(
                borderRadius: BorderRadius.circular(large ? 11 : 7),
                child: ShuroIcon(glyphForGenre(info.name),
                    size: tile * 0.6, color: Colors.white.withValues(alpha: 0.7))),
      );
    }

    return HoverLift(
      radius: BorderRadius.circular(large ? 18 : 14),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: ClickRegion(
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(large ? 18 : 14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  right: pad,
                  top: pad,
                  child: SizedBox(
                    width: tile * 1.7,
                    height: tile * 1.5,
                    child: Stack(
                      children: [
                        Positioned(
                            left: 0,
                            top: tile * 0.25,
                            child: Transform.rotate(angle: -0.17, child: art(0))),
                        Positioned(
                            right: 0,
                            top: 0,
                            child: Transform.rotate(angle: 0.2, child: art(1))),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: pad,
                  right: pad + (large ? 56 : 40),
                  bottom: pad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white,
                              fontSize: large ? 28 : 18,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${info.count} songs',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: large ? 14 : 12)),
                    ],
                  ),
                ),
                Positioned(
                  right: pad,
                  bottom: pad,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: ShuroMotion.std,
                    opacity: _hover ? 1 : 0,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      curve: ShuroMotion.std,
                      scale: _hover ? 1 : 0.85,
                      child: ClickRegion(
                        onTap: widget.onPlay,
                        child: Container(
                          width: large ? 44 : 32,
                          height: large ? 44 : 32,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: Icon(Icons.play_arrow_rounded,
                              color: kBrandColor, size: large ? 26 : 20),
                        ),
                      ),
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

class _GenreRow extends StatelessWidget {
  final _GenreInfo info;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _GenreRow(
      {required this.info, required this.onTap, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final gradient = _genreGradients[info.colorIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClickRegion(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111723),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                    child: ShuroIcon(glyphForGenre(info.name),
                        size: 20, color: Colors.white.withValues(alpha: 0.9))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Text('${info.count} songs',
                  style: libraryCellStyle(color: kStatusText, size: 12)),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Play ${info.name}',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.play_circle_fill_rounded,
                    color: kVioletLight),
                onPressed: onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Songs of one genre (opened from a genre card).
class GenreSongsScreen extends StatelessWidget {
  final String genre;
  const GenreSongsScreen({super.key, required this.genre});

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<AppState>().songsForGenre(genre);
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
          backgroundColor: kSurfaceColor,
          elevation: 0,
          title: Text(genre,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 16))),
      body: songs.isEmpty
          ? const EmptyStateView(
              icon: Icons.category_rounded, title: 'No songs in this genre yet')
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                  song: songs[i],
                  onTap: () => player.playSong(songs[i], queue: songs)),
            ),
    );
  }
}

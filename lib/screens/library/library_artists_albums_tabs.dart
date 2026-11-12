import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../services/artist_artwork_service.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/click_region.dart';
import '../../widgets/loading_skeletons.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import 'library_controls.dart';

const int _pageSize = 24;

Future<void> _refresh(BuildContext context) async {
  HapticFeedback.mediumImpact();
  await context.read<AppState>().refreshLibrary();
}

String _initials(String name) {
  final words =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words.first.substring(0, 1) + words[1].substring(0, 1))
      .toUpperCase();
}

String _letterOf(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  final c = t.substring(0, 1).toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
}

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

// ---------------------------------------------------------------------------
// Artists
// ---------------------------------------------------------------------------

enum _ArtistSort { name, albums, songs }

const _artistSortLabels = <_ArtistSort, String>{
  _ArtistSort.name: 'Name',
  _ArtistSort.albums: 'Most albums',
  _ArtistSort.songs: 'Most songs',
};

/// Library > Artists (board "Library - Artists"): count, "Filter artists",
/// "Sort: Name", grid/list toggle, Play all, round artist cards with
/// "4 albums · 42 songs", an A-Z jump rail and a "Showing 12 of 38 artists"
/// footer with load-more.
class ArtistsTab extends StatefulWidget {
  const ArtistsTab({super.key});

  @override
  State<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<ArtistsTab> {
  final TextEditingController _filter = TextEditingController();
  final Map<String, GlobalKey> _letterKeys = {};
  _ArtistSort _sort = _ArtistSort.name;
  LibraryView _view = LibraryView.grid;
  int _shown = _pageSize;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _jumpTo(String letter, List<Artist> sorted) {
    final index = sorted.indexWhere((a) => _letterOf(a.name) == letter);
    if (index < 0) return;
    if (index >= _shown) {
      setState(() => _shown = ((index ~/ _pageSize) + 1) * _pageSize);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _letterKeys[letter]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 280),
          curve: ShuroMotion.std,
          alignment: 0.02);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final artworkService = context.watch<ArtistArtworkService>();
    final artists = appState.catalogArtists;
    if (artists.isEmpty &&
        appState.connectionStatus == ConnectionStatus.connecting) {
      return const ArtistGridSkeleton();
    }
    if (artists.isEmpty) {
      return const EmptyStateView(
        icon: Icons.person_rounded,
        title: 'No artists yet',
        subtitle: 'Connect a Navidrome server to browse its artists here.',
      );
    }
    // Resolve missing pictures in the background (server metadata first,
    // MusicBrainz fallback).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context
          .read<ArtistArtworkService>()
          .warmUp(artists.map((a) => (id: a.id, name: a.name)).toList());
    });

    final songsByArtist = <String, List<Song>>{};
    for (final s in appState.catalogSongs) {
      (songsByArtist[s.artistId] ??= []).add(s);
    }
    int songCount(Artist a) => songsByArtist[a.id]?.length ?? 0;

    final query = _filter.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<Artist>.of(artists)
        : artists.where((a) => a.name.toLowerCase().contains(query)).toList();
    switch (_sort) {
      case _ArtistSort.name:
        filtered.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _ArtistSort.albums:
        filtered.sort((a, b) => b.albumIds.length.compareTo(a.albumIds.length));
      case _ArtistSort.songs:
        filtered.sort((a, b) => songCount(b).compareTo(songCount(a)));
    }
    final shown = filtered.take(_shown).toList();
    final canRail = _sort == _ArtistSort.name && filtered.length > 12;
    final letters = <String>{for (final a in filtered) _letterOf(a.name)}
        .toList()
      ..sort();
    final firstOfLetter = <String, String>{};
    for (final a in shown) {
      firstOfLetter.putIfAbsent(_letterOf(a.name), () => a.id);
    }

    ImageProvider? artworkFor(Artist a) =>
        a.artwork ?? artworkService.forArtist(id: a.id, name: a.name);

    void open(Artist a) => Navigator.of(context)
        .push(drillDownRoute(ArtistDetailScreen(artist: a)));

    void playAll() {
      final queue = <Song>[
        for (final a in filtered) ...?songsByArtist[a.id],
      ];
      if (queue.isEmpty) return;
      context.read<PlayerController>().playSong(queue.first, queue: queue);
    }

    Widget cardFor(Artist a, int i) {
      final key = firstOfLetter[_letterOf(a.name)] == a.id
          ? _letterKeys.putIfAbsent(_letterOf(a.name), () => GlobalKey())
          : null;
      return Entrance(
        key: ValueKey('artist-${a.id}'),
        delay: Entrance.stagger(i),
        child: KeyedSubtree(
          key: key,
          child: _ArtistCard(
            artist: a,
            artwork: artworkFor(a),
            subtitle:
                '${_plural(a.albumIds.length, 'album')} · ${_plural(songCount(a), 'song')}',
            onTap: () => open(a),
          ),
        ),
      );
    }

    final body = _view == LibraryView.grid
        ? GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 24,
              crossAxisSpacing: 16,
              childAspectRatio: 0.86,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) => cardFor(shown[i], i),
          )
        : Column(
            children: [
              for (var i = 0; i < shown.length; i++)
                Entrance(
                  key: ValueKey('artist-row-${shown[i].id}'),
                  delay: Entrance.stagger(i),
                  child: KeyedSubtree(
                    key: firstOfLetter[_letterOf(shown[i].name)] == shown[i].id
                        ? _letterKeys.putIfAbsent(
                            _letterOf(shown[i].name), () => GlobalKey())
                        : null,
                    child: _MediaRow(
                      leading: _ArtistAvatar(
                          artist: shown[i],
                          artwork: artworkFor(shown[i]),
                          size: 40),
                      title: shown[i].name,
                      subtitle:
                          '${_plural(shown[i].albumIds.length, 'album')} · ${_plural(songCount(shown[i]), 'song')}',
                      onTap: () => open(shown[i]),
                    ),
                  ),
                ),
            ],
          );

    return DesktopContentFrame(
      maxWidth: DesktopTokens.contentTable,
      child: Column(
        children: [
          LibraryToolbar(
            countLabel: query.isEmpty
                ? '${artists.length} artists'
                : '${filtered.length} of ${artists.length} artists',
            filterController: _filter,
            filterHint: 'Filter artists',
            onFilterChanged: () => setState(() => _shown = _pageSize),
            trailing: [
              LibrarySortMenu<_ArtistSort>(
                  value: _sort,
                  options: _artistSortLabels,
                  onSelected: (s) => setState(() {
                        _sort = s;
                        _shown = _pageSize;
                      })),
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
                    title: 'No artists match',
                    subtitle:
                        'Nothing matches "${_filter.text.trim()}" · clear the filter to see all ${artists.length} artists.')
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          color: kBrandColor,
                          backgroundColor: kCardColor,
                          onRefresh: () => _refresh(context),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                            children: [
                              body,
                              LibraryFooter(
                                shown: shown.length,
                                total: filtered.length,
                                noun: 'artists',
                                onLoadMore: shown.length < filtered.length
                                    ? () =>
                                        setState(() => _shown += _pageSize)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (canRail)
                        _LetterRail(
                          letters: letters,
                          onTap: (l) => _jumpTo(l, filtered),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LetterRail extends StatelessWidget {
  final List<String> letters;
  final ValueChanged<String> onTap;
  const _LetterRail({required this.letters, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Plenty of letters but a short window: the rail scrolls rather than
      // overflowing.
      return SizedBox(
        width: 24,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              for (final l in letters)
                ClickRegion(
                  onTap: () => onTap(l),
                  child: SizedBox(
                    width: 24,
                    height: 20,
                    child: Center(
                      child: Text(l,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kMuted2,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _ArtistAvatar extends StatelessWidget {
  final Artist artist;
  final ImageProvider? artwork;
  final double? size;
  const _ArtistAvatar({required this.artist, this.artwork, this.size});

  @override
  Widget build(BuildContext context) {
    Widget circle(double s) {
      if (artwork != null) {
        return ArtworkThumb(
            gradientColors: artist.gradientColors,
            artwork: artwork,
            size: s,
            radius: 999,
            icon: Icons.person_rounded);
      }
      return Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: artist.gradientColors.length >= 2
                  ? artist.gradientColors
                  : [kBrandColor, kSecondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        child: Text(_initials(artist.name),
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: s * 0.34,
                fontWeight: FontWeight.w800)),
      );
    }

    if (size != null) return circle(size!);
    return LayoutBuilder(builder: (context, c) => circle(c.biggest.shortestSide));
  }
}

class _ArtistCard extends StatelessWidget {
  final Artist artist;
  final ImageProvider? artwork;
  final String subtitle;
  final VoidCallback onTap;
  const _ArtistCard(
      {required this.artist,
      required this.artwork,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      radius: BorderRadius.circular(16),
      child: ClickRegion(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _ArtistAvatar(artist: artist, artwork: artwork),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Albums
// ---------------------------------------------------------------------------

enum _AlbumSort { recentlyAdded, titleAz, artistAz, newestYear }

const _albumSortLabels = <_AlbumSort, String>{
  _AlbumSort.recentlyAdded: 'Recently added',
  _AlbumSort.titleAz: 'Title A to Z',
  _AlbumSort.artistAz: 'Artist A to Z',
  _AlbumSort.newestYear: 'Newest year',
};

/// Library > Albums (board "Library - Albums"): count, "Filter albums",
/// sort, grid/list toggle, Play all, album tiles with hover play button and
/// a downloaded check, "Showing 18 of 71 albums" footer with load-more.
class AlbumsTab extends StatefulWidget {
  const AlbumsTab({super.key});

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  final TextEditingController _filter = TextEditingController();
  _AlbumSort _sort = _AlbumSort.recentlyAdded;
  LibraryView _view = LibraryView.grid;
  int _shown = _pageSize;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final albums = appState.catalogAlbums;
    if (albums.isEmpty &&
        appState.connectionStatus == ConnectionStatus.connecting) {
      return const AlbumGridSkeleton();
    }
    if (albums.isEmpty) {
      return const EmptyStateView(
        icon: Icons.album_rounded,
        title: 'No albums yet',
        subtitle: 'Connect a Navidrome server to browse its albums here.',
      );
    }
    final query = _filter.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<Album>.of(albums)
        : albums
            .where((a) =>
                a.title.toLowerCase().contains(query) ||
                a.artist.toLowerCase().contains(query))
            .toList();
    switch (_sort) {
      case _AlbumSort.recentlyAdded:
        // The catalog arrives newest-added first; keep its own order.
        break;
      case _AlbumSort.titleAz:
        filtered.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _AlbumSort.artistAz:
        filtered.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case _AlbumSort.newestYear:
        filtered.sort((a, b) => b.year.compareTo(a.year));
    }
    final shown = filtered.take(_shown).toList();
    final downloaded = appState.downloadedSongIds;
    bool offline(Album a) =>
        a.songIds.isNotEmpty && a.songIds.every(downloaded.contains);

    void open(Album a) => Navigator.of(context)
        .push(drillDownRoute(AlbumDetailScreen(album: a)));

    void play(Album a) {
      final songs = appState.songsByIds(a.songIds);
      if (songs.isEmpty) return;
      context.read<PlayerController>().playSong(songs.first, queue: songs);
    }

    void playAll() {
      final queue = <Song>[
        for (final a in filtered) ...appState.songsByIds(a.songIds),
      ];
      if (queue.isEmpty) return;
      context.read<PlayerController>().playSong(queue.first, queue: queue);
    }

    final body = _view == LibraryView.grid
        ? GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              mainAxisSpacing: 18,
              crossAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final a = shown[i];
              return Entrance(
                key: ValueKey('album-${a.id}'),
                delay: Entrance.stagger(i),
                child: _AlbumTile(
                    album: a,
                    offline: offline(a),
                    onTap: () => open(a),
                    onPlay: () => play(a)),
              );
            },
          )
        : Column(
            children: [
              for (var i = 0; i < shown.length; i++)
                Entrance(
                  key: ValueKey('album-row-${shown[i].id}'),
                  delay: Entrance.stagger(i),
                  child: _MediaRow(
                    leading: ArtworkThumb(
                        gradientColors: shown[i].gradientColors,
                        artwork: shown[i].artwork,
                        size: 40,
                        radius: 8),
                    title: shown[i].title,
                    subtitle:
                        '${shown[i].artist} · ${shown[i].year > 0 ? '${shown[i].year} · ' : ''}${_plural(shown[i].songIds.length, 'song')}',
                    onTap: () => open(shown[i]),
                    onPlay: () => play(shown[i]),
                  ),
                ),
            ],
          );

    return DesktopContentFrame(
      maxWidth: DesktopTokens.contentTable,
      child: Column(
        children: [
          LibraryToolbar(
            countLabel: query.isEmpty
                ? '${albums.length} albums'
                : '${filtered.length} of ${albums.length} albums',
            filterController: _filter,
            filterHint: 'Filter albums',
            onFilterChanged: () => setState(() => _shown = _pageSize),
            trailing: [
              LibrarySortMenu<_AlbumSort>(
                  value: _sort,
                  options: _albumSortLabels,
                  onSelected: (s) => setState(() {
                        _sort = s;
                        _shown = _pageSize;
                      })),
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
                    title: 'No albums match',
                    subtitle:
                        'Nothing matches "${_filter.text.trim()}" · clear the filter to see all ${albums.length} albums.')
                : RefreshIndicator(
                    color: kBrandColor,
                    backgroundColor: kCardColor,
                    onRefresh: () => _refresh(context),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      children: [
                        body,
                        LibraryFooter(
                          shown: shown.length,
                          total: filtered.length,
                          noun: 'albums',
                          onLoadMore: shown.length < filtered.length
                              ? () => setState(() => _shown += _pageSize)
                              : null,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final Album album;
  final bool offline;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  const _AlbumTile(
      {required this.album,
      required this.offline,
      required this.onTap,
      required this.onPlay});

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HoverLift(
        radius: BorderRadius.circular(14),
        child: ClickRegion(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ArtworkThumb(
                            gradientColors: a.gradientColors,
                            artwork: a.artwork,
                            radius: 12,
                            icon: Icons.album_rounded,
                            iconSize: 34),
                      ),
                      if (widget.offline)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                size: 14, color: kGreenLight),
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          curve: ShuroMotion.std,
                          opacity: _hover ? 1 : 0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 180),
                            curve: ShuroMotion.std,
                            offset: _hover ? Offset.zero : const Offset(0, 0.25),
                            child: ClickRegion(
                              onTap: widget.onPlay,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                    color: kBrandColor, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(a.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// List-view row shared by the artists and albums tabs.
class _MediaRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  const _MediaRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClickRegion(
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111723),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              SizedBox(width: 40, height: 40, child: leading),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: libraryCellStyle(color: kStatusText, size: 12)),
                  ],
                ),
              ),
              if (onPlay != null)
                IconButton(
                  tooltip: 'Play',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.play_circle_fill_rounded,
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

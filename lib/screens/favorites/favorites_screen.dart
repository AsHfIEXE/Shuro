import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/animated_favorite_icon.dart';
import '../../widgets/cache_helpers.dart';
import '../../widgets/click_region.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/artist_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';

/// "13. Favorites" (search-favorites board) — favorite songs / albums /
/// artists in one tabbed view, headed by a hero that plays or shuffles the
/// favorites queue. Every number in the hero is derived from the real
/// favorites/downloads state.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

enum _FavSort { dateHearted, title, artist, album, duration }

String _sortLabel(_FavSort s) => switch (s) {
      _FavSort.dateHearted => 'Date hearted',
      _FavSort.title => 'Title',
      _FavSort.artist => 'Artist',
      _FavSort.album => 'Album',
      _FavSort.duration => 'Duration',
    };

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  final TextEditingController _filterController = TextEditingController();
  _FavSort _sort = _FavSort.dateHearted;

  @override
  void initState() {
    super.initState();
    // The pill row highlights from the controller's index, so it needs to
    // rebuild while the TabBarView is animating.
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  List<Song> _visibleSongs(AppState appState, List<Song> all) {
    final q = _filterController.text.trim().toLowerCase();
    final list = q.isEmpty
        ? [...all]
        : all.where((s) {
            final album = appState.albumById(s.albumId)?.title ?? '';
            return s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                album.toLowerCase().contains(q);
          }).toList();
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    switch (_sort) {
      case _FavSort.dateHearted:
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        // Newest first; songs with no recorded date keep their stored order
        // after the dated ones (sort is stable via the index tiebreak).
        final index = {for (final (i, s) in list.indexed) s.id: i};
        list.sort((a, b) {
          final da = appState.favoriteSongDates[a.id] ?? epoch;
          final db = appState.favoriteSongDates[b.id] ?? epoch;
          final c = db.compareTo(da);
          return c != 0 ? c : index[b.id]!.compareTo(index[a.id]!);
        });
      case _FavSort.title:
        list.sort((a, b) => byText(a.title, b.title));
      case _FavSort.artist:
        list.sort((a, b) => byText(a.artist, b.artist));
      case _FavSort.album:
        list.sort((a, b) => byText(appState.albumById(a.albumId)?.title ?? '',
            appState.albumById(b.albumId)?.title ?? ''));
      case _FavSort.duration:
        list.sort((a, b) => a.duration.compareTo(b.duration));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final allFavoriteSongs = appState.songsByIds(appState.favoriteSongIds.toList());
    final favoriteSongs = _visibleSongs(appState, allFavoriteSongs);
    final favoriteAlbums = appState.catalogAlbums.where((a) => appState.favoriteAlbumIds.contains(a.id)).toList();
    final favoriteArtists = appState.catalogArtists.where((a) => appState.favoriteArtistIds.contains(a.id)).toList();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: Column(
        children: [
          Entrance(
            child: _FavoritesHero(
              songCount: allFavoriteSongs.length,
              cachedCount: offlineSongIds(appState, allFavoriteSongs).length,
              totalDuration: allFavoriteSongs.fold(
                  Duration.zero, (sum, s) => sum + s.duration),
              hasSongs: allFavoriteSongs.isNotEmpty,
              onPlay: () {
                if (favoriteSongs.isEmpty) return;
                player.playSong(favoriteSongs.first, queue: favoriteSongs);
              },
              onShuffle: () {
                if (favoriteSongs.isEmpty) return;
                final queue = [...favoriteSongs]..shuffle();
                player.playSong(queue.first, queue: queue);
              },
              onCacheAll: () => cacheSongsWithFeedback(
                  context, appState, allFavoriteSongs, 'your favorites'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                for (final (i, label) in const ['Songs', 'Albums', 'Artists'].indexed)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                    child: _TabPill(
                      label: label,
                      active: _tabController.index == i,
                      onTap: () => _tabController.animateTo(i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                allFavoriteSongs.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.favorite_border_rounded, title: 'No favorite songs yet')
                    : Column(
                        children: [
                          _FilterSortRow(
                            controller: _filterController,
                            sort: _sort,
                            onChanged: (_) => setState(() {}),
                            onSort: (v) => setState(() => _sort = v),
                          ),
                          Expanded(
                            child: favoriteSongs.isEmpty
                                ? const EmptyStateView(
                                    icon: Icons.search_off_rounded, title: 'No matching favorites')
                                : wide
                                    ? _FavoritesTable(
                                        songs: favoriteSongs, total: allFavoriteSongs.length)
                                    : ListView.builder(
                                        padding: const EdgeInsets.only(bottom: 24),
                                        itemCount: favoriteSongs.length,
                                        itemBuilder: (context, i) => Entrance(
                                          delay: Entrance.stagger(i),
                                          child: SongTile(
                                            song: favoriteSongs[i],
                                            onTap: () => player.playOrToggle(favoriteSongs[i],
                                                queue: favoriteSongs),
                                          ),
                                        ),
                                      ),
                          ),
                        ],
                      ),
                favoriteAlbums.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.favorite_border_rounded, title: 'No favorite albums yet')
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 210,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: favoriteAlbums.length,
                        itemBuilder: (context, i) {
                          final album = favoriteAlbums[i];
                          return Entrance(
                            delay: Entrance.stagger(i),
                            child: AlbumCard(
                              album: album,
                              onTap: () => Navigator.of(context)
                                  .push(drillDownRoute(AlbumDetailScreen(album: album))),
                            ),
                          );
                        },
                      ),
                favoriteArtists.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.favorite_border_rounded, title: 'No favorite artists yet')
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: favoriteArtists.length,
                        itemBuilder: (context, i) {
                          final artist = favoriteArtists[i];
                          return Entrance(
                            delay: Entrance.stagger(i),
                            child: ArtistCard(
                              artist: artist,
                              onTap: () => Navigator.of(context)
                                  .push(drillDownRoute(ArtistDetailScreen(artist: artist))),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The board's playlist-style hero, restyled for the favorites queue:
/// violet→pink wash, heart mark, real counts, Play + Shuffle.
class _FavoritesHero extends StatelessWidget {
  const _FavoritesHero({
    required this.songCount,
    required this.cachedCount,
    required this.totalDuration,
    required this.hasSongs,
    required this.onPlay,
    required this.onShuffle,
    required this.onCacheAll,
  });

  final VoidCallback onCacheAll;
  final int songCount;
  final int cachedCount;
  final Duration totalDuration;
  final bool hasSongs;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  String get _stats {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    final length = hours > 0 ? '$hours h $minutes m' : '$minutes min';
    final cached = ' · $cachedCount cached for offline';
    return '$songCount ${songCount == 1 ? 'song' : 'songs'} · $length$cached';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kBrandColor.withValues(alpha: 0.35),
                kAccentColor.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(color: kHairline),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: kAccentColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PLAYLIST',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kVioletPale,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text('Favorites',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: headingFont(
                                color: kTextColor,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_stats,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13)),
              if (hasSongs) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroButton(
                        label: 'Play',
                        primary: true,
                        icon: ShuroIcon(ShuroGlyph.play, size: 14),
                        onTap: onPlay),
                    _HeroButton(
                        label: 'Shuffle',
                        primary: false,
                        icon: ShuroIcon(ShuroGlyph.shuffle, size: 14),
                        onTap: onShuffle),
                    _HeroButton(
                        label: 'Cache all',
                        primary: false,
                        icon: const Icon(Icons.download_rounded, size: 16, color: kTextColor),
                        onTap: onCacheAll),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? kBrandColor : kGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary ? BorderSide.none : BorderSide(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: primary ? Colors.white : kTextColor,
                      fontSize: 13,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Board-style pill tab (the search board's chip, as a tab): active violet
/// fill, inactive glass + hairline.
class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.active, required this.onTap});

  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: active ? Colors.white : kNavText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// The board's favorites table for desktop-width windows: #, title (+cached
/// state), artist, album, time, and a heart that unfavorites with the same
/// spring pop used everywhere else. On phones the list stays [SongTile]s.
class _FavoritesTable extends StatelessWidget {
  const _FavoritesTable({required this.songs, required this.total});

  final List<Song> songs;
  final int total;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final offline = offlineSongIds(appState, songs);
    final currentId = player.currentSong?.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: kRaisedColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kHairline),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    const SizedBox(width: 28),
                    const SizedBox(width: 44),
                    const Expanded(child: _HeaderCell('TITLE')),
                    const SizedBox(width: 200, child: _HeaderCell('ARTIST')),
                    const SizedBox(width: 200, child: _HeaderCell('ALBUM')),
                    const SizedBox(width: 130, child: _HeaderCell('DATE HEARTED')),
                    const SizedBox(width: 56, child: _HeaderCell('TIME', right: true)),
                    const SizedBox(width: 76),
                  ],
                ),
              ),
              Container(height: 1, color: kHairline),
              for (final (i, song) in songs.indexed) ...[
                Entrance(
                  delay: Entrance.stagger(i),
                  child: _FavoriteRow(
                    index: i,
                    song: song,
                    playing: song.id == currentId,
                    cached: offline.contains(song.id),
                    hearted: appState.favoriteSongDates[song.id],
                    albumTitle: appState.albumById(song.albumId)?.title,
                    onTap: () => player.playOrToggle(song, queue: songs),
                    onToggleFavorite: () =>
                        context.read<AppState>().toggleFavoriteSong(song.id),
                  ),
                ),
                if (i < songs.length - 1) Container(height: 1, color: kHairline),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Showing ${songs.length} of $total ${total == 1 ? 'song' : 'songs'}',
            style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 12)),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.right = false});

  final String label;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: GoogleFonts.getFont(currentFontFamily,
          color: kMuted2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.index,
    required this.song,
    required this.playing,
    required this.cached,
    required this.albumTitle,
    required this.hearted,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final int index;
  final Song song;
  final bool playing;
  final bool cached;
  final String? albumTitle;
  final DateTime? hearted;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: playing
                  ? const PlayingBars(size: 14)
                  : Text('${index + 1}',
                      style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            ArtworkThumb(
              gradientColors: song.gradientColors,
              artwork: song.artwork,
              size: 36,
              radius: 8,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: playing ? kVioletPale : kTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(cached ? 'Cached' : 'Streaming',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: cached ? kGreenLight : kMuted3, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 200,
              child: Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13)),
            ),
            SizedBox(
              width: 200,
              child: Text(albumTitle ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13)),
            ),
            SizedBox(
              width: 130,
              child: Text(relativeDay(hearted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13)),
            ),
            SizedBox(
              width: 56,
              child: Text(_timeLabel(song.duration),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 13)),
            ),
            AnimatedFavoriteIcon(
              isFavorite: true,
              activeColor: kPinkLight,
              inactiveColor: kNavText,
              size: 20,
              onTap: onToggleFavorite,
            ),
            Builder(
              builder: (ctx) => ClickRegion(
                onTap: () => showSongMenuAtAnchor(ctx, song, ctx),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.more_horiz_rounded, size: 20, color: kNavText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeLabel(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// "Filter favorites" field + "Sort: Date hearted" menu from the board.
class _FilterSortRow extends StatelessWidget {
  const _FilterSortRow({
    required this.controller,
    required this.sort,
    required this.onChanged,
    required this.onSort,
  });

  final TextEditingController controller;
  final _FavSort sort;
  final ValueChanged<String> onChanged;
  final ValueChanged<_FavSort> onSort;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.getFont(currentFontFamily, color: kTextColor, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 292),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: style,
                  cursorColor: kBrandColor,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter favorites',
                    hintStyle: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: kMuted2),
                    filled: true,
                    fillColor: kRaisedColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kHairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBrandColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<_FavSort>(
            tooltip: 'Sort favorites',
            color: kCardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: onSort,
            itemBuilder: (_) => [
              for (final v in _FavSort.values)
                PopupMenuItem<_FavSort>(
                  value: v,
                  child: Text(_sortLabel(v),
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: v == sort ? kVioletPale : kTextColor, fontSize: 13)),
                ),
            ],
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: kRaisedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kHairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sort: ${_sortLabel(sort)}', style: style),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: kNavText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

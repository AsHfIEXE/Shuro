import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/animated_favorite_icon.dart';
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

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final favoriteSongs = appState.songsByIds(appState.favoriteSongIds.toList());
    final favoriteAlbums = appState.catalogAlbums.where((a) => appState.favoriteAlbumIds.contains(a.id)).toList();
    final favoriteArtists = appState.catalogArtists.where((a) => appState.favoriteArtistIds.contains(a.id)).toList();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('Favorites',
            style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Entrance(
            child: _FavoritesHero(
              songCount: favoriteSongs.length,
              cachedCount:
                  favoriteSongs.where((s) => appState.downloadedSongIds.contains(s.id)).length,
                  totalDuration: favoriteSongs.fold(
                      Duration.zero, (sum, s) => sum + s.duration),
              hasSongs: favoriteSongs.isNotEmpty,
              onPlay: () {
                if (favoriteSongs.isEmpty) return;
                player.playSong(favoriteSongs.first, queue: favoriteSongs);
              },
              onShuffle: () {
                if (favoriteSongs.isEmpty) return;
                final queue = [...favoriteSongs]..shuffle();
                player.playSong(queue.first, queue: queue);
              },
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
                favoriteSongs.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.favorite_border_rounded, title: 'No favorite songs yet')
                    : wide
                        ? _FavoritesTable(songs: favoriteSongs)
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
  });

  final int songCount;
  final int cachedCount;
  final Duration totalDuration;
  final bool hasSongs;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  String get _stats {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    final length = hours > 0 ? '$hours h ${minutes} m' : '$minutes min';
    final cached = cachedCount > 0 ? ' · $cachedCount cached for offline' : '';
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
                      gradient: const LinearGradient(colors: [kAccentColor, kBrandColor]),
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
              Row(
                children: [
                  Expanded(
                    child: Text(_stats,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily, color: kNavText, fontSize: 13)),
                  ),
                  if (hasSongs) ...[
                    _HeroButton(
                        label: 'Play',
                        primary: true,
                        icon: ShuroIcon(ShuroGlyph.play, size: 14),
                        onTap: onPlay),
                    const SizedBox(width: 8),
                    _HeroButton(
                        label: 'Shuffle',
                        primary: false,
                        icon: ShuroIcon(ShuroGlyph.shuffle, size: 14),
                        onTap: onShuffle),
                  ],
                ],
              ),
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
  const _FavoritesTable({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.watch<PlayerController>();
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
                    const SizedBox(width: 56, child: _HeaderCell('TIME', right: true)),
                    const SizedBox(width: 48),
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
                    cached: appState.downloadedSongIds.contains(song.id),
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
        Text('Showing ${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
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
    required this.onTap,
    required this.onToggleFavorite,
  });

  final int index;
  final Song song;
  final bool playing;
  final bool cached;
  final String? albumTitle;
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

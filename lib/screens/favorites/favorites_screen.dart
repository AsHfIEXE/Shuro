import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artist_card.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';

import '../../widgets/page_transitions.dart';
/// "13. Favorites" — favorite songs / albums / artists in one tabbed view.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final favoriteSongs = appState.songsByIds(appState.favoriteSongIds.toList());
    final favoriteAlbums = appState.catalogAlbums.where((a) => appState.favoriteAlbumIds.contains(a.id)).toList();
    final favoriteArtists = appState.catalogArtists.where((a) => appState.favoriteArtistIds.contains(a.id)).toList();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(backgroundColor: kSurfaceColor, elevation: 0, title: Text('Favorites', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16))),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: kBrandColor,
            labelColor: Colors.white,
            unselectedLabelColor: kMutedTextColor,
            labelStyle: GoogleFonts.getFont(currentFontFamily, fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [Tab(text: 'Songs'), Tab(text: 'Albums'), Tab(text: 'Artists')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                favoriteSongs.isEmpty
                    ? const EmptyStateView(icon: Icons.favorite_border_rounded, title: 'No favorite songs yet')
                    : ListView.builder(
                        itemCount: favoriteSongs.length,
                        itemBuilder: (context, i) => SongTile(song: favoriteSongs[i], onTap: () => player.playSong(favoriteSongs[i], queue: favoriteSongs)),
                      ),
                favoriteAlbums.isEmpty
                    ? const EmptyStateView(icon: Icons.favorite_border_rounded, title: 'No favorite albums yet')
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 20, crossAxisSpacing: 16, childAspectRatio: 0.72),
                        itemCount: favoriteAlbums.length,
                        itemBuilder: (context, i) {
                          final album = favoriteAlbums[i];
                          return AlbumCard(album: album, onTap: () => Navigator.of(context).push(drillDownRoute(AlbumDetailScreen(album: album))));
                        },
                      ),
                favoriteArtists.isEmpty
                    ? const EmptyStateView(icon: Icons.favorite_border_rounded, title: 'No favorite artists yet')
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 20, crossAxisSpacing: 12, childAspectRatio: 0.8),
                        itemCount: favoriteArtists.length,
                        itemBuilder: (context, i) {
                          final artist = favoriteArtists[i];
                          return ArtistCard(artist: artist, onTap: () => Navigator.of(context).push(drillDownRoute(ArtistDetailScreen(artist: artist))));
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

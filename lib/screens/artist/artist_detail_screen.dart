import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/artist.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/section_header.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';

import '../../widgets/page_transitions.dart';
/// "06. Artists > Artist detail" — artwork, Play/Shuffle, top songs, and
/// the artist's albums.
class ArtistDetailScreen extends StatelessWidget {
  final Artist artist;
  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final appState = context.watch<AppState>();
    final topSongs = appState.songsByIds(artist.topSongIds);
    final albums = appState.albumsForArtist(artist.id);
    final isFav = appState.isFavoriteArtist(artist.id);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: kSurfaceColor,
            pinned: true,
            expandedHeight: 300,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18), onPressed: () => Navigator.of(context).maybePop()),
            actions: [
              IconButton(
                icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFav ? artist.gradientColors.last : Colors.white70),
                onPressed: () => appState.toggleFavoriteArtist(artist.id),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(48, 64, 48, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: ArtworkThumb(gradientColors: artist.gradientColors, artwork: artist.artwork, radius: 999, icon: Icons.person_rounded, iconSize: 52),
                    ),
                    const SizedBox(height: 16),
                    Text(artist.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: topSongs.isEmpty ? null : () => player.playSong(topSongs.first, queue: topSongs),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: artist.gradientColors.last,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text('Play', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: topSongs.isEmpty
                            ? null
                            : () {
                                player.playSong(topSongs.first, queue: topSongs);
                                if (!player.shuffle) player.toggleShuffle();
                              },
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kDividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23))),
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: Text('Shuffle', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (topSongs.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(title: 'Popular', padding: const EdgeInsets.fromLTRB(20, 0, 20, 4))),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(song: topSongs[i], showArtist: false, onTap: () => player.playSong(topSongs[i], queue: topSongs)),
                childCount: topSongs.length,
              ),
            ),
          ],
          SliverToBoxAdapter(child: SectionHeader(title: 'Albums', padding: const EdgeInsets.fromLTRB(20, 16, 20, 4))),
          if (albums.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: EmptyStateView(
                  icon: Icons.album_rounded,
                  title: 'No albums found',
                  subtitle: topSongs.isEmpty
                      ? "There's nothing from this artist in the connected library right now."
                      : "This artist's albums aren't in the connected library yet.",
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, i) {
                    final album = albums[i];
                    return AlbumCard(album: album, onTap: () => Navigator.of(context).push(drillDownRoute(AlbumDetailScreen(album: album))));
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

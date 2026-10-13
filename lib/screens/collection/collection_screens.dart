import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/album.dart';
import '../../models/song.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../now_playing/now_playing_screen.dart';

/// A plain, complete list of songs — the destination behind Home's "See all".
///
/// Home's rails are horizontal strips with no room to say "how much more is
/// there" or to scroll past a handful of cards, and tapping a rail's title did
/// nothing at all. Every rail now has a real destination instead of being a
/// dead end.
class SongListScreen extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final String? subtitle;

  const SongListScreen({super.key, required this.title, required this.songs, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              subtitle ?? '${songs.length} song${songs.length == 1 ? '' : 's'}',
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              tooltip: 'Shuffle play',
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white70),
              onPressed: () async {
                if (!player.shuffle) player.toggleShuffle();
                await player.playSong(songs.first, queue: songs);
              },
            ),
          if (songs.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              onPressed: () => player.playSong(songs.first, queue: songs),
            ),
        ],
      ),
      body: songs.isEmpty
          ? const EmptyStateView(icon: Icons.music_note_rounded, title: 'Nothing here yet')
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return SongTile(
                  song: song,
                  highlighted: player.currentSong?.id == song.id,
                  onTap: () => player.playOrToggle(song, queue: songs),
                );
              },
            ),
    );
  }
}

/// The album-grid counterpart to [SongListScreen] — Home's "See all" for
/// recently played albums.
class AlbumGridScreen extends StatelessWidget {
  final String title;
  final List<Album> albums;

  const AlbumGridScreen({super.key, required this.title, required this.albums});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              '${albums.length} album${albums.length == 1 ? '' : 's'}',
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
      body: albums.isEmpty
          ? const EmptyStateView(icon: Icons.album_rounded, title: 'Nothing here yet')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 18,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final album = albums[i];
                return AlbumCard(
                  album: album,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                );
              },
            ),
    );
  }
}

/// Convenience for opening a song list from a rail, so Home doesn't repeat the
/// route construction at every call site.
void openSongList(BuildContext context, String title, List<Song> songs, {String? subtitle}) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SongListScreen(title: title, songs: songs, subtitle: subtitle)),
  );
}

/// Opens Now Playing for whatever is current — used by rail headers so the
/// "play" affordance is discoverable without hunting for the mini player.
void openNowPlaying(BuildContext context, Song? song) {
  if (song == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingScreen(initialSong: song)));
}

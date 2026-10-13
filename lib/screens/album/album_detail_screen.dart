import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/album.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_actions_sheet.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';

/// "05. Albums > Album detail" — artwork, metadata, Play/Shuffle, and the
/// numbered track list. Technical format info sits in a small subtitle
/// rather than dominating the header, per the request not to make it too
/// prominent.
class AlbumDetailScreen extends StatelessWidget {
  final Album album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<AppState>().songsForAlbum(album.id);
    final player = context.read<PlayerController>();
    final totalSeconds = songs.fold<int>(0, (sum, s) => sum + s.duration.inSeconds);
    final totalMinutes = (totalSeconds / 60).round();
    final format = songs.isNotEmpty ? songs.first.audioInfo : null;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: kSurfaceColor,
            pinned: true,
            expandedHeight: 340,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18), onPressed: () => Navigator.of(context).maybePop()),
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(32, 64, 32, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: ArtworkThumb(
                        gradientColors: album.gradientColors,
                        artwork: album.artwork,
                        radius: 16,
                        icon: Icons.album_rounded,
                        iconSize: 48,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(album.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(album.artist, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('${album.year} • ${songs.length} tracks • $totalMinutes min',
                        style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11)),
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
                        onPressed: songs.isEmpty ? null : () => player.playSong(songs.first, queue: songs),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: album.gradientColors.last,
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
                        onPressed: songs.isEmpty
                            ? null
                            : () {
                                player.playSong(songs.first, queue: songs);
                                if (!player.shuffle) player.toggleShuffle();
                              },
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kDividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23))),
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: Text('Shuffle', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                    onPressed: () => showAlbumActionsSheet(context, album),
                  ),
                ],
              ),
            ),
          ),
          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: EmptyStateView(
                  icon: Icons.music_off_rounded,
                  title: 'No tracks found',
                  subtitle: "This album has no songs on the connected server right now.",
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: songs[i],
                  index: i + 1,
                  showArtist: false,
                  onTap: () => player.playSong(songs[i], queue: songs),
                ),
                childCount: songs.length,
              ),
            ),
          if (format != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Text('${format.formatLabel} · ${format.bitDepthLabel} · ${format.sampleRateLabel}',
                    style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}

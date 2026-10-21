import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/download_service.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';


/// "12. Downloads / Offline" — downloaded songs & albums, active download
/// progress (shown inline on each SongTile), and storage usage.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    // Real downloads: songs that are files on disk, managed by the service.
    final downloads = context.watch<DownloadService>();
    final downloadedSongs = downloads.songs;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
          backgroundColor: kSurfaceColor,
          elevation: 0,
          title: Text('Downloads',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 16))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: kCardColor, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Stat(label: 'Songs', value: '${downloadedSongs.length}'),
                      _Stat(
                          label: 'Location',
                          value: downloads.customLocation == null
                              ? 'App storage'
                              : 'Custom folder'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Downloads are saved at original quality (format=raw) and survive app updates.',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  // Wrap, not Row: two outlined buttons are ~300 dp wide and
                  // overflowed on narrow windows (landscape phone with the
                  // rail, split-screen, large font).
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final path = await downloads.pickLocation();
                          if (path != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Downloads will be saved to: $path')));
                          }
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('Change location'),
                      ),
                      if (downloadedSongs.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () {
                            for (final song in downloadedSongs) {
                              downloads.remove(song.id);
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('Remove all'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SectionHeader(title: 'Downloaded Songs'),
          if (downloadedSongs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 24),
              child: EmptyStateView(
                  icon: Icons.download_rounded,
                  title: 'Nothing downloaded yet',
                  subtitle:
                      'Download songs or albums from their "⋮" menu to listen offline.'),
            )
          else
            for (final song in downloadedSongs)
              SongTile(
                  song: song,
                  onTap: () => player.playSong(song, queue: downloadedSongs)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 11)),
      ],
    );
  }
}

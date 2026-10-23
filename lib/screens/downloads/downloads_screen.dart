import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/offline_plan.dart';
import '../../services/download_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';
import '../../widgets/download_cards.dart';

/// "12. Downloads / Offline" — downloaded songs & albums, active download
/// progress (shown inline on each SongTile), and storage usage.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Real downloads: songs that are files on disk, managed by the service.
    final downloads = context.watch<DownloadService>();
    final appState = context.watch<AppState>();
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
                      _Stat(
                          label: 'Capacity',
                          value:
                              '${downloads.managedDownloadCount}/${DownloadService.maxManagedDownloads}'),
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
          _OfflinePlansSection(
              plans: appState.offlinePlans,
              appState: appState,
              downloads: downloads),
          SectionHeader(title: 'Downloaded Songs'),
          // Cards with metadata + a real selection mode (long-press a card,
          // then remove just the chosen ones or everything at once).
          const DownloadCardsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OfflinePlansSection extends StatelessWidget {
  const _OfflinePlansSection({
    required this.plans,
    required this.appState,
    required this.downloads,
  });

  final List<OfflinePlan> plans;
  final AppState appState;
  final DownloadService downloads;

  Future<void> _downloadPlan(BuildContext context, OfflinePlan plan) async {
    final songs = appState.songsForOfflinePlan(plan);
    var localOnly = 0;
    var unavailable = 0;
    final requests = <DownloadRequest>[];
    for (final song in songs) {
      if (song.isLocal) {
        localOnly++;
        continue;
      }
      final source = appState.downloadSourceFor(song);
      if (source == null) {
        unavailable++;
      } else {
        requests.add(DownloadRequest(song: song, streamUrl: source));
      }
    }
    if (requests.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'There are no server tracks ready to download in this plan.')));
      }
      return;
    }
    final result = await downloads.enqueueAll(requests);
    if (!context.mounted) return;
    final notes = <String>[
      '${result.queued} queued',
      if (localOnly > 0)
        '$localOnly local file${localOnly == 1 ? '' : 's'} left in place',
      if (unavailable > 0) '$unavailable unavailable',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notes.join(' · '))));
  }

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      SectionHeader(title: 'Offline Plans'),
      for (final plan in plans)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            color: kCardColor,
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const CircleAvatar(
                  backgroundColor: kBrandColor,
                  child: Icon(Icons.download_for_offline_rounded,
                      color: Colors.white)),
              title:
                  Text(plan.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${appState.songsForOfflinePlan(plan).length} currently playable · Original size not reported',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12),
              ),
              trailing: Wrap(spacing: 2, children: [
                IconButton(
                  tooltip: 'Download plan',
                  onPressed: downloads.availableDownloadSlots == 0
                      ? null
                      : () => _downloadPlan(context, plan),
                  icon: const Icon(Icons.download_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Plan options',
                  onSelected: (value) {
                    if (value == 'delete') appState.deleteOfflinePlan(plan.id);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete plan')),
                  ],
                ),
              ]),
            ),
          ),
        ),
    ]);
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

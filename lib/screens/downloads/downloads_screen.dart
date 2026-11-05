import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/download_state.dart';
import '../../models/offline_plan.dart';
import '../../models/song.dart';
import '../../services/download_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/download_cards.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

/// Raised card surface from the redesign boards (#111723) — storage, active
/// downloads and the completed grid all sit on it.
const Color _cardSurface = Color(0xFF111723);

/// "12. Downloads / Offline" — device storage, in-flight transfers, offline
/// plans and the downloaded library (cards with a real selection mode).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Real downloads: songs that are files on disk, managed by the service.
    final downloads = context.watch<DownloadService>();
    final appState = context.watch<AppState>();
    final downloadedSongs = downloads.songs;

    // In-flight and failed transfers, kept in the service's own queue order.
    final active = <MapEntry<String, DownloadStatus>>[
      for (final entry in downloads.status.entries)
        if (entry.value.stage == DownloadStage.downloading ||
            entry.value.stage == DownloadStage.queued ||
            entry.value.stage == DownloadStage.failed)
          entry,
    ];
    final inFlightCount =
        active.where((e) => e.value.stage != DownloadStage.failed).length;
    final failedCount =
        active.where((e) => e.value.stage == DownloadStage.failed).length;

    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatusChip(
            label: 'Downloading',
            count: inFlightCount,
            foreground: kVioletPale,
            background: kBrandColor.withValues(alpha: 0.14),
          ),
          _StatusChip(
            label: 'Completed',
            count: downloadedSongs.length,
            foreground: kGreenLight,
            background: kGreen.withValues(alpha: 0.14),
          ),
          _StatusChip(
            label: 'Failed',
            count: failedCount,
            foreground: Colors.redAccent,
            background: Colors.redAccent.withValues(alpha: 0.14),
          ),
        ],
      ),
    );

    final activeCard = active.isEmpty
        ? const SizedBox.shrink()
        : _ActiveDownloadsCard(entries: active);
    final plans = _OfflinePlansSection(
        plans: appState.offlinePlans, appState: appState, downloads: downloads);
    // Cards with metadata + a real selection mode (long-press a card, then
    // remove just the chosen ones or everything at once).
    final completed = Column(children: const [
      SectionHeader(title: 'Downloaded Songs'),
      DownloadCardsSection(),
      SizedBox(height: 24),
    ]);
    final storage = const _StorageCard();

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
          backgroundColor: kSurfaceColor,
          elevation: 0,
          title: Text('Downloads',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 16))),
      // Wide windows get the board layout: transfers and the completed list
      // scroll in a left column while the storage card sits in a 352 px
      // right column. Narrow windows stack the same sections.
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        if (!wide) {
          return ListView(
            children: [chips, activeCard, storage, plans, completed],
          );
        }
        return DesktopContentFrame(
          maxWidth: DesktopTokens.contentTable,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [chips, activeCard, plans, completed],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 352,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Lines the storage card up with the active-downloads
                    // card: the chips row above is 12 + 32 + 16 high.
                    const SizedBox(height: 60),
                    storage,
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Rounded count chip from the Downloads board: tinted background, label and
/// a live count — one per download state.
class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color foreground;
  final Color background;

  const _StatusChip({
    required this.label,
    required this.count,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('$count',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The in-flight list: live transfers first, then the queue, then failures.
/// Progress comes from the service's per-song status map; there is no pause
/// API, so rows only offer Cancel (the service implements remove() as
/// cancel-and-remove) — no dead Pause button is invented.
class _ActiveDownloadsCard extends StatelessWidget {
  final List<MapEntry<String, DownloadStatus>> entries;

  const _ActiveDownloadsCard({required this.entries});

  // Same path the offline plans and the song sheet use: the Wi-Fi gate,
  // then the service's own start() with an original-quality source.
  Future<void> _retry(BuildContext context, Song song) async {
    final appState = context.read<AppState>();
    final downloads = context.read<DownloadService>();
    if (!appState.canDownloadNow) {
      showErrorSnackBar(
          context,
          "You're on mobile data and the Downloads Wi-Fi-only setting "
          'is on.');
      return;
    }
    final source = appState.downloadSourceFor(song);
    if (source == null) {
      showErrorSnackBar(
          context, 'Connect to a server to retry this download.');
      return;
    }
    await downloads.start(song, source);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final downloads = context.read<DownloadService>();
    final downloading = entries
        .where((e) => e.value.stage == DownloadStage.downloading)
        .toList();
    final queued =
        entries.where((e) => e.value.stage == DownloadStage.queued).toList();
    final failed =
        entries.where((e) => e.value.stage == DownloadStage.failed).toList();
    final ordered = [...downloading, ...queued, ...failed];

    Widget row(MapEntry<String, DownloadStatus> entry) {
      final song = appState.songById(entry.key);
      if (song == null) {
        // Status without a resolvable song (e.g. a stale id after switching
        // servers) — still cancellable so it can be cleared away.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'This song is no longer in your library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMuted2, fontSize: 12),
                ),
              ),
              _CancelIconButton(
                  onTap: () => downloads.remove(entry.key),
                  tooltip: 'Clear this entry'),
            ],
          ),
        );
      }
      return _ActiveDownloadRow(
        song: song,
        albumTitle: appState.albumById(song.albumId)?.title,
        status: entry.value,
        onCancel: () => downloads.remove(song.id),
        onRetry: () => _retry(context, song),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text('ACTIVE DOWNLOADS',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1)),
              ),
              for (var i = 0; i < ordered.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                row(ordered[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One 76 px transfer row (boards): 52 px artwork, title, artist · album, a
/// 4 px progress track, the big percent (or Queued/Failed) on the right, and
/// Cancel — plus Retry for failures.
class _ActiveDownloadRow extends StatelessWidget {
  final Song song;
  final String? albumTitle;
  final DownloadStatus status;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _ActiveDownloadRow({
    required this.song,
    required this.albumTitle,
    required this.status,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final failed = status.stage == DownloadStage.failed;
    final queued = status.stage == DownloadStage.queued;
    final fraction = status.progress.clamp(0.0, 1.0);
    final percent = (fraction * 100).round();

    final rightLabel = failed ? 'Failed' : queued ? 'Queued' : '$percent%';
    final rightColor =
        failed ? Colors.redAccent : queued ? kMuted2 : kVioletPale;
    // The service reports progress only as a fraction — no byte totals or
    // transfer rate — so the sub-line shows the percent, never invented
    // "MB of MB · MB/s" numbers.
    final statusLine = failed
        ? 'Download failed'
        : queued
            ? 'Waiting for a free slot'
            : 'Downloading · $percent%';

    return SizedBox(
      height: 76,
      child: Row(
        children: [
          ArtworkThumb(
              gradientColors: song.gradientColors,
              artwork: song.artwork,
              size: 52,
              radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  albumTitle == null || albumTitle!.isEmpty
                      ? song.artist
                      : '${song.artist} · $albumTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: queued || failed ? 0 : fraction,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(
                        failed ? Colors.redAccent : kVioletLight),
                  ),
                ),
                const SizedBox(height: 4),
                Text(statusLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(rightLabel,
                textAlign: TextAlign.right,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: rightColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          if (failed) ...[
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(72, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: Colors.redAccent,
                side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Retry',
                  style: GoogleFonts.getFont(currentFontFamily,
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
          ],
          _CancelIconButton(
              onTap: onCancel,
              tooltip: failed ? 'Dismiss' : 'Cancel download'),
        ],
      ),
    );
  }
}

/// 32 px round icon button on glass — Cancel for in-flight rows, Dismiss for
/// failed ones (the service's remove() clears both).
class _CancelIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const _CancelIconButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: kGlass, borderRadius: BorderRadius.circular(16)),
          child:
              const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
        ),
      ),
    );
  }
}

/// Device storage card (boards): headline numbers, a segmented usage bar and
/// the Manage storage actions. Nothing in the app defines a byte quota — the
/// download manager caps by count — so the headline is the managed/max pair
/// the old stat card showed, and the sub-line adds the real bytes on disk.
class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  int _bytes = -1; // -1 = not measured yet.
  int _measuredCount = -1;

  static String _formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  Future<void> _changeLocation() async {
    final downloads = context.read<DownloadService>();
    final path = await downloads.pickLocation();
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloads will be saved to: $path')));
    }
  }

  Future<void> _removeAll() async {
    final downloads = context.read<DownloadService>();
    final songs = downloads.songs;
    if (songs.isEmpty) return;
    final confirmed = await confirmAction(
      context,
      title: 'Remove all ${songs.length} downloads?',
      message:
          'The files are deleted from this device. Nothing on your server is affected.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true) return;
    for (final song in songs) {
      await downloads.remove(song.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final count = downloads.managedDownloadCount;
    final limit = DownloadService.maxManagedDownloads;
    // Stat the real files only when the registry changes — progress ticks
    // rebuild this card constantly during a transfer.
    if (count != _measuredCount) {
      _measuredCount = count;
      var total = 0;
      for (final song in downloads.songs) {
        final path = song.localFilePath;
        if (path == null) continue;
        try {
          final file = File(path);
          if (file.existsSync()) total += file.lengthSync();
        } catch (_) {
          // File vanished mid-sum — count what is still there.
        }
      }
      _bytes = total;
    }
    final offline = downloads.songs.length;
    // No pin/priority tier exists in the data model, so the pinned part of
    // the board's sub-line (and its cyan segment) is omitted, not faked.
    final subLine = _bytes > 0
        ? '$offline song${offline == 1 ? '' : 's'} offline '
            '· ${_formatBytes(_bytes)} on disk'
        : '$offline song${offline == 1 ? '' : 's'} offline';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEVICE STORAGE',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMuted2,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$count',
                      style: headingFont(
                          color: kTextColor,
                          fontSize: 32,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('of $limit downloads',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 16),
              // Violet segment = managed downloads vs the manager's cap.
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: limit == 0 ? 0 : (count / limit).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation(kBrandColor),
                ),
              ),
              const SizedBox(height: 8),
              Text(subLine,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PopupMenuButton<String>(
                  color: kCardColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  position: PopupMenuPosition.under,
                  onSelected: (value) {
                    if (value == 'change') {
                      _changeLocation();
                    } else if (value == 'remove_all') {
                      _removeAll();
                    }
                  },
                  // The same two actions the old stat card exposed.
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'change', child: Text('Change location')),
                    if (downloads.songs.isNotEmpty)
                      const PopupMenuItem(
                          value: 'remove_all',
                          child: Text('Remove all downloads')),
                  ],
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Center(
                      child: Text('Manage storage',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Downloads are saved at original quality (format=raw) and '
                'survive app updates.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMuted2, fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
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

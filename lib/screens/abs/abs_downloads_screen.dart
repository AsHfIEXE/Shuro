import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/spoken_media.dart';
import '../../services/abs_download_service.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';
import 'abs_widgets.dart';

/// Settings -> Downloads (Audiobookshelf): every downloaded book and
/// podcast episode on this device, with its size, per-target progress
/// ring while a download runs, and delete. "Auto-remove finished" is the
/// only toggle — when on, marking a title played deletes its files.
class AbsDownloadsScreen extends StatelessWidget {
  const AbsDownloadsScreen({super.key});

  String _size(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<AbsDownloadService>();
    final spoken = context.watch<SpokenLibraryState>();
    final handles = dl.handles
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Downloads', style: absHeading(18)),
        actions: [
          if (dl.totalSizeBytes > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(_size(dl.totalSizeBytes),
                    style: absText(13, color: kMuted2, tabular: true)),
              ),
            ),
        ],
      ),
      body: dl.error != null
          ? _ErrorCard(message: dl.error!, onRetry: () => dl.restore())
          : handles.isEmpty
              ? const _EmptyState()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  // Active downloads first, ring + fraction.
                  for (final handle in handles) ...[
                    _DownloadRow(
                      handle: handle,
                      progress: dl.progressOf(handle.key),
                      item: _itemFor(spoken, handle.itemId),
                      coverUrl: _coverFor(spoken, handle.itemId),
                      onDelete: () async {
                        await dl.remove(handle.itemId,
                            episodeId: handle.episodeId);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                              content: Text(
                                  'Removed ${handle.title}',
                                  style: absText(13)),
                              backgroundColor: kRaisedColor,
                              behavior: SnackBarBehavior.floating));
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: dl.autoRemoveFinished,
                    onChanged: (v) => dl.setAutoRemoveFinished(v),
                    activeThumbColor: kBrandColor,
                    title: Text('Auto-remove finished',
                        style: absText(14, w: FontWeight.w600)),
                    subtitle: Text(
                        'Delete the files when a title is marked as played.',
                        style: absText(12, color: kMuted2)),
                  ),
                ]),
    );
  }

  SpokenItem? _itemFor(SpokenLibraryState spoken, String itemId) {
    for (final item in spoken.allItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  String? _coverFor(SpokenLibraryState spoken, String itemId) {
    final item = _itemFor(spoken, itemId);
    return item == null ? null : spoken.coverUrlFor(item);
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.handle,
    required this.progress,
    required this.item,
    required this.coverUrl,
    required this.onDelete,
  });

  final AbsDownloadHandle handle;
  final double? progress;
  final SpokenItem? item;
  final String? coverUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final downloading = progress != null;
    final it = item;
    final cover = it != null
        ? AbsCover(it, width: 44, height: 44, radius: 8)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(color: kBrandColor.withValues(alpha: 0.2)));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        SizedBox(
          width: 44,
          height: 44,
          child: cover,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(handle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: absText(14, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  downloading
                      ? 'Downloading ${(progress! * 100).round()}% — ${handle.trackCount} file(s)'
                      : '${handle.creator} · ${_sizeOf(context)} · ${absClock(Duration(seconds: handle.durationSeconds.round()))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: absText(12, color: kMuted2),
                ),
              ]),
        ),
        const SizedBox(width: 8),
        if (downloading)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: kBrandColor))
        else
          IconButton(
            tooltip: 'Delete download',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: kMuted2),
            onPressed: onDelete,
          ),
      ]),
    );
  }

  String _sizeOf(BuildContext context) {
    final dl = context.read<AbsDownloadService>();
    final total = dl.handles
        .where((h) =>
            h.itemId == handle.itemId && h.episodeId == handle.episodeId)
        .fold(0, (sum, h) => sum + h.sizeBytes);
    final bytes = total > 0 ? total : handle.sizeBytes;
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).round()} MB';
    return '${(bytes / 1024).round()} KB';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.download_done_rounded, size: 48, color: kMuted2),
        const SizedBox(height: 12),
        Text('No downloads yet',
            style: absText(15, w: FontWeight.w600)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
              'Open a book or podcast, then tap the download badge on the cover.',
              textAlign: TextAlign.center,
              style: absText(13, color: kMuted2)),
        ),
      ]),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: kVioletLight, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center, style: absText(13, color: kMuted2)),
          const SizedBox(height: 16),
          AbsGhostButton('Retry', onTap: onRetry, icon: Icons.refresh_rounded),
        ]),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../services/local_tag_enrichment.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/click_region.dart';
import '../../widgets/motion.dart';
import '../../widgets/state_views.dart';
import 'library_controls.dart';

enum _LocalFilter { all, missingTags, duplicates }

enum _LocalSort { folder, title, artist, size }

const _localSortLabels = <_LocalSort, String>{
  _LocalSort.folder: 'Folder',
  _LocalSort.title: 'Title',
  _LocalSort.artist: 'Artist',
  _LocalSort.size: 'Largest first',
};

const int _localPage = 50;
const Color _amber = Color(0xFFFEB722);

String _folderName(String path) {
  final parts =
      path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

bool _missingTags(Song s) => s.artist.isEmpty || s.artist == 'Local file';

String _dupKey(Song s) =>
    '${s.title.toLowerCase().trim()}|${s.artist.toLowerCase().trim()}|${s.duration.inSeconds}';

/// Library > Local (board "Library - Local files"): one card per folder
/// source (path, file count) plus a dashed "Add folder" tile, All / Missing
/// tags / Duplicates chips, filter, sort and a table of the imported files.
/// Opening the tab re-scans the remembered folders for new files.
class LocalTab extends StatefulWidget {
  const LocalTab({super.key});

  @override
  State<LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<LocalTab> {
  final TextEditingController _filter = TextEditingController();
  final Map<String, int> _sizes = {};
  _LocalFilter _chip = _LocalFilter.all;
  _LocalSort _sort = _LocalSort.folder;
  int _shown = _localPage;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScan());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _autoScan() async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (appState.localFolderPaths.isEmpty) return;
    setState(() => _scanning = true);
    try {
      final added = await appState.rescanLocalFolders();
      if (added > 0) await LocalTagEnrichment.enrich(appState);
    } catch (_) {
      // A folder that went away just yields nothing new.
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _addFolder(AppState appState) async {
    await runLocalImport(context, appState.importLocalFolder);
    await LocalTagEnrichment.enrich(appState);
  }

  Future<void> _addFiles(AppState appState) async {
    await runLocalImport(context, appState.importLocalFiles);
    await LocalTagEnrichment.enrich(appState);
  }

  String _folderOf(Song s, List<String> folders) {
    final path = s.localFilePath ?? '';
    String? best;
    for (final f in folders) {
      if (path.startsWith(f) && (best == null || f.length > best.length)) {
        best = f;
      }
    }
    if (best != null) return _folderName(best);
    final cut = path.lastIndexOf(RegExp(r'[\\/]'));
    return cut > 0 ? _folderName(path.substring(0, cut)) : '—';
  }

  int _sizeOf(Song s) {
    final path = s.localFilePath;
    if (path == null) return 0;
    return _sizes.putIfAbsent(path, () {
      try {
        return File(path).lengthSync();
      } catch (_) {
        return 0;
      }
    });
  }

  String _format(Song s) {
    final path = s.localFilePath ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toUpperCase() : '';
    final label = ext.isEmpty && s.audioInfo.hasFormat
        ? s.audioInfo.format!.toUpperCase()
        : ext;
    if (label.isEmpty) return '—';
    if (s.audioInfo.hasBitrate && label != 'FLAC' && label != 'WAV') {
      return '$label ${s.audioInfo.bitrateKbps}';
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final songs = appState.localSongs;
    final folders = appState.localFolderPaths;

    final dupCounts = <String, int>{};
    for (final s in songs) {
      dupCounts.update(_dupKey(s), (n) => n + 1, ifAbsent: () => 1);
    }
    bool isDup(Song s) => (dupCounts[_dupKey(s)] ?? 0) > 1;
    final missing = songs.where(_missingTags).length;
    final dups = songs.where(isDup).length;

    final query = _filter.text.trim().toLowerCase();
    var filtered = songs.where((s) {
      switch (_chip) {
        case _LocalFilter.all:
          break;
        case _LocalFilter.missingTags:
          if (!_missingTags(s)) return false;
        case _LocalFilter.duplicates:
          if (!isDup(s)) return false;
      }
      if (query.isEmpty) return true;
      return s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query) ||
          (s.localFilePath ?? '').toLowerCase().contains(query);
    }).toList();
    switch (_sort) {
      case _LocalSort.folder:
        final key = {for (final s in filtered) s.id: _folderOf(s, folders).toLowerCase()};
        filtered.sort((a, b) {
          final c = key[a.id]!.compareTo(key[b.id]!);
          return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case _LocalSort.title:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _LocalSort.artist:
        filtered.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case _LocalSort.size:
        final sizes = {for (final s in filtered) s.id: _sizeOf(s)};
        filtered.sort((a, b) => sizes[b.id]!.compareTo(sizes[a.id]!));
    }
    filtered = List<Song>.of(filtered);
    final shown = filtered.take(_shown).toList();

    return DesktopContentFrame(
      maxWidth: DesktopTokens.contentTable,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _folderCards(appState, songs, folders),
          const SizedBox(height: 20),
          _toolbar(appState, songs.length, missing, dups),
          const SizedBox(height: 16),
          if (songs.isEmpty)
            const EmptyStateView(
              icon: Icons.folder_open_rounded,
              title: 'No local files yet',
              subtitle:
                  'Add a music folder, or pick individual audio files, to play them here.',
            )
          else if (filtered.isEmpty)
            const EmptyStateView(
              icon: Icons.search_off_rounded,
              title: 'No files match',
              subtitle: 'Clear the filter or pick another chip to see more.',
            )
          else
            _table(shown, filtered, folders, isDup, player, appState),
        ],
      ),
    );
  }

  Widget _folderCards(AppState appState, List<Song> songs, List<String> folders) {
    final counts = <String, int>{for (final f in folders) f: 0};
    for (final s in songs) {
      final path = s.localFilePath ?? '';
      String? best;
      for (final f in folders) {
        if (path.startsWith(f) && (best == null || f.length > best.length)) {
          best = f;
        }
      }
      if (best != null) counts[best] = counts[best]! + 1;
    }
    final importing = appState.importingLocalFiles;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
      const gap = 16.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < folders.length; i++)
            SizedBox(
              width: w,
              child: Entrance(
                key: ValueKey('folder-${folders[i]}'),
                delay: Entrance.stagger(i),
                child: _FolderCard(
                  path: folders[i],
                  files: counts[folders[i]] ?? 0,
                  scanning: _scanning,
                  onRemove: () async {
                    final ok = await confirmAction(
                      context,
                      title: 'Remove this folder?',
                      message:
                          '"${_folderName(folders[i])}" and every song imported from it will be removed from Shuro. Your files on disk are not touched.',
                      confirmLabel: 'Remove',
                    );
                    if (ok) appState.removeLocalFolder(folders[i]);
                  },
                ),
              ),
            ),
          SizedBox(
            width: w,
            child: _AddFolderTile(
                busy: importing,
                onTap: importing ? null : () => _addFolder(appState)),
          ),
        ],
      );
    });
  }

  Widget _chipButton(String label, int count, _LocalFilter value) {
    final selected = _chip == value;
    return ClickRegion(
      onTap: () => setState(() {
        _chip = value;
        _shown = _localPage;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: ShuroMotion.std,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? kBrandColor : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? kBrandColor : Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: libraryCellStyle(
                  color: selected ? Colors.white : kNavText, size: 13)),
          const SizedBox(width: 6),
          Text('$count',
              style: libraryCellStyle(
                  color: selected ? Colors.white70 : kStatusText, size: 12)),
        ]),
      ),
    );
  }

  Widget _toolbar(AppState appState, int total, int missing, int dups) {
    final filter = LibraryFilterField(
        controller: _filter,
        hint: 'Filter local files',
        width: null,
        onChanged: () => setState(() => _shown = _localPage));
    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      _chipButton('All', total, _LocalFilter.all),
      _chipButton('Missing tags', missing, _LocalFilter.missingTags),
      _chipButton('Duplicates', dups, _LocalFilter.duplicates),
    ]);
    final sort = LibrarySortMenu<_LocalSort>(
        value: _sort,
        options: _localSortLabels,
        onSelected: (s) => setState(() => _sort = s));
    final addFiles = LibraryPill(
        label: 'Add files',
        icon: Icons.audio_file_rounded,
        glass: true,
        onTap: appState.importingLocalFiles ? null : () => _addFiles(appState));
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 860) {
        return Row(children: [
          SizedBox(width: 280, child: filter),
          const SizedBox(width: 16),
          chips,
          const Spacer(),
          sort,
          const SizedBox(width: 8),
          addFiles,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        filter,
        const SizedBox(height: 8),
        chips,
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [sort, addFiles]),
      ]);
    });
  }

  Widget _table(List<Song> shown, List<Song> filtered, List<String> folders,
      bool Function(Song) isDup, PlayerController player, AppState appState) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final columns = [
        const LibraryColumn('TITLE', flex: 4),
        const LibraryColumn('ARTIST', flex: 3),
        if (wide) const LibraryColumn('FOLDER', flex: 2),
        if (wide) const LibraryColumn('FORMAT', width: 100),
        if (wide) const LibraryColumn('SIZE', width: 80),
        const LibraryColumn('TIME', width: 56),
      ];
      return Container(
        decoration: libraryTableCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            LibraryTableHeader(columns: columns),
            for (var i = 0; i < shown.length; i++)
              Entrance(
                key: ValueKey('local-${shown[i].id}'),
                delay: Entrance.stagger(i),
                child: _row(shown[i], i, columns, wide, folders, isDup,
                    filtered, player, appState),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LibraryFooter(
                  shown: shown.length,
                  total: filtered.length,
                  noun: 'files',
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onLoadMore: shown.length < filtered.length
                      ? () => setState(() => _shown += _localPage)
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _row(
      Song s,
      int i,
      List<LibraryColumn> columns,
      bool wide,
      List<String> folders,
      bool Function(Song) isDup,
      List<Song> queue,
      PlayerController player,
      AppState appState) {
    final noTags = _missingTags(s);
    final dup = isDup(s);
    final size = _sizeOf(s);
    return LibraryTableRow(
      columns: columns,
      onTap: () => player.playSong(s, queue: queue),
      index: Text('${i + 1}',
          style: libraryCellStyle(color: kStatusText, size: 13)),
      cells: [
        Row(children: [
          ArtworkThumb(
              gradientColors: s.gradientColors,
              artwork: s.artwork,
              size: 36,
              radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(
                    noTags
                        ? 'Tags missing'
                        : (dup ? 'Duplicate' : 'On this device'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: libraryCellStyle(
                        color: noTags || dup ? _amber : kStatusText, size: 12)),
              ],
            ),
          ),
        ]),
        Text(noTags ? 'Unknown artist' : s.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: libraryCellStyle(color: noTags ? _amber : kNavText)),
        if (wide)
          Text(_folderOf(s, folders),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: libraryCellStyle()),
        if (wide) Text(_format(s), style: libraryCellStyle()),
        if (wide)
          Text(size > 0 ? libraryBytes(size) : '—', style: libraryCellStyle()),
        Text(libraryDuration(s.duration), style: libraryCellStyle()),
      ],
      trailing: IconButton(
        tooltip: 'Remove from library',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close_rounded, size: 18, color: kMuted2),
        onPressed: () async {
          final ok = await confirmAction(
            context,
            title: 'Remove this file?',
            message:
                '"${s.title}" will be removed from your local library. The file on disk is not deleted.',
            confirmLabel: 'Remove',
          );
          if (ok) appState.removeLocalSong(s.id);
        },
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String path;
  final int files;
  final bool scanning;
  final VoidCallback onRemove;
  const _FolderCard({
    required this.path,
    required this.files,
    required this.scanning,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      padding: const EdgeInsets.all(16),
      decoration: libraryTableCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kBrandColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_outlined,
                    size: 18, color: kVioletPale),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_folderName(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: libraryCellStyle(color: kStatusText, size: 11)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove this folder',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 16, color: kMuted2),
                onPressed: onRemove,
              ),
            ],
          ),
          const Spacer(),
          Text(scanning ? '$files files · scanning' : '$files files',
              style: libraryCellStyle(
                  color: scanning ? kVioletLight : kStatusText, size: 12)),
          if (scanning) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                  minHeight: 3,
                  color: kBrandColor,
                  backgroundColor: Color(0x14FFFFFF)),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddFolderTile extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const _AddFolderTile({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      radius: BorderRadius.circular(16),
      child: ClickRegion(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _Dashed(),
          child: SizedBox(
            height: 114,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kVioletLight))
                else
                  const Icon(Icons.add_rounded, size: 24, color: kVioletLight),
                const SizedBox(height: 6),
                Text(busy ? 'Importing...' : 'Add folder',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kVioletLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Scans for new files automatically',
                    style: libraryCellStyle(color: kStatusText, size: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kBrandColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1), const Radius.circular(16)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => false;
}

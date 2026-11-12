import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/smart_playlist_preset.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/click_region.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/playlist_actions_sheet.dart';
import '../../widgets/playlist_collage_art.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../playlist/create_playlist_screen.dart';
import '../playlist/playlist_detail_screen.dart';
import '../playlist/server_playlists_section.dart';
import 'library_cached_tab.dart';
import 'library_controls.dart';

enum _PlaylistSort { newest, name, songCount }

const _playlistSortLabels = <_PlaylistSort, String>{
  _PlaylistSort.newest: 'Recently created',
  _PlaylistSort.name: 'Name',
  _PlaylistSort.songCount: 'Song count',
};

/// "1 h 32 m" / "48 m" label for a total running time.
String _hm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${d.inMinutes} m';
  return '$h h ${m.toString().padLeft(2, '0')} m';
}

class _M3uEntry {
  final String path;
  final String? info;
  const _M3uEntry(this.path, this.info);
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _baseNoExt(String path) {
  final unified = path.replaceAll('\\', '/');
  final name = unified.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Parses an M3U / M3U8 body into entries (path line + the preceding
/// `#EXTINF:<secs>,<Artist - Title>` text, when present).
List<_M3uEntry> _parseM3u(String text) {
  final out = <_M3uEntry>[];
  String? info;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.replaceAll('﻿', '').trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      info = comma >= 0 ? line.substring(comma + 1).trim() : null;
    } else if (line.startsWith('#')) {
      continue;
    } else {
      out.add(_M3uEntry(line, info));
      info = null;
    }
  }
  return out;
}

/// Matches M3U entries against the library: exact/suffix file path for local
/// files first, then "Artist - Title" (from EXTINF or the file name), then the
/// bare title. Returns matched song ids in playlist order, de-duplicated.
List<String> _matchM3u(List<_M3uEntry> entries, List<Song> songs) {
  final byPath = <String, Song>{};
  final byArtistTitle = <String, Song>{};
  final byTitle = <String, Song>{};
  for (final s in songs) {
    final p = s.localFilePath;
    if (p != null) byPath[p.replaceAll('\\', '/').toLowerCase()] = s;
    byArtistTitle.putIfAbsent(_norm('${s.artist} ${s.title}'), () => s);
    byTitle.putIfAbsent(_norm(s.title), () => s);
  }

  Song? fromLabel(String label) {
    final dash = label.indexOf(' - ');
    if (dash > 0) {
      final artist = label.substring(0, dash);
      final title = label.substring(dash + 3);
      final hit = byArtistTitle[_norm('$artist $title')] ?? byTitle[_norm(title)];
      if (hit != null) return hit;
    }
    return byTitle[_norm(label)];
  }

  final ids = <String>[];
  final seen = <String>{};
  for (final e in entries) {
    final path = e.path.replaceAll('\\', '/').toLowerCase();
    Song? hit = byPath[path];
    if (hit == null) {
      for (final entry in byPath.entries) {
        if (entry.key.endsWith(path) || path.endsWith(entry.key)) {
          hit = entry.value;
          break;
        }
      }
    }
    hit ??= e.info == null ? null : fromLabel(e.info!);
    hit ??= fromLabel(_baseNoExt(e.path));
    if (hit != null && seen.add(hit.id)) ids.add(hit.id);
  }
  return ids;
}

class _SmartList {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final List<Song> songs;
  const _SmartList(this.title, this.subtitle, this.icon, this.tint, this.songs);
}

/// Library > Playlists (board "Library - Playlists"): count + filter + sort +
/// Play all, four smart-playlist cards, then "YOUR PLAYLISTS" with a dashed
/// "New playlist" tile (start empty or import an M3U) and the playlist grid.
/// Playlists on the connected server are listed underneath as before.
class PlaylistsTab extends StatefulWidget {
  const PlaylistsTab({super.key});

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  final TextEditingController _filter = TextEditingController();
  _PlaylistSort _sort = _PlaylistSort.newest;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<Song> _songsOf(AppState appState, Playlist p) => p.smartPreset != null
      ? ShuroPulse.smartPlaylistSongs(p.smartPreset!, appState)
      : appState.songsByIds(p.songIds);

  List<_SmartList> _smartLists(AppState appState) {
    final recent = appState.hasServer
        ? ShuroPulse.smartPlaylistSongs(
            SmartPlaylistPreset.recentlyAdded, appState)
        : const <Song>[];
    final played = [
      for (final s in appState.catalogSongs)
        if (s.playCount > 0) s
    ]..sort((a, b) => b.playCount.compareTo(a.playCount));
    final offlineIds = <String>{...appState.downloadedSongIds};
    final offline = <Song>[...appState.songsByIds(offlineIds.toList())];
    for (final c in cachedSongsOf(appState)) {
      if (offlineIds.add(c.song.id)) offline.add(c.song);
    }
    final favorites = [
      for (final s in appState.allSongs)
        if (appState.isFavoriteSong(s.id)) s
    ];
    return [
      _SmartList('Recently added', 'Songs from the last 30 days',
          Icons.schedule_rounded, kSecondaryColor, recent),
      _SmartList('Most played', 'Your top tracks', Icons.local_fire_department_rounded,
          const Color(0xFFF472B6), played.take(50).toList()),
      _SmartList('Ready offline', 'Downloaded and cached songs',
          Icons.download_done_rounded, kGreen, offline),
      _SmartList('Favorites', 'Songs you hearted', Icons.favorite_rounded,
          const Color(0xFFFEB722), favorites),
    ];
  }

  void _openPlaylist(Playlist p) => Navigator.of(context)
      .push(drillDownRoute(PlaylistDetailScreen(playlist: p)));

  void _play(AppState appState, Playlist p) {
    final songs = _songsOf(appState, p);
    if (songs.isEmpty) return;
    context.read<PlayerController>().playSong(songs.first, queue: songs);
  }

  Future<void> _newPlaylist() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: kCardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New playlist',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'empty'),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.add_rounded, color: kVioletLight),
              title: Text('Start empty',
                  style: libraryCellStyle(color: Colors.white, size: 14)),
              subtitle: Text('Name it, then add songs',
                  style: libraryCellStyle(color: kStatusText, size: 12)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'm3u'),
            child: ListTile(
              dense: true,
              leading:
                  const Icon(Icons.upload_file_rounded, color: kVioletLight),
              title: Text('Import an M3U',
                  style: libraryCellStyle(color: Colors.white, size: 14)),
              subtitle: Text('Matches the tracks to songs in your library',
                  style: libraryCellStyle(color: kStatusText, size: 12)),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'empty') {
      await Navigator.of(context)
          .push(drillDownRoute(const CreatePlaylistScreen()));
    } else {
      await _importM3u();
    }
  }

  Future<void> _importM3u() async {
    final appState = context.read<AppState>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8'],
        withData: kIsWeb,
      );
      final file = result?.files.single;
      if (file == null) return;
      final Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw const FormatException('no data');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final entries = _parseM3u(text);
      if (!mounted) return;
      if (entries.isEmpty) {
        showErrorSnackBar(context, 'That file has no tracks in it.');
        return;
      }
      final ids = _matchM3u(entries, appState.allSongs);
      if (ids.isEmpty) {
        showErrorSnackBar(context,
            "None of the ${entries.length} tracks matched songs in your library.");
        return;
      }
      final name = _baseNoExt(file.name).trim().isEmpty
          ? 'Imported playlist'
          : _baseNoExt(file.name).trim();
      appState.createPlaylist(name, songIds: ids);
      showSuccessSnackBar(context,
          'Imported ${ids.length} of ${entries.length} tracks into "$name"');
    } catch (_) {
      if (!mounted) return;
      showErrorSnackBar(context, "Couldn't import that playlist file.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final all = appState.playlists;
    final query = _filter.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<Playlist>.of(all)
        : all.where((p) => p.name.toLowerCase().contains(query)).toList();
    switch (_sort) {
      case _PlaylistSort.newest:
        // Creation order, newest first.
        final reversed = filtered.reversed.toList();
        filtered
          ..clear()
          ..addAll(reversed);
      case _PlaylistSort.name:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _PlaylistSort.songCount:
        filtered.sort(
            (a, b) => b.songIds.length.compareTo(a.songIds.length));
    }
    final smart = _smartLists(appState);

    void playAll() {
      final seen = <String>{};
      final queue = <Song>[];
      for (final p in filtered) {
        for (final s in _songsOf(appState, p)) {
          if (seen.add(s.id)) queue.add(s);
        }
      }
      if (queue.isEmpty) return;
      context.read<PlayerController>().playSong(queue.first, queue: queue);
    }

    return DesktopContentFrame(
      maxWidth: DesktopTokens.contentTable,
      child: Column(
        children: [
          LibraryToolbar(
            countLabel: query.isEmpty
                ? '${all.length} playlists'
                : '${filtered.length} of ${all.length} playlists',
            filterController: _filter,
            filterHint: 'Filter playlists',
            onFilterChanged: () => setState(() {}),
            trailing: [
              LibrarySortMenu<_PlaylistSort>(
                  value: _sort,
                  options: _playlistSortLabels,
                  onSelected: (s) => setState(() => _sort = s)),
              LibraryPill(
                  label: 'Play all',
                  icon: Icons.play_arrow_rounded,
                  onTap: filtered.isEmpty ? null : playAll),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                if (query.isEmpty) ...[
                  const LibrarySectionLabel('SMART PLAYLISTS'),
                  _smartRow(smart),
                  const SizedBox(height: 20),
                ],
                const LibrarySectionLabel('YOUR PLAYLISTS'),
                _grid(appState, filtered, showNew: query.isEmpty),
                if (all.isNotEmpty && filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('No playlists match "${_filter.text.trim()}".',
                        style: libraryCellStyle(color: kStatusText)),
                  ),
                if (query.isEmpty) ...[
                  const SizedBox(height: 12),
                  // Everything the connected server reports, manageable
                  // in-app when the user owns it.
                  const ServerPlaylistsSection(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smartRow(List<_SmartList> lists) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
      const gap = 16.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < lists.length; i++)
            SizedBox(
              width: w,
              child: Entrance(
                delay: Entrance.stagger(i),
                child: _SmartCard(
                  list: lists[i],
                  onTap: () => Navigator.of(context).push(drillDownRoute(
                      _SongListScreen(
                          title: lists[i].title, songs: lists[i].songs))),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _grid(AppState appState, List<Playlist> items, {required bool showNew}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000
          ? 4
          : (c.maxWidth >= 720 ? 3 : (c.maxWidth >= 420 ? 2 : 1));
      // Board gutters are wide (~41 px at 4 across); 32 keeps that feel
      // while still fitting four columns at the table width.
      const gap = 32.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final cells = <Widget>[
        if (showNew) _NewPlaylistTile(size: w, onTap: _newPlaylist),
        for (var i = 0; i < items.length; i++)
          Entrance(
            key: ValueKey('pl-${items[i].id}'),
            delay: Entrance.stagger(i + 1),
            child: _PlaylistTile(
              playlist: items[i],
              songs: _songsOf(appState, items[i]),
              size: w,
              onTap: () => _openPlaylist(items[i]),
              onPlay: () => _play(appState, items[i]),
            ),
          ),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: 24,
        children: [for (final cell in cells) SizedBox(width: w, child: cell)],
      );
    });
  }
}

class _SmartCard extends StatelessWidget {
  final _SmartList list;
  final VoidCallback onTap;
  const _SmartCard({required this.list, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      lift: 2,
      radius: BorderRadius.circular(16),
      child: ClickRegion(
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: libraryTableCardDecoration(),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: list.tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(list.icon, color: list.tint, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(list.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            libraryCellStyle(color: kStatusText, size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${list.songs.length}',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kNavText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistTile extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  const _NewPlaylistTile({required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      radius: BorderRadius.circular(16),
      child: ClickRegion(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
              color: kBrandColor.withValues(alpha: 0.7), radius: 16),
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kBrandColor.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: kVioletPale, size: 26),
                ),
                const SizedBox(height: 14),
                Text('New playlist',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kVioletLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Start empty or import an M3U',
                    textAlign: TextAlign.center,
                    style: libraryCellStyle(color: kStatusText, size: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1), Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _PlaylistTile extends StatefulWidget {
  final Playlist playlist;
  final List<Song> songs;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  const _PlaylistTile({
    required this.playlist,
    required this.songs,
    required this.size,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<_PlaylistTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.playlist;
    var total = Duration.zero;
    for (final s in widget.songs) {
      total += s.duration;
    }
    final meta = widget.songs.isEmpty
        ? '0 songs'
        : '${widget.songs.length} songs · ${_hm(total)}';
    return ContextMenuRegion(
      items: playlistContextMenuItems(context, p),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: HoverLift(
          radius: BorderRadius.circular(16),
          child: ClickRegion(
            onTap: widget.onTap,
            onLongPress: isDesktopPlatform
                ? null
                : () => showPlaylistActionsSheet(context, p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: PlaylistCollageArt(playlist: p, radius: 16)),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          curve: ShuroMotion.std,
                          opacity: _hover ? 1 : 0,
                          child: ClickRegion(
                            onTap: widget.songs.isEmpty ? null : widget.onPlay,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                  color: kBrandColor, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: libraryCellStyle(color: kStatusText, size: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Song list opened from a smart-playlist card.
class _SongListScreen extends StatelessWidget {
  final String title;
  final List<Song> songs;
  const _SongListScreen({required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text(title,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        actions: [
          if (songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: LibraryPill(
                    label: 'Play all',
                    icon: Icons.play_arrow_rounded,
                    onTap: () => player.playSong(songs.first, queue: songs)),
              ),
            ),
        ],
      ),
      body: songs.isEmpty
          ? const EmptyStateView(
              icon: Icons.queue_music_rounded,
              title: 'Nothing here yet',
              subtitle: 'Songs show up here as your library fills in.')
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                  song: songs[i],
                  onTap: () => player.playSong(songs[i], queue: songs)),
            ),
    );
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'desktop_context_menu.dart';

/// True when running as a native desktop app — Windows, Linux or macOS,
/// never web or a phone/tablet. The Library Songs tab swaps its mobile list
/// for [DesktopSongTable] only while this holds, matching the platform gate
/// home_screen.dart already uses for its desktop affordances.
bool get isNativeDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Which column [DesktopSongTable] is sorted by.
enum _SortColumn { title, artist, album, duration }

// Column widths shared by the header row and every data row so the cells
// stay aligned. Title/Artist/Album flex instead of using fixed widths so the
// table never overflows on a narrow desktop window.
const double _indexWidth = 44;
const double _durationWidth = 72;

/// Desktop-only data-table song list for the Library Songs tab: a header row
/// of sort buttons (Title / Artist / Album / Duration) over dense rows.
/// Tapping a header sorts by that column and toggles ascending/descending on
/// repeat taps, with a small arrow on the active column. Rows are denser
/// than [SongTile] but keep its two desktop affordances: tap plays (with the
/// currently sorted list as the queue) and right-click opens the same
/// [songContextMenuItems] menu.
///
/// Only instantiate this behind [isNativeDesktop]; mobile and web keep their
/// existing lists untouched.
class DesktopSongTable extends StatefulWidget {
  final List<Song> songs;

  /// Resolves an album title for a song's `albumId`. Callers usually build a
  /// {id: title} map from `AppState.catalogAlbums` once per build rather than
  /// calling `albumById` per row.
  final String Function(Song song) albumTitleOf;

  /// Fired on row tap — receives the tapped song plus the currently sorted
  /// list, so callers can play with the visible order as the queue.
  final void Function(Song song, List<Song> playQueue) onPlaySong;

  const DesktopSongTable({
    super.key,
    required this.songs,
    required this.albumTitleOf,
    required this.onPlaySong,
  });

  @override
  State<DesktopSongTable> createState() => _DesktopSongTableState();
}

class _DesktopSongTableState extends State<DesktopSongTable> {
  _SortColumn _column = _SortColumn.title;
  bool _ascending = true;

  void _sortBy(_SortColumn column) {
    setState(() {
      if (_column == column) {
        _ascending = !_ascending;
      } else {
        _column = column;
        _ascending = true;
      }
    });
  }

  List<Song> get _sorted {
    // Title is the tie-breaker under every column, so rows that share an
    // artist/album/duration keep a predictable order.
    int byTitle(Song a, Song b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final songs = List<Song>.of(widget.songs)
      ..sort((a, b) {
        switch (_column) {
          case _SortColumn.title:
            return byTitle(a, b);
          case _SortColumn.artist:
            final r =
                a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
            return r != 0 ? r : byTitle(a, b);
          case _SortColumn.album:
            final r = widget
                .albumTitleOf(a)
                .toLowerCase()
                .compareTo(widget.albumTitleOf(b).toLowerCase());
            return r != 0 ? r : byTitle(a, b);
          case _SortColumn.duration:
            final r = a.duration.compareTo(b.duration);
            return r != 0 ? r : byTitle(a, b);
        }
      });
    return _ascending ? songs : songs.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final playingId = context.watch<PlayerController>().currentSong?.id;
    return Column(
      children: [
        _HeaderRow(column: _column, ascending: _ascending, onSort: _sortBy),
        const Divider(height: 1, color: kDividerColor),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final song = sorted[i];
              final playing = song.id == playingId;
              return ContextMenuRegion(
                items: songContextMenuItems(context, song),
                child: InkWell(
                  onTap: () => widget.onPlaySong(song, sorted),
                  hoverColor: Colors.white.withValues(alpha: 0.045),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _indexWidth,
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: GoogleFonts.getFont(
                                currentFontFamily,
                                color: playing
                                    ? kBrandColor
                                    : kMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _cellText(
                            song.title,
                            color: playing ? kBrandColor : Colors.white,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: _cellText(song.artist, color: Colors.white70),
                        ),
                        Expanded(
                          flex: 3,
                          child: _cellText(widget.albumTitleOf(song),
                              color: Colors.white70),
                        ),
                        SizedBox(
                          width: _durationWidth,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _formatDuration(song.duration),
                              style: GoogleFonts.getFont(
                                currentFontFamily,
                                color: kMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cellText(String text,
      {required Color color, FontWeight weight = FontWeight.w400}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.getFont(
          currentFontFamily,
          color: color,
          fontSize: 12.5,
          fontWeight: weight,
        ),
      ),
    );
  }
}

/// The table's header: '#' over the index column, then a sort button per
/// sortable column, aligned exactly like the data rows below.
class _HeaderRow extends StatelessWidget {
  final _SortColumn column;
  final bool ascending;
  final ValueChanged<_SortColumn> onSort;

  const _HeaderRow({
    required this.column,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: _indexWidth,
            child: Center(
              child: Text('#', style: _headerLabelStyle(false)),
            ),
          ),
          Expanded(
            flex: 4,
            child: _HeaderButton(
              label: 'Title',
              column: _SortColumn.title,
              active: column == _SortColumn.title,
              ascending: ascending,
              onSort: onSort,
            ),
          ),
          Expanded(
            flex: 3,
            child: _HeaderButton(
              label: 'Artist',
              column: _SortColumn.artist,
              active: column == _SortColumn.artist,
              ascending: ascending,
              onSort: onSort,
            ),
          ),
          Expanded(
            flex: 3,
            child: _HeaderButton(
              label: 'Album',
              column: _SortColumn.album,
              active: column == _SortColumn.album,
              ascending: ascending,
              onSort: onSort,
            ),
          ),
          SizedBox(
            width: _durationWidth,
            child: _HeaderButton(
              label: 'Duration',
              column: _SortColumn.duration,
              active: column == _SortColumn.duration,
              ascending: ascending,
              onSort: onSort,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// One sortable column header. Shows the direction arrow only on the active
/// column; tapping an inactive column switches to it ascending first.
class _HeaderButton extends StatelessWidget {
  final String label;
  final _SortColumn column;
  final bool active;
  final bool ascending;
  final ValueChanged<_SortColumn> onSort;

  /// Right-align the label (used for the Duration column) — the arrow then
  /// sits before the label so it stays against the column's content.
  final bool alignEnd;

  const _HeaderButton({
    required this.label,
    required this.column,
    required this.active,
    required this.ascending,
    required this.onSort,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final sortLabel = 'Sort by ${label.toLowerCase()}';
    final arrow = Icon(
      ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      size: 13,
      color: kBrandColor,
    );
    return Tooltip(
      message: sortLabel,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: sortLabel,
        child: InkWell(
          onTap: () => onSort(column),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment:
                  alignEnd ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active && alignEnd) ...[arrow, const SizedBox(width: 4)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _headerLabelStyle(active),
                    ),
                  ),
                  if (active && !alignEnd) ...[
                    const SizedBox(width: 4),
                    arrow,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _headerLabelStyle(bool active) => GoogleFonts.getFont(
      currentFontFamily,
      fontSize: 11,
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
      letterSpacing: 0.7,
      color: active ? kBrandColor : kMutedTextColor,
    );

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

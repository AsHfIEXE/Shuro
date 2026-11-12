import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../services/audio_cache.dart';
import '../../widgets/click_region.dart';
import '../../models/song.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/desktop_song_table.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/loading_skeletons.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../downloads/downloads_screen.dart';
import 'library_artists_albums_tabs.dart';
import 'library_controls.dart';
import 'library_cached_tab.dart';
import 'library_genres_tab.dart';
import 'library_local_tab.dart';
import 'library_playlists_tab.dart';
import 'personal_shelves_screen.dart';

enum _SongSort { titleAz, artistAz, recentlyAdded }

/// Short label for the desktop sort chip ("Sort: Title").
extension _SongSortLabel on _SongSort {
  String get label => switch (this) {
        _SongSort.titleAz => 'Title',
        _SongSort.artistAz => 'Artist',
        _SongSort.recentlyAdded => 'Recently added',
      };
}

/// Raised card surface for the desktop table card (boards: #111723).
const Color _tableCardColor = Color(0xFF111723);

/// Shared pull-to-refresh action for the Songs/Albums/Artists tabs —
/// genuinely re-fetches the connected server's library (see
/// AppState.refreshLibrary), same real refresh Home's pull-to-refresh uses.
Future<void> _refreshLibrary(BuildContext context) async {
  HapticFeedback.mediumImpact();
  await context.read<AppState>().refreshLibrary();
}

/// "04. Library" — segmented Songs / Albums / Artists / Genres / Playlists,
/// with quick access to Downloads and Favorites (kept out of the bottom
/// nav — see the note in the request about not adding destinations the UI
/// doesn't need).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 8, vsync: this);
  _SongSort _sort = _SongSort.titleAz;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Library',
                        style: headingFont(
                            color: kTextColor,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9)),
                  ),
                  IconButton(
                    tooltip: 'Personal shelves',
                    icon: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white70),
                    onPressed: () => Navigator.of(context)
                        .push(drillDownRoute(const PersonalShelvesScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: Colors.white70),
                    onPressed: () => Navigator.of(context)
                        .push(drillDownRoute(const DownloadsScreen())),
                  ),
                ],
              ),
            ),
            // Board tab row: text tabs on a hairline, active label white
            // with a 57 px violet underline, Cached carries a count chip,
            // Downloads is a real tab.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _LibraryTab(
                          label: 'Songs',
                          selected: _tabController.index == 0,
                          onTap: () => _tabController.animateTo(0)),
                      _LibraryTab(
                          label: 'Albums',
                          selected: _tabController.index == 1,
                          onTap: () => _tabController.animateTo(1)),
                      _LibraryTab(
                          label: 'Artists',
                          selected: _tabController.index == 2,
                          onTap: () => _tabController.animateTo(2)),
                      _LibraryTab(
                          label: 'Genres',
                          selected: _tabController.index == 3,
                          onTap: () => _tabController.animateTo(3)),
                      _LibraryTab(
                          label: 'Playlists',
                          selected: _tabController.index == 4,
                          onTap: () => _tabController.animateTo(4)),
                      _LibraryTab(
                          label: 'Local',
                          selected: _tabController.index == 5,
                          onTap: () => _tabController.animateTo(5)),
                      _LibraryTab(
                          label: 'Downloads',
                          selected: _tabController.index == 6,
                          onTap: () => _tabController.animateTo(6)),
                      _LibraryTab(
                          label: 'Cached',
                          selected: _tabController.index == 7,
                          onTap: () => _tabController.animateTo(7),
                          count: AudioCache.instance.entries().length),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Songs/Albums/Artists cap at the table width like Genres
                  // already did — extra window width becomes margin,
                  // not stretched rows.
                  DesktopContentFrame(
                    maxWidth: DesktopTokens.contentTable,
                    child: _SongsTab(
                        sort: _sort,
                        onSortChanged: (s) => setState(() => _sort = s)),
                  ),
                  const AlbumsTab(),
                  const ArtistsTab(),
                  const GenresTab(),
                  const PlaylistsTab(),
                  const LocalTab(),
                  const DownloadsScreen(),
                  const CachedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongsTab extends StatefulWidget {
  final _SongSort sort;
  final ValueChanged<_SongSort> onSortChanged;

  const _SongsTab({required this.sort, required this.onSortChanged});

  @override
  State<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<_SongsTab> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// The sort popup items, shared by the mobile trigger and the desktop
  /// sort chip.
  List<PopupMenuItem<_SongSort>> _sortMenuItems() => [
        PopupMenuItem(
            value: _SongSort.titleAz,
            child: Text('Sort: Title A–Z',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13))),
        PopupMenuItem(
            value: _SongSort.artistAz,
            child: Text('Sort: Artist A–Z',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13))),
        PopupMenuItem(
            value: _SongSort.recentlyAdded,
            child: Text('Sort: Recently added',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13))),
      ];

  List<Song> _sorted(BuildContext context) {
    final songs = List<Song>.of(context.watch<AppState>().catalogSongs);
    switch (widget.sort) {
      case _SongSort.titleAz:
        songs.sort((a, b) => a.title.compareTo(b.title));
      case _SongSort.artistAz:
        songs.sort((a, b) => a.artist.compareTo(b.artist));
      case _SongSort.recentlyAdded:
        // The catalog itself arrives newest-added first (NavidromeApiClient
        // requests albums with type=newest), so this is the list's own order —
        // kept rather than re-sorted. The note here used to call it a mock's
        // order standing in for real data, which stopped being true long before
        // this became a real Navidrome client.
        break;
    }
    return songs;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final appState = context.watch<AppState>();
    final songs = _sorted(context);
    // Desktop builds get a sortable data-table list instead of the mobile
    // SongTile list — see DesktopSongTable. Everything below the toolbar
    // row is desktop-only; the mobile path is unchanged.
    final desktop = isNativeDesktop;
    // Album titles for the table's Album column, resolved once per build
    // instead of an albumById lookup per row. Local songs whose albumId has
    // no server album get an em dash rather than an empty cell.
    final albumTitles = {
      for (final album in appState.catalogAlbums) album.id: album.title
    };
    // First fetch in flight: skeleton rows in the shape of the list.
    if (songs.isEmpty &&
        appState.connectionStatus == ConnectionStatus.connecting) {
      return const SongListSkeleton();
    }
    if (songs.isEmpty) {
      return const EmptyStateView(
        icon: Icons.library_music_rounded,
        title: 'No songs yet',
        subtitle:
            'Connect a Navidrome server to see its catalog here, or add files from the Local files tab.',
      );
    }
    // Desktop-only filter field: case-insensitive substring match across
    // title / artist / album.
    final query = _filter.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? songs
        : songs
            .where((song) =>
                song.title.toLowerCase().contains(query) ||
                song.artist.toLowerCase().contains(query) ||
                (albumTitles[song.albumId] ?? '')
                    .toLowerCase()
                    .contains(query))
            .toList();
    if (visible.isEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No songs match',
        subtitle:
            'Nothing matches "${_filter.text.trim()}" · clear the filter to see all ${songs.length} songs.',
      );
    }
    return Column(
      children: [
        if (desktop)
          _DesktopSongsToolbar(
            controller: _filter,
            onFilterChanged: () => setState(() {}),
            visibleCount: visible.length,
            totalCount: songs.length,
            filtering: query.isNotEmpty,
            sort: widget.sort,
            onSortChanged: widget.onSortChanged,
            sortMenuItems: _sortMenuItems(),
            // Play / shuffle the whole current list — the sort and the
            // filter decide the play order, shuffle randomises it. Both queue
            // the full list so next/previous keep working.
            onPlayAll: () => player.playSong(visible.first, queue: visible),
            onShuffle: () {
              final shuffled = [...visible]..shuffle();
              player.playSong(shuffled.first, queue: shuffled);
            },
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Text('${songs.length} songs',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      player.playSong(visible.first, queue: visible),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play all'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    final shuffled = [...visible]..shuffle();
                    player.playSong(shuffled.first, queue: shuffled);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Shuffle'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                // Mobile keeps the sort popup; desktop uses the sort chip
                // in the toolbar plus the table's own column headers.
                PopupMenuButton<_SongSort>(
                  color: kCardColor,
                  initialValue: widget.sort,
                  onSelected: widget.onSortChanged,
                  itemBuilder: (context) => _sortMenuItems(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded,
                          color: kMutedTextColor, size: 16),
                      SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: kMutedTextColor, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: kBrandColor,
            backgroundColor: kCardColor,
            onRefresh: () => _refreshLibrary(context),
            child: desktop
                ? Container(
                    // The board's table card: raised #111723 surface with a
                    // hairline border; the table's 44 px header row lives
                    // inside the clip.
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    decoration: BoxDecoration(
                      color: _tableCardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kHairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: DesktopSongTable(
                      songs: visible,
                      albumTitleOf: (song) =>
                          albumTitles[song.albumId] ?? '—',
                      onPlaySong: (song, queue) =>
                          player.playSong(song, queue: queue),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) => SongTile(
                        song: visible[i],
                        onTap: () =>
                            player.playSong(visible[i], queue: visible)),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Desktop Songs toolbar (board "Library - Songs"): song count, the
/// "Filter songs" field, the sort chip and the Play all / Shuffle pills,
/// sitting right above the table card.
class _DesktopSongsToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onFilterChanged;
  final int visibleCount;
  final int totalCount;
  final bool filtering;
  final _SongSort sort;
  final ValueChanged<_SongSort> onSortChanged;
  final List<PopupMenuItem<_SongSort>> sortMenuItems;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;

  const _DesktopSongsToolbar({
    required this.controller,
    required this.onFilterChanged,
    required this.visibleCount,
    required this.totalCount,
    required this.filtering,
    required this.sort,
    required this.onSortChanged,
    required this.sortMenuItems,
    required this.onPlayAll,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    // Shared toolbar: flush-right controls at every width, the same 36 px
    // band, and the filter drops to its own full-width row on narrow
    // columns instead of disappearing.
    return LibraryToolbar(
      countLabel: filtering
          ? '$visibleCount of $totalCount songs'
          : '$totalCount songs',
      filterController: controller,
      filterHint: 'Filter songs',
      onFilterChanged: onFilterChanged,
      trailing: [
        PopupMenuButton<_SongSort>(
          color: kCardColor,
          initialValue: sort,
          onSelected: onSortChanged,
          position: PopupMenuPosition.under,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (context) => sortMenuItems,
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sort: ${sort.label}',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 14, color: kMuted2),
              ],
            ),
          ),
        ),
        _ToolbarPill(
          label: 'Shuffle',
          icon: Icons.shuffle_rounded,
          onTap: onShuffle,
          glass: true,
        ),
        _ToolbarPill(
          label: 'Play all',
          icon: Icons.play_arrow_rounded,
          onTap: onPlayAll,
        ),
      ],
    );
  }
}

/// h36 pill from the boards: violet filled for Play all, glass for Shuffle.
class _ToolbarPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Glass style (white 6% fill, white 14% border) instead of violet fill.
  final bool glass;

  const _ToolbarPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = glass ? kTextColor : Colors.white;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: glass
                ? Colors.white.withValues(alpha: 0.06)
                : kBrandColor,
            borderRadius: BorderRadius.circular(999),
            border: glass
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// One board tab: 14/600 label, violet 2 px underline when selected, an
/// optional count chip (Cached).
class _LibraryTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  const _LibraryTab(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.count});

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: selected ? Colors.white : kNavText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 34,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kBrandColor.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: selected ? kBrandColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/artist.dart';
import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../screens/playlist/server_playlists_section.dart';
import '../../services/artist_artwork_service.dart';
import '../../services/local_tag_enrichment.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artist_card.dart';
import '../../widgets/desktop_song_table.dart';
import '../../widgets/loading_skeletons.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../downloads/downloads_screen.dart';
import '../../widgets/download_cards.dart';
import 'personal_shelves_screen.dart';
import '../playlist/create_playlist_screen.dart';
import '../playlist/playlist_detail_screen.dart';

enum _SongSort { titleAz, artistAz, recentlyAdded }

/// Shared pull-to-refresh action for the Songs/Albums/Artists tabs —
/// genuinely re-fetches the connected server's library (see
/// AppState.refreshLibrary), same real refresh Home's pull-to-refresh uses.
Future<void> _refreshLibrary(BuildContext context) async {
  HapticFeedback.mediumImpact();
  await context.read<AppState>().refreshLibrary();
}

/// Just the folder's own name for a local-folder source row, falling back
/// to the full path for a root path with nothing to split off.
String _folderDisplayName(String path) {
  final parts =
      path.split(Platform.pathSeparator).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
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
      TabController(length: 7, vsync: this);
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
                            fontSize: 22,
                            fontWeight: FontWeight.w600)),
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
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: kBrandColor,
              labelColor: Colors.white,
              unselectedLabelColor: kMutedTextColor,
              labelStyle: GoogleFonts.getFont(currentFontFamily,
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.getFont(currentFontFamily, fontSize: 13),
              tabs: const [
                Tab(text: 'Songs'),
                Tab(text: 'Albums'),
                Tab(text: 'Artists'),
                Tab(text: 'Genres'),
                Tab(text: 'Playlists'),
                Tab(text: 'Local'),
                Tab(text: 'Downloads'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _SongsTab(
                      sort: _sort,
                      onSortChanged: (s) => setState(() => _sort = s)),
                  const _AlbumsTab(),
                  const _ArtistsTab(),
                  const _GenresTab(),
                  const _PlaylistsTab(),
                  const _LocalTab(),
                  const DownloadCardsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongsTab extends StatelessWidget {
  final _SongSort sort;
  final ValueChanged<_SongSort> onSortChanged;

  const _SongsTab({required this.sort, required this.onSortChanged});

  List<Song> _sorted(BuildContext context) {
    final songs = List<Song>.of(context.watch<AppState>().catalogSongs);
    switch (sort) {
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
    final songs = _sorted(context);
    // Desktop builds get a sortable data-table list instead of the mobile
    // SongTile list — see DesktopSongTable. Everything below the toolbar
    // row is desktop-only; the mobile path is unchanged.
    final desktop = isNativeDesktop;
    // Album titles for the table's Album column, resolved once per build
    // instead of an albumById lookup per row. Local songs whose albumId has
    // no server album get an em dash rather than an empty cell.
    final albumTitles = {
      for (final album in context.watch<AppState>().catalogAlbums)
        album.id: album.title
    };
    // First fetch in flight: skeleton rows in the shape of the list.
    if (songs.isEmpty &&
        context.watch<AppState>().connectionStatus ==
            ConnectionStatus.connecting) {
      return const SongListSkeleton();
    }
    if (songs.isEmpty) {
      return const EmptyStateView(
        icon: Icons.library_music_rounded,
        title: 'No songs yet',
        subtitle:
            'Connect a Navidrome server to see its catalog here, or add files from the Local tab.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Text('${songs.length} songs',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMutedTextColor, fontSize: 12)),
              const Spacer(),
              // Play / shuffle the whole current list — the sort (the "filter")
              // decides the play order, shuffle randomises it. Both queue the
              // full list so next/previous keep working.
              TextButton.icon(
                onPressed: () => player.playSong(songs.first, queue: songs),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Play all'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () {
                  final shuffled = [...songs]..shuffle();
                  player.playSong(shuffled.first, queue: shuffled);
                },
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              // Mobile keeps the sort popup; on desktop the table's column
              // headers are the sort UI, and a second control fighting them
              // would be ambiguous.
              if (!desktop)
                PopupMenuButton<_SongSort>(
                  color: kCardColor,
                  initialValue: sort,
                  onSelected: onSortChanged,
                  itemBuilder: (context) => [
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
                  ],
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
                ? DesktopSongTable(
                    songs: songs,
                    albumTitleOf: (song) => albumTitles[song.albumId] ?? '—',
                    onPlaySong: (song, queue) =>
                        player.playSong(song, queue: queue),
                  )
                : ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) => SongTile(
                        song: songs[i],
                        onTap: () => player.playSong(songs[i], queue: songs)),
                  ),
          ),
        ),
      ],
    );
  }
}

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final albums = appState.catalogAlbums;
    // First fetch in flight: a skeleton in the exact shape of the grid, so
    // the tab reads as "loading" instead of "empty".
    if (albums.isEmpty &&
        appState.connectionStatus == ConnectionStatus.connecting) {
      return const AlbumGridSkeleton();
    }
    if (albums.isEmpty) {
      return const EmptyStateView(
        icon: Icons.album_rounded,
        title: 'No albums yet',
        subtitle: 'Connect a Navidrome server to browse its albums here.',
      );
    }
    return RefreshIndicator(
      color: kBrandColor,
      backgroundColor: kCardColor,
      onRefresh: () => _refreshLibrary(context),
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        // Width-aware columns. Fixed crossAxisCount was the bug: at 2 columns a
        // 1920 px window gave each album a ~950 px cell, which is why albums
        // rendered as giant circles. maxCrossAxisExtent adds columns as the
        // window grows instead, so a cell keeps its designed size everywhere.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final album = albums[i];
          return AlbumCard(
            album: album,
            onTap: () => Navigator.of(context)
                .push(drillDownRoute(AlbumDetailScreen(album: album))),
          );
        },
      ),
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final artists = appState.catalogArtists;
    final artworkService = context.watch<ArtistArtworkService>();
    if (artists.isEmpty &&
        appState.connectionStatus == ConnectionStatus.connecting) {
      return const ArtistGridSkeleton();
    }
    if (artists.isEmpty) {
      return const EmptyStateView(
        icon: Icons.person_rounded,
        title: 'No artists yet',
        subtitle: 'Connect a Navidrome server to browse its artists here.',
      );
    }
    // Resolve missing pictures in the background (server metadata first,
    // MusicBrainz fallback) — each completion notifies, so cards fade their
    // real images in without a manual refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context
          .read<ArtistArtworkService>()
          .warmUp(artists.map((a) => (id: a.id, name: a.name)).toList());
    });
    return RefreshIndicator(
      color: kBrandColor,
      backgroundColor: kCardColor,
      onRefresh: () => _refreshLibrary(context),
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        // Artists read best as circles; a smaller cell than albums because the
        // name sits under a round shape, which wastes corner space.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.82,
        ),
        itemCount: artists.length,
        itemBuilder: (context, i) {
          final artist = artists[i];
          // An artist with no server artwork gets the resolved picture (or the
          // placeholder until one arrives).
          final resolved = artist.artwork ??
              artworkService.forArtist(id: artist.id, name: artist.name);
          return ArtistCard(
            artist: resolved == null
                ? artist
                : Artist(
                    id: artist.id,
                    name: artist.name,
                    gradientColors: artist.gradientColors,
                    artwork: resolved,
                    albumIds: artist.albumIds,
                    topSongIds: artist.topSongIds,
                  ),
            onTap: () => Navigator.of(context)
                .push(drillDownRoute(ArtistDetailScreen(artist: artist))),
          );
        },
      ),
    );
  }
}

class _GenresTab extends StatelessWidget {
  const _GenresTab();

  static const _gradients = [
    kBrandGradient,
    [Color(0xFFFF32C7), Color(0xFF5642DD)],
    [Color(0xFFFEB722), Color(0xFFFF7A00)],
    [Color(0xFF00C9A7), Color(0xFF0575E6)]
  ];

  @override
  Widget build(BuildContext context) {
    final genres = context.watch<AppState>().catalogGenres.keys.toList();
    if (genres.isEmpty) {
      if (context.watch<AppState>().connectionStatus ==
          ConnectionStatus.connecting) {
        return const GenreGridSkeleton();
      }
      return const EmptyStateView(
        icon: Icons.category_rounded,
        title: 'No genres yet',
        subtitle: 'Connect a Navidrome server to browse by genre here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.7,
      ),
      itemCount: genres.length,
      itemBuilder: (context, i) {
        final genre = genres[i];
        final gradient = _gradients[i % _gradients.length];
        return GestureDetector(
          onTap: () => Navigator.of(context)
              .push(drillDownRoute(_GenreSongsScreen(genre: genre))),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // A big, mostly-transparent mark standing in for genre
                // artwork — rotated and overflowing the corner the way a
                // real cover-art treatment would bleed off the edge.
                Positioned(
                  right: -14,
                  bottom: -14,
                  child: Transform.rotate(
                    angle: -0.3,
                    child: ShuroIcon(glyphForGenre(genre),
                        size: 86, color: Colors.white.withValues(alpha: 0.22)),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(genre,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                // Downloads & cached music as cards (roadmap ask): artwork
                // plus metadata, long-press for multi-select, remove
                // selected/all with confirmation.
                ListView(
                  children: const [DownloadCardsSection()],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GenreSongsScreen extends StatelessWidget {
  final String genre;
  const _GenreSongsScreen({required this.genre});

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<AppState>().songsForGenre(genre);
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
          backgroundColor: kSurfaceColor,
          elevation: 0,
          title: Text(genre,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 16))),
      body: songs.isEmpty
          ? const EmptyStateView(
              icon: Icons.category_rounded, title: 'No songs in this genre yet')
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                  song: songs[i],
                  onTap: () => player.playSong(songs[i], queue: songs)),
            ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(colors: kBrandGradient)),
            child: const Icon(Icons.add_rounded, color: Colors.white),
          ),
          title: Text('New Playlist',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          onTap: () => Navigator.of(context)
              .push(drillDownRoute(const CreatePlaylistScreen())),
        ),
        if (appState.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyStateView(
                icon: Icons.queue_music_rounded,
                title: 'No local playlists yet',
                subtitle:
                    'Tap "New Playlist" above, or add a song to one from its "⋮" menu.'),
          )
        else
          for (final playlist in appState.playlists)
            PlaylistCard(
              playlist: playlist,
              onTap: () => Navigator.of(context).push(
                  drillDownRoute(PlaylistDetailScreen(playlist: playlist))),
            ),
        // Everything the connected server reports, manageable in-app when the
        // user owns it (create/rename/delete/add playing song) — changes land
        // on Navidrome immediately.
        const ServerPlaylistsSection(),
      ],
    );
  }
}

class _LocalTab extends StatelessWidget {
  const _LocalTab();

  Future<void> _addFolder(BuildContext context, AppState appState) async {
    await runLocalImport(context, appState.importLocalFolder);
    await LocalTagEnrichment.enrich(appState);
  }

  Future<void> _addFiles(BuildContext context, AppState appState) async {
    await runLocalImport(context, appState.importLocalFiles);
    await LocalTagEnrichment.enrich(appState);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final songs = appState.localSongs;
    final folders = appState.localFolderPaths;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            children: [
              // Folder is the primary way in — pick a whole music folder
              // once (and again for another one; there's no limit to how
              // many folder sources can be added) rather than hunting down
              // individual files every time.
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: appState.importingLocalFiles
                      ? null
                      : () => _addFolder(context, appState),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.white),
                  icon: appState.importingLocalFiles
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.folder_rounded, size: 18),
                  label: Text(
                      appState.importingLocalFiles
                          ? 'Importing…'
                          : 'Add a music folder',
                      style: GoogleFonts.getFont(currentFontFamily,
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: appState.importingLocalFiles
                      ? null
                      : () => _addFiles(context, appState),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: kDividerColor)),
                  icon: const Icon(Icons.audio_file_rounded, size: 18),
                  label: Text('Add individual files',
                      style: GoogleFonts.getFont(currentFontFamily,
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('SOURCES',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kBrandColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
            ),
          ),
          for (final folder in folders)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.folder_rounded,
                  color: kMutedTextColor, size: 20),
              title: Text(_folderDisplayName(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kMutedTextColor, fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: kMutedTextColor, size: 18),
                tooltip: 'Remove this folder',
                // Confirmed first: this used to remove a folder and every song
                // imported from it on a single tap, with no undo.
                onPressed: () async {
                  final confirmed = await confirmAction(
                    context,
                    title: 'Remove this folder?',
                    message:
                        '"${_folderDisplayName(folder)}" and every song imported from it will be removed from Shuro. Your files on disk are not touched.',
                    confirmLabel: 'Remove',
                  );
                  if (confirmed) appState.removeLocalFolder(folder);
                },
              ),
            ),
          const Divider(
              height: 1, color: kDividerColor, indent: 20, endIndent: 20),
        ],
        Expanded(
          child: songs.isEmpty
              ? const EmptyStateView(
                  icon: Icons.folder_open_rounded,
                  title: 'No local files yet',
                  subtitle:
                      'Add a music folder, or pick individual audio files, to play them here.',
                )
              : ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, i) {
                    final song = songs[i];
                    return Dismissible(
                      key: ValueKey(song.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent),
                      ),
                      // Ask first — a swipe is easy to trigger while scrolling,
                      // and this removes the track from the library.
                      confirmDismiss: (_) => confirmAction(
                        context,
                        title: 'Remove this file?',
                        message:
                            '"${song.title}" will be removed from your local library. The file on disk is not deleted.',
                        confirmLabel: 'Remove',
                      ),
                      onDismissed: (_) => appState.removeLocalSong(song.id),
                      child: SongTile(
                          song: song,
                          onTap: () => player.playSong(song, queue: songs)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

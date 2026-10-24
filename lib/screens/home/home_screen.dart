import 'dart:async';

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/album.dart';
import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../services/rediscovery.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/album_card.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/recent_song_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/shelf_row.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../collection/collection_screens.dart';
import '../downloads/downloads_screen.dart';
import '../favorites/favorites_screen.dart';
import '../search/search_screen.dart';
import '../onboarding/server_setup_screen.dart';
import '../settings/settings_screen.dart';

/// The time-of-day greeting, refreshing itself every minute.
///
/// It used to be a static helper evaluated once per build of a *stateless*
/// screen: a session left open kept the old words, and the ranges had no night
/// band at all — which is how "Good evening" ended up on screen at 11:29 pm.
class _GreetingText extends StatefulWidget {
  const _GreetingText();

  @override
  State<_GreetingText> createState() => _GreetingTextState();
}

class _GreetingTextState extends State<_GreetingText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // One rebuild a minute: cheap, and the greeting is never more than 60
    // seconds behind the clock, even if this screen stays mounted all day.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Four bands with a real night at both ends of the day:
  /// 05–11 morning · 12–17 afternoon · 18–21 evening · 22–04 night.
  static String greetingFor(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    if (hour >= 18 && hour < 22) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    return Text(greetingFor(DateTime.now()),
        style: GoogleFonts.getFont(currentFontFamily,
            color: Colors.white60, fontSize: 13));
  }
}

/// "02. Home" — search, greeting, and the Recently Played / Recently Added /
/// Favorites / Recommended / Recently Played Albums rails. The Mini Player
/// itself lives in AppShell so it persists across tabs.
///
/// Everything here is built so it's obvious what each thing does:
///  - every rail has a working "See all" that opens the full list;
///  - a card ripples when pressed, long-presses into the track's actions, and
///    pausing takes one tap on the card that's playing;
///  - the skeleton appears only while a library is genuinely still loading,
///    never as a fixed delay dressed up as work.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Pull-to-refresh genuinely re-fetches the connected server's library
  /// (AppState.refreshLibrary re-calls the repository and swaps the snapshot
  /// in). A local-only session has no server to refresh against, so the gesture
  /// still completes cleanly but does nothing.
  Future<void> _refresh(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await context.read<AppState>().refreshLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final hasServer = appState.hasServer;

    // Skeleton only when there is truly nothing to show *and* the first library
    // fetch is still in flight. This used to be a 650 ms timer on every visit —
    // content that had already loaded was hidden behind a fake wait, which is
    // exactly what makes an app feel slow for no reason.
    final awaitingLibrary = !appState.hasAnyMusic &&
        appState.connectionStatus == ConnectionStatus.connecting;

    // Server-sourced rails only mean anything once there's a server catalog
    // to source them from — a local-only user sees their own imported files
    // standing in for "Recently Added" instead, and nothing at all in the
    // rails that have no local equivalent (Recommended, Recently Played
    // Albums) rather than ever mixing in a mock catalog.
    final recentlyPlayed =
        hasServer ? appState.recentlyPlayedSongs() : const <Song>[];
    final recentlyAdded = hasServer
        ? appState.recentlyAddedSongs()
        : appState.localSongs.reversed.take(10).toList();
    final favorites = appState.songsByIds(appState.favoriteSongIds.toList());
    // Favourites that have not been played inside the recent window. Local
    // rule only — see Rediscovery for what counts as "recent".
    final rediscover = Rediscovery.forgottenFavourites(
      library: appState.allSongs,
      favouriteIds: appState.favoriteSongIds,
      history: appState.listeningHistory,
    );
    // "Recommended" is Shuro Pulse's real heuristic ranking (affinity +
    // discovery, see ShuroPulse.forYou), not a hardcoded list.
    final recommended =
        hasServer ? ShuroPulse.forYou(appState, limit: 10) : const <Song>[];
    // "Recently Played Albums" — distinct albums behind what's actually
    // been played (see listeningHistory), falling back to newest albums
    // for a freshly-connected server with no play history yet.
    final recentPlayedAlbumIds = <String>{};
    final recentAlbums = <Album>[];
    if (hasServer) {
      for (final songId in appState.listeningHistory) {
        final song = appState.songById(songId);
        if (song == null || song.albumId.isEmpty) continue;
        if (recentPlayedAlbumIds.add(song.albumId)) {
          final album = appState.albumById(song.albumId);
          if (album != null) recentAlbums.add(album);
        }
        if (recentAlbums.length >= 10) break;
      }
      if (recentAlbums.isEmpty)
        recentAlbums.addAll(appState.recentlyAddedAlbums());
    }

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: awaitingLibrary
              ? const _HomeSkeleton(key: ValueKey('skeleton'))
              : _HomeScroll(
                  key: const ValueKey('content'),
                  onRefresh: () => _refresh(context),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _GreetingText(),
                                    Text('Your library',
                                        style: headingFont(
                                            color: kTextColor,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              if (!kIsWeb &&
                                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded,
                                      color: Colors.white70),
                                  tooltip: 'Refresh library',
                                  onPressed: () => _refresh(context),
                                ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded,
                                    color: Colors.white70),
                                tooltip: 'Downloads',
                                onPressed: () => Navigator.of(context).push(
                                    drillDownRoute(const DownloadsScreen())),
                              ),
                              // 44px minimum touch target around an 18px-radius
                              // avatar, which was a 36px hit area before.
                              Semantics(
                                button: true,
                                label: 'Settings and profile',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () => Navigator.of(context).push(
                                      drillDownRoute(const SettingsScreen())),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: kCardColor,
                                      backgroundImage:
                                          appState.userAvatarBytes != null
                                              ? MemoryImage(
                                                  appState.userAvatarBytes!)
                                              : null,
                                      child: appState.userAvatarBytes == null
                                          ? const Icon(Icons.person_rounded,
                                              color: Colors.white70, size: 18)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                          // Desktop drops the inline search box (design doc):
                          // the header field is the one search; the box pushed
                          // the shelves down and duplicated search.
                          child: (kIsWeb ||
                                  !(Platform.isWindows ||
                                      Platform.isLinux ||
                                      Platform.isMacOS))
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 16, 20, 8),
                                  child: Semantics(
                                    button: true,
                                    label: 'Search your library',
                                    child: Material(
                                      color: kCardColor,
                                      borderRadius:
                                          BorderRadius.circular(22),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                        onTap: () => Navigator.of(context)
                                            .push(drillDownRoute(
                                                const SearchScreen())),
                                        child: Container(
                                          height: 44,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.search_rounded,
                                                  color: Colors.white70,
                                                  size: 20),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                    'Search songs, artists, albums...',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.getFont(
                                                        currentFontFamily,
                                                        color:
                                                            Colors.white60,
                                                        fontSize: 13)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : null),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      if (!appState.hasAnyMusic)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: const _GetStartedEmptyState(),
                        )
                      else ...[
                        if (hasServer)
                          _SongRail(
                            title: 'Recently Played',
                            songs: recentlyPlayed,
                            currentSongId: player.currentSong?.id,
                            onTapSong: (song) => player.playOrToggle(song,
                                queue: recentlyPlayed),
                            onSeeAll: () => openSongList(
                                context, 'Recently played', recentlyPlayed),
                          ),
                        _SongRail(
                          title: 'Recently Added',
                          songs: recentlyAdded,
                          currentSongId: player.currentSong?.id,
                          onTapSong: (song) =>
                              player.playOrToggle(song, queue: recentlyAdded),
                          onSeeAll: () => openSongList(
                              context, 'Recently added', recentlyAdded),
                        ),
                        SliverToBoxAdapter(
                          child: SectionHeader(
                            title: 'Favorites',
                            onSeeAll: () => Navigator.of(context)
                                .push(drillDownRoute(const FavoritesScreen())),
                          ),
                        ),
                        if (favorites.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: EmptyStateView(
                                icon: Icons.favorite_border_rounded,
                                title: 'No favorites yet',
                                subtitle:
                                    'Tap the heart on a song and it will show up here.',
                              ),
                            ),
                          )
                        else
                          _SongRail(
                            title: '',
                            songs: favorites,
                            currentSongId: player.currentSong?.id,
                            onTapSong: (song) =>
                                player.playOrToggle(song, queue: favorites),
                            showHeader: false,
                            onSeeAll: null,
                          ),
                        _SongRail(
                          title: 'Rediscover',
                          songs: rediscover,
                          currentSongId: player.currentSong?.id,
                          onTapSong: (song) =>
                              player.playOrToggle(song, queue: rediscover),
                          onSeeAll: rediscover.isEmpty
                              ? null
                              : () => openSongList(
                                  context, 'Rediscover', rediscover),
                        ),
                        if (hasServer) ...[
                          _SongRail(
                            title: 'Recommended for you',
                            songs: recommended,
                            currentSongId: player.currentSong?.id,
                            onTapSong: (song) =>
                                player.playOrToggle(song, queue: recommended),
                            onSeeAll: () => openSongList(
                              context,
                              'Recommended for you',
                              recommended,
                              subtitle: 'Ranked from what you actually play',
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SectionHeader(
                              title: 'Recently Played Albums',
                              onSeeAll: recentAlbums.isEmpty
                                  ? null
                                  : () => Navigator.of(context).push(
                                        drillDownRoute(AlbumGridScreen(
                                            title: 'Recently played albums',
                                            albums: recentAlbums)),
                                      ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: cardRailHeight(context),
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: recentAlbums.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 16),
                                itemBuilder: (context, i) {
                                  final album = recentAlbums[i];
                                  return SizedBox(
                                    width: 150,
                                    child: AlbumCard(
                                      album: album,
                                      onTap: () => Navigator.of(context).push(
                                          drillDownRoute(
                                              AlbumDetailScreen(album: album))),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder shown while a library fetch is genuinely in flight —
/// mirrors the real layout's proportions so the transition into real content
/// doesn't jump around.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        ShimmerBox(width: 90, height: 12),
        SizedBox(height: 8),
        ShimmerBox(width: 140, height: 20),
        SizedBox(height: 20),
        ShimmerBox(width: double.infinity, height: 44, radius: 22),
        SizedBox(height: 24),
        ShimmerBox(width: 130, height: 16),
        SizedBox(height: 12),
        _SkeletonRail(),
        SizedBox(height: 20),
        ShimmerBox(width: 130, height: 16),
        SizedBox(height: 12),
        _SkeletonRail(),
      ],
    );
  }
}

class _SkeletonRail extends StatelessWidget {
  const _SkeletonRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) => const SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 150, height: 150, radius: 14),
              SizedBox(height: 8),
              ShimmerBox(width: 110, height: 12),
              SizedBox(height: 6),
              ShimmerBox(width: 70, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of every rail when there's genuinely nothing to play yet —
/// a local-only user with no imported files, before they've done either of
/// the two things that would give Home something to show.
class _GetStartedEmptyState extends StatelessWidget {
  const _GetStartedEmptyState();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: kBrandGradient)),
              child: const Icon(Icons.music_note_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 20),
            Text('Nothing to play yet',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Add a music folder from this device, or connect a Navidrome server to stream your library.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: appState.importingLocalFiles
                    ? null
                    : () => runLocalImport(context, appState.importLocalFolder),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
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
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: appState.importingLocalFiles
                      ? null
                      : () =>
                          runLocalImport(context, appState.importLocalFiles),
                  child: Text('Add files',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                Text('·',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white54, fontSize: 13)),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(drillDownRoute(const ServerSetupScreen())),
                  child: Text('Connect a server',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal rail of song cards. [onSeeAll] makes the section header's
/// "See all" open the complete list — a rail shows ~2.5 of up to 10 cards, so
/// without it the rest of the list was simply unreachable from Home.
class _SongRail extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final String? currentSongId;
  final ValueChanged<Song> onTapSong;
  final bool showHeader;
  final VoidCallback? onSeeAll;

  const _SongRail({
    required this.title,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
    this.showHeader = true,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) SectionHeader(title: title, onSeeAll: onSeeAll),
          // ShelfRow (phase 3): hover arrows step whole cards so a mouse
          // never needs shift-wheel, and no card stops half-cut.
          ShelfRow(
            height: cardRailHeight(context),
            cardWidth: 150,
            gap: 16,
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final song = songs[i];
              return RecentSongCard(
                song: song,
                isPlaying: song.id == currentSongId,
                onTap: () => onTapSong(song),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


/// Pull-to-refresh belongs to touch. On desktop the same scroll view is
/// wrapped in nothing — refresh lives in an explicit, visible button (and the
/// command palette), because a mouse drag from the top of a window is not a
/// gesture anyone looks for.
/// Desktop width discipline (design doc): Home is designed for 1280 px and
/// extra window width becomes margin. Mobile keeps the full width it has
/// always had.
class _HomeFrame extends StatelessWidget {
  final Widget child;

  const _HomeFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return child;
    }
    return DesktopContentFrame(child: child);
  }
}

class _HomeScroll extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const _HomeScroll({super.key, required this.child, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _HomeFrame(child: child);
    }
    return RefreshIndicator(
      color: kBrandColor,
      backgroundColor: kCardColor,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

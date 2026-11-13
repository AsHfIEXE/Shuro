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
import '../../state/appearance_settings.dart';
import 'home_hero_styles.dart';
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

/// Rebuilds its subtree once a minute so the greeting words on a long-lived
/// Home tab never go stale.
///
/// It used to be a static helper evaluated once per build of a *stateless*
/// screen: a session left open kept the old words, and the ranges had no night
/// band at all — which is how "Good evening" ended up on screen at 11:29 pm.
/// Now a builder: the greeting feeds both the hero eyebrow ("GOOD EVENING ·
/// CONTINUE LISTENING") and the hero title.
class _GreetingBuilder extends StatefulWidget {
  final Widget Function(String greeting) builder;

  const _GreetingBuilder({required this.builder});

  @override
  State<_GreetingBuilder> createState() => _GreetingBuilderState();
}

class _GreetingBuilderState extends State<_GreetingBuilder> {
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
    return widget.builder(greetingFor(DateTime.now()));
  }
}

/// "m:ss" for the hero's "Paused at" line (board copy: "Paused at 1:26").
String _formatClock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// "02. Home" — greeting/continue-listening hero, search, and the Recently
/// Played / Recently Added / Favorites / Recommended / Recently Played Albums
/// rails. The Mini Player itself lives in AppShell so it persists across tabs.
///
/// Everything here is built so it's obvious what each thing does:
///  - the hero picks up the last played track where it was paused (or shows
///    the greeting alone when nothing has ever been played);
///  - every rail has a working "See all" that opens the full list;
///  - a card ripples when pressed, long-presses into the track's actions
///    (right-clicks into the same menu on desktop), and pausing takes one tap
///    on the card that's playing;
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

  /// Hero "Resume playback": if the hero track is still the loaded one, just
  /// un-pause it — the audio engine kept its position across the pause, so
  /// that live position IS the resume point. Anything else plays from the
  /// start: AppState persists no per-song position (the only saved position
  /// belongs to the one-shot session-queue restore in app.dart), so a track
  /// that is no longer loaded has no spot to seek to.
  void _resumePlayback(PlayerController player, Song song, List<Song> queue) {
    if (player.currentSong?.id == song.id) {
      if (!player.isPlaying) player.togglePlayPause();
      return;
    }
    player.playSong(song, queue: queue);
  }

  /// Hero "Shuffle all" — exactly what Library's Shuffle button does: shuffle
  /// the whole playable library and start on the first draw.
  void _shuffleLibrary(PlayerController player, List<Song> library) {
    if (library.isEmpty) return;
    final shuffled = [...library]..shuffle();
    player.playSong(shuffled.first, queue: shuffled);
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

    // --- Continue-listening hero data --------------------------------------
    // The last played track from the app's own history (real plays only, so
    // it works for a local-only library too). With no history the hero hides
    // and the greeting header above stands alone.
    final heroQueue = appState.recentlyPlayedSongs();
    final heroSong = heroQueue.isNotEmpty ? heroQueue.first : null;
    final heroIsCurrent =
        heroSong != null && player.currentSong?.id == heroSong.id;
    final heroPausedAt = (heroIsCurrent &&
            !player.isPlaying &&
            player.position > Duration.zero)
        ? player.position
        : null;
    // Board copy shape: "Aria Vale · Orbit. Paused at 1:26. Pick up where
    // you left off…". The Pulse closer only makes sense with a server behind
    // Shuro Pulse.
    String? heroSubtitle;
    if (heroSong != null) {
      final albumTitle = appState.albumById(heroSong.albumId)?.title;
      final byline = [
        heroSong.artist,
        if (albumTitle != null && albumTitle.isNotEmpty) albumTitle,
      ].join(' · ');
      final tail = hasServer
          ? 'Pick up where you left off, or let Shuro Pulse build something new from what you play.'
          : 'Pick up where you left off, or shuffle your library for something new.';
      heroSubtitle = heroPausedAt != null
          ? '$byline. Paused at ${_formatClock(heroPausedAt)}. $tail'
          : '$byline. $tail';
    }

    // Board covers: 168 px on desktop-width windows, 150 on phones.
    final railCoverWidth = railCardWidth(context);

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
                              // No listening history yet → the greeting is
                              // the whole hero (see _ContinueHero for the
                              // with-history treatment).
                              if (heroSong == null)
                                Expanded(
                                  child: _GreetingBuilder(
                                    builder: (greeting) => Text(greeting,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: headingFont(
                                            color: kTextColor,
                                            fontSize:
                                                MediaQuery.sizeOf(context)
                                                            .width >=
                                                        800
                                                    ? 36
                                                    : 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.9)),
                                  ),
                                )
                              else
                                const Spacer(),
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
                                      Platform.isLinux || Platform.isMacOS))
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
                      if (heroSong != null)
                        SliverToBoxAdapter(
                          child: _GreetingBuilder(
                            builder: (greeting) => _ContinueHero(
                              greeting: greeting,
                              song: heroSong,
                              subtitle: heroSubtitle!,
                              onResume: () =>
                                  _resumePlayback(player, heroSong, heroQueue),
                              onShuffleAll: () =>
                                  _shuffleLibrary(player, appState.allSongs),
                            ),
                          ),
                        ),
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
                            eyebrow: 'JUMP BACK IN',
                            songs: recentlyPlayed,
                            currentSongId: player.currentSong?.id,
                            onTapSong: (song) => player.playOrToggle(song,
                                queue: recentlyPlayed),
                            onSeeAll: () => openSongList(
                                context, 'Recently played', recentlyPlayed),
                            coverWidth: railCoverWidth,
                          ),
                        _SongRail(
                          title: 'Recently Added',
                          songs: recentlyAdded,
                          currentSongId: player.currentSong?.id,
                          onTapSong: (song) =>
                              player.playOrToggle(song, queue: recentlyAdded),
                          onSeeAll: () => openSongList(
                              context, 'Recently added', recentlyAdded),
                          coverWidth: railCoverWidth,
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
                            coverWidth: railCoverWidth,
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
                          coverWidth: railCoverWidth,
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
                            coverWidth: railCoverWidth,
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
                              height: cardRailHeight(context,
                                  coverWidth: railCoverWidth),
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
                                    width: railCoverWidth,
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

/// The continue-listening hero from the redesign board: an ambient brand
/// gradient with soft decorative discs, the greeting eyebrow ("GOOD EVENING ·
/// CONTINUE LISTENING", 12/600 violet-pale) over the greeting as the hero
/// title (36–56/800, responsive), and the last-played track under it with
/// "Resume playback" / "Shuffle all".
///
/// Everything decorative is [IgnorePointer]ed and nothing animates, so the
/// hero adds no motion (reduced-motion rule) and never steals a tap. All
/// colours come from palette tokens — the board's #1B0F3D→#0B0F14 backdrop is
/// rebuilt as a brand wash fading into [kSurfaceColor].
class _ContinueHero extends StatelessWidget {
  final String greeting;
  final Song song;
  final String subtitle;
  final VoidCallback onResume;
  final VoidCallback onShuffleAll;

  const _ContinueHero({
    required this.greeting,
    required this.song,
    required this.subtitle,
    required this.onResume,
    required this.onShuffleAll,
  });

  // Board backdrop: violet (#1B0F3D) fading down into the app surface.
  static final LinearGradient _backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [kBrandColor.withValues(alpha: 0.35), kSurfaceColor],
  );
  // Ambient brand washes behind the discs (pink high-right, cyan low-mid).
  static final RadialGradient _pinkWash = RadialGradient(
    center: const Alignment(0.9, -0.15),
    radius: 1.1,
    colors: [kPinkLight.withValues(alpha: 0.30), Colors.transparent],
  );
  static final RadialGradient _cyanWash = RadialGradient(
    center: const Alignment(0.45, 0.95),
    radius: 1.2,
    colors: [kSecondaryColor.withValues(alpha: 0.22), Colors.transparent],
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final titleSize = wide ? 56.0 : 36.0;
    // The discs shrink on phone-width heroes instead of drowning the copy.
    final discScale = wide ? 1.0 : 0.5;
    final appearance = context.watch<AppearanceSettings>();
    final banner = appearance.homeBanner.resolve();
    final classic = banner == HomeBannerStyle.classic;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: wide ? 400.0 : 0.0),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // --- decorative layer -------------------------------------
              if (!classic)
                Positioned.fill(
                    child: HeroBackdrop(style: banner, song: song, wide: wide)),
              if (classic)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      // Board backdrop first, washes and discs over it.
                      Positioned.fill(
                          child: DecoratedBox(
                              decoration: BoxDecoration(gradient: _backdrop))),
                      Positioned.fill(
                          child: DecoratedBox(
                              decoration:
                                  BoxDecoration(gradient: _pinkWash))),
                      Positioned.fill(
                          child: DecoratedBox(
                              decoration:
                                  BoxDecoration(gradient: _cyanWash))),
                      // The board's three rotated "albums", done as soft
                      // gradient discs (palette tokens only).
                      Positioned(
                        top: wide ? 72 : -34,
                        right: wide ? 96 : -52,
                        child: _HeroDisc(
                          size: 320 * discScale,
                          gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kAccentColor, kBrandColor]),
                          glow: kAccentColor,
                        ),
                      ),
                      Positioned(
                        bottom: wide ? 48 : -30,
                        right: wide ? 320 : -20,
                        child: Transform.rotate(
                          angle: -0.09,
                          child: _HeroDisc(
                            size: 200 * discScale,
                            gradient: const LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [kSecondaryColor, kBrandColor]),
                            glow: kSecondaryColor,
                          ),
                        ),
                      ),
                      // Third disc is desktop-only: on a phone it sat under the
                      // body copy and the buttons.
                      if (wide)
                      Positioned(
                        top: 264,
                        right: 28,
                        child: Transform.rotate(
                          angle: 0.14,
                          child: _HeroDisc(
                            size: 110 * discScale,
                            gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomLeft,
                                colors: [kSecondaryColor, kBrandColor]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // --- content -----------------------------------------------
              Padding(
                padding: wide
                    ? const EdgeInsets.fromLTRB(28, 32, 28, 32)
                    : const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // "GOOD EVENING · CONTINUE LISTENING" — the eyebrow
                        // tracks the same four greeting bands as the title.
                        '${greeting.toUpperCase()} · CONTINUE LISTENING',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kVioletPale,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        greeting,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Board: 56/800 with tight (-0.03em) tracking on
                        // desktop; 36 on phones.
                        style: headingFont(
                            color: kTextColor,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: wide ? -1.6 : -1.1,
                            height: 1.08),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor, fontSize: 15, height: 1.45),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _HeroPill(
                            label: 'Resume playback',
                            icon: Icons.play_arrow_rounded,
                            minWidth: 187,
                            onTap: onResume,
                          ),
                          _HeroPill(
                            label: 'Shuffle all',
                            glass: true,
                            onTap: onShuffleAll,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Tap to try the next banner look (saved in Settings →
              // Appearance → Home banner).
              Positioned(
                top: 10,
                right: 10,
                child: Tooltip(
                  message: 'Change banner style',
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.28),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => appearance.setHomeBanner(
                          (appearance.homeBanner == HomeBannerStyle.auto
                                  ? banner
                                  : appearance.homeBanner)
                              .next),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.palette_outlined,
                            size: 18, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 44 dp pill button from the hero board: brand-gradient fill (with a
/// leading icon) for the primary action, glass + hairline ring for secondary
/// ones. Radius 22 = a full pill at this height.
class _HeroPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// Board width for the primary pill; secondary pills size to their label.
  final double minWidth;
  final bool glass;
  final VoidCallback onTap;

  const _HeroPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.minWidth = 0,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Material(
      color: glass ? kGlass : Colors.transparent,
      shape: glass
          ? RoundedRectangleBorder(
              borderRadius: radius, side: BorderSide(color: kHairline))
          : RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        // The gradient sits on the Ink (under the splash); the glass pill
        // keeps its flat kGlass fill from the Material above.
        decoration: glass
            ? null
            : BoxDecoration(
                gradient: const LinearGradient(colors: kBrandGradient),
                borderRadius: radius),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: icon != null ? 22 : 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: glass ? 14 : 15,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft decorative disc for the hero backdrop. Gradient + shadows only —
/// never interactive, never animated.
class _HeroDisc extends StatelessWidget {
  final double size;
  final Gradient gradient;

  /// Optional outer glow in the disc's own tint.
  final Color? glow;

  const _HeroDisc({required this.size, required this.gradient, this.glow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 48,
              offset: const Offset(0, 24)),
          if (glow != null)
            BoxShadow(
                color: glow!.withValues(alpha: 0.30), blurRadius: 90),
        ],
      ),
    );
  }
}

/// Skeleton placeholder shown while a library fetch is genuinely in flight —
/// mirrors the real layout's proportions (hero first, then a rail) so the
/// transition into real content doesn't jump around.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        ShimmerBox(width: double.infinity, height: 240, radius: 26),
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
  final String? eyebrow;
  final VoidCallback? onSeeAll;

  /// Square cover size (168 on desktop windows, 150 on phones — see
  /// [railCardWidth]); drives the row height and the arrow step too.
  final double coverWidth;

  const _SongRail({
    required this.title,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
    this.showHeader = true,
    this.eyebrow,
    this.onSeeAll,
    required this.coverWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            SectionHeader(title: title, eyebrow: eyebrow, onSeeAll: onSeeAll),
          // ShelfRow (phase 3): hover arrows step whole cards so a mouse
          // never needs shift-wheel, and no card stops half-cut.
          ShelfRow(
            height: cardRailHeight(context, coverWidth: coverWidth),
            cardWidth: coverWidth,
            gap: 16,
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final song = songs[i];
              return RecentSongCard(
                song: song,
                isPlaying: song.id == currentSongId,
                width: coverWidth,
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

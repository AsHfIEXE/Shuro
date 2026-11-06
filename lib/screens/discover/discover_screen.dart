import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/artist.dart';
import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/recent_song_card.dart';
import '../../widgets/recommendation_feedback_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/state_views.dart';
import '../artist/artist_detail_screen.dart';
import 'build_with_shuro_screen.dart';
import 'smart_playlists_screen.dart';

/// "Discover" — the real-functionality tab from the design critique: library-
/// based recommendations rather than a Spotify-style tab added for its own
/// sake. Every section here is backed by ShuroPulse running against this
/// user's own favorites, listening history and library — nothing server-side,
/// nothing fabricated. The stats hero and top-artists row are derived from
/// the same signals: plays tracked, summed listening time and real play
/// counts per artist.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.watch<PlayerController>();

    // The skeleton shows only while there is genuinely nothing to derive
    // recommendations from yet — never a fake timer (a fixed 550 ms wait used
    // to flash a skeleton even with a full library).
    final loading = appState.connectionStatus == ConnectionStatus.connecting &&
        appState.catalogSongs.isEmpty;

    final forYou = ShuroPulse.forYou(appState, limit: 12);
    final rediscover = ShuroPulse.rediscover(appState, limit: 10);
    final freshSongs = ShuroPulse.freshFromYourLibrary(appState, limit: 10);
    final deepCuts = ShuroPulse.deepCuts(appState, limit: 10);
    final becauseYouLike = ShuroPulse.becauseYouLike(appState, artistLimit: 3);

    // Real listening stats: play counts come straight from the tracked
    // history, listening time is the sum of those songs' durations. No
    // time-window claims the data can't back (history has no timestamps).
    final playsByArtist = <String, int>{};
    var listened = Duration.zero;
    for (final id in appState.listeningHistory) {
      final song = appState.songById(id);
      if (song == null) continue;
      listened += song.duration;
      playsByArtist[song.artistId] = (playsByArtist[song.artistId] ?? 0) + 1;
    }
    final topArtists = <({Artist artist, int plays})>[];
    final rankedArtistIds = playsByArtist.keys.toList()
      ..sort((a, b) => playsByArtist[b]!.compareTo(playsByArtist[a]!));
    for (final id in rankedArtistIds.take(6)) {
      final artist = appState.artistById(id);
      if (artist != null) topArtists.add((artist: artist, plays: playsByArtist[id]!));
    }

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: loading
              ? const _DiscoverSkeleton(key: ValueKey('skeleton'))
              : !appState.hasAnyMusic
                  ? const EmptyStateView(
                      key: ValueKey('empty'),
                      icon: Icons.auto_awesome_rounded,
                      title: 'Nothing to recommend yet',
                      subtitle: 'Import some local files or connect a server, and Discover will start building rows from your own listening.',
                    )
                  : CustomScrollView(
                  key: const ValueKey('content'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Entrance(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('Shuro Pulse', style: headingFont(color: kTextColor, fontSize: 22, fontWeight: FontWeight.w600)),
                              ),
                              const Icon(Icons.auto_awesome_rounded, color: kBrandColor, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Entrance(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                          child: Text(
                            'Built from your own library — not a stream of what everyone else is playing.',
                            style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    if (appState.listeningHistory.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Entrance(
                          delay: Entrance.stagger(1),
                          child: _PulseStatsCard(
                            plays: appState.listeningHistory.length,
                            listened: listened,
                            favorites: appState.favoriteSongIds.length,
                            topArtist: topArtists.isEmpty ? null : topArtists.first,
                          ),
                        ),
                      ),
                    if (topArtists.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Entrance(
                          delay: Entrance.stagger(2),
                          child: _TopArtistsRow(artists: topArtists),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Entrance(
                        delay: Entrance.stagger(3),
                        child: _TonightsFlowCard(appState: appState, player: player),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverToBoxAdapter(
                      child: Entrance(
                        delay: Entrance.stagger(4),
                        child: _EntryPointsRow(),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    _DiscoverRail(
                      title: 'For You',
                      songs: forYou,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: forYou),
                      entranceDelay: Entrance.stagger(5),
                    ),
                    for (final row in becauseYouLike)
                      _BecauseYouLikeRow(
                        artistId: row.artistId,
                        artistName: row.artistName,
                        songs: row.songs,
                        currentSongId: player.currentSong?.id,
                        onTapSong: (song) => player.playSong(song, queue: row.songs),
                        entranceDelay: Entrance.stagger(6),
                      ),
                    _DiscoverRail(
                      title: 'Rediscover',
                      songs: rediscover,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: rediscover),
                      emptySubtitle: 'Favorite a few songs and check back here.',
                      entranceDelay: Entrance.stagger(7),
                    ),
                    _DiscoverRail(
                      title: 'Fresh From Your Library',
                      songs: freshSongs,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: freshSongs),
                      entranceDelay: Entrance.stagger(8),
                    ),
                    _DiscoverRail(
                      title: 'Deep Cuts',
                      songs: deepCuts,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: deepCuts),
                      emptySubtitle: 'Play a bit more and deep cuts will start showing up.',
                      entranceDelay: Entrance.stagger(8),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Hero stat card over the motion pass's drifting mesh blobs. Every figure
/// is real: plays tracked, summed listening time of those plays, favorites
/// — computed in [DiscoverScreen]'s build from AppState's own signals.
class _PulseStatsCard extends StatelessWidget {
  const _PulseStatsCard({
    required this.plays,
    required this.listened,
    required this.favorites,
    this.topArtist,
  });

  final int plays;
  final Duration listened;
  final int favorites;
  final ({Artist artist, int plays})? topArtist;

  String get _listenedLabel {
    final hours = listened.inHours;
    final minutes = listened.inMinutes % 60;
    if (hours > 0) return '$hours h ${minutes} m';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: kRaisedColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kHairline),
          ),
          child: Stack(fit: StackFit.expand, children: [
            const MeshBlobs(opacity: 0.13),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('YOUR RECENT LISTENING',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kMuted2,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                      if (topArtist != null)
                        Flexible(
                          child: Text('Most heard: ${topArtist!.artist.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kVioletPale,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Stat(value: '$plays', label: 'Plays tracked')),
                      Expanded(child: _Stat(value: _listenedLabel, label: 'Listening time')),
                      Expanded(child: _Stat(value: '$favorites', label: 'Favorites')),
                    ],
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: headingFont(color: kTextColor, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const SizedBox(height: 4),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Top artists by real play count from the listening history — avatars with
/// their counts, tapping opens the artist page.
class _TopArtistsRow extends StatelessWidget {
  const _TopArtistsRow({required this.artists});

  final List<({Artist artist, int plays})> artists;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOP ARTISTS',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMuted2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 12),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final entry = artists[i];
                return SizedBox(
                  width: 96,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context)
                        .push(drillDownRoute(ArtistDetailScreen(artist: entry.artist))),
                    child: Column(
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ArtworkThumb(
                              gradientColors: entry.artist.gradientColors,
                              artwork: entry.artist.artwork,
                              radius: 999,
                              icon: Icons.person_rounded,
                              iconSize: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(entry.artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${entry.plays} ${entry.plays == 1 ? 'play' : 'plays'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kStatusText, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TonightsFlowCard extends StatelessWidget {
  final AppState appState;
  final PlayerController player;
  const _TonightsFlowCard({required this.appState, required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () {
          final flow = ShuroPulse.tonightsFlow(appState, length: 24);
          if (flow.isEmpty) return;
          player.playSong(flow.first, queue: flow);
        },
        child: Container(
          height: 128,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: kBrandGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Tonight's Flow", style: headingFont(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('A session built to move with you, not just a shuffled list.',
                        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryPointsRow extends StatelessWidget {
  const _EntryPointsRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _EntryCard(
              icon: Icons.playlist_play_rounded,
              title: 'Smart Playlists',
              subtitle: 'Live mixes that update themselves',
              onTap: () => Navigator.of(context).push(drillDownRoute(const SmartPlaylistsScreen())),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _EntryCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Build with Shuro',
              subtitle: 'Describe the mood, get a playlist',
              onTap: () => Navigator.of(context).push(drillDownRoute(const BuildWithShuroScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kCardColor, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kSecondaryColor, size: 20),
            const SizedBox(height: 10),
            Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 11), maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _DiscoverRail extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final String? currentSongId;
  final ValueChanged<Song> onTapSong;
  final String? emptySubtitle;
  final Duration entranceDelay;

  const _DiscoverRail({
    required this.title,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
    this.emptySubtitle,
    this.entranceDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Entrance(
        delay: entranceDelay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final song = songs[i];
                  return RecentSongCard(song: song, isPlaying: song.id == currentSongId, onTap: () => onTapSong(song));
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BecauseYouLikeRow extends StatelessWidget {
  final String artistId;
  final String artistName;
  final List<Song> songs;
  final String? currentSongId;
  final ValueChanged<Song> onTapSong;
  final Duration entranceDelay;

  const _BecauseYouLikeRow({
    required this.artistId,
    required this.artistName,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
    this.entranceDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Entrance(
        delay: entranceDelay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Because you like $artistName',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: headingFont(color: kTextColor, fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  RecommendationFeedbackButton(artistId: artistId, artistName: artistName),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final song = songs[i];
                  return RecentSongCard(song: song, isPlaying: song.id == currentSongId, onTap: () => onTapSong(song));
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const ShimmerBox(width: 110, height: 20),
        const SizedBox(height: 16),
        const ShimmerBox(width: double.infinity, height: 120, radius: 20),
        const SizedBox(height: 20),
        const ShimmerBox(width: 130, height: 16),
        const SizedBox(height: 12),
        const ShimmerBox(width: double.infinity, height: 128, radius: 18),
        const SizedBox(height: 20),
        const ShimmerBox(width: 130, height: 16),
        const SizedBox(height: 12),
        SizedBox(
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
        ),
      ],
    );
  }
}

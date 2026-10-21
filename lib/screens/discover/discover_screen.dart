import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/server_config.dart';
import '../../models/song.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/recent_song_card.dart';
import '../../widgets/recommendation_feedback_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/state_views.dart';
import 'build_with_shuro_screen.dart';
import 'smart_playlists_screen.dart';

/// "Discover" — the real-functionality tab from the design critique: library-
/// based recommendations rather than a Spotify-style tab added for its own
/// sake. Every section here is backed by ShuroPulse running against this
/// user's own favorites, listening history and library — nothing server-side,
/// nothing fabricated.
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
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Discover', style: headingFont(color: kTextColor, fontSize: 22, fontWeight: FontWeight.w600)),
                            ),
                            const Icon(Icons.auto_awesome_rounded, color: kBrandColor, size: 18),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                        child: Text(
                          'Built from your own library — not a stream of what everyone else is playing.',
                          style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _TonightsFlowCard(appState: appState, player: player)),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverToBoxAdapter(child: _EntryPointsRow()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    _DiscoverRail(
                      title: 'For You',
                      songs: forYou,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: forYou),
                    ),
                    for (final row in becauseYouLike)
                      _BecauseYouLikeRow(
                        artistId: row.artistId,
                        artistName: row.artistName,
                        songs: row.songs,
                        currentSongId: player.currentSong?.id,
                        onTapSong: (song) => player.playSong(song, queue: row.songs),
                      ),
                    _DiscoverRail(
                      title: 'Rediscover',
                      songs: rediscover,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: rediscover),
                      emptySubtitle: 'Favorite a few songs and check back here.',
                    ),
                    _DiscoverRail(
                      title: 'Fresh From Your Library',
                      songs: freshSongs,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: freshSongs),
                    ),
                    _DiscoverRail(
                      title: 'Deep Cuts',
                      songs: deepCuts,
                      currentSongId: player.currentSong?.id,
                      onTapSong: (song) => player.playSong(song, queue: deepCuts),
                      emptySubtitle: 'Play a bit more and deep cuts will start showing up.',
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
        ),
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

  const _DiscoverRail({
    required this.title,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
    this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
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
    );
  }
}

class _BecauseYouLikeRow extends StatelessWidget {
  final String artistId;
  final String artistName;
  final List<Song> songs;
  final String? currentSongId;
  final ValueChanged<Song> onTapSong;

  const _BecauseYouLikeRow({
    required this.artistId,
    required this.artistName,
    required this.songs,
    required this.currentSongId,
    required this.onTapSong,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
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

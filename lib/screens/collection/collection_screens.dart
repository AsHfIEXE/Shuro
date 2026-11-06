import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/song.dart';
import '../../services/artist_artwork_service.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/desktop_song_table.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/section_header.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../now_playing/now_playing_screen.dart';

/// A plain, complete list of songs — the destination behind Home's "See all".
///
/// Home's rails are horizontal strips with no room to say "how much more is
/// there" or to scroll past a handful of cards, and tapping a rail's title did
/// nothing at all. Every rail now has a real destination instead of being a
/// dead end.
class SongListScreen extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final String? subtitle;

  const SongListScreen({super.key, required this.title, required this.songs, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              subtitle ?? '${songs.length} song${songs.length == 1 ? '' : 's'}',
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              tooltip: 'Shuffle play',
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white70),
              onPressed: () async {
                if (!player.shuffle) player.toggleShuffle();
                await player.playSong(songs.first, queue: songs);
              },
            ),
          if (songs.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              onPressed: () => player.playSong(songs.first, queue: songs),
            ),
        ],
      ),
      body: songs.isEmpty
          ? const EmptyStateView(icon: Icons.music_note_rounded, title: 'Nothing here yet')
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return SongTile(
                  song: song,
                  highlighted: player.currentSong?.id == song.id,
                  onTap: () => player.playOrToggle(song, queue: songs),
                );
              },
            ),
    );
  }
}

/// The album-grid counterpart to [SongListScreen] — Home's "See all" for
/// recently played albums.
class AlbumGridScreen extends StatelessWidget {
  final String title;
  final List<Album> albums;

  const AlbumGridScreen({super.key, required this.title, required this.albums});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              '${albums.length} album${albums.length == 1 ? '' : 's'}',
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
      body: albums.isEmpty
          ? const EmptyStateView(icon: Icons.album_rounded, title: 'Nothing here yet')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 18,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final album = albums[i];
                return AlbumCard(
                  album: album,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                );
              },
            ),
    );
  }
}

/// Convenience for opening a song list from a rail, so Home doesn't repeat the
/// route construction at every call site.
void openSongList(BuildContext context, String title, List<Song> songs, {String? subtitle}) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SongListScreen(title: title, songs: songs, subtitle: subtitle)),
  );
}

/// Opens Now Playing for whatever is current — used by rail headers so the
/// "play" affordance is discoverable without hunting for the mini player.
void openNowPlaying(BuildContext context, Song? song) {
  if (song == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NowPlayingScreen(initialSong: song)));
}

/// Raised card surface for the desktop table card (boards: #111723) —
/// matches the Library Songs tab's card so the genre table doesn't drift.
const Color _tableCardColor = Color(0xFF111723);

/// "Genre detail" board — a large gradient wash header in the genre's own
/// colour (deterministically derived from its name, so every genre keeps
/// its hue between visits) with the GENRE eyebrow, 36/800 title, the
/// songs/artists/albums/duration line and Play + Shuffle pills; a "Top
/// artists in <genre>" rail; and the songs table (the shared 44 px
/// [DesktopSongTable] on desktop, the familiar [SongTile] list on phones).
///
/// The old genre songs screen's behaviour is all here — tap-to-play with
/// the genre as the queue, per-song menus — plus the board's Play/Shuffle
/// header actions.
class GenreDetailScreen extends StatelessWidget {
  final String genre;
  const GenreDetailScreen({super.key, required this.genre});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final artworkService = context.watch<ArtistArtworkService>();
    final songs = appState.songsForGenre(genre);
    final player = context.read<PlayerController>();
    final desktop = isNativeDesktop;

    // The board's "Top artists in Pop": group the genre's songs by artist.
    final counts = <String, int>{};
    for (final song in songs) {
      counts[song.artistId] = (counts[song.artistId] ?? 0) + 1;
    }
    final artistById = {for (final a in appState.catalogArtists) a.id: a};
    final entries = counts.entries.where((e) => artistById.containsKey(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtists = [
      for (final e in entries.take(8)) (artist: artistById[e.key]!, songs: e.value)
    ];
    final albumCount = songs.map((s) => s.albumId).toSet().length;

    // Resolve MusicBrainz/server portraits for the visible circles, the
    // same way the Library > Artists tab does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.read<ArtistArtworkService>().warmUp(
          [for (final t in topArtists) (id: t.artist.id, name: t.artist.name)]);
    });

    final artistsSection = topArtists.isEmpty
        ? const SizedBox.shrink()
        : _TopArtistsRail(
            genre: genre,
            artists: topArtists
                .map((t) => (
                      artist: t.artist,
                      artwork: t.artist.artwork ??
                          artworkService.forArtist(
                              id: t.artist.id, name: t.artist.name),
                      songCount: t.songs
                    ))
                .toList(),
          );

    // Desktop keeps the board's fixed header + artists rail and lets the
    // table card scroll on its own; phones scroll the whole page with the
    // familiar SongTile rows.
    final desktopTable = songs.isEmpty
        ? const Expanded(
            child: EmptyStateView(
                icon: Icons.category_rounded,
                title: 'No songs in this genre yet'),
          )
        : Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: _tableCardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kHairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: DesktopSongTable(
                  songs: songs,
                  albumTitleOf: (song) => appState
                          .catalogAlbums
                          .where((a) => a.id == song.albumId)
                          .firstOrNull
                          ?.title ??
                      '—',
                  onPlaySong: (song, queue) => player.playSong(song, queue: queue),
                ),
              ),
            ),
          );

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: DesktopContentFrame(
          maxWidth: DesktopTokens.contentTable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    _BackCircleButton(
                        onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Library  /  Genres  /  $genre',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kStatusText, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              Entrance(
                child: _GenreHeader(
                  genre: genre,
                  songCount: songs.length,
                  artistCount: entries.length,
                  albumCount: albumCount,
                  totalDuration: songs.fold<Duration>(
                      Duration.zero, (sum, s) => sum + s.duration),
                  hasSongs: songs.isNotEmpty,
                  onPlay: () => player.playSong(songs.first, queue: songs),
                  onShuffle: () {
                    player.playSong(songs.first, queue: songs);
                    if (!player.shuffle) player.toggleShuffle();
                  },
                ),
              ),
              if (desktop) ...[
                if (topArtists.isNotEmpty)
                  Entrance(
                    delay: const Duration(milliseconds: 60),
                    child: artistsSection,
                  ),
                const SectionHeader(
                    title: 'Songs', padding: EdgeInsets.fromLTRB(16, 16, 16, 4)),
                desktopTable,
              ] else
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      if (topArtists.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Entrance(
                            delay: const Duration(milliseconds: 60),
                            child: artistsSection,
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SectionHeader(
                            title: 'Songs',
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 4)),
                      ),
                      if (songs.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyStateView(
                              icon: Icons.category_rounded,
                              title: 'No songs in this genre yet'),
                        )
                      else
                        SliverList.builder(
                          itemCount: songs.length,
                          itemBuilder: (context, i) => Entrance(
                            delay: Entrance.stagger(i),
                            enabled: i < 12,
                            child: SongTile(
                              song: songs[i],
                              onTap: () =>
                                  player.playSong(songs[i], queue: songs),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Board back affordance: a 36 px circle on white 7%.
class _BackCircleButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _BackCircleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kGlass,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kTextColor, size: 16),
        ),
      ),
    );
  }
}

/// The genre's own wash colour, deterministically derived from its name so
/// "Pop" is always the same hue and no two genres share one by accident
/// (the boards assign each genre a distinct hue the same way).
(Color, Color) _genreWash(String genre) {
  var hash = 0;
  for (final unit in genre.codeUnits) {
    hash = (hash * 31 + unit) % 360;
  }
  final hue = hash.toDouble();
  final base = HSVColor.fromAHSV(1, hue, 0.62, 0.55).toColor();
  final deep = HSVColor.fromAHSV(1, hue, 0.72, 0.34).toColor();
  return (base, deep);
}

/// "N hr M min" for the header meta line (boards: "13 h 42 m").
String _formatTotal(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  if (hours > 0) return minutes > 0 ? '$hours h $minutes m' : '$hours h';
  return '$minutes min';
}

/// h44 pill for the wash header — violet filled for Play, dark glass with a
/// white border for Shuffle (board: surface 25% fill + white 50% border).
class _WashPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _WashPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: filled
                ? (onTap != null
                    ? kBrandColor
                    : kBrandColor.withValues(alpha: 0.4))
                : kSurfaceColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(999),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: filled ? FontWeight.w700 : FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the rotated cover-art tiles bleeding off the header's right side
/// (board: right 60 / 230 / 20). Decorative only — static, so it stands
/// unchanged under reduced motion.
class _WashTile extends StatelessWidget {
  final double size;
  final double radius;
  final List<Color> colors;
  final double angle;

  const _WashTile({
    required this.size,
    required this.radius,
    required this.colors,
    required this.angle,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: size * 0.26,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
      ),
    );
  }
}

/// The board's gradient wash header: eyebrow, 36/800 title, the
/// songs/artists/albums/duration line, Play + Shuffle pills, and the
/// rotated art tiles on the right.
class _GenreHeader extends StatelessWidget {
  final String genre;
  final int songCount;
  final int artistCount;
  final int albumCount;
  final Duration totalDuration;
  final bool hasSongs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const _GenreHeader({
    required this.genre,
    required this.songCount,
    required this.artistCount,
    required this.albumCount,
    required this.totalDuration,
    required this.hasSongs,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isNativeDesktop;
    final (base, deep) = _genreWash(genre);
    final meta = [
      '$songCount song${songCount == 1 ? '' : 's'}',
      '$artistCount artist${artistCount == 1 ? '' : 's'}',
      '$albumCount album${albumCount == 1 ? '' : 's'}',
      if (totalDuration > Duration.zero) _formatTotal(totalDuration),
    ].join('  ·  ');
    final titleStyle = desktop
        ? DesktopTokens.pageTitle(
            headingFont(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800))
        : headingFont(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        height: desktop ? 260.0 : 216.0,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [base, deep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(desktop ? 22 : 16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Board: radial highlight at the top-right corner.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.92, -1.0),
                  radius: 1.15,
                  colors: [
                    Colors.white.withValues(alpha: 0.25),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            if (desktop) ...[
              Positioned(
                  right: 230,
                  top: 40,
                  child: _WashTile(
                      size: 150,
                      radius: 20,
                      colors: [kSecondaryColor, kBrandColor],
                      angle: -0.14)),
              Positioned(
                  right: 20,
                  top: 120,
                  child: _WashTile(
                      size: 130,
                      radius: 20,
                      colors: [kPinkLight, kVioletLight],
                      angle: 0.1)),
              Positioned(
                  right: 60,
                  top: -20,
                  child: _WashTile(
                      size: 170,
                      radius: 22,
                      colors: [kAccentColor, kBrandColor],
                      angle: 0.21)),
            ] else ...[
              Positioned(
                  right: -24,
                  top: -28,
                  child: _WashTile(
                      size: 132,
                      radius: 18,
                      colors: [kAccentColor, kBrandColor],
                      angle: 0.21)),
            ],
            // Left scrim keeps the text on AA-contrast ground.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.7],
                  colors: [
                    kSurfaceColor.withValues(alpha: 0.55),
                    kSurfaceColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  desktop ? 36 : 20, 16, desktop ? 36 : 20, desktop ? 28 : 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GENRE',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.68)),
                  const SizedBox(height: 4),
                  Text(genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle),
                  const SizedBox(height: 4),
                  Text(meta,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 14)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _WashPill(
                          label: 'Play',
                          icon: Icons.play_arrow_rounded,
                          onTap: hasSongs ? onPlay : null,
                          filled: true),
                      _WashPill(
                          label: 'Shuffle',
                          icon: Icons.shuffle_rounded,
                          onTap: hasSongs ? onShuffle : null),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Top artists in <genre>" — a horizontal rail of 120 px circular
/// portraits (96 px on phones) with name + song count; tapping opens the
/// artist's page.
class _TopArtistsRail extends StatelessWidget {
  final String genre;
  final List<({Artist artist, ImageProvider? artwork, int songCount})> artists;

  const _TopArtistsRail({required this.genre, required this.artists});

  @override
  Widget build(BuildContext context) {
    final desktop = isNativeDesktop;
    final avatar = desktop ? 120.0 : 96.0;
    final itemWidth = avatar + 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
            title: 'Top artists in $genre',
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12)),
        SizedBox(
          height: avatar + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final entry = artists[i];
              return Entrance(
                delay: Entrance.stagger(i),
                enabled: i < 12,
                child: SizedBox(
                  width: itemWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).push(drillDownRoute(
                        ArtistDetailScreen(artist: entry.artist))),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                                BorderSide(color: Colors.white24)),
                          ),
                          child: ArtworkThumb(
                            gradientColors: entry.artist.gradientColors,
                            artwork: entry.artwork,
                            size: avatar,
                            radius: 999,
                            icon: Icons.person_rounded,
                            iconSize: avatar * 0.34,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(entry.artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kTextColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text(
                            '${entry.songCount} song${entry.songCount == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kStatusText, fontSize: 12)),
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
}

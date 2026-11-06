import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/artist.dart';
import '../../models/song.dart';
import '../../services/artist_artwork_service.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/album_card.dart';
import '../../widgets/artist_actions_sheet.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/section_header.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';
import '../album/album_detail_screen.dart';

/// "06. Artists > Artist detail" — redesigned per the Artist detail board:
/// a gradient-wash art header (circular portrait over the artist's own
/// palette with the drifting mesh blobs), Play/Shuffle pills + favourite +
/// "more" actions, a numbered Top songs list, and the albums grid as
/// 168 px HoverLift cards.
///
/// Everything from the old screen is kept: MusicBrainz/server artwork
/// resolution, play/shuffle over the top songs, favourite toggle, the
/// actions sheet, drill-down into each album, and the empty states.
class ArtistDetailScreen extends StatelessWidget {
  final Artist artist;
  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final player = context.read<PlayerController>();
    final artworkService = context.watch<ArtistArtworkService>();
    final topSongs = appState.songsByIds(artist.topSongIds);
    final albums = appState.albumsForArtist(artist.id);
    final songCount =
        appState.catalogSongs.where((s) => s.artistId == artist.id).length;
    final isFav = appState.isFavoriteArtist(artist.id);

    // Server artwork first, then the MusicBrainz-resolved picture once the
    // background lookup lands (same pattern as the Library > Artists tab).
    final resolvedArt =
        artist.artwork ?? artworkService.forArtist(id: artist.id, name: artist.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context
          .read<ArtistArtworkService>()
          .warmUp([(id: artist.id, name: artist.name)]);
    });

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: DesktopContentFrame(
          maxWidth: DesktopTokens.contentStandard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _BackCircleButton(onPressed: () => Navigator.of(context).maybePop()),
              ),
              Entrance(
                child: _ArtistHeader(
                  artist: artist,
                  artwork: resolvedArt,
                  songCount: songCount,
                  albumCount: albums.length,
                  isFav: isFav,
                  hasSongs: topSongs.isNotEmpty,
                  onPlay: () => player.playSong(topSongs.first, queue: topSongs),
                  onShuffle: () {
                    player.playSong(topSongs.first, queue: topSongs);
                    if (!player.shuffle) player.toggleShuffle();
                  },
                  onFavorite: () => appState.toggleFavoriteArtist(artist.id),
                  onMore: () => showArtistActionsSheet(context, artist),
                ),
              ),
              Expanded(
                child: topSongs.isEmpty && albums.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.album_rounded,
                        title: 'No albums found',
                        subtitle:
                            "There's nothing from this artist in the connected library right now.",
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          if (topSongs.isNotEmpty) ...[
                            const SectionHeader(
                                title: 'Top songs',
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 4)),
                            for (var i = 0; i < topSongs.length; i++)
                              Entrance(
                                delay: Entrance.stagger(i),
                                enabled: i < 12,
                                child: _TopSongRow(
                                  song: topSongs[i],
                                  index: i,
                                  onTap: () => player.playSong(topSongs[i],
                                      queue: topSongs),
                                ),
                              ),
                          ],
                          const SectionHeader(
                              title: 'Albums',
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 4)),
                          if (albums.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                              child: EmptyStateView(
                                icon: Icons.album_rounded,
                                title: 'No albums found',
                                subtitle:
                                    "This artist's albums aren't in the connected library yet.",
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                // 168 px cells (board) with HoverLift cards;
                                // maxCrossAxisExtent keeps them at that size
                                // on any window instead of stretching.
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 168,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.78,
                                ),
                                itemCount: albums.length,
                                itemBuilder: (context, i) {
                                  final album = albums[i];
                                  return Entrance(
                                    delay: Entrance.stagger(i),
                                    enabled: i < 12,
                                    child: HoverLift(
                                      radius: BorderRadius.circular(12),
                                      child: AlbumCard(
                                        album: album,
                                        onTap: () => Navigator.of(context).push(
                                            drillDownRoute(AlbumDetailScreen(
                                                album: album))),
                                      ),
                                    ),
                                  );
                                },
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

/// h44 action pill — violet filled for Play, glass for Shuffle. On the
/// header's colour wash the glass variant goes dark with a white border
/// (board: rgba surface 25% + white 50%).
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool glass;

  const _ActionPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = kTextColor;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: glass
                ? kSurfaceColor.withValues(alpha: 0.25)
                : (onTap != null
                    ? kBrandColor
                    : kBrandColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
            border: glass
                ? Border.all(color: Colors.white.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40/44 px circular icon action for the wash header (white 10% disc).
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final size = isDesktopPlatform ? 40.0 : 44.0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.white10,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color ?? kTextColor),
        ),
      ),
    );
  }
}

String _formatTrackDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// The artist art header: colour wash + mesh blobs + circular portrait,
/// name and actions. Wide windows lay the portrait beside the text;
/// narrow ones centre the pair.
class _ArtistHeader extends StatelessWidget {
  final Artist artist;
  final ImageProvider? artwork;
  final int songCount;
  final int albumCount;
  final bool isFav;
  final bool hasSongs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  const _ArtistHeader({
    required this.artist,
    required this.artwork,
    required this.songCount,
    required this.albumCount,
    required this.isFav,
    required this.hasSongs,
    required this.onPlay,
    required this.onShuffle,
    required this.onFavorite,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final meta = [
      '$songCount song${songCount == 1 ? '' : 's'}',
      '$albumCount album${albumCount == 1 ? '' : 's'}',
    ].join('  ·  ');

    Widget actions({bool centered = false}) => Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ActionPill(
                label: 'Play',
                icon: Icons.play_arrow_rounded,
                onTap: hasSongs ? onPlay : null),
            _ActionPill(
                label: 'Shuffle',
                icon: Icons.shuffle_rounded,
                onTap: hasSongs ? onShuffle : null,
                glass: true),
            _CircleAction(
              icon:
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              tooltip:
                  isFav ? 'Remove from favorites' : 'Add to favorites',
              color: isFav ? kPinkLight : null,
              onTap: onFavorite,
            ),
            _CircleAction(
              icon: Icons.more_vert_rounded,
              tooltip: 'More options',
              onTap: onMore,
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final portrait = wide ? 160.0 : 120.0;
        final nameStyle = wide
            ? headingFont(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)
            : headingFont(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5);

        Widget portraitWidget() => Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: kSurfaceColor,
                border: Border.fromBorderSide(
                    BorderSide(color: Colors.white24)),
              ),
              child: ArtworkThumb(
                gradientColors: artist.gradientColors,
                artwork: artwork,
                size: portrait,
                radius: 999,
                icon: Icons.person_rounded,
                iconSize: portrait * 0.35,
              ),
            );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(artist.gradientColors.first, kSurfaceColor, 0.25)!,
                Color.lerp(artist.gradientColors.last, kSurfaceColor, 0.55)!,
              ],
            ),
            borderRadius: BorderRadius.circular(wide ? 22 : 16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Decorative drift backdrop (stands still under reduced
              // motion — see MeshBlobs).
              const MeshBlobs(opacity: 0.16),
              // Bottom scrim so white text stays ≥ 4.5:1 over any palette.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: const [0, 0.75],
                    colors: [
                      kSurfaceColor.withValues(alpha: 0.62),
                      kSurfaceColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      portraitWidget(),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ARTIST',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.68)),
                            const SizedBox(height: 4),
                            Text(artist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle),
                            const SizedBox(height: 4),
                            Text(meta,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 13)),
                            const SizedBox(height: 16),
                            actions(),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      portraitWidget(),
                      const SizedBox(height: 12),
                      Text(artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: nameStyle),
                      const SizedBox(height: 4),
                      Text(meta,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 13)),
                      const SizedBox(height: 12),
                      actions(centered: true),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// One numbered Top songs row (44 px desktop / 56 px mobile) with the
/// shared table affordances: tap plays with the top songs as the queue,
/// right-click menu on desktop, actions sheet on touch.
class _TopSongRow extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;

  const _TopSongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    final playing =
        context.select<PlayerController, String?>((p) => p.currentSong?.id) ==
            song.id;
    final titleColor = playing ? kVioletPale : kTextColor;

    return ContextMenuRegion(
      items: songContextMenuItems(context, song),
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.045),
        onLongPress: isDesktopPlatform
            ? null
            : () => showSongActionsSheet(context, song),
        child: SizedBox(
          height: desktop ? DesktopTokens.rowTable : 56.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (playing)
                DecoratedBox(
                  decoration:
                      BoxDecoration(color: kBrandColor.withValues(alpha: 0.14)),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Center(
                        child: Text('${index + 1}',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: playing ? kVioletLight : kStatusText,
                                fontSize: 13)),
                      ),
                    ),
                    ArtworkThumb(
                      gradientColors: song.gradientColors,
                      artwork: song.artwork,
                      size: desktop ? 36.0 : 44.0,
                      radius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: titleColor,
                                  fontSize: 14,
                                  fontWeight: desktop
                                      ? FontWeight.w600
                                      : FontWeight.w500)),
                          if (!desktop)
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kStatusText, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (desktop)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kNavText, fontSize: 13)),
                      ),
                    if (desktop)
                      SizedBox(
                        width: 64,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(_formatTrackDuration(song.duration),
                              style: GoogleFonts.getFont(currentFontFamily,
                                  color: kStatusText, fontSize: 13)),
                        ),
                      ),
                    SizedBox(
                      width: 40,
                      child: Builder(
                        builder: (buttonContext) => InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (isDesktopPlatform) {
                              showSongMenuAtAnchor(
                                  context, song, buttonContext);
                            } else {
                              showSongActionsSheet(context, song);
                            }
                          },
                          child: Icon(Icons.more_vert_rounded,
                              size: 18,
                              color: playing ? kVioletLight : kMuted2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (playing)
                Positioned(
                  left: 0,
                  top: 4,
                  bottom: 4,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: kBrandColor,
                      borderRadius: BorderRadius.circular(2),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/subsonic_api.dart';
import '../../models/album.dart';
import '../../models/song.dart';
import '../../services/download_service.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/album_actions_sheet.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';

/// "05. Albums > Album detail" — redesigned per the Album detail board.
///
/// A cover + meta header (large r12 cover, 800-weight title, pink artist,
/// year · length · quality line) over an action row (violet Play pill,
/// glass Shuffle pill, favourite / download / more circles) and a 44 px
/// track table with staggered entrances. Every action the old screen had
/// — play, shuffle, favourite, album download, the "⋮" actions sheet and
/// the footer's technical-format line — is still here, re-homed into the
/// header.
class AlbumDetailScreen extends StatelessWidget {
  final Album album;
  const AlbumDetailScreen({super.key, required this.album});

  /// Header actions live here so the download circle and the "⋮" sheet
  /// share exactly one code path (the sheet's own Download tile mirrors
  /// this logic; kept for its touch-first audience).
  void _downloadAlbum(BuildContext context, List<Song> songs) {
    final appState = context.read<AppState>();
    final downloads = context.read<DownloadService>();
    if (songs.isEmpty) {
      showErrorSnackBar(context, 'This album has no tracks to download.');
      return;
    }
    if (!appState.canDownloadNow) {
      showErrorSnackBar(
          context, "You're on mobile data and Downloads → Wi-Fi only is on.");
      return;
    }
    final api = context.read<ServerSession>().api;
    if (api == null) {
      showErrorSnackBar(context, 'Connect to a server before downloading.');
      return;
    }
    showSuccessSnackBar(context, 'Queued ${songs.length} tracks for download.');
    unawaited(downloads.enqueueAll([
      for (final song in songs)
        DownloadRequest(song: song, streamUrl: api.downloadUrl(song.id)),
    ]).then((result) {
      if (!context.mounted || result.failed == 0) return;
      showErrorSnackBar(context,
          '${result.failed} track${result.failed == 1 ? '' : 's'} could not be downloaded.');
    }));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final songs = appState.songsForAlbum(album.id);
    final player = context.read<PlayerController>();
    final isFav = appState.isFavoriteAlbum(album.id);

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
              Expanded(
                // One body for every case: the pills disable themselves and
                // the table area shows the old empty state when the album
                // has no tracks (still loading or genuinely empty).
                child: _AlbumBody(
                  album: album,
                  songs: songs,
                  isFav: isFav,
                  onPlay: () => player.playSong(songs.first, queue: songs),
                  onShuffle: () {
                    player.playSong(songs.first, queue: songs);
                    if (!player.shuffle) player.toggleShuffle();
                  },
                  onFavorite: () => appState.toggleFavoriteAlbum(album.id),
                  onDownload: () => _downloadAlbum(context, songs),
                  onMore: () => showAlbumActionsSheet(context, album),
                  onPlaySong: (song) => player.playSong(song, queue: songs),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Board back affordance: a 36 px circle on white 7%, used by every detail
/// screen so the whole app has one back button instead of three.
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

/// h44 action pill — violet filled for Play, glass for Shuffle (boards).
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Glass style (white 6% fill, white 14% border) instead of violet fill.
  final bool glass;

  const _ActionPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = glass ? kTextColor : Colors.white;
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
                ? Colors.white.withValues(alpha: 0.06)
                : (enabled ? kBrandColor : kBrandColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
            border: glass
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
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

/// 40/44 px circular icon action on white 10% — the header's heart,
/// download and "more" affordances.
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
          child: Icon(icon,
              size: 20, color: onTap != null ? (color ?? kTextColor) : kMuted2),
        ),
      ),
    );
  }
}

/// "N hr M min" for the header meta line (kept short like the boards).
String _formatTotal(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  if (hours > 0) return minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
  return '$minutes min';
}

String _formatTrackDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// The cover + meta header. Wide layouts put a 200 px cover beside the
/// title block; narrow ones centre a 132 px cover over the text so the
/// screen still reads at 360 px.
class _AlbumHeader extends StatelessWidget {
  final Album album;
  final List<Song> songs;

  const _AlbumHeader({required this.album, required this.songs});

  @override
  Widget build(BuildContext context) {
    final totalSeconds =
        songs.fold<int>(0, (sum, s) => sum + s.duration.inSeconds);
    final meta = [
      if (album.year > 0) '${album.year}',
      '${songs.length} track${songs.length == 1 ? '' : 's'}',
      if (totalSeconds > 0) _formatTotal(Duration(seconds: totalSeconds)),
    ].join('  ·  ');
    // Technical format info from the album's own scan (kept from the old
    // footer line, now the meta line's tail — only shown when the server
    // actually reported something).
    final audio = songs.isNotEmpty ? songs.first.audioInfo : null;
    final qualityBits = [
      if (audio?.hasBitDepth ?? false) audio!.bitDepthLabel,
      if (audio?.hasSampleRate ?? false) audio!.sampleRateLabel,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final coverSize = wide ? 200.0 : 132.0;
      final titleStyle = wide
          ? headingFont(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)
          : headingFont(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5);

      Widget cover() => ArtworkThumb(
            gradientColors: album.gradientColors,
            artwork: album.artwork,
            size: coverSize,
            radius: 12,
            icon: Icons.album_rounded,
            iconSize: wide ? 56 : 40,
          );

      Widget textBlock({bool centered = false}) => Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (wide)
                Text('ALBUM',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.68)),
              if (wide) const SizedBox(height: 4),
              Text(album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: titleStyle),
              const SizedBox(height: 4),
              Text(album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kPinkPale,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(meta,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 13)),
              if (audio != null && !audio.nothingReported) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (audio.hasFormat)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kBrandColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(audio.formatLabel,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kVioletPale,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    if (qualityBits.isNotEmpty) ...[
                      if (audio.hasFormat) const SizedBox(width: 8),
                      Flexible(
                        child: Text(qualityBits.join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kMuted2, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          );

      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover(),
              const SizedBox(width: 24),
              Expanded(child: textBlock()),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            cover(),
            const SizedBox(height: 16),
            textBlock(centered: true),
          ],
        ),
      );
    });
  }
}

/// The header + action row + track table, kept together so the pills can
/// disable themselves in lockstep with the table's emptiness.
class _AlbumBody extends StatelessWidget {
  final Album album;
  final List<Song> songs;
  final bool isFav;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onFavorite;
  final VoidCallback onDownload;
  final VoidCallback onMore;
  final void Function(Song song) onPlaySong;

  const _AlbumBody({
    required this.album,
    required this.songs,
    required this.isFav,
    required this.onPlay,
    required this.onShuffle,
    required this.onFavorite,
    required this.onDownload,
    required this.onMore,
    required this.onPlaySong,
  });

  @override
  Widget build(BuildContext context) {
    final hasSongs = songs.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Entrance(child: _AlbumHeader(album: album, songs: songs)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
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
                icon: isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                color: isFav ? kPinkLight : null,
                onTap: onFavorite,
              ),
              _CircleAction(
                icon: Icons.download_rounded,
                tooltip: 'Download album',
                onTap: onDownload,
              ),
              _CircleAction(
                icon: Icons.more_vert_rounded,
                tooltip: 'More options',
                onTap: onMore,
              ),
            ],
          ),
        ),
        Expanded(
          child: hasSongs
              ? _DetailTrackTable(
                  songs: songs,
                  onPlaySong: onPlaySong,
                  // Album tracks already name the artist in the header.
                  showArtistColumn: false,
                )
              : const EmptyStateView(
                  icon: Icons.music_off_rounded,
                  title: 'No tracks found',
                  subtitle:
                      "This album has no songs on the connected server right now.",
                ),
        ),
      ],
    );
  }
}

/// Raised card surface for the desktop table card (boards: #111723).
const Color _tableCardColor = Color(0xFF111723);

/// The redesigned detail track table: a 44 px sortable-looking header row
/// over 44 px rows inside a hairline card on desktop; the same rows at
/// 56 px (mobile list rhythm) with the artist as a subtitle on phones.
/// Rows keep every affordance [SongTile] had: tap plays with the album as
/// the queue, right-click opens the desktop menu, long-press opens the
/// actions sheet on touch, and the "⋮" opens the same menu anchored.
class _DetailTrackTable extends StatelessWidget {
  final List<Song> songs;
  final void Function(Song song) onPlaySong;

  /// Show the Artist column on desktop (off for album/artist detail, where
  /// every row shares one artist).
  final bool showArtistColumn;

  const _DetailTrackTable({
    required this.songs,
    required this.onPlaySong,
    this.showArtistColumn = true,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    if (songs.isEmpty) return const SizedBox.shrink();
    final rows = ListView.builder(
      padding: EdgeInsets.only(bottom: desktop ? 8 : 24),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final row = Entrance(
          delay: Entrance.stagger(i),
          // Beyond the first screenful the entrance would only replay on
          // scroll-back; stand those rows down.
          enabled: i < 12,
          child: _TrackRow(
            song: songs[i],
            index: i,
            desktop: desktop,
            showArtist: showArtistColumn || !desktop,
            onTap: () => onPlaySong(songs[i]),
          ),
        );
        return row;
      },
    );

    if (!desktop) return rows;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Container(
        decoration: BoxDecoration(
          color: _tableCardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: DesktopTokens.rowTable,
              child: Row(
                children: [
                  const SizedBox(
                      width: 44,
                      child: Center(
                          child: Text('#',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  const Expanded(
                      flex: 4,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('Title',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  if (showArtistColumn)
                    const Expanded(
                        flex: 3,
                        child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text('Artist',
                                style: TextStyle(
                                    color: kMuted2,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.7)))),
                  const SizedBox(
                      width: 64,
                      child: Center(
                          child: Text('Duration',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Divider(height: 1, color: kHairline),
            Expanded(child: rows),
          ],
        ),
      ),
    );
  }
}

/// One 44 px (desktop) / 56 px (mobile) track row.
class _TrackRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool desktop;
  final bool showArtist;
  final VoidCallback onTap;

  const _TrackRow({
    required this.song,
    required this.index,
    required this.desktop,
    required this.showArtist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, String?>(
            (player) => player.currentSong?.id) ==
        song.id;
    final titleColor = playing ? kVioletPale : kTextColor;

    Widget menuButton() => SizedBox(
          width: 40,
          child: Builder(
            builder: (buttonContext) => InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                // Desktop: the menu anchored to this button; touch: the
                // sheet (same split as SongTile).
                if (isDesktopPlatform) {
                  showSongMenuAtAnchor(context, song, buttonContext);
                } else {
                  showSongActionsSheet(context, song);
                }
              },
              child: Icon(Icons.more_vert_rounded,
                  size: 18, color: playing ? kVioletLight : kMuted2),
            ),
          ),
        );

    final content = desktop
        ? Row(
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
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    ArtworkThumb(
                      gradientColors: song.gradientColors,
                      artwork: song.artwork,
                      size: 36,
                      radius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: titleColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              if (showArtist)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kNavText, fontSize: 13)),
                  ),
                ),
              SizedBox(
                width: 64,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(_formatTrackDuration(song.duration),
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 13)),
                ),
              ),
              menuButton(),
            ],
          )
        : Row(
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
                size: 44,
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
                            fontWeight: FontWeight.w500)),
                    if (showArtist)
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 12)),
                  ],
                ),
              ),
              menuButton(),
            ],
          );

    return ContextMenuRegion(
      items: songContextMenuItems(context, song),
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.045),
        // Hold-to-open stays touch-only; desktop right-clicks.
        onLongPress: isDesktopPlatform
            ? null
            : () => showSongActionsSheet(context, song),
        child: SizedBox(
          height: desktop ? DesktopTokens.rowTable : 56.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Now-playing row: soft violet wash + 3 px brand bar on the
              // left edge, under the hover highlight.
              if (playing)
                DecoratedBox(
                  decoration:
                      BoxDecoration(color: kBrandColor.withValues(alpha: 0.14)),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: content,
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

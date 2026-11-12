import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/subsonic_api.dart';
import '../../models/album.dart';
import '../../models/audio_info.dart';
import '../../models/song.dart';
import '../../services/download_service.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/album_actions_sheet.dart';
import '../../widgets/animated_favorite_icon.dart';
import '../../widgets/album_year_card.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/cache_helpers.dart';
import '../../widgets/click_region.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';
import '../artist/artist_detail_screen.dart';

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
    final cachedIds = offlineSongIds(appState, songs);

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
                  cachedIds: cachedIds,
                  onCacheAlbum: () =>
                      cacheSongsWithFeedback(context, appState, songs, album.title),
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

/// "FLAC 24/96" / "MP3 320 kbps" from the server-reported source info; empty
/// when the server reported nothing.
String _qualityLabel(AudioInfo a) {
  final fmt = a.hasFormat ? a.format!.toUpperCase() : '';
  String detail = '';
  if (a.hasBitDepth && a.hasSampleRate) {
    final khz = a.sampleRateHz! / 1000;
    final k = khz == khz.roundToDouble() ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1);
    detail = '${a.bitDepth}/$k';
  } else if (a.hasSampleRate) {
    detail = a.sampleRateLabel;
  } else if (a.hasBitrate) {
    detail = '${a.bitrateKbps} kbps';
  }
  return [fmt, detail].where((e) => e.isNotEmpty).join(' ');
}

String _thousands(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The cover + meta header. Wide layouts put a 200 px cover beside the
/// title block; narrow ones centre a 132 px cover over the text so the
/// screen still reads at 360 px.
class _AlbumHeader extends StatelessWidget {
  final Album album;
  final List<Song> songs;
  final int cachedCount;

  const _AlbumHeader(
      {required this.album, required this.songs, this.cachedCount = 0});

  @override
  Widget build(BuildContext context) {
    final totalSeconds =
        songs.fold<int>(0, (sum, s) => sum + s.duration.inSeconds);
    // Technical format info from the album's own scan — only shown when the
    // server actually reported something.
    final audio = songs.isNotEmpty ? songs.first.audioInfo : null;
    final quality = audio == null ? '' : _qualityLabel(audio);
    final meta = [
      if (album.year > 0) '${album.year}',
      '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
      if (totalSeconds > 0) _formatTotal(Duration(seconds: totalSeconds)),
      if (quality.isNotEmpty) quality,
      if (songs.isNotEmpty) '$cachedCount of ${songs.length} cached',
    ].join(' · ');
    final artistModel = context.read<AppState>().artistById(album.artistId);

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
                        color: kVioletLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.68)),
              if (wide) const SizedBox(height: 4),
              Text(album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: titleStyle),
              const SizedBox(height: 4),
              ClickRegion(
                onTap: artistModel == null
                    ? null
                    : () => Navigator.of(context).push(
                        drillDownRoute(ArtistDetailScreen(artist: artistModel))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtworkThumb(
                      gradientColors:
                          artistModel?.gradientColors ?? album.gradientColors,
                      artwork: artistModel?.artwork,
                      size: 24,
                      radius: 999,
                      icon: Icons.person_rounded,
                      iconSize: 12,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kVioletLight,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(meta,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 13)),
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
  final Set<String> cachedIds;
  final VoidCallback onCacheAlbum;
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
    required this.cachedIds,
    required this.onCacheAlbum,
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
    final appState = context.watch<AppState>();
    final more = appState.catalogAlbums
        .where((a) => a.artistId == album.artistId && a.id != album.id)
        .toList()
      ..sort((a, b) => b.year.compareTo(a.year));
    final copyright = [
      if (album.year > 0) '© ${album.year} ${album.label ?? album.artist}',
      if (album.added != null)
        'Added ${album.added!.day} ${_months[album.added!.month - 1]} ${album.added!.year}',
    ].join(' · ');
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Entrance(
            child: _AlbumHeader(
                album: album,
                songs: songs,
                cachedCount: cachedIds.length)),
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
              _ActionPill(
                  label: 'Cache album',
                  icon: Icons.download_rounded,
                  onTap: hasSongs ? onCacheAlbum : null,
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
        if (hasSongs)
          _DetailTrackTable(
            songs: songs,
            cachedIds: cachedIds,
            onPlaySong: onPlaySong,
            // Album tracks already name the artist in the header.
            showArtistColumn: false,
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyStateView(
              icon: Icons.music_off_rounded,
              title: 'No tracks found',
              subtitle:
                  "This album has no songs on the connected server right now.",
            ),
          ),
        if (copyright.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(copyright,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMuted2, fontSize: 12)),
          ),
        if (more.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text('MORE BY ${album.artist}'.toUpperCase(),
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMuted2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ),
          SizedBox(
            height: 232,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: more.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) => Entrance(
                delay: Entrance.stagger(i),
                enabled: i < 12,
                child: AlbumYearCard(
                  album: more[i],
                  onTap: () => Navigator.of(context)
                      .push(drillDownRoute(AlbumDetailScreen(album: more[i]))),
                ),
              ),
            ),
          ),
        ],
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
  final Set<String> cachedIds;
  final void Function(Song song) onPlaySong;

  /// Show the Artist column on desktop (off for album/artist detail, where
  /// every row shares one artist).
  final bool showArtistColumn;

  const _DetailTrackTable({
    required this.songs,
    required this.onPlaySong,
    this.cachedIds = const {},
    this.showArtistColumn = true,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    if (songs.isEmpty) return const SizedBox.shrink();
    final rows = ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
            cached: cachedIds.contains(songs[i].id),
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
          mainAxisSize: MainAxisSize.min,
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
                          child: Text('TITLE',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  if (showArtistColumn)
                    const Expanded(
                        flex: 3,
                        child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text('ARTIST',
                                style: TextStyle(
                                    color: kMuted2,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.7)))),
                  SizedBox(
                      width: 84,
                      child: Text('OFFLINE',
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                              color: kMuted2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8))),
                  SizedBox(
                      width: 84,
                      child: Text('PLAYS',
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                              color: kMuted2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8))),
                  SizedBox(
                      width: 120,
                      child: Text('QUALITY',
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                              color: kMuted2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8))),
                  SizedBox(
                      width: 64,
                      child: Text('TIME',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: kMuted2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8))),
                  const SizedBox(width: 36),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Divider(height: 1, color: kHairline),
            rows,
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
  final bool cached;
  final VoidCallback onTap;

  const _TrackRow({
    required this.song,
    required this.index,
    required this.desktop,
    required this.showArtist,
    required this.onTap,
    this.cached = false,
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
                  child: playing
                      ? const PlayingBars(size: 14)
                      : Text('${index + 1}',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 13)),
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
                width: 84,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: cached
                      ? Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: kGreen.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 14, color: kGreenLight),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(song.playCount > 0 ? _thousands(song.playCount) : '—',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kStatusText, fontSize: 13)),
              ),
              SizedBox(
                width: 120,
                child: Text(
                    _qualityLabel(song.audioInfo).isEmpty
                        ? '—'
                        : _qualityLabel(song.audioInfo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 13)),
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
              SizedBox(
                width: 36,
                child: Center(
                  child: AnimatedFavoriteIcon(
                    isFavorite:
                        context.watch<AppState>().isFavoriteSong(song.id),
                    activeColor: kPinkLight,
                    inactiveColor: kMuted2,
                    size: 18,
                    onTap: () =>
                        context.read<AppState>().toggleFavoriteSong(song.id),
                  ),
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

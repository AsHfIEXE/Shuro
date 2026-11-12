import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../backend/subsonic_api.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../services/audio_cache.dart';
import '../../services/download_service.dart';
import '../../services/shuro_pulse.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/add_songs_sheet.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/motion.dart';
import '../../widgets/playlist_collage_art.dart';
import '../../widgets/sheet_scroll.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/state_views.dart';
import '../../widgets/click_region.dart';

/// "08. Playlists > Playlist detail" — redesigned per the Playlist detail
/// board: a collage/cover + meta header with Play/Shuffle pills and the
/// edit actions (add songs, change artwork by tapping the cover, rename,
/// delete), over the redesigned track table with staggered entrances.
///
/// Every feature of the old screen is kept: live re-read of the playlist
/// (renames/edits reflect immediately), smart-playlist track computation,
/// add-songs sheet, artwork picker, rename/delete, swipe-to-remove for
/// regular playlists, and every per-track menu.
class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  Future<void> _changeArtwork(BuildContext context, String playlistId) async {
    final appState = context.read<AppState>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SheetScroll(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.image_rounded, color: Colors.white70),
                title: Text('Choose photo',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 14)),
                onTap: () => Navigator.of(sheetContext).pop('choose'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.grid_view_rounded, color: Colors.white70),
                title: Text('Use auto collage',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 14)),
                onTap: () => Navigator.of(sheetContext).pop('collage'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == 'collage') {
      await appState.clearPlaylistCover(playlistId);
    } else if (choice == 'choose') {
      final bytes = await appState.pickImageBytes();
      if (bytes != null) {
        final saved = await appState.setPlaylistCover(playlistId, bytes);
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not save the cover on this device')));
        }
      }
    }
  }

  Future<void> _rename(BuildContext context, String currentName) async {
    final newName = await promptForRename(context,
        title: 'Rename playlist',
        currentName: currentName,
        hintText: 'Playlist name');
    if (newName != null && context.mounted) {
      context.read<AppState>().renamePlaylist(playlist.id, newName);
    }
  }

  Future<void> _confirmDelete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Delete "$name"?',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 16)),
        content: Text('This can\'t be undone.',
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AppState>().deletePlaylist(playlist.id);
      Navigator.of(context).pop();
    }
  }

  void _showAddSongs(BuildContext context, Playlist live) {
    final appState = context.read<AppState>();
    final existing = {for (final id in live.songIds) id};
    final available = appState.allSongs.where((s) => !existing.contains(s.id)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => AddSongsSheet(
        available: available,
        onAdd: (selected) {
          for (final song in selected) {
            appState.addSongToPlaylist(live.id, song.id);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Re-read the live playlist from AppState so renames/edits reflect immediately.
    final appState = context.watch<AppState>();
    final live = appState.playlists
        .firstWhere((p) => p.id == playlist.id, orElse: () => playlist);
    final songs = live.isSmart
        ? ShuroPulse.smartPlaylistSongs(live.smartPreset!, appState)
        : appState.songsByIds(live.songIds);
    final player = context.read<PlayerController>();

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Board breadcrumb: Library › Playlists › <name>.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(4),
                            child: Text('Library',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kMuted2,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('›',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Color(0xFF6F7890), fontSize: 14)),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(4),
                            child: Text('Playlists',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kMuted2,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('›',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Color(0xFF6F7890), fontSize: 14)),
                          ),
                          Expanded(
                            child: Text(live.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kTextColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    Entrance(
                      child: _PlaylistHeader(
                        playlist: live,
                        songs: songs,
                        onPlay: songs.isEmpty
                            ? null
                            : () => player.playSong(songs.first, queue: songs),
                        onShuffle: songs.isEmpty
                            ? null
                            : () {
                                player.playSong(songs.first, queue: songs);
                                if (!player.shuffle) player.toggleShuffle();
                              },
                        onAddSongs: () => _showAddSongs(context, live),
                        onChangeArtwork: () => _changeArtwork(context, live.id),
                        onRename: () => _rename(context, live.name),
                        onDelete: () => _confirmDelete(context, live.name),
                        onCache: songs.isEmpty
                            ? null
                            : () {
                                final session =
                                    context.read<ServerSession>().api;
                                final api2 = session;
                                if (api2 == null) return;
                                unawaited(context
                                    .read<DownloadService>()
                                    .enqueueAll([
                                      for (final song in songs)
                                        DownloadRequest(
                                            song: song,
                                            streamUrl:
                                                api2.downloadUrl(song.id)),
                                    ]));
                              },
                      ),
                    ),
                    Expanded(
                      child: songs.isEmpty
                          ? const EmptyStateView(
                              icon: Icons.queue_music_rounded,
                              title: 'No songs yet',
                              subtitle:
                                  'Add songs from any track\'s "⋮" menu.')
                          : _DetailTrackTable(
                              songs: songs,
                              onPlaySong: (song) =>
                                  player.playSong(song, queue: songs),
                              // Smart playlists compute their tracks live —
                              // nothing to swipe-remove.
                              wrapRow: live.isSmart
                                  ? null
                                  : (row, index) => Dismissible(
                                        key: ValueKey(
                                            '${live.id}_${songs[index].id}'),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          color: Colors.redAccent
                                              .withValues(alpha: 0.15),
                                          alignment: Alignment.centerRight,
                                          padding:
                                              const EdgeInsets.only(right: 24),
                                          child: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.redAccent),
                                        ),
                                        onDismissed: (_) => context
                                            .read<AppState>()
                                            .removeSongFromPlaylist(
                                                live.id, songs[index].id),
                                        child: row,
                                      ),
                            ),
                    ),
                    if (!live.isSmart)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                        child: _FindSongsRow(
                            onTap: () => _showAddSongs(context, live)),
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
/// Board: dashed "Find songs to add to this playlist" row under the table.
class _FindSongsRow extends StatelessWidget {
  const _FindSongsRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedRRect(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.5), radius: 14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_rounded, size: 18, color: Color(0xFFC4B5FD)),
            const SizedBox(width: 10),
            Text('Find songs to add to this playlist',
                style: GoogleFonts.getFont(currentFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFC4B5FD))),
          ]),
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  _DashedRRect({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}

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

/// 40/44 px circular icon action on white 10%.
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

/// "N hr M min" for the header meta line.
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

/// Collage/cover + meta + actions. Tapping the cover still opens the
/// artwork picker (choose photo / auto collage).
class _PlaylistHeader extends StatelessWidget {
  final Playlist playlist;
  final List<Song> songs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onAddSongs;
  final VoidCallback onChangeArtwork;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onCache;

  const _PlaylistHeader({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddSongs,
    required this.onChangeArtwork,
    required this.onRename,
    required this.onDelete,
    this.onCache,
  });

  @override
  Widget build(BuildContext context) {
    final totalSeconds =
        songs.fold<int>(0, (sum, s) => sum + s.duration.inSeconds);
    final meta = [
      '${songs.length} song${songs.length == 1 ? '' : 's'}',
      if (totalSeconds > 0) _formatTotal(Duration(seconds: totalSeconds)),
    ].join('  ·  ');

    // Board hero: a full-width gradient card (r24) with the 144 px mosaic,
    // the 48/800 title, and the four action pills.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0x8C4C1D95), // #4C1D95 at 55%
              Color(0x331E3A8A), // #1E3A8A at 20%
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(playlist.isSmart ? 'SMART PLAYLIST' : 'PLAYLIST · PRIVATE',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kVioletPale,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: Text(playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headingFont(
                            color: Colors.white,
                            fontSize: wide ? 48 : 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: wide ? -1.2 : -0.75)),
                  ),
                  const SizedBox(width: 12),
                  // Board edit circle (32, white 8%) next to the title.
                  Tooltip(
                    message: 'Rename playlist',
                    child: ClickRegion(
                      onTap: onRename,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 16, color: Color(0xFFB4BBCB)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(meta,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 13)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HeroPill(
                      label: 'Play', icon: Icons.play_arrow_rounded, onTap: onPlay),
                  _HeroPill(
                      label: 'Shuffle',
                      icon: Icons.shuffle_rounded,
                      onTap: onShuffle,
                      glass: true),
                  _HeroPill(
                      label: 'Cache',
                      icon: Icons.download_rounded,
                      onTap: onCache,
                      glass: true),
                  if (!playlist.isSmart)
                    _HeroPill(
                        label: 'Add songs',
                        icon: Icons.add_rounded,
                        onTap: onAddSongs,
                        glass: true),
                ],
              ),
            ],
          );

          final art = Tooltip(
            message: 'Change playlist artwork',
            child: ClickRegion(
              onTap: onChangeArtwork,
              child: SizedBox(
                  width: wide ? 144 : 112,
                  height: wide ? 144 : 112,
                  child: PlaylistCollageArt(playlist: playlist, radius: 20)),
            ),
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                art,
                const SizedBox(width: 28),
                Expanded(child: textBlock),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art,
              const SizedBox(height: 16),
              textBlock,
            ],
          );
        }),
      ),
    );
  }
}

/// Board hero pill: 44 px tall, radius 22; violet filled or white 6% glass
/// with a white 14% border.
class _HeroPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool glass;

  const _HeroPill(
      {required this.label, required this.icon, this.onTap, this.glass = false});

  @override
  Widget build(BuildContext context) {
    final foreground = glass ? kTextColor : Colors.white;
    return Opacity(
      opacity: onTap != null ? 1 : 0.45,
      child: ClickRegion(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:
                glass ? Colors.white.withValues(alpha: 0.06) : kBrandColor,
            borderRadius: BorderRadius.circular(22),
            border: glass
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised card surface for the desktop table card (boards: #111723).
const Color _tableCardColor = Color(0xFF111723);

/// The redesigned playlist track table — 44 px rows in a hairline card on
/// desktop, 56 px rows on phones, with optional per-row wrapping for the
/// swipe-to-remove Dismissible (regular playlists only).
class _DetailTrackTable extends StatelessWidget {
  final List<Song> songs;
  final void Function(Song song) onPlaySong;
  final Widget Function(Widget row, int index)? wrapRow;

  const _DetailTrackTable({
    required this.songs,
    required this.onPlaySong,
    this.wrapRow,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    // Board row subtitle: a green "Cached" tag under the title for tracks
    // whose audio is already on this device.
    final cachedKeys = AudioCache.instance.entries().map((e) => e.songKey).toSet();
    final rows = ListView.builder(
      padding: EdgeInsets.only(bottom: desktop ? 8 : 24),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final row = Entrance(
          delay: Entrance.stagger(i),
          enabled: i < 12,
          child: _TrackRow(
            song: songs[i],
            index: i,
            desktop: desktop,
            cached: cachedKeys.contains(AudioCache.sanitizeId(songs[i].id)),
            onTap: () => onPlaySong(songs[i]),
          ),
        );
        return wrapRow?.call(row, i) ?? row;
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
              height: 42,
              child: const Row(
                children: [
                  SizedBox(
                      width: 44,
                      child: Center(
                          child: Text('#',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  Expanded(
                      flex: 4,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('TITLE',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  Expanded(
                      flex: 3,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('ARTIST',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  Expanded(
                      flex: 3,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('ALBUM',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  SizedBox(
                      width: 64,
                      child: Center(
                          child: Text('TIME',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)))),
                  SizedBox(width: 40),
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

/// One track row: tap plays with the playlist as the queue; right-click
/// opens the desktop menu, long-press the actions sheet on touch, and the
/// "⋮" opens the same menu anchored / as a sheet.
class _TrackRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool desktop;
  final bool cached;
  final VoidCallback onTap;

  const _TrackRow({
    required this.song,
    required this.index,
    required this.desktop,
    this.cached = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing =
        context.select<PlayerController, String?>((p) => p.currentSong?.id) ==
            song.id;
    final titleColor = playing ? kVioletPale : kTextColor;
    final albumTitle =
        context.select<AppState, String?>((a) => a.albumById(song.albumId)?.title);

    Widget menuButton() => SizedBox(
          width: 40,
          child: Builder(
            builder: (buttonContext) => InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
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
                                  fontWeight: FontWeight.w600)),
                          if (cached)
                            Text('Cached',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: const Color(0xFF6EE7B7),
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(albumTitle ?? '',
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
        onLongPress: isDesktopPlatform
            ? null
            : () => showSongActionsSheet(context, song),
        child: SizedBox(
          height: 56.0,
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

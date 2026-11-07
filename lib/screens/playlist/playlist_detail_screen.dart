import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/song.dart';
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

  const _PlaylistHeader({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddSongs,
    required this.onChangeArtwork,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final totalSeconds =
        songs.fold<int>(0, (sum, s) => sum + s.duration.inSeconds);
    final meta = [
      '${songs.length} song${songs.length == 1 ? '' : 's'}',
      if (totalSeconds > 0) _formatTotal(Duration(seconds: totalSeconds)),
      if (playlist.isSmart) 'Smart Playlist',
    ].join('  ·  ');

    Widget cover(double size) => Tooltip(
          message: 'Change playlist artwork',
          child: ClickRegion(
            onTap: onChangeArtwork,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                    width: size,
                    height: size,
                    child: PlaylistCollageArt(playlist: playlist, radius: 12)),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: kBrandColor, shape: BoxShape.circle),
                    child: const Icon(Icons.edit_rounded,
                        color: Colors.white, size: 12),
                  ),
                ),
              ],
            ),
          ),
        );

    Widget actions({bool centered = false}) => Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ActionPill(
                label: 'Play',
                icon: Icons.play_arrow_rounded,
                onTap: onPlay),
            _ActionPill(
                label: 'Shuffle',
                icon: Icons.shuffle_rounded,
                onTap: onShuffle,
                glass: true),
            if (!playlist.isSmart)
              _CircleAction(
                icon: Icons.add_rounded,
                tooltip: 'Add songs',
                onTap: onAddSongs,
              ),
            _CircleAction(
              icon: Icons.edit_rounded,
              tooltip: 'Rename playlist',
              onTap: onRename,
            ),
            _CircleAction(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete playlist',
              color: Colors.redAccent.shade100,
              onTap: onDelete,
            ),
          ],
        );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final titleStyle = wide
          ? headingFont(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.75)
          : headingFont(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5);

      Widget textBlock({bool centered = false}) => Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (wide)
                Text(playlist.isSmart ? 'SMART PLAYLIST' : 'PLAYLIST',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.68)),
              if (wide) const SizedBox(height: 4),
              Text(playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: titleStyle),
              const SizedBox(height: 4),
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
              cover(160),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    textBlock(),
                    const SizedBox(height: 16),
                    actions(),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            cover(112),
            const SizedBox(height: 16),
            textBlock(centered: true),
            const SizedBox(height: 12),
            actions(centered: true),
          ],
        ),
      );
    });
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
              height: DesktopTokens.rowTable,
              child: const Row(
                children: [
                  SizedBox(
                      width: 44,
                      child: Center(
                          child: Text('#',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  Expanded(
                      flex: 4,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('Title',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  Expanded(
                      flex: 3,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('Artist',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
                  SizedBox(
                      width: 64,
                      child: Center(
                          child: Text('Duration',
                              style: TextStyle(
                                  color: kMuted2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7)))),
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
  final VoidCallback onTap;

  const _TrackRow({
    required this.song,
    required this.index,
    required this.desktop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing =
        context.select<PlayerController, String?>((p) => p.currentSong?.id) ==
            song.id;
    final titleColor = playing ? kVioletPale : kTextColor;

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

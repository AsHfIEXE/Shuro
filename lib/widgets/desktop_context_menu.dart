import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/download_state.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../backend/subsonic_api.dart';
import '../screens/album/album_detail_screen.dart';
import '../screens/artist/artist_detail_screen.dart';
import '../screens/now_playing/audio_info_sheet.dart';
import '../services/download_service.dart';
import '../services/server_link.dart';
import '../services/shuro_pulse.dart';
import 'add_to_playlist_sheet.dart';
import 'page_transitions.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';
import 'click_region.dart';

const _menuMotion = AnimationStyle(
  curve: Cubic(0.2, 0.8, 0.2, 1),
  reverseCurve: Cubic(0.2, 0.8, 0.2, 1),
  duration: Duration(milliseconds: 140),
  reverseDuration: Duration(milliseconds: 90),
);

/// Desktop right-click context menu for any surface.
///
/// The entries are real [PopupMenuEntry]s, so [showMenu] can lay them out and
/// nothing silently drops an action. An entry closes the menu itself and then
/// runs its callback; callers must not pop the menu again, or the route
/// underneath would close too.
class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<PopupMenuEntry<String>> items;

  const ContextMenuRegion(
      {super.key, required this.child, required this.items});

  @override
  Widget build(BuildContext context) {
    return ClickRegion(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) {
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (overlay == null) return;
        final position = RelativeRect.fromRect(
          Rect.fromPoints(
            overlay.globalToLocal(details.globalPosition),
            overlay.globalToLocal(details.globalPosition),
          ),
          Offset.zero & overlay.size,
        );
        showMenu<String>(
          context: context,
          position: position,
          color: kCardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          popUpAnimationStyle: _menuMotion,
          items: items,
        );
      },
      child: child,
    );
  }
}

/// Opens a context menu at a global pointer position. Shared by the lyric
/// line and seek bar right-click menus so they use the same motion and card.
Future<void> showContextMenuAt(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<String>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future<void>.value();
  final local = overlay.globalToLocal(globalPosition);
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
        Rect.fromPoints(local, local), Offset.zero & overlay.size),
    color: kCardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    popUpAnimationStyle: _menuMotion,
    items: items,
  );
}

/// A single actionable row in a desktop context menu.
///
/// Tapping closes the menu and then runs [onTap]. That order matters: the
/// action often opens a dialog or changes the page, and it must not race the
/// popup route's own dismissal.
class ContextMenuItem extends PopupMenuEntry<String> {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;

  /// Right-aligned hint (e.g. "Enter"). When [activator] is also set the key
  /// combination triggers this row while the menu is open.
  final String? shortcut;
  final SingleActivator? activator;

  const ContextMenuItem({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.color,
    this.shortcut,
    this.activator,
  });

  @override
  double get height => 36;

  @override
  bool represents(String? value) => false;

  @override
  State<ContextMenuItem> createState() => _ContextMenuItemState();
}

class _ContextMenuItemState extends State<ContextMenuItem> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.activator != null) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (widget.activator != null) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  // The menu is a popup route; while it is mounted every row listens for its
  // own shortcut so Enter / Ctrl+Enter / Alt+Enter / Del work as listed.
  bool _onKey(KeyEvent event) {
    final a = widget.activator;
    if (a == null || event is! KeyDownEvent) return false;
    if (!a.accepts(event, HardwareKeyboard.instance)) return false;
    final nav = Navigator.of(context);
    nav.pop();
    widget.onTap();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Material(
        color: _hovered
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            widget.onTap();
          },
          onHover: (hovering) {
            if (hovering != _hovered) setState(() => _hovered = hovering);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 16, color: widget.color ?? Colors.white60),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: widget.color ?? Colors.white70, fontSize: 13),
                  ),
                ),
                if (widget.shortcut != null) ...[
                  const SizedBox(width: 18),
                  Text(widget.shortcut!,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white30, fontSize: 11.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline separator between groups. Typed as a String entry so it can sit in
/// the same list as [ContextMenuItem] without being filtered out.
class ContextMenuDivider extends PopupMenuEntry<String> {
  const ContextMenuDivider({super.key});

  @override
  double get height => 9;

  @override
  bool represents(String? value) => false;

  @override
  State<ContextMenuDivider> createState() => _ContextMenuDividerState();
}

class _ContextMenuDividerState extends State<ContextMenuDivider> {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 9, thickness: 1, color: Color(0x1AFFFFFF));
}

/// A non-interactive line, used to explain why the actions above are inert
/// (for example a library group with no playable tracks).
class ContextMenuNote extends PopupMenuEntry<String> {
  final String text;

  const ContextMenuNote(this.text, {super.key});

  @override
  double get height => 28;

  @override
  bool represents(String? value) => false;

  @override
  State<ContextMenuNote> createState() => _ContextMenuNoteState();
}

class _ContextMenuNoteState extends State<ContextMenuNote> {
  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.text,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white24, fontSize: 11.5)),
          ),
        ),
      );
}

/// Opens the song menu AT A CONTROL (the row's ellipsis button), centred
/// under it, instead of a phone bottom sheet. Desktop only; mobile callers
/// keep using [showSongActionsSheet].
Future<void> showSongMenuAtAnchor(
  BuildContext context,
  Song song,
  BuildContext anchorContext,
) async {
  // The anchor is the button's own element. It used to be one static
  // GlobalKey shared by every song row, which threw
  // "Multiple widgets used the same GlobalKey" the moment two rows were
  // on screen at once and silently broke the menu anchor.
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final origin = box.localToGlobal(Offset(box.size.width, box.size.height),
      ancestor: overlay);
  await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
    color: kCardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    popUpAnimationStyle: _menuMotion,
    items: songContextMenuItems(context, song),
  );
}

/// Convenience builder for song context menu items (used by right-click on
/// any song row or card in the desktop shell).
List<PopupMenuEntry<String>> songContextMenuItems(
    BuildContext context, Song song) {
  final player = context.read<PlayerController>();
  final appState = context.read<AppState>();
  final isFav = appState.isFavoriteSong(song.id);

  final artist = appState.artistById(song.artistId);
  final album = appState.albumById(song.albumId);
  final downloads = context.read<DownloadService>();
  final downloaded =
      downloads.statusFor(song.id).stage == DownloadStage.downloaded;

  return [
    ContextMenuItem(
      label: 'Play now',
      icon: Icons.play_arrow_rounded,
      shortcut: 'Enter',
      activator: const SingleActivator(LogicalKeyboardKey.enter),
      onTap: () => player.playSong(song),
    ),
    ContextMenuItem(
      label: 'Play next',
      icon: Icons.queue_rounded,
      shortcut: 'Ctrl Enter',
      activator:
          const SingleActivator(LogicalKeyboardKey.enter, control: true),
      onTap: () => player.playNext(song),
    ),
    ContextMenuItem(
      label: 'Add to queue',
      icon: Icons.add_rounded,
      onTap: () => player.addToQueue(song),
    ),
    ContextMenuItem(
      label: 'Add to playlist',
      icon: Icons.playlist_add_rounded,
      onTap: () => showAddToPlaylistSheet(context, song),
    ),
    const ContextMenuDivider(),
    ContextMenuItem(
      label: isFav ? 'Remove from favorites' : 'Favorite',
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      onTap: () => appState.toggleFavoriteSong(song.id),
    ),
    ContextMenuItem(
      label: 'Go to artist',
      icon: Icons.person_outline_rounded,
      onTap: () {
        if (artist == null) {
          showErrorSnackBar(context, 'Artist not found in the library.');
          return;
        }
        pushDrillDownOnce(context, ArtistDetailScreen(artist: artist));
      },
    ),
    ContextMenuItem(
      label: 'Go to album',
      icon: Icons.album_outlined,
      onTap: () {
        if (album == null) {
          showErrorSnackBar(context, 'Album not found in the library.');
          return;
        }
        pushDrillDownOnce(context, AlbumDetailScreen(album: album));
      },
    ),
    ContextMenuItem(
      label: downloaded ? 'Remove download' : 'Download',
      icon: downloaded
          ? Icons.delete_outline_rounded
          : Icons.download_rounded,
      onTap: () => _downloadSongs(context, [song], remove: downloaded),
    ),
    const ContextMenuDivider(),
    ContextMenuItem(
      label: 'Song info',
      icon: Icons.info_outline_rounded,
      shortcut: 'Alt Enter',
      activator: const SingleActivator(LogicalKeyboardKey.enter, alt: true),
      onTap: () => showAudioInfoSheet(context, song),
    ),
  ];
}

/// Starts downloads for [songs] (or removes a single finished one), with the
/// same Wi-Fi-only and server checks the action sheets use.
void _downloadSongs(BuildContext context, List<Song> songs,
    {bool remove = false}) {
  final appState = context.read<AppState>();
  final downloads = context.read<DownloadService>();
  if (remove && songs.length == 1) {
    unawaited(downloads.remove(songs.first.id));
    return;
  }
  if (songs.isEmpty) {
    showErrorSnackBar(context, 'No tracks to download.');
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
  showSuccessSnackBar(context,
      'Queued ${songs.length} track${songs.length == 1 ? '' : 's'} for download.');
  unawaited(downloads.enqueueAll([
    for (final song in songs)
      DownloadRequest(song: song, streamUrl: api.downloadUrl(song.id)),
  ]));
}

/// Play / Shuffle / Add to queue for a group of tracks. When the group is
/// empty the rows stay visible but do nothing, and a note says why.
List<PopupMenuEntry<String>> _bulkSongItems(
  BuildContext context, {
  required List<Song> songs,
  bool withQueue = true,
}) {
  final player = context.read<PlayerController>();
  final hasSongs = songs.isNotEmpty;

  return [
    ContextMenuItem(
      label: 'Play',
      icon: Icons.play_arrow_rounded,
      onTap: hasSongs
          ? () => player.playSong(songs.first, queue: songs)
          : () {},
    ),
    ContextMenuItem(
      label: 'Shuffle',
      icon: Icons.shuffle_rounded,
      onTap: hasSongs
          ? () {
              player.playSong(songs.first, queue: songs);
              if (!player.shuffle) player.toggleShuffle();
            }
          : () {},
    ),
    if (withQueue)
    ContextMenuItem(
      label: 'Add to queue',
      icon: Icons.add_to_queue_rounded,
      onTap: hasSongs
          ? () {
              for (final song in songs) {
                player.addToQueue(song);
              }
            }
          : () {},
    ),
    if (!hasSongs) const ContextMenuNote('No tracks loaded for this item'),
  ];
}

/// Desktop right-click items for an album card.
List<PopupMenuEntry<String>> albumContextMenuItems(
    BuildContext context, Album album) {
  final appState = context.read<AppState>();
  final songs = appState.songsForAlbum(album.id);
  final isFav = appState.isFavoriteAlbum(album.id);

  return [
    ..._bulkSongItems(context, songs: songs, withQueue: false),
    ContextMenuItem(
      label: 'Download album',
      icon: Icons.download_rounded,
      onTap: () => _downloadSongs(context, songs),
    ),
    ContextMenuItem(
      label: 'Share link',
      icon: Icons.link_rounded,
      onTap: () async {
        // No public share URL exists for a private server, so this copies
        // plain text, not a link that opens anywhere.
        await Clipboard.setData(
            ClipboardData(text: '${album.title} by ${album.artist}'));
        if (context.mounted) {
          showSuccessSnackBar(context,
              'No public link for a private server. Copied "${album.title} by ${album.artist}" instead.');
        }
      },
    ),
    const ContextMenuDivider(),
    ContextMenuItem(
      label: isFav ? 'Remove from favourites' : 'Add to favourites',
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      onTap: () => appState.toggleFavoriteAlbum(album.id),
    ),
  ];
}

/// Desktop right-click items for an artist card.
List<PopupMenuEntry<String>> artistContextMenuItems(
    BuildContext context, Artist artist) {
  final appState = context.read<AppState>();
  final songs =
      appState.catalogSongs.where((s) => s.artistId == artist.id).toList();
  final isFav = appState.isFavoriteArtist(artist.id);

  return [
    ..._bulkSongItems(context, songs: songs),
    const ContextMenuDivider(),
    ContextMenuItem(
      label: isFav ? 'Remove from favourites' : 'Add to favourites',
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      onTap: () => appState.toggleFavoriteArtist(artist.id),
    ),
  ];
}

/// Desktop right-click items for a playlist card. Smart playlists compute
/// their live track list the same way the detail screen does, so Play and
/// Shuffle never disagree with what opening the playlist shows.
List<PopupMenuEntry<String>> playlistContextMenuItems(
    BuildContext context, Playlist playlist) {
  final appState = context.read<AppState>();
  final songs = playlist.isSmart
      ? ShuroPulse.smartPlaylistSongs(playlist.smartPreset!, appState)
      : appState.songsByIds(playlist.songIds);

  return [
    ..._bulkSongItems(context, songs: songs),
    if (!playlist.isSmart) ...[
      const ContextMenuDivider(),
      ContextMenuItem(
        label: 'Rename',
        icon: Icons.edit_rounded,
        onTap: () async {
          final newName = await promptForRename(context,
              title: 'Rename playlist',
              currentName: playlist.name,
              hintText: 'Playlist name');
          if (newName != null && context.mounted) {
            context.read<AppState>().renamePlaylist(playlist.id, newName);
          }
        },
      ),
      ContextMenuItem(
        label: 'Delete playlist',
        icon: Icons.delete_rounded,
        color: Colors.redAccent,
        shortcut: 'Del',
        activator: const SingleActivator(LogicalKeyboardKey.delete),
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: kCardColor,
              title: Text('Delete "${playlist.name}"?',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white, fontSize: 15)),
              content: Text('The playlist is removed. Your songs are not affected.',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white60, fontSize: 12.5)),
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
          }
        },
      ),
    ],
  ];
}

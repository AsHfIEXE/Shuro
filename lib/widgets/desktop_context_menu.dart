import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/shuro_pulse.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';

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
    return GestureDetector(
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
          items: items,
        );
      },
      child: child,
    );
  }
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

  const ContextMenuItem({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.color,
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
  GlobalKey anchorKey,
) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final origin = box.localToGlobal(Offset(box.size.width, box.size.height),
      ancestor: overlay);
  await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
    color: kCardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  return [
    ContextMenuItem(
      label: 'Play',
      icon: Icons.play_arrow_rounded,
      onTap: () => player.playSong(song),
    ),
    ContextMenuItem(
      label: 'Play next',
      icon: Icons.queue_rounded,
      onTap: () => player.playNext(song),
    ),
    ContextMenuItem(
      label: 'Add to queue',
      icon: Icons.add_rounded,
      onTap: () => player.addToQueue(song),
    ),
    const ContextMenuDivider(),
    ContextMenuItem(
      label: isFav ? 'Remove from favourites' : 'Add to favourites',
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      onTap: () => appState.toggleFavoriteSong(song.id),
    ),
  ];
}

/// Play / Shuffle / Add to queue for a group of tracks. When the group is
/// empty the rows stay visible but do nothing, and a note says why.
List<PopupMenuEntry<String>> _bulkSongItems(
  BuildContext context, {
  required List<Song> songs,
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
    ..._bulkSongItems(context, songs: songs),
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
        label: 'Delete',
        icon: Icons.delete_rounded,
        color: Colors.redAccent,
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';

/// Desktop right-click context menu for a song.
///
/// Shows a positioned popup menu at the cursor with the same actions as the
/// mobile bottom sheet, presented as a desktop context menu. Usage:
///
/// ```dart
/// ContextMenuRegion(
///   child: SongTile(song),
///   items: [
///     ContextMenuItem('Play', () => player.playSong(song)),
///     ContextMenuItem('Play next', () => player.playNext(song)),
///     ContextMenuSeparator(),
///     ContextMenuItem('Favourite', () => appState.toggleFavoriteSong(song.id)),
///   ],
/// )
/// ```
class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<Widget> items;

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
          items: items.whereType<PopupMenuEntry<String>>().toList(),
        );
      },
      child: child,
    );
  }
}

/// A single item in a desktop context menu.
class ContextMenuItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PopupMenuItem<String>(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 36,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color ?? Colors.white60),
            const SizedBox(width: 10),
          ],
          Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: color ?? Colors.white70, fontSize: 13)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Convenience builder for song context menu items (used by right-click on
/// any song row or card in the desktop shell).
List<Widget> songContextMenuItems(BuildContext context, Song song) {
  final player = context.read<PlayerController>();
  final appState = context.read<AppState>();
  final isFav = appState.isFavoriteSong(song.id);

  return [
    ContextMenuItem(
        label: 'Play',
        icon: Icons.play_arrow_rounded,
        onTap: () {
          Navigator.of(context).pop();
          player.playSong(song);
        }),
    ContextMenuItem(
        label: 'Play next',
        icon: Icons.queue_rounded,
        onTap: () {
          Navigator.of(context).pop();
          player.playNext(song);
        }),
    ContextMenuItem(
        label: 'Add to queue',
        icon: Icons.add_rounded,
        onTap: () {
          Navigator.of(context).pop();
          player.addToQueue(song);
        }),
    const PopupMenuDivider(),
    ContextMenuItem(
      label: isFav ? 'Remove from favourites' : 'Add to favourites',
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      onTap: () {
        Navigator.of(context).pop();
        appState.toggleFavoriteSong(song.id);
      },
    ),
  ];
}

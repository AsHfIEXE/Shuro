import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import '../theme/app_theme.dart';

/// A native-style top menu bar for the desktop shell.
///
/// Every item runs an action that already exists elsewhere (transport,
/// navigation, lyrics, the command palette, quit) — the bar is a keyboardless
/// path to the same commands, not a second implementation of anything.
class DesktopMenuBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onToggleLyrics;
  final VoidCallback onOpenPalette;
  final VoidCallback onQuit;

  const DesktopMenuBar({
    super.key,
    required this.currentIndex,
    required this.onSelectTab,
    required this.onToggleLyrics,
    required this.onOpenPalette,
    required this.onQuit,
  });

  static const _destinations = [
    (Icons.home_rounded, 'Home'),
    (Icons.library_music_rounded, 'Library'),
    (Icons.search_rounded, 'Search'),
    (Icons.auto_awesome_rounded, 'Shuro Pulse'),
    (Icons.favorite_rounded, 'Favorites'),
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();

    final label = GoogleFonts.getFont(
      currentFontFamily,
      color: Colors.white70,
      fontSize: 12,
    );

    MenuItemButton item(String text, VoidCallback onPressed, {String? hint}) {
      return MenuItemButton(
        onPressed: onPressed,
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(160, 34),
        ),
        trailingIcon: hint == null
            ? null
            : Text(hint,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white24, fontSize: 10)),
        child: Text(text, style: label),
      );
    }

    SubmenuButton menu(String title, List<Widget> children) {
      return SubmenuButton(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(kCardColor),
          elevation: const WidgetStatePropertyAll(6),
        ),
        style: SubmenuButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(title,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white70, fontSize: 12)),
        menuChildren: children,
      );
    }

    return Container(
      height: 30,
      color: kCardColor,
      child: Row(
        children: [
          const SizedBox(width: 8),
          menu(
            'Playback',
            [
              item(player.isPlaying ? 'Pause' : 'Play',
                  player.togglePlayPause,
                  hint: 'Space'),
              item('Next track', player.next, hint: 'Ctrl+→'),
              item('Previous track', player.previous, hint: 'Ctrl+←'),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              item(
                  player.shuffle
                      ? 'Turn shuffle off'
                      : 'Turn shuffle on',
                  player.toggleShuffle),
              item('Cycle repeat mode', player.cycleRepeatMode),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              item('Clear queue', player.clearQueue,
                  hint: 'undoable'),
            ],
          ),
          menu(
            'View',
            [
              for (final (index, dest) in _destinations.indexed)
                item(dest.$2, () => onSelectTab(index),
                    hint: 'Ctrl+${index + 1}'),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              item('Lyrics panel', onToggleLyrics, hint: 'Ctrl+L'),
              item('Command palette', onOpenPalette, hint: 'Ctrl+Shift+P'),
            ],
          ),
          menu(
            'Help',
            [
              item('Keyboard shortcuts', () => _showShortcuts(context)),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              item('Quit Shuro', onQuit),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'Shuro',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white24, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _showShortcuts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Keyboard shortcuts',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (keys, action) in [
                ('Space', 'Play / pause'),
                ('Ctrl+→ / Ctrl+←', 'Next / previous track'),
                ('Ctrl+1 … Ctrl+5', 'Home, Library, Search, Shuro Pulse, Favorites'),
                ('Ctrl+K', 'Search'),
                ('Ctrl+L', 'Lyrics panel'),
                ('Ctrl+Shift+P', 'Command palette'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(keys,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kBrandColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(action,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white60, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

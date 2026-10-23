import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'command_palette.dart';
import '../services/desktop_lifecycle.dart';

import '../models/download_state.dart' show PlayerRepeatMode;
import '../models/song.dart';
import '../screens/downloads/downloads_screen.dart';
import '../screens/library/personal_shelves_screen.dart';
import '../screens/library/spoken_library_screen.dart';
import '../screens/now_playing/lyrics_screen.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../screens/now_playing/queue_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/playback_prefs.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';
import 'app_logo.dart';
import 'artwork_thumb.dart';
import 'page_transitions.dart';
import 'shuro_icons.dart';

/// Windows/Linux workspace. All content screens and the mobile shell remain
/// unchanged; this is only the pointer-and-keyboard presentation around them.
class DesktopShell extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelectTab;
  final List<Widget> tabChildren;
  final GlobalKey tabStackKey;

  const DesktopShell({
    super.key,
    required this.currentIndex,
    required this.onSelectTab,
    required this.tabChildren,
    required this.tabStackKey,
  });

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const _tabs = <(IconData, String)>[
    (Icons.home_rounded, 'Home'),
    (Icons.library_music_rounded, 'Library'),
    (Icons.search_rounded, 'Search'),
    (Icons.auto_awesome_rounded, 'Shuro Pulse'),
    (Icons.favorite_rounded, 'Favorites'),
  ];

  bool _sidebarCollapsed = false;

  /// Every page pushed from inside the shell lands on this navigator, so the
  /// sidebar and the player bar stay on screen. Pushing on the root navigator
  /// (the old behaviour) covered the whole window and made the app feel like a
  /// phone app with a desktop skin.
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  NavigatorState? get _contentNav => _contentNavKey.currentState;
  bool _lyricsOpen = false;

  void _openSettings() =>
      _contentNav?.push(drillDownRoute(const SettingsScreen()));

  void _openDownloads() =>
      _contentNav?.push(drillDownRoute(const DownloadsScreen()));

  void _openShelves() =>
      _contentNav?.push(drillDownRoute(const PersonalShelvesScreen()));

  void _openSpoken() =>
      _contentNav?.push(drillDownRoute(const SpokenLibraryScreen()));

  /// Ctrl+Shift+P launcher. Every entry closes over an action that already
  /// exists elsewhere in the shell, so there is exactly one implementation of
  /// each command.
  Future<void> _openCommandPalette() async {
    final player = context.read<PlayerController>();
    final commands = <CommandPaletteEntry>[
      for (final (index, tab) in _tabs.indexed)
        CommandPaletteEntry(
          label: 'Go to ${tab.$2}',
          section: 'Go to',
          hint: 'Ctrl+${index + 1}',
          run: () => widget.onSelectTab(index),
        ),
      CommandPaletteEntry(
        label: player.isPlaying ? 'Pause' : 'Play',
        section: 'Playback',
        hint: 'Space',
        run: player.togglePlayPause,
      ),
      CommandPaletteEntry(
        label: 'Next track',
        section: 'Playback',
        hint: 'Ctrl+\u2192',
        run: player.next,
      ),
      CommandPaletteEntry(
        label: 'Previous track',
        section: 'Playback',
        hint: 'Ctrl+\u2190',
        run: player.previous,
      ),
      CommandPaletteEntry(
        label: player.shuffle ? 'Turn shuffle off' : 'Turn shuffle on',
        section: 'Playback',
        run: player.toggleShuffle,
      ),
      CommandPaletteEntry(
        label: 'Cycle repeat mode (off \u2192 all \u2192 one)',
        section: 'Playback',
        run: player.cycleRepeatMode,
      ),
      CommandPaletteEntry(
        label: _lyricsOpen ? 'Hide lyrics' : 'Show lyrics',
        section: 'View',
        hint: 'Ctrl+L',
        run: _toggleLyrics,
      ),
      CommandPaletteEntry(
        label: _sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
        section: 'View',
        run: _toggleSidebar,
      ),
      if (context.read<AppState>().undoStack.canUndo)
        CommandPaletteEntry(
          label:
              'Undo: ${context.read<AppState>().undoStack.lastLabel}',
          section: 'Edit',
          run: () => context.read<AppState>().undoStack.undo(),
        ),
    ];

    await showCommandPalette(context, commands: commands);
  }

  void _toggleLyrics() {
    // A side inspector only fits beside real content on a roomy desktop.
    // Smaller windows still get the full lyrics screen, never an invisible
    // state change.
    if (MediaQuery.sizeOf(context).width < 1480) {
      Navigator.of(context).push(
        drillDownRoute(
          LyricsScreen(
            initialSong: context.read<PlayerController>().currentSong,
            embedded: false,
          ),
        ),
      );
      return;
    }
    setState(() => _lyricsOpen = !_lyricsOpen);
  }

  /// One shared implementation for every "collapse the sidebar" entry
  /// point — the sidebar's own button, the header quick menu, and the
  /// command palette all call this, so there is a single toggle to change.
  /// True once the user has pressed the collapse control themselves. After
  /// that the window width stops deciding for them.
  bool _sidebarChosenByUser = false;

  void _toggleSidebar() => setState(() {
        _sidebarCollapsed = !_sidebarCollapsed;
        _sidebarChosenByUser = true;
      });

  /// Applies the width rule below the design threshold (1100 px) unless the
  /// user has made an explicit choice.
  void _applyAutoCollapse(double width) {
    if (_sidebarChosenByUser) return;
    final shouldCollapse = width < DesktopTokens.autoCollapseBelow;
    if (shouldCollapse != _sidebarCollapsed) {
      _sidebarCollapsed = shouldCollapse;
    }
  }

  /// CallbackShortcuts reports a matched key as handled even when its callback
  /// does nothing, so the old "skip when typing" check still swallowed the key:
  /// a space typed in the search box never arrived, and Ctrl+Left/Right skipped
  /// tracks instead of moving by word. This runs first (it is nearer the text
  /// field in the focus tree) and tells the framework to stop propagating the
  /// event WITHOUT marking it handled, so the text field gets it.
  KeyEventResult _letTextFieldKeepKeys(FocusNode node, KeyEvent event) {
    final primary = FocusManager.instance.primaryFocus;
    final typing =
        primary?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (!typing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (key == LogicalKeyboardKey.space ||
        (ctrl &&
            (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight))) {
      return KeyEventResult.skipRemainingHandlers;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final song = context.watch<PlayerController>().currentSong;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () {
          final focus = FocusManager.instance.primaryFocus;
          if (focus?.context?.widget is! EditableText) {
            context.read<PlayerController>().togglePlayPause();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            () => context.read<PlayerController>().next(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            () => context.read<PlayerController>().previous(),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            _toggleLyrics,
        const SingleActivator(LogicalKeyboardKey.keyP,
            control: true, shift: true): _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            widget.onSelectTab(2),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            widget.onSelectTab(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            widget.onSelectTab(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            widget.onSelectTab(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            widget.onSelectTab(3),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            widget.onSelectTab(4),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _letTextFieldKeepKeys,
        child: Scaffold(
          backgroundColor: kSurfaceColor,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _applyAutoCollapse(constraints.maxWidth + 240);
                      final showInspector =
                          _lyricsOpen && constraints.maxWidth >= 1240;
                      return Row(
                        children: [
                          _DesktopSidebar(
                            collapsed: _sidebarCollapsed,
                            currentIndex: widget.currentIndex,
                            tabs: _tabs,
                            onCollapse: _toggleSidebar,
                            onSelect: widget.onSelectTab,
                            onShelves: _openShelves,
                            onSpoken: _openSpoken,
                            onDownloads: _openDownloads,
                            onSettings: _openSettings,
                          ),
                          const VerticalDivider(width: 1, color: kDividerColor),
                          Expanded(
                            child: Column(
                              children: [
                                _DesktopHeader(
                                  label: _tabs[widget.currentIndex].$2,
                                  lyricsOpen: _lyricsOpen,
                                  sidebarCollapsed: _sidebarCollapsed,
                                  onSearch: () => widget.onSelectTab(2),
                                  onLyrics: _toggleLyrics,
                                  onOpenPalette: _openCommandPalette,
                                  onCollapseSidebar: _toggleSidebar,
                                ),
                                const Divider(height: 1, color: kDividerColor),
                                Expanded(
                                  // The content navigator: tabs are the
                                  // first route, pushed pages stack on top of
                                  // them, the shell never leaves.
                                  child: Navigator(
                                    key: _contentNavKey,
                                    onGenerateRoute: (settings) =>
                                        MaterialPageRoute<void>(
                                      settings: settings,
                                      builder: (_) => IndexedStack(
                                        key: widget.tabStackKey,
                                        index: widget.currentIndex,
                                        children: widget.tabChildren,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showInspector) ...[
                            const VerticalDivider(
                                width: 1, color: kDividerColor),
                            SizedBox(
                              width: 348,
                              child: _LyricsInspector(song: song),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                _PlayerDock(
                  lyricsOpen: _lyricsOpen,
                  onLyrics: _toggleLyrics,
                  onLyricsPage: () => _contentNav?.push(
                    drillDownRoute(
                        LyricsScreen(initialSong: song, embedded: false)),
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

class _DesktopSidebar extends StatelessWidget {
  final bool collapsed;
  final int currentIndex;
  final List<(IconData, String)> tabs;
  final VoidCallback onCollapse;
  final ValueChanged<int> onSelect;
  final VoidCallback onShelves;
  final VoidCallback onSpoken;
  final VoidCallback onDownloads;
  final VoidCallback onSettings;

  const _DesktopSidebar({
    required this.collapsed,
    required this.currentIndex,
    required this.tabs,
    required this.onCollapse,
    required this.onSelect,
    required this.onShelves,
    required this.onSpoken,
    required this.onDownloads,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed
          ? DesktopTokens.sidebarCollapsed
          : DesktopTokens.sidebarExpanded,
      decoration: const BoxDecoration(color: kCardColor),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    button: true,
                    label: 'Toggle navigation size',
                    child: InkResponse(
                      onTap: onCollapse,
                      radius: 28,
                      child: AppLogo(size: collapsed ? 32 : 38),
                    ),
                  ),
                  if (!collapsed)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Shuro',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white60,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3),
                      ),
                    ),
                ],
              ),
            ),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'YOUR MUSIC',
                    style: GoogleFonts.getFont(
                      currentFontFamily,
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            for (var index = 0; index < tabs.length; index++)
              _RailItem(
                icon: tabs[index].$1,
                label: tabs[index].$2,
                selected: currentIndex == index,
                collapsed: collapsed,
                onTap: () => onSelect(index),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  collapsed ? 14 : 18, 18, collapsed ? 14 : 18, 12),
              child: const Divider(height: 1, color: kDividerColor),
            ),
            _RailItem(
              // A shelf, not the Pulse sparkle: the two destinations were
              // indistinguishable in the collapsed rail.
              icon: Icons.view_agenda_outlined,
              label: 'Personal shelves',
              collapsed: collapsed,
              onTap: onShelves,
            ),
            _RailItem(
              icon: Icons.menu_book_rounded,
              label: 'Books & podcasts',
              collapsed: collapsed,
              onTap: onSpoken,
            ),
            _RailItem(
              icon: Icons.download_rounded,
              label: 'Downloads',
              collapsed: collapsed,
              onTap: onDownloads,
            ),
            const Spacer(),
            _RailItem(
              icon: collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              label: 'Collapse sidebar',
              collapsed: collapsed,
              onTap: onCollapse,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RailItem(
                icon: Icons.settings_rounded,
                label: 'Settings',
                collapsed: collapsed,
                onTap: onSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white60;
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: collapsed ? 10 : 12, vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: Material(
            color: selected
                ? kBrandColor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              focusColor: kBrandColor.withValues(alpha: 0.3),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: SizedBox(
                height: 46,
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: collapsed ? null : 48,
                      child: Icon(
                        icon,
                        size: 20,
                        color: selected ? kBrandColor : color,
                      ),
                    ),
                    if (!collapsed)
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(
                            currentFontFamily,
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                    if (!collapsed) const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  final String label;
  final bool lyricsOpen;
  final bool sidebarCollapsed;
  final VoidCallback onSearch;
  final VoidCallback onLyrics;
  final VoidCallback onOpenPalette;
  final VoidCallback onCollapseSidebar;

  const _DesktopHeader({
    required this.label,
    required this.lyricsOpen,
    required this.sidebarCollapsed,
    required this.onSearch,
    required this.onLyrics,
    required this.onOpenPalette,
    required this.onCollapseSidebar,
  });

  /// One row of the quick menu: icon, label, optional shortcut hint.
  PopupMenuItem<String> _quickItem({
    required String value,
    required IconData icon,
    required String label,
    String? hint,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 12.5),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 12),
            Text(
              hint,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white38, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  /// The same row shape as [_quickItem], for entries that are built inline
  /// (dividers, keybinding reference, quit).
  Widget _quickRowContent(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white, fontSize: 12.5)),
        ],
      );

  /// Keyboard reference, carried over from the retired menu bar so the
  /// shortcut list did not disappear with that row.
  void _showShortcuts(BuildContext context) {
    final rows = <(String, String)>[
      ('Space', 'Play / pause'),
      ('Ctrl+→ / Ctrl+←', 'Next / previous track'),
      ('Ctrl+1 … Ctrl+5', 'Home, Library, Search, Shuro Pulse, Favorites'),
      ('Ctrl+K', 'Search'),
      ('Ctrl+L', 'Lyrics panel'),
      ('Ctrl+Shift+P', 'Command palette'),
      ('Ctrl+B', 'Collapse sidebar'),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCardColor,
        title: Text('Keyboard shortcuts',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, action) in rows)
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
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(
              label,
              style: headingFont(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Open search',
              child: SizedBox(
                width: 220,
                height: 38,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    onTap: onSearch,
                    borderRadius: BorderRadius.circular(11),
                    focusColor: kBrandColor.withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(Icons.search_rounded,
                            size: 19, color: Colors.white54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Search your music',
                            style: GoogleFonts.getFont(
                              currentFontFamily,
                              fontSize: 12.5,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        Text(
                          'Ctrl K',
                          style: GoogleFonts.getFont(
                            currentFontFamily,
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: lyricsOpen ? 'Close lyrics' : 'Open lyrics',
              onPressed: onLyrics,
              icon: Icon(
                Icons.lyrics_rounded,
                color: lyricsOpen ? kBrandColor : Colors.white60,
              ),
            ),
            const SizedBox(width: 4),
            // Compact top-right overflow menu. It is a third entry point to
            // the SAME callbacks the header buttons and menu bar already
            // use (lyrics toggle, palette, sidebar collapse) — never a
            // second implementation of any of them.
            PopupMenuButton<String>(
              tooltip: 'Quick actions',
              color: kCardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              icon: const Icon(Icons.read_more_rounded,
                  color: Colors.white60, size: 22),
              onSelected: (value) {
                switch (value) {
                  case 'lyrics':
                    onLyrics();
                  case 'palette':
                    onOpenPalette();
                  case 'sidebar':
                    onCollapseSidebar();
                  case 'shortcuts':
                    _showShortcuts(context);
                  case 'quit':
                    unawaited(DesktopLifecycle.instance.quitApplication());
                }
              },
              itemBuilder: (context) => [
                _quickItem(
                  value: 'lyrics',
                  icon: Icons.lyrics_rounded,
                  label:
                      lyricsOpen ? 'Hide lyrics panel' : 'Show lyrics panel',
                  hint: 'Ctrl+L',
                ),
                _quickItem(
                  value: 'palette',
                  icon: Icons.terminal_rounded,
                  label: 'Command palette',
                  hint: 'Ctrl+Shift+P',
                ),
                const PopupMenuDivider(),
                _quickItem(
                  value: 'sidebar',
                  icon: Icons.menu_open_rounded,
                  label: sidebarCollapsed
                      ? 'Expand sidebar'
                      : 'Collapse sidebar',
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'shortcuts',
                  child: _quickRowContent(Icons.keyboard_rounded,
                      'Keyboard shortcuts'),
                ),
                PopupMenuItem<String>(
                  value: 'quit',
                  child:
                      _quickRowContent(Icons.power_settings_new_rounded, 'Quit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsInspector extends StatelessWidget {
  final Song? song;

  const _LyricsInspector({required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCardColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Row(
              children: [
                const Icon(Icons.lyrics_rounded, size: 19, color: kBrandColor),
                const SizedBox(width: 8),
                Text(
                  'LYRICS',
                  style: GoogleFonts.getFont(
                    currentFontFamily,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: LyricsScreen(initialSong: song, embedded: true)),
        ],
      ),
    );
  }
}

class _PlayerDock extends StatefulWidget {
  final bool lyricsOpen;
  final VoidCallback onLyrics;
  final VoidCallback onLyricsPage;

  const _PlayerDock({
    required this.lyricsOpen,
    required this.onLyrics,
    required this.onLyricsPage,
  });

  @override
  State<_PlayerDock> createState() => _PlayerDockState();
}

class _PlayerDockState extends State<_PlayerDock> {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final playbackPrefs = context.watch<PlaybackPrefs>();
    final appState = context.watch<AppState>();
    final song = player.currentSong;
    if (song == null) return const _EmptyPlayerDock();

    // Accent rule (design doc): chrome is always brand violet. The per-song
    // gradient is a placeholder derived from the id, so using it here made the
    // play button orange for a teal cover and green for a red one.
    const accent = kBrandColor;
    final favorite = appState.isFavoriteSong(song.id);
    return Container(
      height: DesktopTokens.playerBarHeight,
      decoration: const BoxDecoration(
        color: kCardColor,
        border: Border(top: BorderSide(color: kDividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          return Row(
            children: [
              const SizedBox(width: 18),
              Semantics(
                button: true,
                label: 'Open now playing',
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    drillDownRoute(NowPlayingScreen(initialSong: song)),
                  ),
                  borderRadius: BorderRadius.circular(11),
                  child: ArtworkThumb(
                    gradientColors: song.gradientColors,
                    artwork: song.artwork,
                    size: 62,
                    radius: 11,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              SizedBox(
                width: compact ? 150 : 210,
                child: _TrackIdentity(song: song),
              ),
              if (compact)
                const Spacer()
              else ...[
                const SizedBox(width: 18),
                Expanded(
                    child: _SeekControl(
                        player: player, song: song, accent: accent)),
              ],
              _Transport(player: player, accent: accent, compact: compact),
              if (compact)
                IconButton(
                  tooltip: 'Lyrics',
                  onPressed: widget.onLyricsPage,
                  icon: const Icon(Icons.lyrics_rounded, color: Colors.white54),
                ),
              if (!compact) ...[
                const SizedBox(width: 10),
                _VolumeControl(
                  volume: playbackPrefs.appVolume,
                  enabled: true,
                  onChanged: playbackPrefs.setAppVolume,
                ),
                IconButton(
                  tooltip: 'Lyrics',
                  onPressed: widget.onLyricsPage,
                  icon: const Icon(Icons.lyrics_rounded, color: Colors.white54),
                ),
                IconButton(
                  tooltip: 'Queue',
                  onPressed: () => Navigator.of(context)
                      .push(drillDownRoute(const QueueScreen())),
                  icon: const Icon(Icons.queue_music_rounded,
                      color: Colors.white54),
                ),
                IconButton(
                  tooltip:
                      favorite ? 'Remove from favourites' : 'Add to favourites',
                  onPressed: () => appState.toggleFavoriteSong(song.id),
                  icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite ? accent : Colors.white54,
                  ),
                ),
              ],
              const SizedBox(width: 10),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPlayerDock extends StatelessWidget {
  const _EmptyPlayerDock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesktopTokens.playerBarHeight,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: kCardColor,
        border: Border(top: BorderSide(color: kDividerColor)),
      ),
      child: Text(
        'Nothing playing — choose something from your library.',
        style: GoogleFonts.getFont(
          currentFontFamily,
          color: Colors.white38,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  final Song song;

  const _TrackIdentity({required this.song});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(
            currentFontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(
            currentFontFamily,
            fontSize: 11.5,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  final PlayerController player;
  final Color accent;
  final bool compact;

  const _Transport({
    required this.player,
    required this.accent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          _DockToggleButton(
            tooltip: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
            icon: Icons.shuffle_rounded,
            active: player.shuffle,
            onTap: player.toggleShuffle,
          ),
        IconButton(
          tooltip: 'Previous',
          onPressed: player.previous,
          icon: ShuroIcon(ShuroGlyph.previous, size: 21, color: Colors.white),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Semantics(
            button: true,
            label: player.isPlaying ? 'Pause' : 'Play',
            child: Material(
              color: accent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: player.togglePlayPause,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Center(
                    child: player.isBuffering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : ShuroIcon(
                            player.isPlaying
                                ? ShuroGlyph.pause
                                : ShuroGlyph.play,
                            size: 22,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          onPressed: player.next,
          icon: ShuroIcon(ShuroGlyph.next, size: 21, color: Colors.white),
        ),
        if (!compact)
          _DockToggleButton(
            tooltip: 'Repeat: ${player.repeatMode.name}',
            icon: player.repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            active: player.repeatMode != PlayerRepeatMode.off,
            onTap: player.cycleRepeatMode,
          ),
      ],
    );
  }
}

/// A 40x40 transport toggle (shuffle, repeat) for the dock. The plain
/// IconButtons it replaces were too subtle: their "active" state was a
/// faint icon tint that read as a hover. This keeps the icon always visible
/// and makes the active state unmistakable — brand-colored icon over a soft
/// brand wash plus a small underline bar under the icon. Inactive keeps a
/// neutral icon with the underline slot transparent, so the icon never
/// shifts position between states.
class _DockToggleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _DockToggleButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: active
                ? kBrandColor.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: active ? kBrandColor : Colors.white60,
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color: active ? kBrandColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekControl extends StatelessWidget {
  final PlayerController player;
  final Song song;
  final Color accent;

  const _SeekControl({
    required this.player,
    required this.song,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final active =
        player.currentSong?.id == song.id && player.loadedSongId == song.id;
    final duration = active ? player.duration : song.duration;
    final maximum =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value =
        player.position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
    return Row(
      children: [
        Text(_formatDuration(player.position), style: _timeStyle()),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: accent.withValues(alpha: 0.18),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: value,
              max: maximum,
              onChanged: active
                  ? (next) =>
                      player.seekTo(Duration(milliseconds: next.round()))
                  : null,
            ),
          ),
        ),
        Text(_formatDuration(duration), style: _timeStyle()),
      ],
    );
  }

  TextStyle _timeStyle() => GoogleFonts.getFont(
        currentFontFamily,
        fontSize: 10.5,
        color: Colors.white54,
      );
}

class _VolumeControl extends StatelessWidget {
  final double volume;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _VolumeControl({
    required this.volume,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: Row(
        children: [
          Icon(
            volume == 0
                ? Icons.volume_off_rounded
                : volume < .5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            size: 18,
            color: Colors.white60,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white10,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: volume,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

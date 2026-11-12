import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
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
import '../screens/playlist/playlist_detail_screen.dart';
import '../models/playlist.dart';
import '../services/playback_prefs.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';
import 'app_logo.dart';
import 'playlist_collage_art.dart';
import 'page_transitions.dart';
import 'player_bar_extras.dart';
import 'queue_panel.dart';
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

  /// The runtime type of the page currently on top of the content navigator,
  /// or null when the tabs are showing. Every push dedupes against this: the
  /// reported bug was N clicks stacking N copies of a page, so Back had to be
  /// pressed N times.
  String? _topPage;

  void _openContentPage(Widget page) {
    final nav = _contentNav;
    if (nav == null) return;
    final name = page.runtimeType.toString();
    if (_topPage == name) return; // already showing it — never stack copies
    setState(() => _topPage = name);
    nav.push(drillDownRoute(page)).whenComplete(() {
      if (!mounted) return;
      // Only clear it if no newer page replaced this one while it was open.
      if (_topPage == name) setState(() => _topPage = null);
    });
  }



  /// Sidebar and header navigation: switch the tab AND leave any pushed page
  /// (Settings, Books & podcasts, an album...). Clicking a destination while
  /// on a pushed page used to switch the tab underneath invisibly, so the
  /// click appeared dead.
  void _goToTab(int index) {
    if (_topPage != null) setState(() => _topPage = null);
    _contentNav?.popUntil((route) => route.isFirst);
    widget.onSelectTab(index);
  }

  void _openSettings() => _openContentPage(const SettingsScreen());

  void _openDownloads() => _openContentPage(const DownloadsScreen());

  void _openShelves() => _openContentPage(const PersonalShelvesScreen());

  void _openSpoken() => _openContentPage(const SpokenLibraryScreen());

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
                ValueListenableBuilder<bool>(
                  valueListenable: DesktopLifecycle.customChrome,
                  builder: (context, custom, _) =>
                      custom ? const _WindowTitleBar() : const SizedBox.shrink(),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _applyAutoCollapse(constraints.maxWidth);
                      final showInspector =
                          _lyricsOpen && constraints.maxWidth >= 1240;
                      return Row(
                        children: [
                          _DesktopSidebar(
                            collapsed: _sidebarCollapsed,
                            // A pushed page (Settings, Lyrics, Queue...)
                            // owns the content area, so no tab is lit.
                            currentIndex:
                                _topPage == null ? widget.currentIndex : -1,
                            tabs: _tabs,
                            onCollapse: _toggleSidebar,
                            onSelect: _goToTab,
                            onShelves: _openShelves,
                            onSpoken: _openSpoken,
                            onDownloads: _openDownloads,
                            onSettings: _openSettings,
                            onOpenPlaylist: (playlist) => _openContentPage(
                                PlaylistDetailScreen(playlist: playlist)),
                          ),
                          VerticalDivider(width: 1, color: kHairline),
                          Expanded(
                            child: Column(
                              children: [
                                _DesktopHeader(
                                  lyricsOpen: _lyricsOpen,
                                  sidebarCollapsed: _sidebarCollapsed,
                                  onSearch: () => _goToTab(2),
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
                  onLyricsPage: () => _openContentPage(
                      LyricsScreen(initialSong: song, embedded: false)),
                  onQueuePage: () => unawaited(showQueuePanel(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// App-drawn title bar (Windows/Linux): drag to move, double-click to
/// maximise, and minimise / maximise / close on the right. Close goes through
/// the window manager so the hide-to-tray behaviour still applies.
class _WindowTitleBar extends StatefulWidget {
  const _WindowTitleBar();

  @override
  State<_WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<_WindowTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    try {
      if (_maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: kSidebarColor,
      child: Row(
        children: [
          Expanded(
            // DragToMoveArea already handles drag-to-move and double-click
            // to maximise; a second GestureDetector around it fought for
            // the same pointer and could swallow the drag.
            child: DragToMoveArea(
              child: Container(
                height: 36,
                color: Colors.transparent,
                padding: const EdgeInsets.only(left: 14),
                child: Row(
                  children: [
                    const AppLogo(size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Shuro',
                      style: GoogleFonts.getFont(currentFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kMuted2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CaptionButton(
            tooltip: 'Minimise',
            icon: Icons.remove_rounded,
            onPressed: () async {
              try {
                await windowManager.minimize();
              } catch (_) {}
            },
          ),
          _CaptionButton(
            tooltip: _maximized ? 'Restore' : 'Maximise',
            icon: _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: _maximized ? 13 : 15,
            onPressed: _toggleMaximize,
          ),
          _CaptionButton(
            tooltip: 'Close',
            icon: Icons.close_rounded,
            hoverColor: const Color(0xFFE81123),
            onPressed: () async {
              try {
                await windowManager.close();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 16,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;
  final Color? hoverColor;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 36,
            alignment: Alignment.center,
            color: _hover
                ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.08))
                : Colors.transparent,
            child: Icon(widget.icon,
                size: widget.iconSize,
                color: _hover && widget.hoverColor != null
                    ? Colors.white
                    : kNavText),
          ),
        )),
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
  final void Function(Playlist playlist) onOpenPlaylist;

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
    required this.onOpenPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed
          ? DesktopTokens.sidebarCollapsed
          : DesktopTokens.sidebarExpanded,
      // Board: sidebar surface #0E131B with a 7% white hairline on the right.
      decoration: const BoxDecoration(color: kSidebarColor),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            children: [
              // Everything above the pinned Collapse/Settings pair scrolls
              // when the window is short (it overflowed by 40 px at ~700 px
              // tall, with the playlist list squeezed to nothing).
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Toggle navigation size',
                      child: InkResponse(
                        onTap: onCollapse,
                        radius: 28,
                        child: LogoPop(size: 34, child: const AppLogo(size: 34)),
                      ),
                    ),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Shuro',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kTextColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.28),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Account card (board: r14, #151B26, hairline, 36px gradient
              // avatar, name 14/600, server line 12 muted). Tapping opens
              // Settings, where accounts/servers are actually managed.
              if (!collapsed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AccountCard(appState: appState, onTap: onSettings),
                ),
              if (!collapsed)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 14, 10, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _SidebarSectionLabel('YOUR MUSIC'),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Container(height: 1, color: kHairline),
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
            if (!collapsed) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 18, 4, 8),
                child: _SidebarPlaylistsHeader(),
              ),
              _SidebarPlaylists(
                appState: appState,
                onOpen: onOpenPlaylist,
              ),
            ],
                      ],
                    ),
                  ),
                ),
              ),
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
      ),
    );
  }
}

/// Board "aside" account card: r14, #151B26, hairline, 36 px gradient
/// avatar with the server user's initial, name 14/600 and a live server
/// status line. Opens Settings, where accounts and servers are managed.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.appState, required this.onTap});

  final AppState appState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final server = appState.activeServer;
    final raw = server?.username.trim();
    final displayName = (raw == null || raw.isEmpty) ? 'Listener' : raw;
    final status = appState.hasServer
        ? '${server!.name} \u00b7 connected'
        : appState.isLocalOnly
            ? 'Local files \u00b7 offline'
            : 'No server';
    return Semantics(
      button: true,
      label: 'Account and servers: $displayName, $status',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: Colors.white.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kRaisedColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [kAccentColor, kBrandColor]),
                ),
                child: Text(
                  displayName.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: kTextColor)),
                    const SizedBox(height: 2),
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            fontSize: 12, color: kStatusText)),
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

/// "YOUR MUSIC" / "PLAYLISTS": 12/600, ls 1, #8B93A7.
class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.getFont(currentFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: kMuted2),
    );
  }
}

/// PLAYLISTS header row with the 24x24 "new playlist" action.
class _SidebarPlaylistsHeader extends StatelessWidget {
  const _SidebarPlaylistsHeader();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Row(
      children: [
        const Expanded(child: _SidebarSectionLabel('PLAYLISTS')),
        SizedBox(
          width: 24,
          height: 24,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'New playlist',
            onPressed: () => _promptNewPlaylist(context, appState),
            icon: const Icon(Icons.add_rounded, size: 18, color: kStatusText),
          ),
        ),
      ],
    );
  }
}

Future<void> _promptNewPlaylist(BuildContext context, AppState appState) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kCardColor,
      title: Text('New playlist',
          style: GoogleFonts.getFont(currentFontFamily,
              fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return;
  appState.createPlaylist(name);
}

/// Quick-access playlist list (board: 36-high rows, 22x22 r6 swatch, 14/400
/// #B4BBCB). Expanded sidebar only.
class _SidebarPlaylists extends StatelessWidget {
  const _SidebarPlaylists({required this.appState, required this.onOpen});

  final AppState appState;
  final void Function(Playlist playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    final playlists = appState.playlists;
    if (playlists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 4),
        child: Text('Playlists you create appear here.',
            style: GoogleFonts.getFont(
                currentFontFamily, fontSize: 12, color: kMuted2)),
      );
    }
    return ListView.builder(
      // Sized to its rows: the sidebar scrolls as one unit (see the sidebar).
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Tooltip(
          message: playlist.name,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onOpen(playlist),
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: SizedBox(
                height: 38,
                // 11 px in so the 22 px swatch shares its centre line with the
                // 20 px nav icons above (both at 22 px from the item edge).
                child: Padding(
                  padding: const EdgeInsets.only(left: 11, right: 8),
                  child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: PlaylistCollageArt(playlist: playlist, radius: 6),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: kNavText),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
    // Board: 40-high items, radius 10, icon 20, label 14; active = violet 18%
    // fill + a 3x20 violet bar pinned to the left edge, white 14/600 label;
    // inactive = #B4BBCB 14/500.
    final color = selected ? Colors.white : kNavText;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 0, vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: Material(
            color: selected
                ? kBrandColor.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              focusColor: kBrandColor.withValues(alpha: 0.3),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: SizedBox(
                height: 40,
                child: Stack(
                  children: [
                    if (selected && !collapsed)
                      const Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: VerticalBar(),
                          ),
                        ),
                      ),
                    // Positioned.fill: a bare Row in a Stack is top-aligned
                    // (icon and label sat at the top of the 40 px row).
                    Positioned.fill(
                        child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: collapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: collapsed ? 24 : 44,
                          height: 40,
                          child: Center(
                            child: Icon(
                              icon,
                              size: 20,
                              color: selected ? kBrandColor : color,
                            ),
                          ),
                        ),
                        if (!collapsed)
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  // Even leading puts the glyphs on the same
                                  // centre line as the 20 px icon.
                                  textHeightBehavior: const TextHeightBehavior(
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                  ),
                                  style: GoogleFonts.getFont(
                                    currentFontFamily,
                                    fontSize: 14,
                                    height: 1.2,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!collapsed) const SizedBox(width: 12),
                      ],
                    )),
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

/// The active item's 3x20 violet indicator bar (board: left 0, top/bottom 10).
class VerticalBar extends StatelessWidget {
  const VerticalBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 20,
      decoration: BoxDecoration(
        color: kBrandColor,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  final bool lyricsOpen;
  final bool sidebarCollapsed;
  final VoidCallback onSearch;
  final VoidCallback onLyrics;
  final VoidCallback onOpenPalette;
  final VoidCallback onCollapseSidebar;

  const _DesktopHeader({
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
            // Boards give the top bar no page title - every screen paints
            // its own title in content, so a second one here read as a dupe.
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
      // The embedded LyricsScreen renders its own LYRICS header + toolbar
      // (redesign docs/02), so no second label is painted here.
      child: LyricsScreen(initialSong: song, embedded: true),
    );
  }
}

class _PlayerDock extends StatefulWidget {
  final bool lyricsOpen;
  final VoidCallback onLyrics;
  final VoidCallback onLyricsPage;
  final VoidCallback onQueuePage;

  const _PlayerDock({
    required this.lyricsOpen,
    required this.onLyrics,
    required this.onLyricsPage,
    required this.onQueuePage,
  });

  @override
  State<_PlayerDock> createState() => _PlayerDockState();
}

/// Gradient + note placeholder for the dock's square cover.
class _DockArtFallback extends StatelessWidget {
  const _DockArtFallback({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: song.gradientColors.length > 1
              ? song.gradientColors
              : [kAccentColor, kBrandColor],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white70, size: 24),
      ),
    );
  }
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
          // Three zones (design doc, Table 3): track identity left, transport
          // centred UNDER the seek bar, auxiliaries right. The old bar put the
          // transport ~1000px from the track name.
          return Row(
            children: [
              // --- Left zone: identity ----------------------------------
              SizedBox(
                width: compact ? 240 : 320,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Open now playing',
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            drillDownRoute(NowPlayingScreen(initialSong: song)),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          // Square cover (the ring + scrubbing live on Now
                          // Playing; the dock's seek bar is the scrubber).
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: song.artwork != null
                                  ? Image(
                                      image: song.artwork!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _DockArtFallback(song: song),
                                    )
                                  : _DockArtFallback(song: song),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(child: _TrackIdentity(song: song)),
                      IconButton(
                        tooltip: favorite
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                        onPressed: () => appState.toggleFavoriteSong(song.id),
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite ? accent : Colors.white54,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // --- Center zone: transport over seek ---------------------
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Transport(player: player, accent: accent, compact: false),
                    const SizedBox(height: 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: SizedBox(
                        width: double.infinity,
                        child: _SeekControl(
                            player: player, song: song, accent: accent),
                      ),
                    ),
                  ],
                ),
              ),
              // --- Right zone: auxiliaries ------------------------------
              if (!compact)
                SizedBox(
                  width: 360,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (song != null && qualityChipLabel(song) != null) ...[
                        // The board's bar chip is just the format ("FLAC");
                        // the full signal path lives in the popover. Flexible
                        // + ellipsis so a long queue of aux controls can
                        // never push this past the window edge.
                        Flexible(
                          child: SignalPathChip(
                            song: song,
                            label: qualityChipShortLabel(song) ??
                                qualityChipLabel(song)!,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      _VolumeControl(
                        volume: playbackPrefs.appVolume,
                        enabled: true,
                        onChanged: playbackPrefs.setAppVolume,
                      ),
                      IconButton(
                        tooltip: 'Lyrics',
                        onPressed: widget.onLyricsPage,
                        icon: const Icon(Icons.lyrics_rounded,
                            color: Colors.white54),
                      ),
                      QueuePeekButton(
                        onOpen: widget.onQueuePage,
                        color: Colors.white54,
                      ),
                      IconButton(
                        tooltip: player.sleepUntil != null
                            ? 'Sleep timer running'
                            : 'Sleep timer',
                        onPressed: () =>
                            showSleepTimerSheet(context, player),
                        icon: Icon(Icons.bedtime_rounded,
                            color: player.sleepUntil != null
                                ? accent
                                : Colors.white54),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              if (compact)
                IconButton(
                  tooltip: 'Lyrics',
                  onPressed: widget.onLyricsPage,
                  icon:
                      const Icon(Icons.lyrics_rounded, color: Colors.white54),
                ),
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
            child: SizedBox(
              // A Slider's default preferred height (48) plus the transport
              // row overflowed the 88px dock by 9px (found in the debug
              // log). 32px keeps the track, thumb and labels inside the bar.
              height: 32,
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

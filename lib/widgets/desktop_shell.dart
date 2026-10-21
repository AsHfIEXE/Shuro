import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:volume_controller/volume_controller.dart';

import '../screens/discover/discover_screen.dart';
import '../screens/downloads/downloads_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/now_playing/lyrics_screen.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../screens/now_playing/queue_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/settings_screen.dart';
import 'package:just_audio/just_audio.dart' show PlayerRepeatMode;
import '../models/download_state.dart' show PlayerRepeatMode;
import '../models/song.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'artwork_thumb.dart';
import 'page_transitions.dart';
import 'shuro_icons.dart';

/// The desktop shell (Windows/Linux/macOS): a persistent sidebar, a content
/// pane, an optional lyrics side panel, and an always-visible now-playing
/// bar — plus keyboard shortcuts. This is a different navigation model from
/// the phone shell on purpose: desktop users expect a sidebar and a bottom
/// transport bar, not a bottom nav and a full-screen player page.
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
  bool _lyricsOpen = false;
  bool _sidebarCollapsed = false;

  static const List<(IconData, String)> _tabs = [
    (Icons.home_rounded, 'Home'),
    (Icons.library_music_rounded, 'Library'),
    (Icons.search_rounded, 'Search'),
    (Icons.auto_awesome_rounded, 'Discover'),
    (Icons.favorite_rounded, 'Favorites'),
  ];

  void _openSettings() {
    Navigator.of(context).push(
      drillDownRoute(const SettingsScreen()),
    );
  }

  void _openDownloads() {
    Navigator.of(context).push(
      drillDownRoute(const DownloadsScreen()),
    );
  }

  void _toggleLyrics() => setState(() => _lyricsOpen = !_lyricsOpen);

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final song = player.currentSong;

    return CallbackShortcuts(
      bindings: {
        // Space toggles playback — but never while the user is typing.
        const SingleActivator(LogicalKeyboardKey.space): () {
          final focus = FocusManager.instance.primaryFocus;
          final typing = focus?.context?.widget is EditableText;
          if (!typing) context.read<PlayerController>().togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            () => context.read<PlayerController>().next(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            () => context.read<PlayerController>().previous(),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            _toggleLyrics,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            widget.onSelectTab(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            widget.onSelectTab(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            widget.onSelectTab(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            widget.onSelectTab(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            widget.onSelectTab(4),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: kSurfaceColor,
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _sidebar(context),
                    const VerticalDivider(width: 1, color: kDividerColor),
                    Expanded(
                      child: IndexedStack(
                        key: widget.tabStackKey,
                        index: widget.currentIndex,
                        children: widget.tabChildren,
                      ),
                    ),
                    if (_lyricsOpen) ...[
                      const VerticalDivider(width: 1, color: kDividerColor),
                      SizedBox(
                        width: 340,
                        child: LyricsScreen(
                          initialSong: song,
                          embedded: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _NowPlayingBar(
                lyricsOpen: _lyricsOpen,
                onToggleLyrics: _toggleLyrics,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    final collapsed = _sidebarCollapsed;
    final width = collapsed ? 68.0 : 216.0;

    Widget item({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final content = Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: selected ? kBrandColor : Colors.white60),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
          ],
        ],
      );
      final row = collapsed
          ? Tooltip(
              message: label,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: content))
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 2), child: content);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: row,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      decoration: const BoxDecoration(color: kCardColor),
      child: SafeArea(
        right: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppLogo(size: collapsed ? 30 : 40),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _tabs.length; i++)
                item(
                  icon: _tabs[i].$1,
                  label: _tabs[i].$2,
                  selected: widget.currentIndex == i,
                  onTap: () => widget.onSelectTab(i),
                ),
              const Divider(color: kDividerColor, height: 24),
              item(
                icon: Icons.download_rounded,
                label: 'Downloads',
                selected: false,
                onTap: _openDownloads,
              ),
              item(
                icon: Icons.settings_rounded,
                label: 'Settings',
                selected: false,
                onTap: _openSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The desktop now-playing bar: artwork, metadata with a seek bar, transport,
/// volume, and panel toggles — always visible, like a desktop player.
class _NowPlayingBar extends StatefulWidget {
  final bool lyricsOpen;
  final VoidCallback onToggleLyrics;

  const _NowPlayingBar(
      {required this.lyricsOpen, required this.onToggleLyrics});

  @override
  State<_NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<_NowPlayingBar> {
  bool _volumeReady = false;
  double _volume = 0.8;

  @override
  void initState() {
    super.initState();
    try {
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.getVolume().then((v) {
        if (mounted)
          setState(() {
            _volume = v;
            _volumeReady = true;
          });
      }).catchError((_) {});
    } catch (_) {}
  }

  void _setVolume(double v) {
    setState(() => _volume = v.clamp(0.0, 1.0));
    try {
      VolumeController.instance.setVolume(_volume);
    } catch (_) {}
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final song = player.currentSong;
    final isFav = song != null && appState.isFavoriteSong(song.id);
    final accent = song?.gradientColors.last ?? kBrandColor;

    final bar = Container(
      height: 76,
      decoration: const BoxDecoration(
        color: kCardColor,
        border: Border(top: BorderSide(color: kDividerColor)),
      ),
      child: song == null
          ? Center(
              child: Text('Nothing playing — pick something from your library.',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white38, fontSize: 12.5)),
            )
          : Row(
              children: [
                const SizedBox(width: 12),
                // Artwork + metadata + seek (the wide middle).
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      ArtworkThumb(
                          gradientColors: song.gradientColors,
                          artwork: song.artwork,
                          size: 48,
                          radius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white54, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Seek: times + bar, with drag preview committed on release.
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BarSeek(
                        player: player,
                        song: song,
                        accent: accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Transport cluster.
                IconButton(
                  tooltip: player.shuffle ? 'Shuffle on' : 'Shuffle off',
                  onPressed: player.toggleShuffle,
                  icon: Icon(Icons.shuffle_rounded,
                      size: 20,
                      color: player.shuffle ? kBrandColor : Colors.white54),
                ),
                IconButton(
                  tooltip: 'Previous',
                  onPressed: player.previous,
                  icon: ShuroIcon(ShuroGlyph.previous,
                      size: 22, color: Colors.white),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: player.togglePlayPause,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [accent, accent.withValues(alpha: 0.7)]),
                      ),
                      child: player.isBuffering
                          ? const Icon(Icons.hourglass_top_rounded,
                              size: 20, color: Colors.white)
                          : ShuroIcon(
                              player.isPlaying
                                  ? ShuroGlyph.pause
                                  : ShuroGlyph.play,
                              size: 22,
                              color: Colors.white,
                              key: ValueKey(player.isPlaying),
                            ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: player.next,
                  icon:
                      ShuroIcon(ShuroGlyph.next, size: 22, color: Colors.white),
                ),
                IconButton(
                  tooltip: player.repeatMode.name,
                  onPressed: player.cycleRepeatMode,
                  icon: Icon(Icons.repeat_rounded,
                      size: 20,
                      color: player.repeatMode == PlayerRepeatMode.off
                          ? Colors.white54
                          : kBrandColor),
                ),
                const SizedBox(width: 8),
                // Volume.
                SizedBox(
                  width: 120,
                  child: Row(
                    children: [
                      Icon(
                        _volume == 0
                            ? Icons.volume_off_rounded
                            : (_volume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded),
                        size: 18,
                        color: Colors.white60,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: Colors.white60,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white10,
                          ),
                          child: Slider(
                              value: _volume,
                              onChanged: _volumeReady ? _setVolume : null),
                        ),
                      ),
                    ],
                  ),
                ),
                // Panels.
                IconButton(
                  tooltip: 'Lyrics',
                  onPressed: widget.onToggleLyrics,
                  icon: Icon(Icons.lyrics_rounded,
                      size: 20,
                      color: widget.lyricsOpen ? kBrandColor : Colors.white54),
                ),
                IconButton(
                  tooltip: 'Queue',
                  onPressed: () => Navigator.of(context)
                      .push(drillDownRoute(const QueueScreen())),
                  icon: const Icon(Icons.queue_music_rounded,
                      size: 20, color: Colors.white54),
                ),
                if (song != null)
                  IconButton(
                    tooltip:
                        isFav ? 'Remove from favourites' : 'Add to favourites',
                    onPressed: () => appState.toggleFavoriteSong(song.id),
                    icon: Icon(
                      isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: isFav ? accent : Colors.white54,
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(song?.id ?? 'none'),
        decoration: const BoxDecoration(color: kCardColor),
        child: bar,
      ),
    );
  }
}

/// Desktop seek bar: previews while dragging (bar follows the finger, no
/// engine calls), commits once on release, and shows the live position
/// otherwise. Mirrors the phone scrub bar's preview-then-commit contract.
class _BarSeek extends StatefulWidget {
  final PlayerController player;
  final Song song;
  final Color accent;

  const _BarSeek(
      {required this.player, required this.song, required this.accent});

  @override
  State<_BarSeek> createState() => _BarSeekState();
}

class _BarSeekState extends State<_BarSeek> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final song = widget.song;
    final isActive = player.currentSong?.id == song.id;
    final live = isActive && player.loadedSongId == song.id;
    final total = live ? player.duration : song.duration;
    final totalMs = total.inMilliseconds == 0 ? 1 : total.inMilliseconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(_fmt(player.position),
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white54, fontSize: 10.5)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                double fractionAt(double dx) =>
                    (dx / c.maxWidth).clamp(0.0, 1.0);

                void commit(double fraction) {
                  if (!isActive) return;
                  player.seekTo(
                      Duration(milliseconds: (totalMs * fraction).round()));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) =>
                      setState(() => _preview = fractionAt(d.localPosition.dx)),
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _preview = fractionAt(d.localPosition.dx)),
                  onHorizontalDragEnd: (_) {
                    final t = _preview;
                    setState(() => _preview = null);
                    if (t != null) commit(t);
                  },
                  onTapUp: (d) {
                    final t = fractionAt(d.localPosition.dx);
                    setState(() => _preview = t);
                    commit(t);
                  },
                  child: SizedBox(
                    height: 22,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Track.
                        Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Fill: preview while dragging, smooth position otherwise.
                        if (!isActive)
                          const SizedBox.shrink()
                        else
                          LayoutBuilder(builder: (context, c) {
                            final fraction = _preview ??
                                (live
                                    ? (player.position.inMilliseconds / totalMs)
                                        .clamp(0.0, 1.0)
                                    : 0.0);
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: c.maxWidth * fraction,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: widget.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        // Knob marks the draggable position.
                        if (isActive)
                          LayoutBuilder(builder: (context, c) {
                            final fraction = _preview ??
                                (live
                                    ? (player.position.inMilliseconds / totalMs)
                                        .clamp(0.0, 1.0)
                                    : 0.0);
                            return Align(
                              alignment: Alignment((fraction * 2) - 1, 0),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 3),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Text(_fmt(total),
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white54, fontSize: 10.5)),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

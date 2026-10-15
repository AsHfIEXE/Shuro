import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../playback/audio_capability.dart';
import '../../playback/audio_diagnostics.dart';
import '../../services/server_link.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/animated_favorite_icon.dart';
import '../../widgets/artwork_ring.dart';
import '../../widgets/blurred_artwork_backdrop.dart';
import '../../widgets/immersive_scope.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/song_actions_sheet.dart';
import '../../widgets/up_next_list.dart';
import 'audio_info_sheet.dart';
import 'lyrics_screen.dart';
import 'queue_screen.dart';

/// At or above this width the screen switches from the phone stack to a
/// two-pane layout (artwork beside the controls). 1024 also happens to be the
/// smallest common tablet-landscape / TV width, so one number covers tablets,
/// desktop windows and Android TV.
const double kNowPlayingWideBreakpoint = 1024;

/// Vertical space the non-artwork chrome needs in the phone layout: header,
/// title block, transport, quick actions and the lyrics affordance, plus their
/// paddings. The ring is sized from what is *left*, which is what keeps this
/// screen from overflowing on a short or landscape window.
const double _kPhoneChromeHeight = 430;

/// "09. Now Playing" — artwork, metadata, a drag-to-seek progress ring,
/// transport controls, and quick access to Queue / Lyrics / Audio info.
///
/// It follows [PlayerController.currentSong] for its entire life; the song it is
/// opened with is only the starting point (see the class doc's history in the
/// analyzer notes — the old version kept the constructor's song and described
/// the wrong track).
///
/// **Dimension-proof by construction.** Two things used to make this screen
/// fragile: the ring was sized from width alone (`width * 0.79`, clamped to
/// 220–320), and the layout was a rigid `Column` of fixed-height blocks with
/// `Spacer`s. On a 1920×1080 window that combination asked for more height than
/// the viewport had and Flutter drew "BOTTOM OVERFLOWED BY 33 PIXELS" over the
/// transport controls. Now:
///
///  * the ring is `min(width * 0.79, height - chrome)`, so it gives way first;
///  * the phone layout is a scroll view that only scrolls when it genuinely
///    doesn't fit (`SliverFillRemaining(hasScrollBody: false)`), with
///    `spaceBetween` instead of `Spacer`s so a scrolling column stays valid;
///  * wide windows get a real two-pane layout rather than a stretched phone one.
class NowPlayingScreen extends StatelessWidget {
  /// Only the starting point — see the class doc.
  final Song? initialSong;

  const NowPlayingScreen({super.key, this.initialSong});

  static const Duration _trackChangeDuration = Duration(milliseconds: 360);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleSeekDrag(PlayerController player, Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final theta = math.atan2(dy, dx);
    var delta = theta - math.pi / 2;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    final progress = (delta / (2 * math.pi)).clamp(0.0, 1.0);
    player.seekToProgress(progress);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();

    final song = player.currentSong ?? initialSong;
    if (song == null) {
      return Scaffold(
        backgroundColor: kSurfaceColor,
        appBar: AppBar(backgroundColor: kSurfaceColor, elevation: 0, leading: const BackButton(color: Colors.white)),
        body: Center(
          child: Text('Nothing is playing', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 14)),
        ),
      );
    }

    final isCurrent = player.currentSong?.id == song.id;
    final isPlaying = isCurrent && player.isPlaying;
    final total = isCurrent ? player.duration : song.duration;
    final position = isCurrent ? player.position : Duration.zero;
    final progress = isCurrent ? player.progress : 0.0;
    final isFav = appState.isFavoriteSong(song.id);

    return ImmersiveScope(
      // Settings → Appearance → "Immersive screens": hides the system bars while
      // this screen is open, and restores them on the way out.
      child: ArtworkPaletteBuilder(
      artwork: song.artwork,
      fallback: song.gradientColors,
      cacheKey: song.id,
      builder: (context, colors) {
        final accent = colors.last;
        return Scaffold(
          backgroundColor: kSurfaceColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: BlurredArtworkBackdrop(
                  artwork: song.artwork,
                  palette: colors,
                  cacheKey: song.id,
                ),
              ),
              // The right pane's darkening lives HERE, full-screen, so it is
              // vertically uniform across the whole viewport — painting it
              // inside the pane started abruptly at the header's bottom edge
              // and drew a hard horizontal seam (reported on Android + web).
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.28),
                          Colors.black.withValues(alpha: 0.45),
                        ],
                        stops: const [0.45, 0.72, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Two-pane on tablets/desktop (>=1024) AND on landscape
                    // phones (wider than tall, >=600 wide) — a phone rotated
                    // sideways used to get the portrait stack, which cramped
                    // into its scroll fallback with a 160 px ring; the split
                    // layout is the correct landscape composition at any size.
                    final wide = constraints.maxWidth >= kNowPlayingWideBreakpoint ||
                        (constraints.maxWidth > constraints.maxHeight && constraints.maxWidth >= 600);
                    final body = wide
                        ? _wideLayout(
                            context: context,
                            constraints: constraints,
                            song: song,
                            accent: accent,
                            colors: colors,
                            progress: progress,
                            position: position,
                            total: total,
                            isPlaying: isPlaying,
                            isCurrent: isCurrent,
                            appState: appState,
                            player: player,
                          )
                        : _phoneLayout(
                            context: context,
                            constraints: constraints,
                            song: song,
                            accent: accent,
                            colors: colors,
                            progress: progress,
                            position: position,
                            total: total,
                            isPlaying: isPlaying,
                            isCurrent: isCurrent,
                            appState: appState,
                            player: player,
                          );
                    return body;
                  },
                ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }

  // --- phone / compact: one column that scrolls rather than overflowing ----

  Widget _phoneLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required Song song,
    required Color accent,
    required List<Color> colors,
    required double progress,
    required Duration position,
    required Duration total,
    required bool isPlaying,
    required bool isCurrent,
    required bool isFav,
    required AppState appState,
    required PlayerController player,
  }) {
    // The ring gives way before anything else does. Clamped at the low end so a
    // very short window still shows recognisable artwork, and at 320 so a tall
    // phone keeps the design's proportions.
    final ringSize = math
        .min(constraints.maxWidth * 0.79, math.max(160.0, constraints.maxHeight - _kPhoneChromeHeight))
        .clamp(160.0, 360.0);

    return CustomScrollView(
      // `hasScrollBody: false` hands the column at least the viewport height, so
      // spaceBetween still separates the groups on a tall screen — and when the
      // content is taller than the viewport the sliver simply scrolls instead of
      // drawing an overflow banner over the controls.
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Header(
                song: song,
                accent: accent,
                onMore: () => showSongActionsSheet(context, song),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ring(context, player, song, progress, colors, 'artwork_${song.id}', ringSize),
                    const SizedBox(height: 18),
                    _TimesRow(position: position, total: total, format: _formatDuration),
                    const SizedBox(height: 6),
                    const _PlayingFromLine(),
                    const SizedBox(height: 14),
                    _TrackTitleBlock(
                      song: song,
                      accent: accent,
                      duration: _trackChangeDuration,
                      shuffleOn: player.shuffle,
                      repeatMode: player.repeatMode,
                      onShuffleToggle: player.toggleShuffle,
                      onRepeatToggle: player.cycleRepeatMode,
                      isFavorite: isFav,
                      onToggleFavorite: () => Favorites.toggle(context, song.id),
                    ),
                    const SizedBox(height: 22),
                    _transport(player, song, isPlaying, isCurrent, accent),
                  ],
                ),
              ),
              // The lyric that's being sung right now, plus the next lines —
              // this is what fills the portrait screen's empty space. The same
              // lyrics view the full screen uses, hosted inline (embedded: no
              // chrome of its own, compact: no sync bar), in a fade-masked box
              // so lines appear out of the background instead of inside a
              // visible rectangle. Tapping a line seeks; the LYRICS bar below
              // opens the full screen.
              // A small, fixed-height preview: the sung line plus the next
              // ones, fade-masked. Deliberately NOT expanded to all leftover
              // space — the first version swallowed the whole lower screen and
              // turned Now Playing into a second lyrics page.
              SizedBox(
                height: 150,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  // Edge fade = ALPHA-ONLY mask on the lyrics themselves
                  // (ClipRect + dstIn ShaderMask, bounded to this 150 dp box:
                  // static, small, no per-frame work — safe on Skia and
                  // CanvasKit). Painting kSurfaceColor over the box instead —
                  // as an earlier iteration did — draws a dark rectangular
                  // band over the artwork; darkening overlays on the backdrop
                  // are never the answer, the lyrics fade, the art stays.
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                        stops: [0.0, 0.22, 0.78, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: ScrollConfiguration(
                        // The preview is a passive glance, not a document: no
                        // scrollbar thumb (web/desktop draw one by default,
                        // and Android flashes one while scrolling).
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: LyricsScreen(initialSong: song, embedded: true, compact: true),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuickActions(
                    onQueue: () => Navigator.of(context).push(risingRoute(const QueueScreen())),
                    onAudioInfo: () => showAudioInfoSheet(context, song),
                    onSleep: () => showSleepTimerSheet(context, player),
                    sleepActiveUntil: player.sleepUntil,
                  ),
                  const SizedBox(height: 14),
                  _LyricsBar(onTap: () => openLyricsScreen(context, song), accent: accent),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- wide: artwork beside the controls (tablet, desktop, TV) -------------

  Widget _wideLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required Song song,
    required Color accent,
    required List<Color> colors,
    required double progress,
    required Duration position,
    required Duration total,
    required bool isPlaying,
    required bool isCurrent,
    required bool isFav,
    required AppState appState,
    required PlayerController player,
  }) {
    // Compact tuning for short windows (landscape phones: ~360 dp tall) —
    // the tablet proportions would overflow into the scroll fallback,
    // which is exactly the cramped landscape look this layout replaces.
    final compact = constraints.maxHeight < 520;
    // Sized from the *shorter* axis AND constrained by its own column width —
    // on short landscape windows the height factor alone let the ring grow
    // past the column and clip at the screen edge (the reported screenshot).
    final columnWidth = math.max(160.0, constraints.maxWidth * 0.5 - (compact ? 40 : 56));
    final artworkSize = math
        .min(math.min(constraints.maxHeight * (compact ? 0.46 : 0.44), columnWidth), compact ? 260.0 : 340.0)
        .clamp(160.0, compact ? 260.0 : 340.0);

    return Column(
      children: [
        _Header(
          song: song,
          accent: accent,
          onMore: () => showSongActionsSheet(context, song),
          onQueue: () => Navigator.of(context).push(risingRoute(const QueueScreen())),
          onAudioInfo: () => showAudioInfoSheet(context, song),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: the player half. One fitted column, spaceBetween, so the
              // transport owns a real slot instead of hanging off the bottom
              // edge; the ring drops its progress arc because the linear seek
              // bar under it is now the single progress display on this screen.
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 2, compact ? 20 : 28, compact ? 8 : 18),
                  // LayoutBuilder + scroll fallback: at normal sizes the column
                  // is spaceBetween (artwork up top, controls at the bottom,
                  // nothing clipped — the reported bug); on an unusually short
                  // wide window it scrolls instead of overflowing.
                  child: LayoutBuilder(
                    builder: (context, columnConstraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: columnConstraints.maxHeight),
                        // One centered, cohesive player group: ring, time,
                        // title, controls. The old spaceBetween pinned the ring
                        // to the top and controls to the bottom, hollowing out
                        // the middle on large screens.
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ring(context, player, song, progress, colors, 'artwork_${song.id}', artworkSize),
                            SizedBox(height: compact ? 14 : 30),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _TimesRow(position: position, total: total, format: _formatDuration),
                                  SizedBox(height: compact ? 8 : 14),
                                  // Title + artist stay visible in landscape
                                  // too — only the controls dissolve.
                                  _TrackTitleBlock(
                                    song: song,
                                    accent: accent,
                                    duration: _trackChangeDuration,
                                    shuffleOn: player.shuffle,
                                    repeatMode: player.repeatMode,
                                    onShuffleToggle: player.toggleShuffle,
                                    onRepeatToggle: player.cycleRepeatMode,
                                    isFavorite: isFav,
                                    onToggleFavorite: () => Favorites.toggle(context, song.id),
                                  ),
                                  SizedBox(height: compact ? 6 : 14),
                                  _transport(player, song, isPlaying, isCurrent, accent),
                                  SizedBox(height: compact ? 6 : 10),
                                  // Landscape volume: the phone's own buttons
                                  // are across the device in this orientation.
                                  const _VolumeSlider(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Right: the lyrics as a left-aligned column that starts near
              // the centre of the screen, so the two halves read as one
              // composition rather than two apps glued together.
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        // Top padding keeps the first lyric lines clear of the
                        // header and its scrim, which previously cut through them.
                        // (The pane's own darkening gradient was removed — it
                        // lives full-screen now, see the layer above SafeArea.)
                        padding: EdgeInsets.only(left: 28, right: 28, top: compact ? 12 : 28),
                        // With no lyrics to show, the pane falls back to the
                        // Up Next list — real content instead of a dark void
                        // (the TV-width "empty half" report).
                        child: LyricsScreen(
                          initialSong: song,
                          embedded: true,
                          embeddedFallback: const UpNextList(),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: 'Open full lyrics',
                          onPressed: () => openLyricsScreen(context, song),
                          icon: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- shared pieces --------------------------------------------------------

  Widget _ring(BuildContext context, PlayerController player, Song song, double progress, List<Color> colors, String heroTag, double size, {bool showProgress = true}) {
    return _ScrubbingRing(
      player: player,
      size: size,
      song: song,
      progress: progress,
      colors: colors,
      heroTag: heroTag,
      showProgress: showProgress,
    );
  }

  Widget _transport(PlayerController player, Song song, bool isPlaying, bool isCurrent, Color accent) {
    return PlaybackControls(
      isPlaying: isPlaying,
      isBuffering: isCurrent && player.isBuffering,
      accentColor: accent,
      onPlayPause: () async {
        if (isCurrent) {
          await player.togglePlayPause();
        } else {
          await player.playSong(song);
        }
      },
      onPrevious: player.previous,
      onNext: player.next,
    );
  }
}

/// The ring with its drag-to-seek gesture AND the scrubbing state: while a
/// finger is down on the ring, the knob grows and its glow strengthens (see
/// ProgressRingPainter.scrubbing) so the seek control visibly answers touch.
class _ScrubbingRing extends StatefulWidget {
  final PlayerController player;
  final double size;
  final Song song;
  final double progress;
  final List<Color> colors;
  final String heroTag;
  final bool showProgress;

  const _ScrubbingRing({
    required this.player,
    required this.size,
    required this.song,
    required this.progress,
    required this.colors,
    required this.heroTag,
    this.showProgress = true,
  });

  @override
  State<_ScrubbingRing> createState() => _ScrubbingRingState();
}

class _ScrubbingRingState extends State<_ScrubbingRing> {
  bool _scrubbing = false;

  void _seekFrom(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final theta = math.atan2(dy, dx);
    var delta = theta - math.pi / 2;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    final progress = (delta / (2 * math.pi)).clamp(0.0, 1.0);
    widget.player.seekToProgress(progress);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scrubbing = true),
      onPointerUp: (_) => setState(() => _scrubbing = false),
      onPointerCancel: (_) => setState(() => _scrubbing = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _seekFrom(details.localPosition),
        onTapUp: (details) => _seekFrom(details.localPosition),
        child: ArtworkRing(
          song: widget.song,
          progress: widget.progress,
          colors: widget.colors,
          size: widget.size,
          heroTag: widget.heroTag,
          showProgress: widget.showProgress,
          scrubbing: _scrubbing,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Song song;
  final Color accent;
  final VoidCallback onMore;

  /// Wide screens move Queue/Audio-info up here (the bottom-left column has no
  /// room for a separate actions row).
  final VoidCallback? onQueue;
  final VoidCallback? onAudioInfo;

  const _Header({
    required this.song,
    required this.accent,
    required this.onMore,
    this.onQueue,
    this.onAudioInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Now Playing',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              tooltip: 'Close',
            ),
          ),
          Expanded(
            child: Center(
              child: Text('PLAYING NOW',
                  style: GoogleFonts.getFont(currentFontFamily, color: const Color(0x80FFFFFF), fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 2.0)),
            ),
          ),
          // (No favourite here: the heart lives in its sweet spot under the
          // artist — a second one in the header was duplicate clutter.)
          if (onQueue != null)
            IconButton(
              onPressed: onQueue,
              icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
              tooltip: 'Queue',
            ),
          if (onAudioInfo != null)
            IconButton(
              onPressed: onAudioInfo,
              icon: const Icon(Icons.info_outline_rounded, color: Colors.white70),
              tooltip: 'Audio information',
            ),
          IconButton(
            onPressed: onMore,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'More options',
          ),
        ],
      ),
    );
  }
}

class _TimesRow extends StatelessWidget {
  final Duration position;
  final Duration total;
  final String Function(Duration) format;

  const _TimesRow({required this.position, required this.total, required this.format});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 11);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(format(position), style: style),
        const SizedBox(width: 24),
        Text(format(total), style: style),
      ],
    );
  }
}

/// The thin progress line under the landscape artwork (the reference layout),
/// with the elapsed/total times split to its edges. The ring around the
/// artwork remains the primary progress display — this is its large-screen
/// companion, not a replacement.
class _ProgressLine extends StatelessWidget {
  final Duration position;
  final Duration total;
  final double progress;
  final Color accent;
  final String Function(Duration) format;

  /// Called with the tapped/dragged fraction (0..1) when the user seeks.
  final ValueChanged<double>? onSeek;

  const _ProgressLine({
    required this.position,
    required this.total,
    required this.progress,
    required this.accent,
    required this.format,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()]);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 4,
        backgroundColor: Colors.white24,
        valueColor: AlwaysStoppedAnimation(accent),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onSeek == null)
          bar
        else
          // Draggable: a seek bar you can't grab is decoration. A taller hit
          // area (the Padding) keeps a 4 px line tappable without making the
          // line itself heavy.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seekFrom(d.localPosition.dx, context),
            onHorizontalDragUpdate: (d) => _seekFrom(d.localPosition.dx, context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: bar,
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(format(position), style: style),
            Text(format(total), style: style),
          ],
        ),
      ],
    );
  }

  void _seekFrom(double dx, BuildContext context) {
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    onSeek?.call((dx / width).clamp(0.0, 1.0));
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onQueue;
  final VoidCallback onAudioInfo;
  final VoidCallback onSleep;
  final DateTime? sleepActiveUntil;

  const _QuickActions({
    required this.onQueue,
    required this.onAudioInfo,
    required this.onSleep,
    this.sleepActiveUntil,
  });

  @override
  Widget build(BuildContext context) {
    final sleepActive = sleepActiveUntil != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _QuickAction(icon: Icons.queue_music_rounded, label: 'Queue', onTap: onQueue),
        const SizedBox(width: 36),
        _QuickAction(
          icon: Icons.bedtime_rounded,
          label: sleepActive
              ? 'Sleep · ${TimeOfDay.fromDateTime(sleepActiveUntil!).format(context)}'
              : 'Sleep',
          onTap: onSleep,
        ),
        const SizedBox(width: 36),
        _QuickAction(icon: Icons.info_outline_rounded, label: 'Audio info', onTap: onAudioInfo),
      ],
    );
  }
}

class _LyricsBar extends StatelessWidget {
  final VoidCallback onTap;
  final Color accent;
  const _LyricsBar({required this.onTap, required this.accent});

  @override
  Widget build(BuildContext context) {
    // A quiet pill instead of the old full-width grey slab: lyrics are one
    // action among several on this screen, so it gets a normal button's
    // footprint, a hairline border, and the track's accent on the icon.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lyrics_rounded, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  'Lyrics',
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Title + artist + shuffle/repeat, animated as a single block when the track
/// changes. Uses the shared [TrackInfoRow] so the layout stays identical to the
/// rest of the app — only the swap is animated.
class _TrackTitleBlock extends StatelessWidget {
  final Song song;
  final Color accent;
  final Duration duration;
  final bool shuffleOn;
  final PlayerRepeatMode repeatMode;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;

  /// Favourite sweet spot passthrough (see TrackInfoRow).
  final bool? isFavorite;
  final VoidCallback? onToggleFavorite;

  const _TrackTitleBlock({
    required this.song,
    required this.accent,
    required this.duration,
    required this.shuffleOn,
    required this.repeatMode,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
    this.isFavorite,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Incoming (forward): a small rise + fade. Outgoing (reverse): fade
        // only — the old block sliding *down* while the new one rose read as
        // a lurch.
        if (animation.status == AnimationStatus.reverse) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: TrackInfoRow(
        key: ValueKey(song.id),
        song: song,
        accent: accent,
        shuffleOn: shuffleOn,
        repeatMode: repeatMode,
        onShuffleToggle: onShuffleToggle,
        onRepeatToggle: onRepeatToggle,
        isFavorite: isFavorite,
        onToggleFavorite: onToggleFavorite,
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Sleep timer picker: Off / preset minutes / end of track. Shows what's
/// armed with the time it will pause.
Future<void> showSleepTimerSheet(BuildContext context, PlayerController player) {
  Color? rowColor(BuildContext c) => Theme.of(c).scaffoldBackgroundColor == Colors.transparent ? null : null;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              'Sleep timer',
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (player.sleepUntil != null)
            ListTile(
              leading: const Icon(Icons.timer_off_rounded, color: Colors.redAccent),
              title: Text(
                'Cancel timer (pauses at ${TimeOfDay.fromDateTime(player.sleepUntil!).format(context)})',
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13.5),
              ),
              onTap: () {
                player.cancelSleepTimer();
                Navigator.of(sheetContext).pop();
              },
            ),
          for (final minutes in const [15, 30, 45, 60, 90])
            ListTile(
              leading: const Icon(Icons.bedtime_rounded, color: kBrandColor),
              title: Text('$minutes minutes', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13.5)),
              onTap: () {
                player.startSleepTimer(Duration(minutes: minutes));
                Navigator.of(sheetContext).pop();
              },
            ),
          ListTile(
            leading: const Icon(Icons.music_note_rounded, color: kBrandColor),
            title: Text('End of current track', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13.5)),
            onTap: () {
              player.startSleepTimerEndOfTrack();
              Navigator.of(sheetContext).pop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// "Playing from <device>" — the current audio output route, exactly what
/// Apple Music/Spotify surface. Data comes from the Kotlin capability
/// monitor (real device product names on the routes that report them).
/// Honesty rules apply: the line is only shown when the route is actually
/// KNOWN — unknown routes render nothing.
class _PlayingFromLine extends StatefulWidget {
  const _PlayingFromLine();

  @override
  State<_PlayingFromLine> createState() => _PlayingFromLineState();
}

class _PlayingFromLineState extends State<_PlayingFromLine> {
  AudioCapabilityReport? _report;

  @override
  void initState() {
    super.initState();
    _report = sharedAudioCapabilityMonitor.last;
    // Re-read when the app returns (route may have changed while hidden);
    // route changes while open are pushed by the Kotlin monitor via app.dart's
    // lifecycle recheck.
    unawaited(sharedAudioCapabilityMonitor.recheck().then((r) {
      if (mounted) setState(() => _report = r);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    if (report == null || report.routeKind == RouteKind.unknown) {
      return const SizedBox(height: 18);
    }
    final label = report.routeLabel;
    final kindText = switch (report.routeKind) {
      RouteKind.bluetooth => 'Bluetooth',
      RouteKind.wired => 'Wired headphones',
      RouteKind.usb => 'USB audio',
      RouteKind.builtIn => 'This device',
      RouteKind.other || RouteKind.unknown => 'External output',
    };
    final deviceName = (label != null && label.trim().isNotEmpty) ? label.trim() : null;
    final text = deviceName != null && report.routeKind != RouteKind.builtIn
        ? 'Playing from $deviceName'
        : 'Playing from $kindText';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconFor(report.routeKind), size: 13, color: Colors.white38),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(RouteKind kind) => switch (kind) {
        RouteKind.bluetooth => Icons.bluetooth_audio_rounded,
        RouteKind.wired => Icons.headset_rounded,
        RouteKind.usb => Icons.usb_rounded,
        RouteKind.builtIn => Icons.smartphone_rounded,
        _ => Icons.speaker_rounded,
      };
}

/// Landscape volume: a media-volume slider with speaker icons, for the
/// orientation where the phone's own volume rocker sits across the device.
/// Web has no volume plugin — the widget hides itself there.
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider();

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _volume;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    try {
      VolumeController.instance.showSystemUI = false;
      // fetchInitialVolume: true → the first event delivers the current
      // value, so no separate getVolume round trip is needed.
      _sub = VolumeController.instance.addListener((v) {
        if (mounted) setState(() => _volume = v);
      });
    } catch (_) {
      _volume = null;
    }
  }

  StreamSubscription<double>? _sub;

  void _onVolume(double v) {
    if (mounted) setState(() => _volume = v);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    try {
      unawaited(VolumeController.instance.removeListener());
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final value = (_volume ?? 0.5).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.volume_down_rounded, size: 18, color: Colors.white54),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value,
                onChanged: _volume == null
                    ? null
                    : (v) async {
                        setState(() => _volume = v);
                        try {
                          await VolumeController.instance.setVolume(v);
                        } catch (_) {}
                      },
              ),
            ),
          ),
          Icon(Icons.volume_up_rounded, size: 18, color: Colors.white54),
        ],
      ),
    );
  }
}

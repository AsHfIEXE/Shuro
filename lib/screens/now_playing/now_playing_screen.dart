import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../backend/subsonic_api.dart';
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
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= kNowPlayingWideBreakpoint;
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
                            isFav: isFav,
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
                            isFav: isFav,
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
                isFav: isFav,
                onFavorite: () => Favorites.toggle(context, song.id),
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
                    const SizedBox(height: 22),
                    _TrackTitleBlock(
                      song: song,
                      accent: accent,
                      duration: _trackChangeDuration,
                      shuffleOn: player.shuffle,
                      repeatMode: player.repeatMode,
                      onShuffleToggle: player.toggleShuffle,
                      onRepeatToggle: player.cycleRepeatMode,
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
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                        stops: [0.0, 0.22, 0.78, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: LyricsScreen(initialSong: song, embedded: true, compact: true),
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
    // Sized from the *shorter* axis and deliberately smaller than before: the
    // reported problem was the transport row clipped at the bottom, which is
    // exactly what an artwork that fills the column causes.
    final artworkSize = math.min(constraints.maxHeight * 0.44, constraints.maxWidth * 0.28).clamp(200.0, 360.0);

    return Column(
      children: [
        _Header(
          song: song,
          accent: accent,
          isFav: isFav,
          onFavorite: () => Favorites.toggle(context, song.id),
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
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 18),
                  // LayoutBuilder + scroll fallback: at normal sizes the column
                  // is spaceBetween (artwork up top, controls at the bottom,
                  // nothing clipped — the reported bug); on an unusually short
                  // wide window it scrolls instead of overflowing.
                  child: LayoutBuilder(
                    builder: (context, columnConstraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: columnConstraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // The ring is the progress display on this screen (like
                            // portrait) — the separate linear bar under it was
                            // removed as duplicate clutter.
                            _ring(context, player, song, progress, colors, 'artwork_${song.id}', artworkSize),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _TimesRow(position: position, total: total, format: _formatDuration),
                                  const SizedBox(height: 18),
                                  _TrackTitleBlock(
                                    song: song,
                                    accent: accent,
                                    duration: _trackChangeDuration,
                                    shuffleOn: player.shuffle,
                                    repeatMode: player.repeatMode,
                                    onShuffleToggle: player.toggleShuffle,
                                    onRepeatToggle: player.cycleRepeatMode,
                                  ),
                                  const SizedBox(height: 16),
                                  _transport(player, song, isPlaying, isCurrent, accent),
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
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.40),
                                Colors.black.withValues(alpha: 0.55),
                              ],
                              stops: const [0.0, 0.38, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 28, right: 28, top: 8),
                        child: LyricsScreen(initialSong: song, embedded: true),
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
    return GestureDetector(
      onPanUpdate: (details) => _handleSeekDrag(player, details.localPosition, size),
      onTapUp: (details) => _handleSeekDrag(player, details.localPosition, size),
      child: ArtworkRing(
        song: song,
        progress: progress,
        // The track's real artwork-derived palette (see ArtworkPaletteBuilder),
        // not a single accent smeared into a gradient — the ring's own glow and
        // placeholder artwork both read from it.
        colors: colors,
        size: size,
        heroTag: heroTag,
        showProgress: showProgress,
      ),
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

class _Header extends StatelessWidget {
  final Song song;
  final Color accent;
  final bool isFav;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  /// Wide screens move Queue/Audio-info up here (the bottom-left column has no
  /// room for a separate actions row).
  final VoidCallback? onQueue;
  final VoidCallback? onAudioInfo;

  const _Header({
    required this.song,
    required this.accent,
    required this.isFav,
    required this.onFavorite,
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
          AnimatedFavoriteIcon(isFavorite: isFav, activeColor: accent, onTap: onFavorite),
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

  const _QuickActions({required this.onQueue, required this.onAudioInfo});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _QuickAction(icon: Icons.queue_music_rounded, label: 'Queue', onTap: onQueue),
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

  const _TrackTitleBlock({
    required this.song,
    required this.accent,
    required this.duration,
    required this.shuffleOn,
    required this.repeatMode,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
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

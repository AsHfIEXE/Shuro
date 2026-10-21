import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../../widgets/smooth_position_builder.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/shuro_icons.dart';
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
const double _kPhoneChromeHeight = 520;

/// The inline lyric preview shares what the ring leaves over: it never drops
/// below the minimum (a sung line plus the next one) and never grows past the
/// maximum (it must not turn Now Playing into a second lyrics page).
const double _kLyricPreviewMin = 110;
const double _kLyricPreviewMax = 190;

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

  void _handleSeekDrag(
      PlayerController player, Offset localPosition, double size) {
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

    final current = player.currentSong;
    final song = current ?? initialSong;
    if (song == null || (current == null && player.everHadSong)) {
      // Never played anything: the placeholder track renders for the first
      // frames. Queue emptied while open: the mini player hides itself, so
      // a ghost track here would disagree with it (audit finding F5-1) —
      // show the empty state instead.
      return Scaffold(
        backgroundColor: kSurfaceColor,
        appBar: AppBar(
            backgroundColor: kSurfaceColor,
            elevation: 0,
            leading: const BackButton(color: Colors.white)),
        body: Center(
          child: Text('Nothing is playing',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white70, fontSize: 14)),
        ),
      );
    }

    final isCurrent = current?.id == song.id;
    // Live only when the engine has audio for THIS song loaded — during the
    // load window the engine still reports the outgoing track's position and
    // duration, which must not render under the new title (audit finding
    // F6-1, the "progress ring jumping on track change" symptom).
    final live = isCurrent && player.loadedSongId == song.id;
    final isPlaying = isCurrent && player.isPlaying;
    final total = live ? player.duration : song.duration;
    final position = live ? player.position : Duration.zero;
    final progress = live ? player.progress : 0.0;
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
                      final wide =
                          constraints.maxWidth >= kNowPlayingWideBreakpoint ||
                              (constraints.maxWidth > constraints.maxHeight &&
                                  constraints.maxWidth >= 600);
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
    //
    // The chrome constant covers everything EXCEPT the ring and the lyric
    // preview; the preview's minimum is reserved first. Before, the ring was
    // sized as if the 150 dp preview did not exist, so on a normal tall phone
    // the quick-actions row and the Lyrics button ended up below the fold and
    // the page opened already scrolled/clipped.
    final ringCap = math.min(constraints.maxWidth * 0.79, 360.0);
    final ringSize = math
        .min(ringCap,
            constraints.maxHeight - _kPhoneChromeHeight - _kLyricPreviewMin - 10)
        .clamp(170.0, math.max(170.0, ringCap))
        .toDouble();
    final previewHeight = (constraints.maxHeight -
            _kPhoneChromeHeight -
            ringSize -
            10)
        .clamp(_kLyricPreviewMin, _kLyricPreviewMax)
        .toDouble();

    return LayoutBuilder(
      builder: (context, viewport) => _RingAwareScroll(
        // A stable storage identity: the scroll offset survives every rebuild
        // (the player notifies ~1×/s while playing), so the page can never
        // silently jump position mid-playback.
        scrollKey: const PageStorageKey('npv_portrait'),
        // Real scrolling: ConstrainedBox(minHeight) lets the column stretch to
        // the viewport on tall phones (spaceBetween still separates the
        // groups), while content taller than the viewport (small phones, with
        // the title heart + output line that the old fixed-height sliver
        // overflowed on) now SCROLLS instead of drawing an overflow — the
        // sliver variant overflowed the moment the content grew.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
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
                    _ring(context, player, song, progress, colors,
                        'artwork_${song.id}', ringSize),
                    const SizedBox(height: 18),
                    _TimesRow(
                        position: position,
                        total: total,
                        format: _formatDuration),
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
                      onToggleFavorite: () =>
                          Favorites.toggle(context, song.id),
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
                height: previewHeight,
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
                        colors: [
                          Color(0x00000000),
                          Color(0xFF000000),
                          Color(0xFF000000),
                          Color(0x00000000)
                        ],
                        stops: [0.0, 0.22, 0.78, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: ScrollConfiguration(
                        // The preview is a passive glance, not a document: no
                        // scrollbar thumb (web/desktop draw one by default,
                        // and Android flashes one while scrolling). And its
                        // list ALWAYS absorbs drag gestures (AlwaysScrollable
                        // + clamping): without this, once the auto-scrolling
                        // list reached an edge, a drag/drag-end propagated to
                        // the portrait page's outer scroll view and nudged the
                        // whole screen a few pixels — the reported "NPV scrolls
                        // down a little when lyrics change line".
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: false,
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics()),
                        ),
                        child: LyricsScreen(
                            initialSong: song, embedded: true, compact: true),
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
                    onQueue: () => pushRisingOnce(context, const QueueScreen()),
                    onAudioInfo: () => showAudioInfoSheet(context, song),
                    onSleep: () => showSleepTimerSheet(context, player),
                    onVolume: () => showVolumeSheet(context, player),
                    sleepActiveUntil: player.sleepUntil,
                  ),
                  const SizedBox(height: 14),
                  _LyricsBar(
                      onTap: () => openLyricsScreen(context, song),
                      accent: accent),
                ],
              ),
            ],
          ),
        ),
      ),
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
    // The ring cap is derived so ring + times + title + transport + volume
    // FIT the column without scrolling (that sum overflowing was the
    // "controls cut off at the bottom" bug).
    final compact = constraints.maxHeight < 520;
    // Sized from the *shorter* axis AND constrained by its own column width —
    // on short landscape windows the height factor alone let the ring grow
    // past the column and clip at the screen edge (the reported screenshot).
    final columnWidth =
        math.max(160.0, constraints.maxWidth * 0.5 - (compact ? 40 : 56));
    // Compact column: header 48 + paddings 6, then ring + gap 6 + times 14 +
    // gap 2 + title block 43 + gap 2 + one control row 56 + 8 spare — the ring
    // takes what is left (it was 0.36 × height ≈ 137 dp on a phone, with the
    // controls still spilling off the bottom).
    final compactRing = constraints.maxHeight - 48 - 6 - 6 - 14 - 2 - 43 - 2 - 56 - 8;
    final artworkSize = math
        .min(
            math.min(
                compact ? compactRing : constraints.maxHeight * 0.44,
                columnWidth),
            compact ? 210.0 : 340.0)
        .clamp(compact ? 110.0 : 160.0, compact ? 210.0 : 340.0);

    return Column(
      children: [
        _Header(
          song: song,
          accent: accent,
          onMore: () => showSongActionsSheet(context, song),
          onQueue: () => pushRisingOnce(context, const QueueScreen()),
          onAudioInfo: () => showAudioInfoSheet(context, song),
          onSleep: () => showSleepTimerSheet(context, player),
          sleepActive: player.sleepUntil != null,
          // Landscape has no quick-actions row, so volume lives up here.
          onVolume: () => showVolumeSheet(context, player),
          dense: compact,
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
                  padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 2,
                      compact ? 16 : 28, compact ? 4 : 18),
                  // LayoutBuilder + scroll fallback: at normal sizes the column
                  // is spaceBetween (artwork up top, controls at the bottom,
                  // nothing clipped — the reported bug); on an unusually short
                  // wide window it scrolls instead of overflowing.
                  child: LayoutBuilder(
                    builder: (context, columnConstraints) => _RingAwareScroll(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: columnConstraints.maxHeight),
                        // One centered, cohesive player group: ring, time,
                        // title, controls. The old spaceBetween pinned the ring
                        // to the top and controls to the bottom, hollowing out
                        // the middle on large screens.
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ring(context, player, song, progress, colors,
                                'artwork_${song.id}', artworkSize),
                            SizedBox(height: compact ? 6 : 30),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: compact
                                  ? _compactControls(
                                      context: context,
                                      player: player,
                                      song: song,
                                      accent: accent,
                                      position: position,
                                      total: total,
                                      isPlaying: isPlaying,
                                      isCurrent: isCurrent,
                                      isFav: isFav,
                                    )
                                  : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _TimesRow(
                                      position: position,
                                      total: total,
                                      format: _formatDuration),
                                  SizedBox(height: compact ? 4 : 14),
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
                                    onToggleFavorite: () =>
                                        Favorites.toggle(context, song.id),
                                    dense: compact,
                                  ),
                                  SizedBox(height: compact ? 3 : 14),
                                  _transport(player, song, isPlaying, isCurrent,
                                      accent,
                                      compact: compact),
                                  SizedBox(height: compact ? 2 : 10),
                                  // Landscape volume: same animated control as
                                  // portrait — a slim chip opening the full
                                  // volume sheet. The old inline slider was a
                                  // second seek-bar lookalike and cost layout
                                  // height this column doesn't have.
                                  Center(
                                    child: _QuickAction(
                                      icon: Icons.volume_up_rounded,
                                      label: 'Volume',
                                      onTap: () =>
                                          showVolumeSheet(context, player),
                                    ),
                                  ),
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
                        padding: EdgeInsets.only(
                            left: 28, right: 28, top: compact ? 12 : 28),
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
                          icon: const Icon(Icons.open_in_full_rounded,
                              color: Colors.white, size: 18),
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

  Widget _ring(BuildContext context, PlayerController player, Song song,
      double progress, List<Color> colors, String heroTag, double size,
      {bool showProgress = true}) {
    Widget buildRing(double p) => _ScrubbingRing(
          player: player,
          size: size,
          song: song,
          progress: p,
          colors: colors,
          heroTag: heroTag,
          showProgress: showProgress,
        );

    // Per-frame interpolation while playing (the ring used to step at the
    // ~1 Hz notify rate). SmoothPositionBuilder's ticker is muted whenever
    // playback is paused, so a still screen costs nothing; reduce-motion (and
    // therefore the Performance profile) keeps the plain 1 Hz value.
    if (!showProgress || reduceMotionEnabled) return buildRing(progress);
    return SmoothPositionBuilder(
      builder: (context, player, position, smoothProgress) =>
          buildRing(smoothProgress),
    );
  }

  /// Landscape-phone control cluster: times, title with the heart beside it,
  /// and ONE row holding shuffle, transport and repeat. The portrait block
  /// (title, a separate heart row, a separate transport row, a volume chip)
  /// needs ~60 dp more than a 360-410 dp window has, which is what clipped the
  /// play button at the bottom edge.
  Widget _compactControls({
    required BuildContext context,
    required PlayerController player,
    required Song song,
    required Color accent,
    required Duration position,
    required Duration total,
    required bool isPlaying,
    required bool isCurrent,
    required bool isFav,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TimesRow(position: position, total: total, format: _formatDuration),
        const SizedBox(height: 2),
        Row(
          children: [
            const SizedBox(width: 40),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white,
                          fontSize: 18,
                          height: 24 / 18,
                          fontWeight: FontWeight.w700)),
                  Text(song.artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 17 / 12.5,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 6)
                          ])),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Favorites.toggle(context, song.id),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: AnimatedFavoriteIcon(
                    isFavorite: isFav,
                    activeColor: accent,
                    inactiveColor: Colors.white60,
                    size: 20,
                    onTap: () => Favorites.toggle(context, song.id),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        _transport(
          player,
          song,
          isPlaying,
          isCurrent,
          accent,
          compact: true,
          leading: PlayerModeButton(
            shuroIcon: ShuroGlyph.shuffle,
            modeLabel: 'Shuffle',
            active: player.shuffle,
            accent: accent,
            onTap: player.toggleShuffle,
          ),
          trailing: PlayerModeButton(
            materialIcon: player.repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            modeLabel: switch (player.repeatMode) {
              PlayerRepeatMode.off => 'Repeat off',
              PlayerRepeatMode.all => 'Repeat all',
              PlayerRepeatMode.one => 'Repeat one',
            },
            active: player.repeatMode != PlayerRepeatMode.off,
            badge: player.repeatMode == PlayerRepeatMode.one ? '1' : null,
            accent: accent,
            onTap: player.cycleRepeatMode,
          ),
        ),
      ],
    );
  }

  Widget _transport(PlayerController player, Song song, bool isPlaying,
      bool isCurrent, Color accent,
      {bool compact = false, Widget? leading, Widget? trailing}) {
    return PlaybackControls(
      leading: leading,
      trailing: trailing,
      isPlaying: isPlaying,
      isBuffering: isCurrent && player.isBuffering,
      accentColor: accent,
      compact: compact,
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

/// True while a finger is down on the seek ring. When the player column is
/// taller than the viewport (landscape, small windows) it scrolls, and its
/// vertical drag recognizer used to win the gesture arena against the ring's
/// pan, so scrubbing on the ring scrolled the page instead of seeking.
final ValueNotifier<bool> _ringTouched = ValueNotifier<bool>(false);

/// A [SingleChildScrollView] that stops accepting drags while the ring is
/// touched, so the ring's pan always wins.
class _RingAwareScroll extends StatelessWidget {
  final Widget child;

  /// Applied to the inner scroll view so a [PageStorageKey] keeps its offset.
  final Key? scrollKey;
  const _RingAwareScroll({this.scrollKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _ringTouched,
      child: child,
      builder: (context, touched, child) => SingleChildScrollView(
        key: scrollKey,
        physics: touched ? const NeverScrollableScrollPhysics() : null,
        child: child,
      ),
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

  /// Drag preview: while the finger moves, only this local value changes and
  /// the ring repaints. The engine is seeked ONCE, on release. The old code
  /// seeked on every pan update — a 6-second drag produced 26 seeks and 26
  /// re-buffers (seen in a real diagnostics export), which is why scrubbing
  /// felt laggy and sometimes stuck.
  double? _preview;

  @override
  void dispose() {
    // A ring torn down mid-touch (rotation, track change) must not leave the
    // page's scroll view frozen.
    _ringTouched.value = false;
    super.dispose();
  }

  double _progressAt(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final theta = math.atan2(dy, dx);
    var delta = theta - math.pi / 2;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    return (delta / (2 * math.pi)).clamp(0.0, 1.0);
  }

  void _updatePreview(Offset localPosition) {
    setState(() => _preview = _progressAt(localPosition));
  }

  void _commitSeek() {
    final target = _preview;
    if (target == null) return;
    // Keep showing the preview until the engine confirms the seek: clearing
    // it immediately made the ring snap back to the old position and then
    // jump forward (visible on streamed tracks, where the seek takes a beat).
    widget.player.seekToProgress(target).whenComplete(() {
      if (mounted && _preview == target) setState(() => _preview = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _ringTouched.value = true;
        setState(() => _scrubbing = true);
      },
      onPointerUp: (_) {
        _ringTouched.value = false;
        if (_preview != null) _commitSeek();
        setState(() => _scrubbing = false);
      },
      onPointerCancel: (_) {
        _ringTouched.value = false;
        if (_preview != null) _commitSeek();
        setState(() => _scrubbing = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _updatePreview(details.localPosition),
        onPanUpdate: (details) => _updatePreview(details.localPosition),
        onTapUp: (details) {
          _updatePreview(details.localPosition);
          _commitSeek();
        },
        child: ArtworkRing(
          song: widget.song,
          progress: _preview ?? widget.progress,
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

  /// Sleep timer entry — portrait has it in the quick-actions row; landscape
  /// had NO way to arm or cancel a timer at all.
  final VoidCallback? onSleep;
  final bool sleepActive;

  /// Volume entry for layouts without a quick-actions row (landscape).
  final VoidCallback? onVolume;

  /// Tighter icon buttons for short windows (48 → 40 dp each).
  final bool dense;

  const _Header({
    required this.song,
    required this.accent,
    required this.onMore,
    this.onQueue,
    this.onAudioInfo,
    this.onSleep,
    this.sleepActive = false,
    this.onVolume,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final density = dense ? VisualDensity.compact : VisualDensity.standard;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Now Playing',
            child: IconButton(
            visualDensity: density,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              tooltip: 'Close',
            ),
          ),
          Expanded(
            child: Center(
              child: Text('PLAYING NOW',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: const Color(0xB3FFFFFF),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 2.0)),
            ),
          ),
          // (No favourite here: the heart lives in its sweet spot under the
          // artist — a second one in the header was duplicate clutter.)
          if (onVolume != null)
            IconButton(
              visualDensity: density,
              onPressed: onVolume,
              icon: const Icon(Icons.volume_up_rounded, color: Colors.white70),
              tooltip: 'Volume',
            ),
          if (onSleep != null)
            IconButton(
            visualDensity: density,
              onPressed: onSleep,
              icon: Icon(
                Icons.bedtime_rounded,
                color: sleepActive ? accent : Colors.white70,
              ),
              tooltip: sleepActive ? 'Sleep timer running' : 'Sleep timer',
            ),
          if (onQueue != null)
            IconButton(
            visualDensity: density,
              onPressed: onQueue,
              icon:
                  const Icon(Icons.queue_music_rounded, color: Colors.white70),
              tooltip: 'Queue',
            ),
          if (onAudioInfo != null)
            IconButton(
            visualDensity: density,
              onPressed: onAudioInfo,
              icon:
                  const Icon(Icons.info_outline_rounded, color: Colors.white70),
              tooltip: 'Audio information',
            ),
          IconButton(
            visualDensity: density,
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

  const _TimesRow(
      {required this.position, required this.total, required this.format});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.getFont(currentFontFamily,
        color: Colors.white,
        fontSize: 11,
        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]);
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
    final style = GoogleFonts.getFont(currentFontFamily,
        color: Colors.white70,
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()]);
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
            onHorizontalDragUpdate: (d) =>
                _seekFrom(d.localPosition.dx, context),
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
  final VoidCallback onVolume;
  final DateTime? sleepActiveUntil;

  const _QuickActions({
    required this.onQueue,
    required this.onAudioInfo,
    required this.onSleep,
    required this.onVolume,
    this.sleepActiveUntil,
  });

  @override
  Widget build(BuildContext context) {
    final sleepActive = sleepActiveUntil != null;
    // FittedBox: three actions + gaps never overflow a narrow screen (or the
    // test renderer's wider fallback glyphs) — the row scales down only when
    // it would otherwise clip.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _QuickAction(
              icon: Icons.queue_music_rounded, label: 'Queue', onTap: onQueue),
          const SizedBox(width: 36),
          _QuickAction(
            icon: Icons.bedtime_rounded,
            label: sleepActive
                ? 'Sleep · ${formatSleepCountdown(sleepActiveUntil!.difference(DateTime.now()))}'
                : 'Sleep',
            onTap: onSleep,
          ),
          const SizedBox(width: 36),
          _QuickAction(
              icon: Icons.volume_up_rounded, label: 'Volume', onTap: onVolume),
          const SizedBox(width: 36),
          _QuickAction(
              icon: Icons.info_outline_rounded,
              label: 'Audio info',
              onTap: onAudioInfo),
        ],
      ),
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
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3),
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

  /// Short-window sizing passthrough (see TrackInfoRow.dense).
  final bool dense;

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
    this.dense = false,
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
            position:
                Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero)
                    .animate(animation),
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
        dense: dense,
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

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
            Text(label,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Sleep timer picker: Off / preset minutes / end of track. Shows what's
/// armed with the time it will pause.
Future<void> showSleepTimerSheet(
    BuildContext context, PlayerController player) async {
  // The fade preference persists (the timer itself never does — spec rule).
  final prefs = await SharedPreferences.getInstance();
  var fade = prefs.getBool('shuro_sleep_fade') ?? true;

  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text(
                  'Sleep timer',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (player.sleepUntil != null) ...[
                ListTile(
                  leading: const Icon(Icons.exposure_plus_1_rounded,
                      color: kBrandColor),
                  title: Text(
                    '+10 minutes (now pauses at ${TimeOfDay.fromDateTime(player.sleepUntil!.add(const Duration(minutes: 10))).format(sheetContext)})',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5),
                  ),
                  onTap: () {
                    player.extendSleepTimer();
                    Navigator.of(sheetContext).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_off_rounded,
                      color: Colors.redAccent),
                  title: Text(
                    'Cancel timer (pauses at ${TimeOfDay.fromDateTime(player.sleepUntil!).format(sheetContext)})',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5),
                  ),
                  onTap: () {
                    player.cancelSleepTimer();
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
              for (final minutes in const [15, 30, 45, 60, 90])
                ListTile(
                  leading:
                      const Icon(Icons.bedtime_rounded, color: kBrandColor),
                  title: Text('$minutes minutes',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white, fontSize: 13.5)),
                  onTap: () {
                    player.startSleepTimer(Duration(minutes: minutes),
                        fadeOut: fade);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded, color: kBrandColor),
                title: Text('Custom time…',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5)),
                subtitle: Text('Pause at a specific clock time',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11.5)),
                onTap: () async {
                  final now = DateTime.now();
                  final soon = now.add(const Duration(minutes: 30));
                  final picked = await showTimePicker(
                    context: sheetContext,
                    helpText: 'Pause at',
                    initialTime:
                        TimeOfDay(hour: soon.hour, minute: soon.minute),
                    initialEntryMode: TimePickerEntryMode.dial,
                  );
                  if (picked == null) return;
                  // A clock time, not a duration: 12:17 AM means "at 12:17",
                  // and if that moment has already passed today it means
                  // tomorrow. (The old code read the picked hour/minute as
                  // h*60+m minutes — picking 12:17 scheduled +17 minutes,
                  // which is exactly why a 12:17 setting fired at 12:33.)
                  var target = DateTime(
                      now.year, now.month, now.day, picked.hour, picked.minute);
                  if (!target.isAfter(now)) {
                    target = target.add(const Duration(days: 1));
                  }
                  final remaining = target.difference(now);
                  if (remaining <= Duration.zero) return;
                  player.startSleepTimer(remaining, fadeOut: fade);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.music_note_rounded, color: kBrandColor),
                title: Text('End of current track',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5)),
                onTap: () {
                  player.startSleepTimerEndOfTrack(fadeOut: fade);
                  Navigator.of(sheetContext).pop();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.queue_music_rounded, color: kBrandColor),
                title: Text('End of queue',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5)),
                subtitle: Text('Plays everything queued, then pauses',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11.5)),
                onTap: () {
                  player.startSleepTimerEndOfQueue();
                  Navigator.of(sheetContext).pop();
                },
              ),
              SwitchListTile(
                secondary:
                    const Icon(Icons.graphic_eq_rounded, color: kBrandColor),
                title: Text('Fade out before pausing',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5)),
                subtitle: Text('10 seconds, player volume only',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11.5)),
                value: fade,
                activeThumbColor: kBrandColor,
                onChanged: (value) async {
                  setSheetState(() => fade = value);
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('shuro_sleep_fade', value);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Volume control, available in every mode (the slider used to exist only
/// inline in the landscape column, so portrait and web users had NO volume
/// control at all). System media volume when the platform allows it; a real
/// player-volume fallback otherwise — never a fake.
Future<void> showVolumeSheet(BuildContext context, PlayerController player) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => SafeArea(child: _VolumeSheet(player: player)),
  );
}

class _VolumeSheet extends StatefulWidget {
  final PlayerController player;
  const _VolumeSheet({required this.player});

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  double? _systemVolume;
  StreamSubscription<double>? _sub;
  bool _systemWorking = false;
  bool _systemTried = false;
  late double _playerVolume = widget.player.playerVolume;
  double _preMute = 1.0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _systemTried = true; // browsers: player-volume fallback immediately
      return;
    }
    try {
      VolumeController.instance.showSystemUI = false;
      _sub = VolumeController.instance.addListener((v) {
        if (mounted) {
          setState(() {
            _systemVolume = v;
            _systemWorking = true;
          });
        }
      });
      VolumeController.instance.getVolume().then((v) {
        if (mounted) {
          setState(() {
            _systemVolume = v;
            _systemWorking = true;
          });
        }
      }).catchError((_) {});
    } catch (_) {}
    // No answer shortly → honest fallback to the player's own volume.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_systemWorking) setState(() => _systemTried = true);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    try {
      unawaited(VolumeController.instance.removeListener());
    } catch (_) {}
    super.dispose();
  }

  bool get _useSystem => !kIsWeb && _systemWorking;
  bool get _unknown => !_useSystem && !_systemTried && !kIsWeb;

  bool _dragging = false;
  bool _hitZero = false;
  bool _hitFull = false;

  Future<void> _set(double v) async {
    if (_useSystem) {
      try {
        await VolumeController.instance.setVolume(v);
      } catch (_) {}
    } else {
      await widget.player.setPlayerVolume(v);
    }
  }

  void _onDrag(double v, double width) {
    final value = (v / width).clamp(0.0, 1.0);
    setState(() {
      _systemVolume = value;
      _playerVolume = value;
      if (value <= 0.001 && !_hitZero) {
        _hitZero = true;
        HapticFeedback.selectionClick();
      } else if (value > 0.001) {
        _hitZero = false;
      }
      if (value >= 0.999 && !_hitFull) {
        _hitFull = true;
        HapticFeedback.selectionClick();
      } else if (value < 0.999) {
        _hitFull = false;
      }
    });
    _set(value);
  }

  IconData _levelIcon(double v) {
    if (v == 0) return Icons.volume_off_rounded;
    if (v < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final value =
        (_useSystem ? (_systemVolume ?? 0.5) : _playerVolume).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()}%';

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Volume',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                    scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
                    child: child),
              ),
              child: _unknown
                  ? const SizedBox.shrink(key: ValueKey('unknown'))
                  : Text(percent,
                      key: ValueKey(percent),
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_unknown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kBrandColor)),
                const SizedBox(width: 12),
                Text('Reading system volume…',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 12.5)),
              ],
            ),
          )
        else ...[
          // The smart control: a pill track that breathes taller while you
          // drag, a white translucent fill, NO thumb — the fill edge IS the
          // handle. A floating percentage bubble rides the edge and fades
          // away on release. Accent stays reserved for the seek bar.
          LayoutBuilder(
            builder: (context, c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onDrag(d.localPosition.dx, c.maxWidth),
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) =>
                    _onDrag(d.localPosition.dx, c.maxWidth),
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                child: SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 7, end: _dragging ? 14 : 7),
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        builder: (context, h, _) => Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(h),
                          ),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: value),
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => FractionallySizedBox(
                          widthFactor: v.clamp(0.0, 1.0),
                          child: Container(
                            height: _dragging ? 14 : 7,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      // Floating bubble at the fill edge while dragging.
                      Positioned(
                        left: (value * c.maxWidth - 26)
                            .clamp(0.0, c.maxWidth - 52),
                        top: -26,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _dragging ? 1 : 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(percent,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.black87,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _VolumeIconButton(
                icon: value == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_mute_rounded,
                tooltip: value == 0 ? 'Unmute' : 'Mute',
                onTap: () async {
                  HapticFeedback.lightImpact();
                  if (value == 0) {
                    setState(() {
                      _playerVolume = _preMute;
                      _systemVolume = _preMute;
                    });
                    await _set(_preMute);
                  } else {
                    _preMute = value;
                    setState(() {
                      _playerVolume = 0;
                      _systemVolume = 0;
                    });
                    await _set(0);
                  }
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(_levelIcon(value),
                    key: ValueKey(_levelIcon(value)),
                    color: Colors.white70,
                    size: 22),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _useSystem
                ? 'System media volume'
                : (kIsWeb
                    ? 'Player volume — in a browser the tab/speaker volume is the system control'
                    : 'Player volume — this device did not expose its system control'),
            style: GoogleFonts.getFont(currentFontFamily,
                color: kMutedTextColor, fontSize: 11.5),
          ),
        ],
      ],
    );

    // Entrance: a short rise + fade so the sheet feels composed, not popped.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, 14 * (1 - t)), child: child),
        ),
        child: body,
      ),
    );
  }
}

/// Small icon button with a tactile scale-down on press — used by the
/// volume sheet's mute control.
class _VolumeIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _VolumeIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  State<_VolumeIconButton> createState() => _VolumeIconButtonState();
}

class _VolumeIconButtonState extends State<_VolumeIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(widget.icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
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
    // Follow the monitor instead of reading once: a route change (headset
    // plugged/unplugged, Bluetooth connected) now repaints this line live
    // instead of waiting for the screen to be reopened (fixed 2026-10-18).
    sharedAudioCapabilityMonitor.addListener(_onMonitorChanged);
    unawaited(sharedAudioCapabilityMonitor.recheck());
  }

  @override
  void dispose() {
    sharedAudioCapabilityMonitor.removeListener(_onMonitorChanged);
    super.dispose();
  }

  void _onMonitorChanged() {
    if (!mounted) return;
    final latest = sharedAudioCapabilityMonitor.last;
    // Keep showing the previous route while a re-check is in flight - only a
    // genuinely fresh answer replaces it, so the label never flickers empty.
    if (latest != null) setState(() => _report = latest);
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
    final deviceName =
        (label != null && label.trim().isNotEmpty) ? label.trim() : null;
    final text = deviceName != null && report.routeKind != RouteKind.builtIn
        ? 'Playing from $deviceName'
        : 'Playing from $kindText';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconFor(report.routeKind), size: 13, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white70,
                  fontSize: 11,
                  shadows: const [
                    Shadow(color: Color(0x66000000), blurRadius: 6)
                  ]),
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

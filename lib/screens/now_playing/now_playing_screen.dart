import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../services/playback_prefs.dart';
import '../../services/server_link.dart';

import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../playback/audio_capability.dart';
import '../../playback/audio_diagnostics.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/add_to_playlist_sheet.dart';
import '../../widgets/animated_favorite_icon.dart';
import '../../widgets/artwork_ring.dart';
import '../../widgets/blurred_artwork_backdrop.dart';
import '../../widgets/window_caption_buttons.dart';
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
import '../../widgets/click_region.dart';
import '../../widgets/player_bar_extras.dart';
import '../../widgets/queue_panel.dart';

/// At or above this width the screen switches from the phone stack to a
/// two-pane layout (artwork beside the controls). 1024 also happens to be the
/// smallest common tablet-landscape / TV width, so one number covers tablets,
/// desktop windows and Android TV.
const double kNowPlayingWideBreakpoint = 1024;

/// Vertical space the Now Playing SEGMENT's own chrome needs: times row,
/// metadata block, quality chip, transport and the bottom action row, plus
/// their gaps (header and page tabs sit outside the segment). The ring is
/// sized from the design proportion (NpvMetrics.ring) minus what this chrome
/// needs, which keeps the screen from overflowing on short viewports; the
/// scroll fallback catches anything the estimate misses.
const double _kPhoneBodyChrome = 300;


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
/// `Spacer`s. On a 1920Ã—1080 window that combination asked for more height than
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
      // Settings â†’ Appearance â†’ "Immersive screens": hides the system bars while
      // this screen is open, and restores them on the way out.
      child: ArtworkPaletteBuilder(
        artwork: song.artwork,
        fallback: song.gradientColors,
        cacheKey: song.id,
        builder: (context, colors) {
          final accent = colors.last;
          // Plain arrow keys nudge the position ±5 s (docs/02 interaction
          // table). Space and L are the shell's global bindings and are
          // deliberately NOT re-wired here. The Focus node gives the route a
          // primary focus so the bindings work without a prior tap.
          return CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _nudgeBy(live, player, const Duration(seconds: -5)),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _nudgeBy(live, player, const Duration(seconds: 5)),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(

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
                // Three soft mesh blobs behind the content (docs/02
                // backdrop): pink / violet / cyan radial washes, static, at
                // 10-16% alpha. Pure gradients - no blur filter, no per-frame
                // work - and skipped entirely under reduce-motion
                // (see _MeshBlobs).
                Positioned.fill(
                  child: IgnorePointer(child: _MeshBlobs()),
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
                          : _PhoneNowPlaying(
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
                // The immersive screens cover the shell's title bar, so the
                // window controls travel with them (Windows/Linux only).
                if (WindowCaptionButtons.supported)
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: WindowCaptionButtons(),
                  ),
              ],
            ),
          ),
        ),
      );
        },
      ),
    );
  }

  /// +/-5 s nudge for the plain arrow keys. Ignored while the shown track is
  /// not the loaded one (the placeholder song must not seek real audio) or
  /// while a text field has the focus.
  void _nudgeBy(bool live, PlayerController player, Duration delta) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText) return;
    if (!live) return;
    player.seekBy(delta);
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
    // Compact tuning for short windows (landscape phones: ~360 dp tall):
    // keeps the old fitted cluster. The redesigned column (docs/02 desktop)
    // is for windows with room to breathe.
    final compact = constraints.maxHeight < 520;
    final columnWidth =
        math.max(160.0, constraints.maxWidth * 0.5 - (compact ? 40 : 56));
    final compactRing =
        constraints.maxHeight - 48 - 6 - 6 - 14 - 2 - 43 - 2 - 56 - 8;
    // Redesigned ring: NpvMetrics caps the desktop ring at 400 and keeps it
    // inside its own column. Landscape-compact keeps the tighter budget that
    // fits the 360 dp window.
    final artworkSize = compact
        ? math
            .min(math.min(compactRing, columnWidth), 210.0)
            .clamp(110.0, 210.0).toDouble()
        : NpvMetrics.ring(
            height: constraints.maxHeight,
            colWidth: columnWidth,
            desktop: true);

    return Column(
      children: [
        _Header(
          song: song,
          accent: accent,
          albumName: appState.albumById(song.albumId)?.title,
          onMore: () => showSongActionsSheet(context, song),
          onAudioInfo: () => showAudioInfoSheet(context, song),
          sleepActive: player.sleepUntil != null,
          showOutputChip: !compact,
          dense: compact,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: the player column. One fitted column with a scroll
              // fallback (an unusually short wide window scrolls instead of
              // overflowing).
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 2,
                      compact ? 16 : 28, compact ? 4 : 18),
                  child: LayoutBuilder(
                    builder: (context, columnConstraints) => _RingAwareScroll(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: columnConstraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ring(player, song, progress, colors,
                                'artwork_${song.id}', artworkSize,
                                knobSize: compact ? null : NpvMetrics.knobDesktop),
                            SizedBox(height: compact ? 6 : 16),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 560),
                              child: compact
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _compactControls(
                                          context: context,
                                          player: player,
                                          song: song,
                                          accent: accent,
                                          position: position,
                                          total: total,
                                          isPlaying: isPlaying,
                                          isCurrent: isCurrent,
                                          isFav: isFav,
                                        ),
                                        const SizedBox(height: 8),
                                        // Landscape phones get the same
                                        // action row as portrait (volume,
                                        // sleep, queue...), which the old
                                        // compact cluster dropped.
                                        _NpvActionRow(
                                          desktop: false,
                                          song: song,
                                          player: player,
                                          appState: appState,
                                          isFav: isFav,
                                          accent: accent,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _smoothTimes(player, position, total,
                                            live: isCurrent &&
                                                player.loadedSongId ==
                                                    song.id),
                                        const SizedBox(height: 12),
                                        _MetaBlock(
                                          song: song,
                                          appState: appState,
                                          titleSize: 30,
                                          metaSize: 16,
                                        ),
                                        const SizedBox(height: 24),
                                        _transport(
                                          player,
                                          song,
                                          isPlaying,
                                          isCurrent,
                                          accent,
                                          discSize: NpvMetrics.playDiscDesktop,
                                          flankDistance: 2 * 62,
                                          prevNextIconSize: 35,
                                          whiteDisc: true,
                                          leading: _shuffleFlank(player),
                                          trailing: _repeatFlank(player),
                                        ),
                                        const SizedBox(height: 24),
                                        _NpvActionRow(
                                          desktop: true,
                                          song: song,
                                          player: player,
                                          appState: appState,
                                          isFav: isFav,
                                          accent: accent,
                                        ),
                                        const SizedBox(height: 16),
                                        const _HintLine(),
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
              // Right: the lyrics as a column that starts near the centre of
              // the screen, so the two halves read as one composition.
              // Left-aligned per the docs/02 alignment note; the pane falls
              // back to the Up Next list when there is nothing to sing.
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(
                            left: 28, right: 28, top: compact ? 12 : 28),
                        child: LyricsScreen(
                          initialSong: song,
                          embedded: true,
                          // A landscape phone pane is a preview, not the
                          // full desktop lyrics column: compact drops the
                          // toolbar whose fixed rows cannot fit 360 dp.
                          compact: compact,
                          embeddedFallback: const UpNextList(),
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

}

// --- shared ring + transport builders (top-level: both layouts use them) --

/// The ring plus its drag-to-seek gesture and per-frame progress. The
  /// buffered arc comes straight off the controller (no interpolation
  /// needed); the progress is interpolated per frame while playing
  /// (SmoothPositionBuilder's ticker mutes when paused, so a still screen
  /// costs nothing; reduce-motion keeps the plain 1 Hz value).
  Widget _ring(PlayerController player, Song song, double progress,
      List<Color> colors, String heroTag, double size,
      {bool showProgress = true, double? knobSize}) {
    Widget buildRing(double p) => _ScrubbingRing(
          player: player,
          size: size,
          song: song,
          progress: p,
          colors: colors,
          heroTag: heroTag,
          showProgress: showProgress,
          buffered: player.bufferedFraction,
          knobSize: knobSize,
        );

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
      {bool compact = false,
      Widget? leading,
      Widget? trailing,
      double? discSize,
      double? flankDistance,
      double? prevNextIconSize,
      bool whiteDisc = false}) {
    return PlaybackControls(
      leading: leading,
      trailing: trailing,
      isPlaying: isPlaying,
      isBuffering: isCurrent && player.isBuffering,
      accentColor: accent,
      compact: compact,
      discSize: discSize,
      flankDistance: flankDistance,
      prevNextIconSize: prevNextIconSize,
      whiteDisc: whiteDisc,
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

// --- shared builders (used by both layouts) -------------------------------

/// mm:ss for the times row and the scrub bubble.
String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Times row on the smooth per-frame clock while playing (the same source
/// the ring uses); the ~1 Hz notify value stands in when paused or under
/// reduce-motion.
Widget _smoothTimes(PlayerController player, Duration position,
    Duration total, {required bool live}) {
  if (!live || reduceMotionEnabled) {
    return _TimesRow(position: position, total: total);
  }
  return SmoothPositionBuilder(
    builder: (context, p, pos, _) => _TimesRow(
      position: pos,
      total: p.duration > Duration.zero ? p.duration : total,
    ),
  );
}

/// Shuffle / repeat flanking the redesigned transport (docs/02): bare icons
/// at white 60% when off; repeat turns brand violet when on and shuffle warms
/// to full white, each with a dot so the ON state never reads as "dimmed".
Widget _shuffleFlank(PlayerController player) => PlayerModeButton(
      shuroIcon: ShuroGlyph.shuffle,
      modeLabel: 'Shuffle',
      active: player.shuffle,
      accent: kBrandColor,
      activeColor: Colors.white,
      onTap: player.toggleShuffle,
      plain: true,
      size: 22,
    );

Widget _repeatFlank(PlayerController player) => PlayerModeButton(
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
      accent: kBrandColor,
      activeColor: kBrandColor,
      onTap: player.cycleRepeatMode,
      plain: true,
      size: 22,
    );

/// The phone (portrait) Now Playing: header, the page-tab pill (Now Playing |
/// Lyrics | Queue) and the segment body (docs/02 mobile board). The Now
/// Playing segment is the dimension-proof column - ring, times, metadata,
/// transport, action row - inside the same scroll fallback; the Lyrics
/// segment hosts the lyrics inline with the full-screen bar kept at its
/// foot.
class _PhoneNowPlaying extends StatefulWidget {
  final Song song;
  final Color accent;
  final List<Color> colors;
  final double progress;
  final Duration position;
  final Duration total;
  final bool isPlaying;
  final bool isCurrent;
  final bool isFav;
  final AppState appState;
  final PlayerController player;
  final BoxConstraints constraints;

  const _PhoneNowPlaying({
    required this.song,
    required this.accent,
    required this.colors,
    required this.progress,
    required this.position,
    required this.total,
    required this.isPlaying,
    required this.isCurrent,
    required this.isFav,
    required this.appState,
    required this.player,
    required this.constraints,
  });

  @override
  State<_PhoneNowPlaying> createState() => _PhoneNowPlayingState();
}

class _PhoneNowPlayingState extends State<_PhoneNowPlaying> {
  /// 0 = Now Playing, 1 = Lyrics. Queue is a launcher for the queue screen
  /// (it keeps its own toolbar), so it never becomes the selected segment.
  int _tab = 0;

  Widget _nowPlayingSegment(double ringSize) {
    final w = widget;
    return LayoutBuilder(
      builder: (context, viewport) => _RingAwareScroll(
        // Stable storage identity: the scroll offset survives every rebuild
        // (the player notifies ~1x/s while playing).
        scrollKey: const PageStorageKey('npv_portrait'),
        // Real scrolling: the column stretches to the viewport on tall
        // phones (spaceBetween separates the groups) and SCROLLS on small
        // ones instead of drawing an overflow.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ring(w.player, w.song, w.progress, w.colors,
                        'artwork_${w.song.id}', ringSize,
                        knobSize: NpvMetrics.knobMobile),
                    const SizedBox(height: 12),
                    _smoothTimes(w.player, w.position, w.total,
                        live: w.isCurrent &&
                            w.player.loadedSongId == w.song.id),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: _MetaBlock(
                        song: w.song,
                        appState: w.appState,
                        titleSize: 26,
                        metaSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _transport(
                      w.player,
                      w.song,
                      w.isPlaying,
                      w.isCurrent,
                      w.accent,
                      discSize: NpvMetrics.playDiscMobile,
                      flankDistance: 2 * 54,
                      prevNextIconSize: 31,
                      whiteDisc: true,
                      leading: _shuffleFlank(w.player),
                      trailing: _repeatFlank(w.player),
                    ),
                  ],
                ),
              ),
              // Inline lyric preview (restored from the pre-redesign phone
              // layout): the sung line plus the next ones in a small
              // fade-masked box between the controls and the action row. It
              // takes only what the ring leaves over and disappears on short
              // screens, where the Lyrics tab is the place to read.
              if (viewport.maxHeight - ringSize - 330 >= 100)
                SizedBox(
                  height: (viewport.maxHeight - ringSize - 330)
                      .clamp(100.0, 190.0)
                      .toDouble(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          // A passive glance: no scrollbar, and the list
                          // absorbs its own drags so the page never nudges.
                          behavior: ScrollConfiguration.of(context).copyWith(
                            scrollbars: false,
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: ClampingScrollPhysics()),
                          ),
                          child: LyricsScreen(
                              initialSong: w.song,
                              embedded: true,
                              compact: true),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: _NpvActionRow(
                  desktop: false,
                  song: w.song,
                  player: w.player,
                  appState: w.appState,
                  isFav: w.isFav,
                  accent: w.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lyricsSegment() {
    final w = widget;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LyricsScreen(initialSong: w.song, embedded: true),
          ),
        ),
        // Keeps the full lyrics screen (sync offset, appearance, editor)
        // one tap away from the inline view.
        _LyricsBar(
            onTap: () => openLyricsScreen(context, w.song),
            accent: w.accent),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    // Ring (docs/02 mobile): the design proportion - 44% of height, capped
    // at 340, column width ~ screen - 60, so 330 on a 390-wide phone -
    // giving way to the segment chrome on short viewports. The scroll
    // fallback above catches anything the estimate misses.
    final ringCap = math.min(w.constraints.maxWidth - 60, 340.0);
    var ringSize = NpvMetrics.ring(
        height: w.constraints.maxHeight, colWidth: ringCap, desktop: false);
    final headroom = w.constraints.maxHeight - _kPhoneBodyChrome;
    if (ringSize > headroom) {
      ringSize = headroom.clamp(160.0, ringSize).toDouble();
    }

    return Column(
      children: [
        _Header(
          song: w.song,
          accent: w.accent,
          albumName: w.appState.albumById(w.song.albumId)?.title,
          onMore: () => showSongActionsSheet(context, w.song),
          sleepActive: w.player.sleepUntil != null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _PageTabs(
            selected: _tab,
            onSelect: (i) {
              if (i == 2) {
                // The queue keeps its own screen (save-as-playlist and the
                // rest of its toolbar), so the segment launches the route.
                showQueuePanel(context);
              } else {
                setState(() => _tab = i);
              }
            },
          ),
        ),
        Expanded(
          child:
              _tab == 1 ? _lyricsSegment() : _nowPlayingSegment(ringSize),
        ),
      ],
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
/// A time bubble rides the knob's radial line while dragging (and, for mouse
/// users, while hovering), and drags tick a haptic at every 10% boundary
/// (docs/02 interactions).
class _ScrubbingRing extends StatefulWidget {
  final PlayerController player;
  final double size;
  final Song song;
  final double progress;
  final List<Color> colors;
  final String heroTag;
  final bool showProgress;

  /// Buffered fraction (0..1) for the painter's white arc; null hides it.
  final double? buffered;

  /// Knob diameter override - NpvMetrics.knobDesktop / knobMobile.
  final double? knobSize;

  const _ScrubbingRing({
    required this.player,
    required this.size,
    required this.song,
    required this.progress,
    required this.colors,
    required this.heroTag,
    this.showProgress = true,
    this.buffered,
    this.knobSize,
  });

  @override
  State<_ScrubbingRing> createState() => _ScrubbingRingState();
}

class _ScrubbingRingState extends State<_ScrubbingRing> {
  bool _scrubbing = false;

  /// Drag preview: while the finger moves, only this local value changes and
  /// the ring repaints. The engine is seeked ONCE, on release - a drag used
  /// to seek on every pan update, which re-buffered the stream dozens of
  /// times per scrub and made it feel laggy.
  double? _preview;

  /// Mouse hover position (desktop): shows the bubble with the time a click
  /// would seek to, before anything is committed.
  Offset? _hover;

  /// Last 10%-bucket a haptic fired for (tick per boundary crossing).
  int _lastTickBucket = -1;

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
    // The painter starts at 12 o'clock (-pi/2) and sweeps clockwise, so the
    // angle-to-fraction conversion undoes exactly that rotation.
    var delta = theta + math.pi / 2;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    return (delta / (2 * math.pi)).clamp(0.0, 1.0);
  }

  void _updatePreview(Offset localPosition, {bool withHaptic = false}) {
    final next = _progressAt(localPosition);
    if (withHaptic) {
      // One tick each time the scrub crosses a 10% boundary (docs/02).
      final bucket = (next * 10).floor();
      if (bucket != _lastTickBucket) {
        _lastTickBucket = bucket;
        HapticFeedback.selectionClick();
      }
    }
    setState(() => _preview = next);
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

  Duration get _totalDuration => widget.player.duration > Duration.zero
      ? widget.player.duration
      : widget.song.duration;

  /// The scrub bubble (docs/02): 56x26 pill at 85% surface colour on a white
  /// 20% hairline, sitting OUTSIDE the ring on the knob's radial line. It is
  /// clamped into the ring's own box - around 3/6/9 o'clock that flips it to
  /// hug the ring instead of poking past the layout, so it never leaves the
  /// screen. 120 ms fade in and out.
  Widget _buildBubble(double? bubbleProgress) {
    const bubbleWidth = 56.0, bubbleHeight = 26.0;
    final shown = bubbleProgress ?? 0.0;
    final angle = -math.pi / 2 + 2 * math.pi * shown;
    final radial = Offset(math.cos(angle), math.sin(angle));
    final knobRadius = (widget.knobSize ?? 18) / 2;
    final center = Offset(widget.size / 2, widget.size / 2) +
        radial * (widget.size / 2 + knobRadius + 34);
    final left = (center.dx - bubbleWidth / 2)
        .clamp(0.0, math.max(0.0, widget.size - bubbleWidth))
            .toDouble();
    final top = (center.dy - bubbleHeight / 2)
        .clamp(0.0, math.max(0.0, widget.size - bubbleHeight))
            .toDouble();
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: bubbleProgress == null ? 0 : 1,
          child: Container(
            width: bubbleWidth,
            height: bubbleHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kSurfaceColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(13),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: Text(
              _formatDuration(_totalDuration * shown),
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleProgress =
        _preview ?? (_hover != null ? _progressAt(_hover!) : null);
    return MouseRegion(
      opaque: false,
      onEnter: (e) => setState(() => _hover = e.localPosition),
      onHover: (e) => setState(() => _hover = e.localPosition),
      onExit: (_) => setState(() => _hover = null),
      child: Listener(
        onPointerDown: (_) {
          _ringTouched.value = true;
          _lastTickBucket = -1;
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
        child: ClickRegion(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) =>
              _updatePreview(details.localPosition, withHaptic: true),
          onPanUpdate: (details) =>
              _updatePreview(details.localPosition, withHaptic: true),
          onTapUp: (details) {
            _updatePreview(details.localPosition);
            _commitSeek();
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ArtworkRing(
                  song: widget.song,
                  progress: _preview ?? widget.progress,
                  colors: widget.colors,
                  size: widget.size,
                  heroTag: widget.heroTag,
                  showProgress: widget.showProgress,
                  scrubbing: _scrubbing,
                  buffered: widget.buffered,
                  knobSize: widget.knobSize,
                ),
                _buildBubble(bubbleProgress),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Docs/02 header: a round 40 px collapse button (white 10% circle,
/// chevron-down), the "PLAYING FROM ALBUM / <name>" eyebrow centred, and the
/// output chip + audio-info + more on the right (desktop). Phones carry the
/// output chip in the bottom action row instead, so their header stays
/// close | playing-from | more.
class _Header extends StatelessWidget {
  final Song song;
  final Color accent;
  final VoidCallback onMore;

  final VoidCallback? onAudioInfo;
  final bool sleepActive;

  /// Album name for the eyebrow; null (local file, placeholder track, server
  /// offline) falls back to the generic "PLAYING NOW" label.
  final String? albumName;

  /// Show the audio-output chip (desktop header only).
  final bool showOutputChip;

  /// Tighter icon buttons for short windows (48 -> 40 dp each).
  final bool dense;

  const _Header({
    required this.song,
    required this.accent,
    required this.onMore,
    this.onAudioInfo,
    this.sleepActive = false,
    this.albumName,
    this.showOutputChip = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final density = dense ? VisualDensity.compact : VisualDensity.standard;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Now Playing',
            child:
                _RoundCollapseButton(onPressed: () => Navigator.of(context).maybePop()),
          ),
          Expanded(
            child: Center(
              child: albumName == null
                  ? Text('PLAYING NOW',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: const Color(0xB3FFFFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          letterSpacing: 2.0))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('PLAYING FROM ALBUM',
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: kMuted2,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 2),
                        Text(albumName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(currentFontFamily,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
            ),
          ),
          Padding(
            // The window caption buttons own the top-right corner on
            // desktop; the output chip, info and "..." keep their distance.
            padding: EdgeInsets.only(
                right: WindowCaptionButtons.supported ? 152 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showOutputChip) ...[
                  _OutputChip(width: 148, height: 40),
                  const SizedBox(width: 8),
                ],
                // (No favourite here: the heart lives in the action row under
                // the transport - a second one in the header was clutter.)
                if (sleepActive)
                  Icon(Icons.bedtime_rounded, color: accent, size: 18),
                // Board: 32 px glass circles (info, more) next to the output pill.
                if (onAudioInfo != null) ...[
                  _HeaderGlassCircle(
                      icon: Icons.info_outline_rounded,
                      tooltip: 'Audio information',
                      onTap: onAudioInfo),
                  const SizedBox(width: 8),
                ],
                _HeaderGlassCircle(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More options',
                    onTap: onMore),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 32 px white-8% circle on a hairline: the Now Playing header's info and
/// "..." buttons.
class _HeaderGlassCircle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _HeaderGlassCircle(
      {required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Icon(icon, size: 16, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

/// Round 40 px collapse control (docs/02): white 10% circle on a hairline
/// with a chevron-down - the screen folds back into the mini player.
class _RoundCollapseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RoundCollapseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: kHairline),
        ),
        child: const Center(
          child: Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// "1:26 · -2:44" (docs/02): elapsed, then NEGATIVE remaining, 13 px with
/// tabular figures so the digits don't jitter as the position ticks. The
/// optional [format] keeps the compact landscape cluster's existing call.
class _TimesRow extends StatelessWidget {
  final Duration position;
  final Duration total;
  final String Function(Duration)? format;

  const _TimesRow({required this.position, required this.total, this.format});

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? _formatDuration;
    final remaining = total - position;
    final left = remaining < Duration.zero ? Duration.zero : remaining;
    final style = GoogleFonts.getFont(currentFontFamily,
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmt(position), style: style),
        const SizedBox(width: 8),
        Text('·',
            style: style.copyWith(
                color: kMuted3, fontFeatures: const [])),
        const SizedBox(width: 8),
        Text('-${fmt(left)}', style: style.copyWith(color: kMutedTextColor)),
      ],
    );
  }
}

/// The thin progress line under the landscape artwork (the reference layout),
/// with the elapsed/total times split to its edges. The ring around the
/// artwork remains the primary progress display — this is its large-screen
/// companion, not a replacement.
// Superseded by the ring/seek layout; removal is tracked separately.
// ignore: unused_element
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
  }) : onSeek = null;

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
          ClickRegion(
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

/// Now Playing | Lyrics | Queue pill (docs/02 mobile): 270x36, glass fill on
/// a hairline border, radius 999, the active segment a white 12% pill.
/// Queue keeps its own screen (its toolbar has save-as-playlist and more),
/// so that segment launches the route rather than swapping the body.
class _PageTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _PageTabs({required this.selected, required this.onSelect});

  static const _labels = ['Now Playing', 'Lyrics', 'Queue'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kHairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: ClickRegion(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  selected: selected == i,
                  label: _labels[i],
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: ShuroMotion.std,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected == i
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: selected == i ? Colors.white : kMuted2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quality chip label from the audio-info data source (docs/02):
/// "FLAC · 24-bit / 96 kHz · Lossless" for a tagged lossless file,
/// "MP3 · 320 kbps" for a lossy one. Null = hide the chip (the server
/// reported nothing technical about the file) - never a guess.
String? qualityChipLabel(Song song) {
  final info = song.audioInfo;
  final parts = <String>[];
  if (info.hasFormat) parts.add(info.format!.toUpperCase());
  if (info.hasBitDepth && info.hasSampleRate) {
    parts.add('${info.bitDepthLabel} / ${info.sampleRateLabel}');
  } else if (info.hasBitrate) {
    parts.add('${info.bitrateKbps} kbps');
  }
  // Mirrors AudioInfo's own lossless set (see audio_info.dart).
  const lossless = {'FLAC', 'ALAC', 'WAV', 'AIFF', 'APE', 'WV'};
  if (info.hasFormat && lossless.contains(info.format!.toUpperCase())) {
    parts.add('Lossless');
  }
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// Board playbar chip: just the format ("FLAC", "MP3"); the full
/// "format · depth/rate · Lossless" string stays in [qualityChipLabel]
/// and the signal-path popover. Null = hide, same honesty rule.
String? qualityChipShortLabel(Song song) {
  final info = song.audioInfo;
  if (!info.hasFormat) return null;
  return info.format!.toUpperCase();
}

/// Title + "Artist · Album · Year" + quality chip (docs/02 metadata block):
/// the artist is #F9A8D4 (kPinkPale) w600, the album/year muted. The whole
/// block swaps as one animated unit when the track changes.
class _MetaBlock extends StatelessWidget {
  final Song song;
  final AppState appState;

  /// 30 desktop / 26 mobile (docs/02).
  final double titleSize;

  /// 16 desktop / 15 mobile.
  final double metaSize;

  const _MetaBlock({
    required this.song,
    required this.appState,
    required this.titleSize,
    required this.metaSize,
  });

  @override
  Widget build(BuildContext context) {
    final album = appState.albumById(song.albumId);
    final albumTitle = album?.title;
    // Year 0 is the model's "unknown" - omit it rather than show "· 0".
    final year = (album?.year ?? 0) > 0 ? album!.year.toString() : null;
    final quality = qualityChipLabel(song);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Incoming: a small rise + fade; outgoing: fade only, so the swap
        // never reads as a lurch.
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
      child: Column(
        key: ValueKey(song.id),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            song.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white,
                fontSize: titleSize,
                height: 1.25,
                fontWeight: FontWeight.w800,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 8)
                ]),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: song.artist,
                  style: TextStyle(
                      color: kPinkPale, fontWeight: FontWeight.w600),
                ),
                if (albumTitle != null && albumTitle.trim().isNotEmpty)
                  TextSpan(text: ' · $albumTitle'),
                if (year != null) TextSpan(text: ' · $year'),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.getFont(currentFontFamily,
                color: kStatusText,
                fontSize: metaSize,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 6)
                ]),
          ),
          if (quality != null) ...[
            const SizedBox(height: 8),
            SignalPathChip(song: song, label: quality),
          ],
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
    return ClickRegion(
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
                leading: const Icon(Icons.album_rounded, color: kBrandColor),
                title: Text('End of album',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white, fontSize: 13.5)),
                subtitle: Text('Pauses after this album\'s last queued track',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, fontSize: 11.5)),
                onTap: () {
                  player.startSleepTimerEndOfAlbum();
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
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (kIsWeb || isDesktop) {
      // Desktop controls Shuro's own output. System volume would alter every
      // other Windows/Linux app, which is surprising and not what this
      // player affordance promises.
      _systemTried = true;
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
    // No answer shortly â†’ honest fallback to the player's own volume.
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
      await context.read<PlaybackPrefs>().setAppVolume(v);
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
              child: ClickRegion(
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
                    : 'Shuro volume — does not change other applications'),
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
    return ClickRegion(
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

/// The action row under the transport (docs/02): heart on a white 10%
/// circle, add-to-playlist, the volume control (inline slider on desktop /
/// output chip on mobile), sleep timer and queue. Mobile keeps volume and
/// audio info reachable through a trailing overflow button - folded into a
/// sheet, never removed.
class _NpvActionRow extends StatelessWidget {
  final bool desktop;
  final Song song;
  final PlayerController player;
  final AppState appState;
  final bool isFav;
  final Color accent;

  const _NpvActionRow({
    required this.desktop,
    required this.song,
    required this.player,
    required this.appState,
    required this.isFav,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final sleepArmed = player.sleepUntil != null;
    // FittedBox: the row scales down rather than clipping on a narrow phone.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CircleAction(
            tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
            child: SizedBox(
              width: 40,
              height: 40,
              // AnimatedFavoriteIcon keeps its pop + semantics; the tight
              // 40x40 box reins its default 48 px IconButton in.
              child: AnimatedFavoriteIcon(
                isFavorite: isFav,
                activeColor: accent,
                inactiveColor: Colors.white60,
                size: 20,
                onTap: () => Favorites.toggle(context, song.id),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _CircleAction(
            icon: Icons.playlist_add_rounded,
            tooltip: 'Add to playlist',
            onTap: () => showAddToPlaylistSheet(context, song),
          ),
          const SizedBox(width: 12),
          if (desktop)
            _InlineVolume(player: player)
          else
            _OutputChip(
                width: 128, height: 36, defaultLabel: 'This phone'),
          const SizedBox(width: 12),
          _CircleAction(
            icon: Icons.bedtime_rounded,
            tooltip: sleepArmed
                ? 'Sleep timer running · ${formatSleepCountdown(player.sleepUntil!.difference(DateTime.now()))}'
                : 'Sleep timer',
            color: sleepArmed ? kVioletLight : Colors.white70,
            onTap: () => showSleepTimerSheet(context, player),
          ),
          const SizedBox(width: 12),
          QueuePeekButton(
            onOpen: () => showQueuePanel(context),
            child: _CircleAction(
              icon: Icons.queue_music_rounded,
              tooltip: 'Queue (hold to peek)',
              onTap: () => showQueuePanel(context),
            ),
          ),
          if (!desktop) ...[
            const SizedBox(width: 12),
            _CircleAction(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Volume and audio info',
              onTap: () => _showPlaybackOverflowSheet(context, song, player),
            ),
          ],
        ],
      ),
    );
  }
}

/// Volume / audio info for the mobile action row: the two controls that no
/// longer fit the redesigned row live behind one overflow button instead of
/// disappearing.
Future<void> _showPlaybackOverflowSheet(
    BuildContext context, Song song, PlayerController player) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.volume_up_rounded, color: kBrandColor),
            title: Text('Volume',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13.5)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showVolumeSheet(context, player);
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.info_outline_rounded, color: kBrandColor),
            title: Text('Audio info',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13.5)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showAudioInfoSheet(context, song);
            },
          ),
        ],
      ),
    ),
  );
}

/// 40 px circular action on a white 10% plate (docs/02 action row).
class _CircleAction extends StatelessWidget {
  final IconData? icon;

  /// Custom content (the heart) instead of an icon.
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  const _CircleAction({
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(color: kHairline),
          ),
          child: Center(
            child: child ?? Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// Inline volume for the desktop action row (docs/02): a 100-wide pill
/// slider plus numeric value, backed by the SAME source the volume sheet
/// uses - system media volume where the platform allows it, the player's own
/// volume otherwise (desktop/web). Never a fake control.
class _InlineVolume extends StatefulWidget {
  final PlayerController player;

  const _InlineVolume({required this.player});

  @override
  State<_InlineVolume> createState() => _InlineVolumeState();
}

class _InlineVolumeState extends State<_InlineVolume> {
  double? _systemVolume;
  StreamSubscription<double>? _sub;
  bool _systemWorking = false;
  late double _playerVolume = widget.player.playerVolume;

  @override
  void initState() {
    super.initState();
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (kIsWeb || isDesktop) {
      // Desktop controls Shuro's own output; system volume would change every
      // other application (see the volume sheet for the long version).
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
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    // Desktop (the only place this widget's system branch is skipped) never
    // registered a global listener, so this only touches real listeners.
    try {
      unawaited(VolumeController.instance.removeListener());
    } catch (_) {}
    super.dispose();
  }

  bool get _useSystem => !kIsWeb && _systemWorking;

  Future<void> _set(double v) async {
    if (_useSystem) {
      try {
        await VolumeController.instance.setVolume(v);
      } catch (_) {}
    } else {
      await context.read<PlaybackPrefs>().setAppVolume(v);
    }
  }

  void _onDrag(double dx, double width) {
    final value = (dx / width).clamp(0.0, 1.0);
    setState(() => _playerVolume = value);
    _set(value);
  }

  @override
  Widget build(BuildContext context) {
    final value =
        (_useSystem ? (_systemVolume ?? 0.5) : _playerVolume).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value == 0
              ? Icons.volume_off_rounded
              : value < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: 16,
          color: Colors.white60,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          height: 32,
          child: LayoutBuilder(
            builder: (context, c) => ClickRegion(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _onDrag(d.localPosition.dx, c.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _onDrag(d.localPosition.dx, c.maxWidth),
              // The fill edge IS the handle - no thumb (same control language
              // as the volume sheet).
              child: Center(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(currentFontFamily,
                color: kStatusText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}

/// The audio-output chip ("This computer" / "This phone" / the real device
/// name): glass pill on a hairline border. It reads the same capability
/// monitor the old "Playing from ..." line did - route changes repaint it
/// live - under the same honesty rule: an unknown route falls back to the
/// platform default label rather than a guess.
class _OutputChip extends StatefulWidget {
  /// Fixed pill width (mobile action row: 128). Null sizes to the label.
  final double? width;
  final double height;
  final String defaultLabel;

  const _OutputChip({
    this.width,
    this.height = 36,
    this.defaultLabel = 'This computer',
  });

  @override
  State<_OutputChip> createState() => _OutputChipState();
}

class _OutputChipState extends State<_OutputChip> {
  AudioCapabilityReport? _report;

  @override
  void initState() {
    super.initState();
    _report = sharedAudioCapabilityMonitor.last;
    // Follow the monitor so a route change (headset plugged, Bluetooth
    // connected) repaints the chip live.
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
    // Keep the previous route while a re-check is in flight - only a fresh
    // answer replaces the label, so it never flickers empty.
    if (latest != null) setState(() => _report = latest);
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    var label = widget.defaultLabel;
    var icon = isPhone ? Icons.smartphone_rounded : Icons.cast_rounded;
    final report = _report;
    if (report != null && report.routeKind != RouteKind.unknown) {
      final name = (report.routeLabel ?? '').trim();
      switch (report.routeKind) {
        case RouteKind.builtIn:
          break; // platform default label already set
        case RouteKind.bluetooth:
          label = name.isNotEmpty ? name : 'Bluetooth';
          icon = Icons.bluetooth_audio_rounded;
        case RouteKind.wired:
          label = name.isNotEmpty ? name : 'Wired headphones';
          icon = Icons.headset_rounded;
        case RouteKind.usb:
          label = name.isNotEmpty ? name : 'USB audio';
          icon = Icons.usb_rounded;
        case RouteKind.other:
          label = name.isNotEmpty ? name : 'External output';
          icon = Icons.speaker_rounded;
        case RouteKind.unknown:
          break;
      }
    }
    final song = context.watch<PlayerController>().currentSong;
    final small = widget.height <= 36;
    return Builder(
      builder: (anchor) {
        final pill = Container(
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: kGlass,
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisAlignment: widget.width != null
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            mainAxisSize:
                widget.width != null ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: small ? 12 : 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
        if (song == null) return pill;
        // Board: the chip opens the live signal path popover.
        return ClickRegion(
          onTap: () => showSignalPathPopover(context, anchor, song),
          child: pill,
        );
      },
    );
  }
  }

/// Desktop keyboard/gesture hint (docs/02): 11 px, white 45%.
class _HintLine extends StatelessWidget {
  const _HintLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        'Drag the ring to seek · Space play · ← → ±5 s · L lyrics',
        textAlign: TextAlign.center,
        style: GoogleFonts.getFont(currentFontFamily,
            color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
      ),
    );
  }
}

/// Three soft mesh blobs behind the Now Playing content (docs/02 backdrop):
/// pink / violet / cyan radial washes, each 0.5-0.7 of the screen, static.
/// Pre-blurred gradients (no ImageFilter, no ticker) - one cheap paint per
/// blob. Skipped entirely under reduce-motion.
class _MeshBlobs extends StatelessWidget {
  const _MeshBlobs();

  @override
  Widget build(BuildContext context) {
    if (reduceMotionEnabled) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final big = math.max(constraints.maxWidth, constraints.maxHeight);
        Widget blob(Color color, Alignment alignment, double fraction,
                double alpha) =>
            Align(
              alignment: alignment,
              child: Container(
                width: big * fraction,
                height: big * fraction,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    color.withValues(alpha: alpha),
                    color.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            );
        return Stack(
          fit: StackFit.expand,
          children: [
            // Pink top-left, violet bottom-right, cyan lower-left - the
            // left column (the player) keeps two of the three behind it.
            blob(kAccentColor, const Alignment(-0.85, -0.85), 0.7, 0.14),
            blob(kBrandColor, const Alignment(0.75, 0.8), 0.65, 0.12),
            blob(kSecondaryColor, const Alignment(-0.8, 0.75), 0.55, 0.12),
          ],
        );
      },
    );
  }
}

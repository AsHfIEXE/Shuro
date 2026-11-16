import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../screens/now_playing/queue_screen.dart';
import '../services/server_link.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';
import 'animated_favorite_icon.dart';
import 'artwork_thumb.dart';
import 'artwork_ring.dart';
import 'smooth_position_builder.dart';
import 'page_transitions.dart';
import 'shuro_icons.dart';
import 'click_region.dart';
import 'player_bar_extras.dart';

/// Persistent bar shown above the bottom nav on every main tab.
///
/// Redesign (docs/01 mobile rules): a 64 px bar with a 44 px RING artwork
/// (stroke 3, knob 9) that is itself the scrubber - drag or tap the ring to
/// seek, angle to fraction, preview while dragging, one engine seek on
/// release. The linear progress line is gone; the ring is the progress.
///  * **Queue is reachable from here.** A queue button on the right, because the
///    queue is the second most common thing to want mid-playback.
///  * **It uses the artwork's real palette**, not the per-ID placeholder colour,
///    so it agrees with Now Playing and Lyrics.
///  * **Wide windows get more, not just wider.** Past [_kWideBreakpoint] the bar
///    shows the album and a queue button; on a phone it stays compact.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  /// Above this width the bar has room to say more (tablet, desktop, TV).
  static const double _kWideBreakpoint = 1024;

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.currentSong);

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      child: song == null
          ? const SizedBox(width: double.infinity, key: ValueKey('empty'))
          : _MiniPlayerBar(key: ValueKey(song.id), song: song),
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  final Song song;
  const _MiniPlayerBar({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final isFav = appState.isFavoriteSong(song.id);
    final isActive = player.currentSong?.id == song.id;
    final isPlaying = isActive && player.isPlaying;
    final isBuffering = isActive && player.isBuffering;
    final wide = MediaQuery.sizeOf(context).width >= MiniPlayer._kWideBreakpoint;

    final bar = wide
        ? _desktopBar(context, player, appState, isFav, isActive, isPlaying,
            isBuffering)
        : _androidBar(context, player, appState, isFav, isActive, isPlaying,
            isBuffering);

    return ClickRegion(
      onTap: () => pushRisingOnce(context, NowPlayingScreen(initialSong: song)),
      // NOTE: horizontal swipe-to-skip used to live here, but it competed
      // with the seek bar's own horizontal drag in the gesture arena — the
      // progress line became undraggable (reported bug). Skipping stays on
      // the transport buttons; the bar keeps tap-to-open and swipe-up.
      // Swipe UP opens Now Playing (the tap does too — the gesture is the
      // shortcut for a thumb already resting on the bar).
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -350) {
          HapticFeedback.lightImpact();
          pushRisingOnce(context, NowPlayingScreen(initialSong: song));
        }
      },
      child: bar,
    );
  }

  /// Desktop / wide window: the redesign bar — palette-tinted surface, the
  /// 44 px ring artwork as the scrubber, queue peek on the side.
  Widget _desktopBar(
      BuildContext context,
      PlayerController player,
      AppState appState,
      bool isFav,
      bool isActive,
      bool isPlaying,
      bool isBuffering) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kCardColor,
            Color.lerp(kCardColor, song.gradientColors.first, 0.22) ??
                kCardColor,
          ],
        ),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _RingScrubber(song: song, player: player, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.artist} · ${appState.albumById(song.albumId)?.title ?? ''}'
                          .trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedFavoriteIcon(
                isFavorite: isFav,
                activeColor: song.gradientColors.last,
                inactiveColor: Colors.white70,
                size: 22,
                onTap: () => Favorites.toggle(context, song.id),
              ),
              QueuePeekButton(
                color: Colors.white70,
                iconSize: 22,
                onOpen: () => pushRisingOnce(context, const QueueScreen()),
              ),
              _TransportButton(
                icon: ShuroGlyph.previous,
                label: 'Previous track',
                onPressed: player.previous,
              ),
              _PlayPauseButton(
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                accent: song.gradientColors.last,
                onPressed: player.togglePlayPause,
              ),
              _TransportButton(
                icon: ShuroGlyph.next,
                label: 'Next track',
                onPressed: player.next,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Android kit bar (mobile, < 1024): 60 dp, flat raised surface with a
  /// hairline top, 44 dp square artwork (playing = dim scrim + bars), and a
  /// 2 dp violet progress line along the top edge. Violet is the only state
  /// colour; no gradients, no glows. Every touch target is >= 48 dp.
  Widget _androidBar(
      BuildContext context,
      PlayerController player,
      AppState appState,
      bool isFav,
      bool isActive,
      bool isPlaying,
      bool isBuffering) {
    return Container(
      decoration: const BoxDecoration(
        color: kRaisedColor,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Stack(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ArtworkThumb(
                    gradientColors: song.gradientColors,
                    artwork: song.artwork,
                    size: 44,
                    radius: 8,
                    iconSize: 18,
                    playing: isActive && isPlaying,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kMuted2, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: AnimatedFavoriteIcon(
                    isFavorite: isFav,
                    activeColor: kVioletPale,
                    inactiveColor: kMuted2,
                    size: 22,
                    onTap: () => Favorites.toggle(context, song.id),
                  ),
                ),
                _KitPlayPause(
                  isPlaying: isPlaying,
                  isBuffering: isBuffering,
                  onPressed: player.togglePlayPause,
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    tooltip: 'Next track',
                    onPressed: player.next,
                    icon: ShuroIcon(ShuroGlyph.next,
                        color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          // 2 dp violet progress line along the top edge - the flat Android
          // equivalent of the desktop ring.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SmoothPositionBuilder(
              builder: (context, p, position, progress) => Container(
                height: 2,
                color: Colors.transparent,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(color: kBrandColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The kit's play/pause: a flat 48 dp violet disc - no glow, violet is the
/// only state colour on the Android surface.
class _KitPlayPause extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPressed;

  const _KitPlayPause(
      {required this.isPlaying,
      required this.isBuffering,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isBuffering ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: kBrandColor,
            ),
            child: IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              icon: isBuffering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)))
                  : ShuroIcon(isPlaying ? ShuroGlyph.pause : ShuroGlyph.play,
                      color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mini player's 44 px ring artwork + scrubber (docs/02, mini variant).
///
/// Same interaction contract as the big Now Playing ring: dragging (or
/// tapping) anywhere on the ring sets a preview fraction from the touch
/// angle - 12 o'clock start, clockwise - and exactly ONE engine seek fires
/// on release. Haptic tick each crossed 10% boundary.
class _RingScrubber extends StatefulWidget {
  const _RingScrubber(
      {required this.song, required this.player, required this.size});

  final Song song;
  final PlayerController player;
  final double size;

  @override
  State<_RingScrubber> createState() => _RingScrubberState();
}

class _RingScrubberState extends State<_RingScrubber> {
  double? _preview;
  Duration? _hoverTime;
  Offset? _hoverPos;
  int _lastTickBucket = -1;

  void _onPreview(double fraction) {
    // Haptic tick each 10% of the ring swept through.
    final bucket = (fraction * 10).floor();
    if (bucket != _lastTickBucket) {
      _lastTickBucket = bucket;
      HapticFeedback.selectionClick();
    }
    setState(() => _preview = fraction);
  }

  Future<void> _commit(double fraction) {
    final total = widget.player.duration.inMilliseconds;
    if (total <= 0) return Future<void>.value();
    return widget.player
        .seekTo(Duration(milliseconds: (total * fraction).round()));
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final player = widget.player;
    final isActive = player.currentSong?.id == song.id;
    final live = isActive && player.loadedSongId == song.id;

    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      final center = Offset(box.width / 2, box.height / 2);
      double fractionAt(Offset position) {
        final angle =
            math.atan2(position.dy - center.dy, position.dx - center.dx);
        // 12 o'clock start, clockwise - matches ProgressRingPainter.
        return (((angle + math.pi / 2) / (2 * math.pi)) % 1.0 + 1.0) % 1.0;
      }

      return MouseRegion(
        onHover: (e) {
          final total = widget.player.duration;
          if (total <= Duration.zero) return;
          final f = fractionAt(e.localPosition);
          // Fraction -> time: clamp inside [0, total).
          final t = Duration(
              milliseconds:
                  (total.inMilliseconds * f).round().clamp(0, total.inMilliseconds - 1));
          setState(() {
            _hoverTime = t;
            _hoverPos = e.localPosition;
          });
        },
        onExit: (_) => setState(() {
          _hoverTime = null;
          _hoverPos = null;
        }),
        child: ClickRegion(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final target = fractionAt(details.localPosition);
          _onPreview(target);
          _commit(target).whenComplete(() {
            if (mounted) setState(() => _preview = null);
          });
        },
        onPanStart: (details) => _onPreview(fractionAt(details.localPosition)),
        onPanUpdate: (details) => _onPreview(fractionAt(details.localPosition)),
        onPanEnd: (_) {
          final target = _preview;
          if (target == null) return;
          // Hold the preview until the engine confirms - clearing first made
          // the ring snap back then jump (same audit finding as the old bar).
          _commit(target).whenComplete(() {
            if (mounted && _preview == target) setState(() => _preview = null);
          });
        },
        onPanCancel: () => setState(() => _preview = null),
        child: SizedBox(
          width: widget.size + 12,
          height: widget.size + 12,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
            child: _preview != null || !live
                ? ArtworkRing(
                    song: song,
                    progress: live ? _preview! : 0,
                    buffered: live ? player.bufferedFraction : null,
                    colors: song.gradientColors,
                    size: widget.size,
                    strokeWidth: NpvMetrics.ringStrokeMini,
                    knobSize: NpvMetrics.knobMini,
                    scrubbing: _preview != null,
                  )
                : SmoothPositionBuilder(
                    builder: (context, player, position, progress) =>
                        ArtworkRing(
                      song: song,
                      progress: progress,
                      buffered: player.bufferedFraction,
                      colors: song.gradientColors,
                      size: widget.size,
                      strokeWidth: NpvMetrics.ringStrokeMini,
                      knobSize: NpvMetrics.knobMini,
                    ),
                  ),
              ),
              if (_hoverTime != null && _hoverPos != null)
                Positioned(
                  left: (_hoverPos!.dx - 24).clamp(0.0, widget.size - 36),
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_hoverTime!.inMinutes}:${(_hoverTime!.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      );
    });
  }
}

class _TransportButton extends StatelessWidget {
  final ShuroGlyph icon;
  final String label;
  final VoidCallback onPressed;

  const _TransportButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        tooltip: label,
        icon: ShuroIcon(icon, color: Colors.white, size: 26),
        onPressed: onPressed,
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final Color accent;
  final VoidCallback onPressed;

  const _PlayPauseButton(
      {required this.isPlaying,
      required this.isBuffering,
      required this.accent,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isBuffering ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          // Filled accent disc with a soft glow — the one anchored control on
          // the bar; prev/next stay quiet beside it.
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 1),
            ],
          ),
          child: IconButton(
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: onPressed,
            icon: isBuffering
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)))
                : ShuroIcon(isPlaying ? ShuroGlyph.pause : ShuroGlyph.play,
                    color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

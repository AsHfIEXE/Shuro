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
import 'animated_favorite_icon.dart';
import 'artwork_thumb.dart';
import 'page_transitions.dart';
import 'shuro_icons.dart';

/// Persistent bar shown above the bottom nav on every main tab.
///
/// What changed, and why (the previous version was reported as cramped and
/// uninformative):
///
///  * **The progress bar is seekable.** It used to be a 2 px read-only
///    indicator. It is now a real drag target with a comfortably tall hit area,
///    so the most common action ("skip ahead a bit") no longer requires opening
///    the full screen.
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
      child: song == null ? const SizedBox(width: double.infinity, key: ValueKey('empty')) : _MiniPlayerBar(key: ValueKey(song.id), song: song),
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
    final width = MediaQuery.of(context).size.width;
    final wide = width >= MiniPlayer._kWideBreakpoint;

    return GestureDetector(
      onTap: () => pushRisingOnce(context, NowPlayingScreen(initialSong: song)),
      // Swipe left/right skips — a shortcut on top of (not instead of) the tap
      // and the transport buttons. Deliberately not the *only* way to skip: it
      // would be unreachable on a TV remote.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 200) return;
        HapticFeedback.lightImpact();
        if (velocity < 0) {
          player.next();
        } else {
          player.previous();
        }
      },
      // Swipe UP opens Now Playing (the tap does too — the gesture is the
      // shortcut for a thumb already resting on the bar).
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -350) {
          HapticFeedback.lightImpact();
          pushRisingOnce(context, NowPlayingScreen(initialSong: song));
        }
      },
      child: Container(
        // Palette-tinted: the bar quietly picks up the track's own colours —
        // same design language as the NPV backdrop — over the base card color.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kCardColor,
              Color.lerp(kCardColor, song.gradientColors.first, 0.22) ?? kCardColor,
            ],
          ),
          // No border of its own: the mini player lives INSIDE the nav bar's
          // rounded block now (see ShuroNavBar.header), so its own edges would
          // draw mismatched corners against the bar's.
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 12, vertical: 8),
              child: Row(
                children: [
                  Hero(
                    tag: 'artwork_${song.id}',
                    child: ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: wide ? 48 : 44, radius: 8),
                  ),
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
                          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: wide ? 14 : 13.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          wide ? '${song.artist} · ${appState.albumById(song.albumId)?.title ?? ''}'.trim() : song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 12),
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
                  if (wide)
                    IconButton(
                      tooltip: 'Queue',
                      icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
                      onPressed: () => pushRisingOnce(context, const QueueScreen()),
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
            // The progress line is the bar's BASE EDGE — bottom, full-bleed —
            // the classic mini-player read: content above, position below.
            _SeekBar(player: player, song: song),
          ],
        ),
      ),
    );
  }
}

/// The draggable progress bar. A thin line, but with a 20 px-tall hit area so it
/// can actually be grabbed; drag anywhere on it to seek.
class _SeekBar extends StatelessWidget {
  final PlayerController player;
  final Song song;

  const _SeekBar({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final isActive = player.currentSong?.id == song.id;
    // Live only when the engine has audio for THIS song loaded — during the
    // load window the engine still reports the outgoing track's duration,
    // which must not size this bar (audit finding F6-1).
    final live = isActive && player.loadedSongId == song.id;
    final total = live ? player.duration : song.duration;
    final totalMs = total.inMilliseconds == 0 ? 1 : total.inMilliseconds;

    return LayoutBuilder(
      builder: (context, constraints) {
        void seekTo(double dx) {
          if (!isActive) return;
          final fraction = (dx / constraints.maxWidth).clamp(0.0, 1.0);
          player.seekTo(Duration(milliseconds: (totalMs * fraction).round()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition.dx),
          child: SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.center,
              child: SmoothProgressBar(
                player: player,
                songId: song.id,
                totalMs: totalMs,
                accent: song.gradientColors.last,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Only this 2 px line repaints per frame — it listens to the interpolated
/// position stream directly instead of rebuilding the whole bar.
class SmoothProgressBar extends StatelessWidget {
  final PlayerController player;
  final String songId;
  final int totalMs;
  final Color accent;

  const SmoothProgressBar({super.key, required this.player, required this.songId, required this.totalMs, required this.accent});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.smoothPositionStream,
      builder: (context, snapshot) {
        final isActive = player.currentSong?.id == songId;
        final live = isActive && player.loadedSongId == songId;
        final position = live ? (snapshot.data ?? player.position) : Duration.zero;
        final value = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: value,
          minHeight: 2,
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation(accent),
        );
      },
    );
  }
}

class _TransportButton extends StatelessWidget {
  final ShuroGlyph icon;
  final String label;
  final VoidCallback onPressed;

  const _TransportButton({required this.icon, required this.label, required this.onPressed});

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

  const _PlayPauseButton({required this.isPlaying, required this.isBuffering, required this.accent, required this.onPressed});

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
              BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: 1),
            ],
          ),
          child: IconButton(
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: onPressed,
            icon: isBuffering
                ? const SizedBox(width: 22, height: 22, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : ShuroIcon(isPlaying ? ShuroGlyph.pause : ShuroGlyph.play, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

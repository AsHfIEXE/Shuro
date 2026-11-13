import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'animated_favorite_icon.dart';
import 'shuro_icons.dart';
import 'click_region.dart';
import 'motion.dart';

/// Track title + artist, flanked by shuffle/repeat — the "Música/Artista"
/// row from the design. [accent] is passed in explicitly (the track's
/// *real* artwork-derived color, resolved once by the screen that hosts
/// this — see NowPlayingScreen) rather than read off `song.gradientColors`
/// here, since that per-ID hash color has nothing to do with what the
/// cover art actually looks like.
///
/// The redesigned Now Playing (docs/02) no longer uses this row — its
/// shuffle/repeat moved to the transport flanks and the metadata grew a
/// dedicated block — but it remains the shared row for the compact
/// landscape cluster and any future host, so the layout stays identical
/// across the app.
class TrackInfoRow extends StatelessWidget {
  final Song song;
  final Color accent;
  final bool shuffleOn;
  final PlayerRepeatMode repeatMode;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;

  /// The favourite sweet spot: a compact heart right under the artist — the
  /// most natural place to love a track while it plays. Null/absent = the
  /// caller doesn't want it rendered here.
  final bool? isFavorite;
  final VoidCallback? onToggleFavorite;

  /// Short-window sizing (landscape phones): smaller type and heart so the
  /// whole player column fits the viewport without clipping.
  final bool dense;

  const TrackInfoRow({
    super.key,
    required this.song,
    required this.accent,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PlayerModeButton(
            shuroIcon: ShuroGlyph.shuffle,
            modeLabel: 'Shuffle',
            active: shuffleOn,
            accent: accent,
            onTap: onShuffleToggle,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  song.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: dense ? 18 : 22,
                      height: dense ? 24 / 18 : 28 / 22,
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dense ? 2 : 4),
                Text(
                  song.artist,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white70,
                      fontSize: dense ? 12.5 : 14,
                      height: dense ? 17 / 12.5 : 20 / 14,
                      fontWeight: FontWeight.w500,
                      shadows: const [
                        Shadow(color: Color(0x66000000), blurRadius: 6)
                      ]),
                ),
                if (isFavorite != null && onToggleFavorite != null) ...[
                  SizedBox(height: dense ? 2 : 6),
                  // The favourite sweet spot: heart under the artist, one tap
                  // from the thumb's natural arc while the transport plays.
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onToggleFavorite,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10, vertical: dense ? 1 : 3),
                      child: AnimatedFavoriteIcon(
                        isFavorite: isFavorite!,
                        activeColor: accent,
                        inactiveColor: Colors.white60,
                        size: dense ? 17 : 20,
                        onTap: onToggleFavorite!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The icon itself changes for repeat-one, so "one" and "all" are
          // different pictures — plus the badge makes it unmistakable.
          PlayerModeButton(
            materialIcon: repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            modeLabel: switch (repeatMode) {
              PlayerRepeatMode.off => 'Repeat off',
              PlayerRepeatMode.all => 'Repeat all',
              PlayerRepeatMode.one => 'Repeat one',
            },
            active: repeatMode != PlayerRepeatMode.off,
            badge: repeatMode == PlayerRepeatMode.one ? '1' : null,
            accent: accent,
            onTap: onRepeatToggle,
          ),
        ],
      ),
    );
  }
}

/// Previous / play-pause / next — the "Play/Pause" group from the design.
///
/// Two geometries:
///
///  * **Legacy** (no [discSize]): a centred row with an 80 dp accent disc
///    (56 compact), used by the landscape-compact cluster where the column
///    is barely 360 dp tall.
///  * **Redesigned** ([discSize] set, docs/02): exact board geometry — the
///    play disc is WHITE with dark icons and a soft drop shadow, prev/next
///    get explicit icon sizes, and [flankDistance] pins the shuffle/repeat
///    centres at ±2·62 (desktop) / ±2·54 (mobile) from the middle. The row
///    is then a fixed-width `spaceBetween` so those offsets are exact.
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;

  /// True while the current track's audio is still loading or refilling its
  /// buffer — the play button then shows progress instead of a play glyph, so
  /// a slow track doesn't look like an ignored tap.
  final bool isBuffering;
  final Color accentColor;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Smaller footprint for short (landscape phone) windows, where the
  /// 80 dp disc plus default icon padding was the element that pushed the
  /// whole column past the viewport and clipped the transport at the
  /// screen's bottom edge.
  final bool compact;

  /// Optional widgets at the far ends of the row (e.g. shuffle / repeat), so a
  /// short window can show the whole control cluster on one line.
  final Widget? leading;
  final Widget? trailing;

  /// Play disc diameter for the redesigned geometry: 76 on desktop, 68 on
  /// mobile ([NpvMetrics.playDiscDesktop] / [NpvMetrics.playDiscMobile]).
  /// Null keeps the legacy 80/56 accent disc.
  final double? discSize;

  /// Distance of the flank (shuffle/repeat) button CENTRES from the row
  /// centre: ±2·62 = 124 on desktop, ±2·54 = 108 on mobile (docs/02).
  /// Only meaningful together with [discSize] and a [leading] widget.
  final double? flankDistance;

  /// Prev/next icon size: 35 desktop / 31 mobile (legacy stays 30).
  final double? prevNextIconSize;

  /// White disc with dark icons and subtle elevation (redesign) instead of
  /// the accent gradient with a glow.
  final bool whiteDisc;

  const PlaybackControls({
    super.key,
    this.leading,
    this.trailing,
    required this.isPlaying,
    required this.accentColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    this.isBuffering = false,
    this.compact = false,
    this.discSize,
    this.flankDistance,
    this.prevNextIconSize,
    this.whiteDisc = false,
  });

  @override
  Widget build(BuildContext context) {
    // Redesigned transport only when the board geometry was asked for.
    if (discSize != null) return _buildRedesigned(context);
    return _buildLegacy(context);
  }

  // --- legacy: centred accent-disc row (landscape compact) ------------------

  Widget _buildLegacy(BuildContext context) {
    final discSize = compact ? 56.0 : 80.0;
    final iconSize = compact ? 24.0 : 30.0;
    final gap = compact ? 18.0 : 26.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, SizedBox(width: gap * 0.5)],
        Semantics(
          button: true,
          label: 'Previous track',
          child: IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            icon: ShuroIcon(ShuroGlyph.previous,
                size: iconSize, color: Colors.white),
            onPressed: onPrevious,
            tooltip: 'Previous',
          ),
        ),
        SizedBox(width: gap),
        _disc(discSize, compact ? 24.0 : 34.0),
        SizedBox(width: gap),
        Semantics(
          button: true,
          label: 'Next track',
          child: IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            icon: ShuroIcon(ShuroGlyph.next, size: iconSize, color: Colors.white),
            onPressed: onNext,
            tooltip: 'Next',
          ),
        ),
        if (trailing != null) ...[SizedBox(width: gap * 0.5), trailing!],
      ],
    );
  }

  // --- redesigned: exact board geometry (docs/02 transport) ----------------

  Widget _buildRedesigned(BuildContext context) {
    final disc = discSize!;
    // Touch targets: 48 desktop / 44 mobile (the a11y floor) — the flank
    // distance is measured to these slots' centres.
    final sideBox = disc >= 76 ? 48.0 : 44.0;
    final iconSize = prevNextIconSize ?? 30.0;

    Widget flank(Widget? child) => child == null
        ? const SizedBox.shrink()
        : SizedBox(
            width: sideBox, height: disc, child: Center(child: child));

    Widget skip(String label, ShuroGlyph glyph, VoidCallback? onPressed) =>
        SizedBox(
          width: sideBox,
          height: disc,
          child: Center(
            child: IconButton(
              tooltip: label,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: iconSize,
              visualDensity: VisualDensity.compact,
              icon: ShuroIcon(glyph, size: iconSize, color: Colors.white),
              onPressed: onPressed,
            ),
          ),
        );

    final children = [
      if (leading != null) flank(leading),
      skip('Previous', ShuroGlyph.previous, onPrevious),
      _disc(disc, (disc * 0.42).roundToDouble()),
      skip('Next', ShuroGlyph.next, onNext),
      if (trailing != null) flank(trailing),
    ];

    if (flankDistance != null && leading != null) {
      // Fixed width + spaceBetween: with symmetric outer slot widths the
      // flank centres land exactly at ±flankDistance from the middle.
      final rowWidth = 2 * flankDistance! + sideBox;
      return SizedBox(
        width: rowWidth,
        height: disc,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          children[i],
        ],
      ],
    );
  }

  /// The play disc itself. Redesign: white plate, DARK glyphs, one soft drop
  /// shadow ("subtle elevation"). Legacy: accent gradient + accent glow.
  /// The buffering spinner keeps working in both, recoloured to sit on the
  /// disc.
  Widget _disc(double size, double iconSize) {
    final fg = whiteDisc ? kSurfaceColor : Colors.white;
    return ClickRegion(
      onTap: onPlayPause,
      child: PressScale(child: Semantics(
        button: true,
        label: isBuffering ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: ShuroMotion.std,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: whiteDisc ? Colors.white : null,
            gradient: whiteDisc
                ? null
                : LinearGradient(colors: [
                    accentColor,
                    accentColor.withValues(alpha: 0.7)
                  ]),
            boxShadow: whiteDisc
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            // docs/02 motion: play/pause glyph cross-fades in 160 ms.
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: isBuffering
                ? Padding(
                    key: const ValueKey('buffering'),
                    padding: EdgeInsets.all(size * 0.33),
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: fg),
                  )
                : ShuroIcon(
                    isPlaying ? ShuroGlyph.pause : ShuroGlyph.play,
                    key: ValueKey(isPlaying),
                    color: fg,
                    size: iconSize,
                  ),
          ),
        ),
      )),
    );
  }
}

/// A shuffle/repeat toggle whose state is impossible to misread.
///
/// The old versions were the same icon at one of two opacities, which read as
/// "dimmed because inactive" — there was no way to tell whether shuffle was on.
/// This one mutes the icon when off, colours it with the accent and draws a dot
/// under it when on, swaps the icon entirely for repeat-one, and states the mode
/// in words for screen readers and tooltips.
///
/// [plain] drops the dim background circle for the redesigned transport
/// flanks (docs/02): bare icons at white 60% when off; on-state colour comes
/// from [activeColor] (repeat: brand violet; shuffle: full white) plus the dot.
class PlayerModeButton extends StatelessWidget {
  /// Shuro's own glyph set, when the mode has one (shuffle).
  final ShuroGlyph? shuroIcon;

  /// A Material icon, for modes the glyph set doesn't cover (repeat-one).
  final IconData? materialIcon;
  final String modeLabel;
  final bool active;
  final String? badge;
  final Color accent;
  final VoidCallback onTap;

  /// Bare-icon variant for the transport flanks — no tinted circle.
  final bool plain;

  /// Icon size (transport flanks shrink to 20-22).
  final double size;

  /// Colour used for the ON state (defaults to [accent]); the redesigned
  /// repeat passes brand violet regardless of the track's artwork accent.
  final Color? activeColor;

  const PlayerModeButton({
    super.key,
    required this.modeLabel,
    required this.active,
    required this.accent,
    required this.onTap,
    this.shuroIcon,
    this.materialIcon,
    this.badge,
    this.plain = false,
    this.size = 22,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = activeColor ?? accent;
    final colour = plain
        ? (active ? onColor : Colors.white.withValues(alpha: 0.6))
        : (active ? accent : Colors.white.withValues(alpha: 0.9));
    final iconWidget = materialIcon != null
        ? Icon(materialIcon, size: size, color: colour)
        : ShuroIcon(shuroIcon!, size: size, color: colour);

    // Plain mode marks ON with a small dot under the icon — without the
    // tinted circle there is no other place for the state to live.
    final content = (plain && active && badge == null)
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: onColor, shape: BoxShape.circle),
              ),
            ],
          )
        : iconWidget;

    // A dim circle behind every (non-plain) mode button: on Now Playing the
    // background is bright blurred artwork, and bare white54 icons
    // disappeared into it (the "shuffle button is gone" report). The circle
    // keeps both states readable over any cover; the active state adds the
    // accent tint + the dot below.
    return Semantics(
      button: true,
      label: '$modeLabel, ${active ? 'on' : 'off'}',
      child: IconButton(
        tooltip: '$modeLabel — ${active ? 'on' : 'off'}',
        onPressed: onTap,
        style: plain
            ? null
            : IconButton.styleFrom(
                backgroundColor: active
                    ? accent.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.28),
              ),
        icon: badge == null
            ? content
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  content,
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        badge!,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

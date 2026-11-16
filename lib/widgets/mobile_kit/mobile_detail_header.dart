import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Android Album / Playlist header (< 900 dp wide). Centred 216 dp cover, one
/// wash of the artwork's own colour that fades out by 420 dp, then a single
/// filled violet Play pill with two quiet round buttons beside it. Every touch
/// target is >= 48 dp. Put it as the first sliver (SliverToBoxAdapter) under a
/// transparent SliverAppBar that carries back + more.
class MobileDetailHeader extends StatelessWidget {
  final String title;
  final Widget cover; // 216 dp square, radius 16 (ArtworkThumb)
  final Color accent;
  final Widget? byline; // tappable artist/owner text
  final List<String> meta;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final Widget? trailingAction; // e.g. heart button

  const MobileDetailHeader({
    super.key,
    required this.title,
    required this.cover,
    required this.accent,
    this.byline,
    this.meta = const [],
    this.onPlay,
    this.onShuffle,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final metaText = meta.where((m) => m.isNotEmpty).join(' · ');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.55 * 0.8), kSurfaceColor.withValues(alpha: 0)],
          stops: const [0, 1],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          Container(
            width: 216,
            height: 216,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kHairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: cover,
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: headingFont(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 34 / 28)),
          if (byline != null) ...[const SizedBox(height: 6), byline!],
          if (metaText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(metaText,
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kStatusText,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: Text('Play',
                        style: GoogleFonts.getFont(currentFontFamily,
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _RoundOutline(
                  icon: Icons.shuffle_rounded, tooltip: 'Shuffle', onTap: onShuffle),
              if (trailingAction != null) ...[
                const SizedBox(width: 12),
                trailingAction!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 52 dp outlined circle button (shuffle, favourite, download).
class MobileRoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  const MobileRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.activeColor = kAccentColor,
  });

  @override
  Widget build(BuildContext context) => _RoundOutline(
      icon: icon, tooltip: tooltip, onTap: onTap, active: active, activeColor: activeColor);
}

class _RoundOutline extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  const _RoundOutline({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.activeColor = kAccentColor,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: Colors.transparent,
            shape: CircleBorder(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, size: 22, color: active ? activeColor : kTextColor),
            ),
          ),
        ),
      );
}

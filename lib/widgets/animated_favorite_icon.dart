import 'package:flutter/material.dart';
import 'shuro_icons.dart';

/// A heart icon that pops with a quick scale-bounce when toggled, instead
/// of a hard instant swap. One TweenAnimationBuilder, driven purely by the
/// [isFavorite] value changing — no controller to manage or dispose.
class AnimatedFavoriteIcon extends StatelessWidget {
  final bool isFavorite;
  final Color activeColor;
  final Color inactiveColor;
  final double size;
  final VoidCallback onTap;

  const AnimatedFavoriteIcon({
    super.key,
    required this.isFavorite,
    required this.onTap,
    this.activeColor = Colors.red,
    this.inactiveColor = Colors.white,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: TweenAnimationBuilder<double>(
        key: ValueKey(isFavorite),
        tween: Tween(begin: 0.6, end: 1.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: ShuroIcon(
          isFavorite ? ShuroGlyph.heartFilled : ShuroGlyph.heartOutline,
          color: isFavorite ? activeColor : inactiveColor,
          size: size,
        ),
      ),
    );
  }
}

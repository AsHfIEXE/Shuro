import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'page_transitions.dart';

/// A single pulsing placeholder block for skeleton-loading states. One
/// shared, cheap opacity tween (no shader/gradient sweep) — enough to read
/// as "loading" without extra render cost, and stops entirely once its
/// widget is removed from the tree.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({super.key, this.width, required this.height, this.radius = 8});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _opacity = Tween(begin: 0.35, end: 0.7).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Settings → Appearance → Reduce animations: a pulsing placeholder is motion
    // for its own sake, so it becomes a plain static block instead of animating
    // forever.
    if (reduceMotionEnabled) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: kCardColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: kCardColor.withValues(alpha: _opacity.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

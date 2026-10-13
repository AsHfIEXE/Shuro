import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A small branded loading animation (pulsing equalizer bars in the brand
/// gradient) used for "connecting" / "loading your library" moments,
/// instead of a generic spinner — one AnimationController, cheap to run,
/// disposed with its widget.
class BrandLoadingIndicator extends StatefulWidget {
  final double size;
  const BrandLoadingIndicator({super.key, this.size = 56});

  @override
  State<BrandLoadingIndicator> createState() => _BrandLoadingIndicatorState();
}

class _BrandLoadingIndicatorState extends State<BrandLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(4, (i) {
              final t = (_controller.value + i * 0.22) % 1.0;
              final wave = (t < 0.5 ? t * 2 : (1 - t) * 2);
              final height = widget.size * (0.28 + 0.62 * wave);
              return Container(
                width: widget.size * 0.12,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.size * 0.06),
                  gradient: const LinearGradient(colors: kBrandGradient, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

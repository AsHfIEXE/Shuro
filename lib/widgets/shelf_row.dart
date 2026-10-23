import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A horizontal shelf with hover arrows that step WHOLE cards (design doc,
/// phase 3): mouse users never need shift-wheel, and no card is left cut in
/// half at a stopped position reached via the arrows.
///
/// The list itself stays a plain horizontal [ListView]; the arrows animate
/// the controller by [stepWidth], so a step lands exactly on the next card
/// edge. Arrows appear on hover and hide at the respective ends.
class ShelfRow extends StatefulWidget {
  /// Height of the list area (a rail height, e.g. cardRailHeight(context)).
  final double height;

  /// One card's width, and the gap between cards. The arrow step — one whole
  /// card plus its gap — is derived, so a step always lands on a card edge.
  final double cardWidth;
  final double gap;

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  /// Horizontal padding of the list.
  final EdgeInsets padding;

  const ShelfRow({
    super.key,
    required this.height,
    required this.cardWidth,
    this.gap = 16,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });


  @override
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> {
  final ScrollController _controller = ScrollController();
  bool _hovering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canGoLeft =>
      _controller.hasClients && _controller.position.pixels > 1;

  bool get _canGoRight => _controller.hasClients
      ? _controller.position.pixels <
          _controller.position.maxScrollExtent - 1
      : true;

  void _step({required bool forward}) {
    if (!_controller.hasClients) return;
    final step = widget.cardWidth + widget.gap;
    final target = (_controller.position.pixels + (forward ? step : -step))
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    HapticFeedback.selectionClick();
    setState(() {}); // refresh the end-of-list arrow states
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              itemCount: widget.itemCount,
              separatorBuilder: (_, __) => SizedBox(width: widget.gap),
              itemBuilder: widget.itemBuilder,
            ),
            // Edge fades + arrows, visible only while the pointer is over
            // the shelf and only in the direction that has more cards.
            if (_hovering && _canGoLeft) _arrow(alignment: -1),
            if (_hovering && _canGoRight) _arrow(alignment: 1),
          ],
        ),
      ),
    );
  }

  Widget _arrow({required int alignment}) {
    return Align(
      alignment:
          alignment < 0 ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(
          left: alignment < 0 ? 4 : 0,
          right: alignment > 0 ? 4 : 0,
        ),
        child: _ArrowButton(
          forward: alignment > 0,
          onTap: () => _step(forward: alignment > 0),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final bool forward;
  final VoidCallback onTap;

  const _ArrowButton({required this.forward, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardColor.withValues(alpha: 0.92),
      elevation: 3,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            forward
                ? Icons.chevron_right_rounded
                : Icons.chevron_left_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

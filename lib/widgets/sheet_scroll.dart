import 'package:flutter/material.dart';

/// Makes a bottom-sheet body safe at any window height.
///
/// A plain `showModalBottomSheet` caps its content at 9/16 of the screen,
/// which is only ~230 dp on a landscape phone (411 dp tall). A sheet with four
/// or five ListTiles overflows there and paints the yellow-black stripes. Use
/// this around the sheet body *together with* `isScrollControlled: true` (the
/// 9/16 cap only goes away in that mode): the content is bounded to 85% of the
/// window and scrolls instead of overflowing. Same shape as the song-actions
/// sheet, factored out so every sheet can share it.
class SheetScroll extends StatelessWidget {
  final Widget child;
  const SheetScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: child),
    );
  }
}

/// [SafeArea] + [SheetScroll] in one widget, so a sheet that already starts with
/// `SafeArea(child: ...)` becomes overflow-proof by renaming that one widget
/// (and adding `isScrollControlled: true` to its `showModalBottomSheet`).
class ScrollSafeArea extends StatelessWidget {
  final Widget child;
  const ScrollSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SafeArea(child: SheetScroll(child: child));
}

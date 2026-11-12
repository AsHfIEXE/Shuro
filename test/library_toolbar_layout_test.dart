import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/screens/library/library_controls.dart';

/// The library toolbar contract, at every width:
///   - the trailing controls always end flush at the toolbar's right edge
///     (right-aligned in the wide row AND on narrow columns),
///   - every control shares the same 36 px height, so nothing sits 1-2 px
///     off its neighbours.
void main() {
  const rightInset = 20.0; // default toolbar padding LTRB(20, 8, 20, 0).

  Widget harness(double width) {
    final controller = TextEditingController();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: LibraryToolbar(
              countLabel: '911 songs',
              filterController: controller,
              filterHint: 'Filter',
              onFilterChanged: () {},
              trailing: [
                LibrarySortMenu<int>(
                    key: const Key('sort'),
                    value: 1,
                    options: const {1: 'Name'},
                    onSelected: (_) {}),
                LibraryViewToggle(
                    key: const Key('view'),
                    value: LibraryView.grid,
                    onChanged: (_) {}),
                const LibraryPill(
                    key: Key('play'),
                    label: 'Play all',
                    icon: Icons.play_arrow_rounded,
                    onTap: null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  for (final width in [1200.0, 900.0, 700.0, 420.0]) {
    testWidgets('controls end flush right at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(width));
      await tester.pump();

      final toolbar = tester.getRect(find.byType(LibraryToolbar));
      final sort = tester.getRect(find.byKey(const Key('sort')));
      final view = tester.getRect(find.byKey(const Key('view')));
      final play = tester.getRect(find.byKey(const Key('play')));
      // ignore: avoid_print
      print('W$width toolbar=$toolbar sort=$sort view=$view play=$play');

      // Flush right: the last control's right edge is the toolbar's right
      // edge minus the toolbar's own right padding.
      expect(play.right, moreOrLessEquals(toolbar.right - rightInset, epsilon: 0.5),
          reason: 'Play all must sit flush right at $width px');

      // Uniform 36 px band and sort -> view -> play order.
      expect(sort.height, moreOrLessEquals(36, epsilon: 1.0),
          reason: 'sort menu is 36 px at $width px');
      expect(view.height, moreOrLessEquals(36, epsilon: 1.0),
          reason: 'view toggle must match the 36 px row at $width px');
      expect(play.height, moreOrLessEquals(36, epsilon: 1.0),
          reason: 'pill is 36 px at $width px');
      // Order holds within a single run; when the controls wrap on the
      // narrowest columns the last run just needs to stay flush right.
      if (sort.top == play.top) {
        expect(sort.left, lessThan(view.left));
        expect(view.left, lessThan(play.left));
      }
    });
  }
}

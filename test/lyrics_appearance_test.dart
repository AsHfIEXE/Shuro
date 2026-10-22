import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/screens/now_playing/lyrics_appearance_sheet.dart';
import 'package:shuro/state/appearance_settings.dart';

/// The three knobs must actually move the notifier the lyrics screen renders
/// from — a control that changes nothing is decoration.
void main() {
  testWidgets('the sheet drives the persisted appearance state',
      (tester) async {
    final appearance = AppearanceSettings();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceSettings>.value(
        value: appearance,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );

    // Not awaited: the sheet's future only completes when it closes.
    unawaited(showLyricsAppearanceSheet(
        tester.element(find.byType(SizedBox).first)));
    await tester.pumpAndSettle();

    // Defaults are the designed look.
    expect(appearance.lyricsFontScale, 1.0);
    expect(appearance.lyricsAlignCenter, isTrue);
    expect(appearance.lyricsGlow, isTrue);

    // Alignment: centre -> left.
    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();
    expect(appearance.lyricsAlignCenter, isFalse);

    // Glow off.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(appearance.lyricsGlow, isFalse);

    // Size: drag right grows the scale within the clamp.
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(appearance.lyricsFontScale, greaterThan(1.0));
    expect(appearance.lyricsFontScale, lessThanOrEqualTo(1.5));
  });

  test('setters clamp the font scale to the honest range', () async {
    final appearance = AppearanceSettings();
    await appearance.setLyricsFontScale(3.0);
    expect(appearance.lyricsFontScale, 1.5);
    await appearance.setLyricsFontScale(0.1);
    expect(appearance.lyricsFontScale, 0.85);
  });
}

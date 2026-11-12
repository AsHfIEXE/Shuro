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

    // Glow off. The sheet's own 44x26 violet switch (a second, frozen
    // instance previews the look, so target the real one).
    await tester.tap(find.byType(LyricsSwitch).first);
    await tester.pumpAndSettle();
    expect(appearance.lyricsGlow, isFalse);

    // Size: the sheet's private gradient slider (4 px pink-violet track,
    // 5% steps). Tap the far right of the track to land near 100% no
    // matter how wide the sheet rendered.
    final slider = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_GradientSlider');
    expect(slider, findsOneWidget);
    final track = tester.getRect(slider);
    await tester.tapAt(Offset(track.right - 8, track.center.dy));
    await tester.pumpAndSettle();
    expect(appearance.lyricsFontScale, greaterThan(1.0));
    expect(appearance.lyricsFontScale, lessThanOrEqualTo(1.5));

    // Drain the sheet's one-shot timers (4 s preview, 25 s lookup
    // timeout) so the test ends with nothing pending.
    await tester.pump(const Duration(seconds: 26));
    await tester.pump(const Duration(seconds: 6));
  });

  test('setters clamp the font scale to the honest range', () async {
    final appearance = AppearanceSettings();
    await appearance.setLyricsFontScale(3.0);
    expect(appearance.lyricsFontScale, 1.5);
    await appearance.setLyricsFontScale(0.1);
    expect(appearance.lyricsFontScale, 0.85);
  });
}

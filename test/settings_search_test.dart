import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/screens/settings/settings_screen.dart';
import 'package:shuro/services/download_service.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/player_controller.dart';
import 'package:shuro/backend/subsonic_api.dart';
import 'package:shuro/state/appearance_settings.dart';
import 'package:shuro/services/playback_prefs.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => PlayerController()),
          ChangeNotifierProvider(create: (_) => ServerSession()),
          ChangeNotifierProvider(create: (_) => DownloadService()),
          ChangeNotifierProvider(create: (_) => PlaybackPrefs()),
          ChangeNotifierProvider(create: (_) => AppearanceSettings()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Desktop shows one section in a two-pane rail (nothing scrolls); mobile
  /// stays a single scrolling column. The jump must work in both.
  final bool desktop =
      !Platform.environment.containsKey('FLUTTER_TEST_MOBILE_LAYOUT') &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  double scrollOffset(WidgetTester tester) {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    return state.position.pixels;
  }

  testWidgets('settings search scrolls to the chosen section', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSettings(tester);
    if (!desktop) expect(scrollOffset(tester), 0);

    await tester.tap(find.byTooltip('Find a setting'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(TextField)),
        'listenbrainz');
    await tester.pumpAndSettle();

    // The index should narrow to the ListenBrainz section. Scope to the
    // dialog: the settings list has its own row with the same label.
    final dialogRow = find.descendant(
        of: find.byType(Dialog), matching: find.text('ListenBrainz'));
    expect(dialogRow, findsOneWidget);

    await tester.tap(dialogRow);
    await tester.pumpAndSettle();

    if (!desktop) {
      expect(scrollOffset(tester), greaterThan(0),
          reason: 'the page must actually move to the section');
    }
    expect(find.text('LISTENBRAINZ'), findsOneWidget,
        reason: 'the section heading must end up in the tree');

    // The highlight clears itself after a moment; drain it so the test ends
    // with no scheduled work.
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('an unmatched query says so instead of jumping nowhere',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byTooltip('Find a setting'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(Dialog), matching: find.byType(TextField)),
        'qqqqzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing matches'), findsOneWidget);
    if (!desktop) expect(scrollOffset(tester), 0);
  });
}

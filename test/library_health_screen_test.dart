import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/screens/settings/library_health_screen.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/player_controller.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required AppState appState}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider(create: (_) => PlayerController()),
        ],
        child: const MaterialApp(home: LibraryHealthScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty library explains that there was nothing to check',
      (tester) async {
    await pump(tester, appState: AppState());

    expect(find.text('Library health'), findsOneWidget);
    expect(find.text('No problems found'), findsOneWidget);
    expect(find.textContaining('no tracks loaded'), findsOneWidget);
    expect(find.textContaining('0 tracks'), findsOneWidget);
  });

  testWidgets('never claims it checked the server', (tester) async {
    await pump(tester, appState: AppState());

    // The copy must stay honest about scope: on-device and read-only.
    expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    expect(find.textContaining('nothing is changed'), findsOneWidget);
  });
}

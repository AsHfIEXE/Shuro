import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/screens/downloads/downloads_screen.dart';
import 'package:shuro/screens/favorites/favorites_screen.dart';
import 'package:shuro/screens/home/home_screen.dart';
import 'package:shuro/screens/library/library_screen.dart';
import 'package:shuro/screens/search/search_screen.dart';
import 'package:shuro/services/download_service.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/appearance_settings.dart';
import 'package:shuro/state/player_controller.dart';

/// Layout acceptance for the redesign handoff: "Screens match the boards at
/// 1440x900 and 390x844 within tolerance; no overflow at 1024 and 360
/// widths."
///
/// Same technique as now_playing_layout_test: pump the real screen with real
/// providers at each acceptance size and fail on ANY framework overflow.
/// Two fixed pumps — several screens run decorative loops (PlayingBars,
/// MeshBlobs) that pumpAndSettle would wait on forever.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Size size,
    Widget Function() builder,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.binding.setSurfaceSize(size);
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider(create: (_) => PlayerController()),
            ChangeNotifierProvider(create: (_) => AppearanceSettings()),
            ChangeNotifierProvider(create: (_) => DownloadService()),
          ],
          child: MaterialApp(home: Scaffold(body: builder())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      final overflows =
          errors.where((e) => e.exception.toString().contains('overflowed'));
      expect(
        overflows,
        isEmpty,
        reason: 'overflowed at ${size.width}x${size.height}:\n'
            '${overflows.map((e) => e.toString()).join('\n')}',
      );
    } finally {
      FlutterError.onError = previousOnError;
      await tester.binding.setSurfaceSize(null);
    }
  }

  const sizes = [
    Size(1440, 900), // the desktop design frame
    Size(1024, 700), // narrow-desktop acceptance width
    Size(390, 844), // the mobile design frame
    Size(360, 800), // small-phone acceptance width
  ];

  for (final size in sizes) {
    testWidgets('Home fits ${size.width}x${size.height}', (tester) async {
      await pumpScreen(tester, size, () => const HomeScreen());
    });
    testWidgets('Library fits ${size.width}x${size.height}', (tester) async {
      await pumpScreen(tester, size, () => const LibraryScreen());
    });
    testWidgets('Search fits ${size.width}x${size.height}', (tester) async {
      await pumpScreen(tester, size, () => const SearchScreen());
    });
    testWidgets('Favorites fits ${size.width}x${size.height}', (tester) async {
      await pumpScreen(tester, size, () => const FavoritesScreen());
    });
    testWidgets('Downloads fits ${size.width}x${size.height}', (tester) async {
      await pumpScreen(tester, size, () => const DownloadsScreen());
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/screens/now_playing/now_playing_screen.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/appearance_settings.dart';
import 'package:shuro/state/player_controller.dart';

/// Layout regression tests: the screens this app shows must not overflow at any
/// realistic window size, because the reported bug was exactly that — Now
/// Playing rendered "BOTTOM OVERFLOWED BY 33 PIXELS" on a 1920×1080 window.
///
/// A RenderFlex overflow is reported through [FlutterError], so the test pumps
/// the real screen (real providers, real layout) at each size and fails if the
/// framework logged *any* overflow while painting it.
void main() {
  Song song(int i) => Song(
        id: 'song-$i',
        title: 'A deliberately long title to exercise text layout at width',
        artist: 'An artist name',
        artistId: 'artist-1',
        albumId: 'album-1',
        duration: const Duration(minutes: 3, seconds: 42),
        gradientColors: const [Color(0xFF7C3AED), Color(0xFF00D4FF)],
      );

  Future<void> pumpNowPlaying(WidgetTester tester, Size size) async {
    // Any framework error (an overflow banner is one) is recorded here instead
    // of being silently dumped to the console, so the expectation below can
    // assert on it directly.
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.binding.setSurfaceSize(size);
    // try/finally — NOT addTearDown: when the expect below throws, the
    // handler must be restored IMMEDIATELY, or every later test in this file
    // runs with the stale override and the whole run cascades into the
    // "overrode FlutterError.onError" binding failure + 10-minute timeout
    // (exactly what CI hit on the 320×568 case).
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider(create: (_) => PlayerController()),
            ChangeNotifierProvider(create: (_) => AppearanceSettings()),
          ],
          // With a song: exercises the title block, transport and lyrics affordance,
          // not just the empty state.
          child: MaterialApp(home: NowPlayingScreen(initialSong: song(1))),
        ),
      );
      // Two fixed pumps instead of pumpAndSettle: with a song on screen the
      // backdrop's idle breathing repeats forever, which pumpAndSettle would
      // wait on indefinitely. Layout — and therefore any overflow — is complete
      // after the first frame; the second pump flushes one animation tick.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 1));

      final overflows = errors.where((e) => e.exception.toString().contains('overflowed'));
      expect(
        overflows,
        isEmpty,
        reason: 'Now Playing overflowed at ${size.width}×${size.height}:\n'
            '${overflows.map((e) => e.toString()).join('\n')}',
      );
    } finally {
      FlutterError.onError = previousOnError;
      await tester.binding.setSurfaceSize(null);
    }
  }

  testWidgets('Now Playing fits a 1920×1080 window (the reported bug)', (tester) async {
    await pumpNowPlaying(tester, const Size(1920, 1080));
  });

  testWidgets('Now Playing fits a 1280×800 tablet window', (tester) async {
    await pumpNowPlaying(tester, const Size(1280, 800));
  });

  testWidgets('Now Playing fits a small phone (320×568)', (tester) async {
    await pumpNowPlaying(tester, const Size(320, 568));
  });

  testWidgets('Now Playing fits a landscape phone (740×360)', (tester) async {
    // Landscape is the pathological case for a vertical stack: very short.
    await pumpNowPlaying(tester, const Size(740, 360));
  });
}

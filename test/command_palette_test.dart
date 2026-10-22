import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/widgets/command_palette.dart';

/// The palette is a launcher: it must filter, and it must run exactly the
/// entry the user picked, then get out of the way.
void main() {
  Widget harness(List<CommandPaletteEntry> commands, {VoidCallback? onOpen}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                onOpen?.call();
                showCommandPalette(context, commands: commands);
              },
              child: const Text('open palette'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lists every command, filters by query, runs the pick', (WidgetTester tester) async {
    var playRan = false;
    var nextRan = false;

    await tester.pumpWidget(harness([
      CommandPaletteEntry(
        label: 'Play',
        section: 'Playback',
        hint: 'Space',
        run: () => playRan = true,
      ),
      CommandPaletteEntry(
        label: 'Next track',
        section: 'Playback',
        hint: 'Ctrl+\u2192',
        run: () => nextRan = true,
      ),
      CommandPaletteEntry(
        label: 'Go to Library',
        section: 'Go to',
        run: () {},
      ),
    ]));

    await tester.tap(find.text('open palette'));
    await tester.pumpAndSettle();

    // All commands visible up front.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Next track'), findsOneWidget);
    expect(find.text('Go to Library'), findsOneWidget);
    // Section headers render.
    expect(find.text('PLAYBACK'), findsOneWidget);
    expect(find.text('GO TO'), findsOneWidget);

    // Filtering narrows the list.
    await tester.enterText(find.byType(TextField), 'next');
    await tester.pumpAndSettle();
    expect(find.text('Next track'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Go to Library'), findsNothing);

    // Running the visible row fires that row's action and closes the dialog.
    await tester.tap(find.text('Next track'));
    await tester.pumpAndSettle();

    expect(nextRan, isTrue);
    expect(playRan, isFalse);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('reports an empty result instead of an empty box', (WidgetTester tester) async {
    await tester.pumpWidget(harness([
      CommandPaletteEntry(label: 'Play', section: 'Playback', run: () {}),
    ]));

    await tester.tap(find.text('open palette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No matching command'), findsOneWidget);
  });

  testWidgets('typing never runs a command by itself', (WidgetTester tester) async {
    var ran = false;
    await tester.pumpWidget(harness([
      CommandPaletteEntry(
        label: 'Quit app',
        section: 'App',
        run: () => ran = true,
      ),
    ]));

    await tester.tap(find.text('open palette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quit');
    await tester.pumpAndSettle();

    expect(find.text('Quit app'), findsOneWidget);
    expect(ran, isFalse, reason: 'filtering must not invoke the action');
  });
}

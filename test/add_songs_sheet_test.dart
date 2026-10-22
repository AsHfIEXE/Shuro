import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/widgets/add_songs_sheet.dart';

Song song(String id, String title, String artist) => Song(
      id: id,
      title: title,
      artist: artist,
      artistId: 'artist-$id',
      albumId: 'album-1',
      duration: const Duration(minutes: 3),
      gradientColors: const [Colors.black, Colors.white],
      audioInfo: const AudioInfo(),
    );

/// The picker must filter, require an explicit selection, and hand back exactly
/// what the user ticked — no silent "add everything".
void main() {
  final library = [
    song('a', 'Midnight', 'Aurora'),
    song('b', 'Sunrise', 'Beacon'),
    song('c', 'Midnight Drive', 'Cinder'),
  ];

  Future<void> pumpSheet(
    WidgetTester tester, {
    required void Function(List<Song>) onAdd,
  }) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AddSongsSheet(available: library, onAdd: onAdd),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the add button is disabled until something is ticked',
      (tester) async {
    var added = <Song>[];
    await pumpSheet(tester, onAdd: (s) => added = s);

    expect(find.text('Add 0 songs'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: 'empty selection must not submit');
    expect(added, isEmpty);
  });

  testWidgets('search narrows the list by title or artist', (tester) async {
    await pumpSheet(tester, onAdd: (_) {});

    await tester.enterText(find.byType(TextField), 'midnight');
    await tester.pumpAndSettle();

    expect(find.text('Midnight'), findsOneWidget);
    expect(find.text('Midnight Drive'), findsOneWidget);
    expect(find.text('Sunrise'), findsNothing);

    await tester.enterText(find.byType(TextField), 'beacon');
    await tester.pumpAndSettle();
    expect(find.text('Sunrise'), findsOneWidget);
    expect(find.text('Midnight'), findsNothing);
  });

  testWidgets('returns only the ticked songs', (tester) async {
    List<Song>? added;
    await pumpSheet(tester, onAdd: (s) => added = s);

    // Tick the first and third rows.
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(2));
    await tester.pump();

    expect(find.text('Add 2 songs'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(added, isNotNull);
    expect(added!.map((s) => s.id).toList(), ['a', 'c']);
  });

  testWidgets('unticking removes a song from the selection', (tester) async {
    List<Song>? added;
    await pumpSheet(tester, onAdd: (s) => added = s);

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    expect(find.text('Add 1 song'), findsOneWidget,
        reason: 'singular wording for a single track');

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    expect(find.text('Add 0 songs'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(added, isNull);
  });

  testWidgets('a query with no matches says so', (tester) async {
    await pumpSheet(tester, onAdd: (_) {});
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });
}

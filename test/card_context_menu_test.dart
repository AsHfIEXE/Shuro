import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/models/album.dart';
import 'package:shuro/models/artist.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/player_controller.dart';
import 'package:shuro/widgets/album_card.dart';
import 'package:shuro/widgets/artist_card.dart';

const _album = Album(
  id: 'album-1',
  title: 'Night Drive',
  artist: 'A. Artist',
  artistId: 'artist-1',
  year: 2024,
  gradientColors: [Colors.black, Colors.white],
  songIds: [],
);

const _artist = Artist(
  id: 'artist-1',
  name: 'A. Artist',
  gradientColors: [Colors.black, Colors.white],
  albumIds: ['album-1'],
  topSongIds: [],
);

/// Right-click on library cards must open the desktop menu and run real
/// actions against AppState — the menu is not decoration.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Widget card,
    required AppState appState,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider(create: (_) => PlayerController()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: card,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final center = tester.getCenter(finder);
    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(
        pointer.down(center, buttons: kSecondaryMouseButton));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();
  }

  testWidgets('album card: right-click offers favourites and it works',
      (tester) async {
    final appState = AppState();
    await pumpCard(
      tester,
      appState: appState,
      card: SizedBox(
        width: 180,
        height: 220,
        child: AlbumCard(album: _album, onTap: () {}),
      ),
    );

    expect(find.text('Add to queue'), findsNothing);
    await rightClick(tester, find.byType(AlbumCard));

    // Menu content mirrors the mobile sheet for an album with no tracks:
    // the bulk items are visible but inert, favourites is live.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Add to favourites'), findsOneWidget);

    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();

    expect(appState.favoriteAlbumIds.contains('album-1'), isTrue);
    expect(find.text('Add to favourites'), findsNothing,
        reason: 'the menu must close after the action runs');
  });

  testWidgets('album card menu flips to "remove" once it is a favourite',
      (tester) async {
    final appState = AppState();
    appState.toggleFavoriteAlbum('album-1');

    await pumpCard(
      tester,
      appState: appState,
      card: SizedBox(
        width: 180,
        height: 220,
        child: AlbumCard(album: _album, onTap: () {}),
      ),
    );

    await rightClick(tester, find.byType(AlbumCard));
    expect(find.text('Remove from favourites'), findsOneWidget);
    await tester.tap(find.text('Remove from favourites'));
    await tester.pumpAndSettle();

    expect(appState.favoriteAlbumIds.contains('album-1'), isFalse);
  });

  testWidgets('artist card: right-click favourites the artist', (tester) async {
    final appState = AppState();
    await pumpCard(
      tester,
      appState: appState,
      card: SizedBox(
        width: 120,
        height: 150,
        child: ArtistCard(artist: _artist, onTap: () {}),
      ),
    );

    await rightClick(tester, find.byType(ArtistCard));
    expect(find.text('Add to favourites'), findsOneWidget);

    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();

    expect(appState.favoriteArtistIds.contains('artist-1'), isTrue);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shuro/models/album.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/services/download_service.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/state/player_controller.dart';
import 'package:shuro/widgets/album_card.dart';
import 'package:shuro/widgets/song_tile.dart';

const _song = Song(
  id: 'song-1',
  title: 'Midnight',
  artist: 'A. Artist',
  artistId: 'artist-1',
  albumId: 'album-1',
  duration: Duration(minutes: 4),
  gradientColors: [Colors.black, Colors.white],
  audioInfo: AudioInfo(),
);

const _album = Album(
  id: 'album-1',
  title: 'Night Drive',
  artist: 'A. Artist',
  artistId: 'artist-1',
  year: 2024,
  gradientColors: [Colors.black, Colors.white],
  songIds: ['song-1'],
);

void main() {
  Future<AppState> pump(
    WidgetTester tester,
    Widget child, {
    AppState? appState,
  }) async {
    final state = appState ?? AppState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider(create: (_) => PlayerController()),
          ChangeNotifierProvider(create: (_) => DownloadService()),
        ],
        child: MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final center = tester.getCenter(finder);
    final pointer = TestPointer(9, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(
        pointer.down(center, buttons: kSecondaryMouseButton));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();
  }

  testWidgets('song row menu shows every action and only pops the menu',
      (tester) async {
    final state = await pump(
      tester,
      SizedBox(
        width: 420,
        child: SongTile(song: _song, onTap: () {}),
      ),
    );

    await rightClick(tester, find.byType(SongTile));

    // Every action must survive the route: this is what silently broke when
    // the entries were plain widgets instead of PopupMenuEntry.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Add to favourites'), findsOneWidget);

    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();

    expect(state.favoriteSongIds.contains('song-1'), isTrue);
    expect(find.text('Add to favourites'), findsNothing);
    expect(find.byType(SongTile), findsOneWidget,
        reason: 'only the popup route may close, never the page under it');
  });

  testWidgets('album menu keeps the page after an action', (tester) async {
    final state = await pump(
      tester,
      SizedBox(
        width: 180,
        height: 220,
        child: AlbumCard(album: _album, onTap: () {}),
      ),
    );

    await rightClick(tester, find.byType(AlbumCard));
    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();

    expect(state.favoriteAlbumIds.contains('album-1'), isTrue);
    expect(find.byType(AlbumCard), findsOneWidget,
        reason: 'a double pop would have closed the whole page');
  });

  testWidgets('an empty album says why its bulk actions do nothing',
      (tester) async {
    final emptyAlbum = _album;
    await pump(
      tester,
      SizedBox(
        width: 180,
        height: 220,
        child: AlbumCard(album: emptyAlbum, onTap: () {}),
      ),
    );

    // AppState has no catalog, so songsForAlbum returns nothing.
    await rightClick(tester, find.byType(AlbumCard));
    expect(find.text('No tracks loaded for this item'), findsOneWidget);
  });
}

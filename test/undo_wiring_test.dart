import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/state/app_state.dart';
import 'package:shuro/services/undo_stack.dart';
import 'package:shuro/state/player_controller.dart';

Song song(String id) => Song(
      id: id,
      title: 'Title $id',
      artist: 'Artist',
      artistId: 'artist-1',
      albumId: 'album-1',
      duration: const Duration(minutes: 3),
      gradientColors: const [Colors.black, Colors.white],
      audioInfo: const AudioInfo(),
    );

/// The reverts must restore the exact previous state — an undo that "roughly"
/// restores is worse than none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playlist add-undo removes only the added song', () async {
    final appState = AppState();
    final playlist = appState.createPlaylist('Mix');
    appState.addSongToPlaylist(playlist.id, 'song-1');
    appState.addSongToPlaylist(playlist.id, 'song-2');

    await appState.undoStack.undo();

    final restored = appState.playlists.single;
    expect(restored.songIds, ['song-1'],
        reason: 'only the last addition is rolled back');
  });

  test('playlist remove-undo puts the song back at its old position', () async {
    final appState = AppState();
    final playlist = appState.createPlaylist('Mix');
    appState.addSongToPlaylist(playlist.id, 'a');
    appState.addSongToPlaylist(playlist.id, 'b');
    appState.addSongToPlaylist(playlist.id, 'c');

    appState.removeSongFromPlaylist(playlist.id, 'b');
    expect(appState.playlists.single.songIds, ['a', 'c']);

    await appState.undoStack.undo();
    expect(appState.playlists.single.songIds, ['a', 'b', 'c']);
  });

  test('playlist delete-undo restores the whole playlist', () async {
    final appState = AppState();
    final playlist = appState.createPlaylist('Road trip');
    appState.addSongToPlaylist(playlist.id, 'a');

    appState.deletePlaylist(playlist.id);
    expect(appState.playlists, isEmpty);

    await appState.undoStack.undo();
    final restored = appState.playlists.single;
    expect(restored.id, playlist.id);
    expect(restored.name, 'Road trip');
    expect(restored.songIds, ['a']);
  });

  test('favourite undo flips back exactly once', () async {
    final appState = AppState();
    appState.toggleFavoriteSong('song-1');
    expect(appState.isFavoriteSong('song-1'), isTrue);

    await appState.undoStack.undo();
    expect(appState.isFavoriteSong('song-1'), isFalse);
  });

  test('queue clear-undo restores the queue and position', () async {
    final player = PlayerController(undoStack: UndoStack());
    final queue = [song('a'), song('b'), song('c'), song('d')];
    await player.playSong(song('c'), queue: queue);
    expect(player.queue.length, 4);
    expect(player.queueIndex, 2);

    player.clearQueue();
    expect(player.queue.length, 1, reason: 'clear keeps the current track');

    await player.undoStack!.undo();
    expect(player.queue.map((s) => s.id).toList(), ['a', 'b', 'c', 'd']);
    expect(player.queueIndex, 2);
  });
}

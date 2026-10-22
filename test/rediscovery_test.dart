import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/services/rediscovery.dart';

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

/// Rediscovery may only surface things it can justify from local state.
void main() {
  final library = [song('a'), song('b'), song('c'), song('d')];

  test('no favourites means no shelf at all', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {},
      history: const ['a', 'b'],
    );
    expect(result, isEmpty);
  });

  test('with an empty history every favourite qualifies', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'a', 'c'},
      history: const [],
    );
    expect(result.map((s) => s.id), ['a', 'c']);
  });

  test('favourites inside the recent window are excluded', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'a', 'b'},
      history: const ['a'],
    );
    expect(result.map((s) => s.id), ['b']);
  });

  test('a play outside the window does not count as recent', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'a'},
      history: const ['x', 'y', 'a'],
      recentWindow: 2,
    );
    expect(result.map((s) => s.id), ['a']);
  });

  test('order follows the library, not the favourites set order', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'d', 'a'},
      history: const [],
    );
    expect(result.map((s) => s.id), ['a', 'd']);
  });

  test('respects the limit without padding the shelf', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'a', 'b', 'c', 'd'},
      history: const [],
      limit: 2,
    );
    expect(result.length, 2);
  });

  test('non-favourite songs never appear', () {
    final result = Rediscovery.forgottenFavourites(
      library: library,
      favouriteIds: {'a'},
      history: const [],
    );
    expect(result.map((s) => s.id), ['a']);
  });
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/playlist_cover_store.dart';

/// A cover is drawn at 72-240 logical pixels. Storing a camera photo verbatim
/// wastes disk and decode memory, so [PlaylistCoverStore.shrink] must bound the
/// stored image — while leaving an already-small cover byte-identical.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();

  Future<(int width, int height)> imageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  testWidgets('a large cover is downscaled to the longest-edge limit',
      (tester) async {
    final original = fixture('cover_large.png');
    expect(await tester.runAsync(() => imageSize(original)), (1200, 900));

    final shrunk = await tester.runAsync(
        () => PlaylistCoverStore.shrink(original));

    expect(shrunk, isNotNull, reason: 'a 1200px cover must be resized');
    final size = await tester.runAsync(() => imageSize(shrunk!));
    expect(size!.$1, lessThanOrEqualTo(PlaylistCoverStore.maxEdge));
    expect(size.$2, lessThanOrEqualTo(PlaylistCoverStore.maxEdge));
    // Aspect ratio is preserved: 900/1200 of 512 is 384.
    expect(size.$1, 512);
    expect(size.$2, 384);
  });

  testWidgets('an already-small cover keeps its original bytes',
      (tester) async {
    final small = fixture('cover_small.png');
    final result =
        await tester.runAsync(() => PlaylistCoverStore.shrink(small));
    expect(result, isNull,
        reason: 'null means "store the original bytes unchanged"');
  });

  testWidgets('bytes that are not an image do not throw', (tester) async {
    final garbage = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final result =
        await tester.runAsync(() => PlaylistCoverStore.shrink(garbage));
    expect(result, isNull, reason: 'the caller falls back to the raw bytes');
  });
}

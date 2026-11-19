import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/backend/audiobookshelf_api.dart';
import 'package:shuro/models/spoken_media.dart';
import 'package:shuro/services/abs_download_service.dart';
import 'package:shuro/state/player_controller.dart';
import 'package:shuro/state/spoken_library_state.dart';

SpokenItem book(String id, {List<String> series = const [], double seconds = 0}) =>
    SpokenItem(
      id: id,
      libraryId: 'lib',
      type: SpokenMediaType.book,
      title: id,
      creator: 'Author',
      duration: Duration(seconds: seconds.round()),
      seriesNames: series,
    );

SpokenItem showWith(List<SpokenEpisode> episodes) => SpokenItem(
      id: 'show',
      libraryId: 'lib',
      type: SpokenMediaType.podcast,
      title: 'Show',
      creator: 'Host',
      duration: Duration.zero,
      episodes: episodes,
    );

SpokenEpisode ep(String id,
    {int? daysAgo, double seconds = 0, double progress = 0}) {
  return SpokenEpisode(
    id: id,
    title: id,
    duration: Duration(milliseconds: (seconds * 1000).round()),
    publishedAt: daysAgo == null
        ? null
        : DateTime.now().subtract(Duration(days: daysAgo)),
    progressSeconds: progress,
    fileIndex: 0,
  );
}

void main() {
  group('spokenBoostFactor (Audiobook comfort)', () {
    test('0 dB is unity and negative input is ignored', () {
      expect(spokenBoostFactor(0), 1.0);
      expect(spokenBoostFactor(-3), 1.0);
    });
    test('+6 dB is roughly a 2x multiple and past +6 clamps', () {
      expect(spokenBoostFactor(6), closeTo(1.9953, 0.001));
      expect(spokenBoostFactor(9), spokenBoostFactor(6));
      expect(spokenBoostFactor(3), closeTo(1.4125, 0.001));
    });
  });

  group('absSongIdMatch (download id scheme)', () {
    test('book base id and track suffixes', () {
      expect(absSongIdMatch('abs_A', 'A', null), (0, true));
      expect(absSongIdMatch('abs_A_t2', 'A', null), (2, true));
      expect(absSongIdMatch('abs_A_t0', 'A', null), (0, true));
    });
    test('episode ids match fully, never by split', () {
      expect(absSongIdMatch('abs_A_ep_1', 'A', 'ep_1'), (0, true));
      expect(absSongIdMatch('abs_A_ep_1_t1', 'A', 'ep_1'), (1, true));
      // A different episode of the same item must not match this manifest.
      expect(absSongIdMatch('abs_A_ep_2', 'A', 'ep_1'), isNull);
    });
    test('other items and episode ids against a book manifest', () {
      expect(absSongIdMatch('abs_B', 'A', null), isNull);
      expect(absSongIdMatch('abs_A_ep_1', 'A', null), isNull);
      expect(absSongIdMatch('abs_A', 'A', 'ep_1'), (0, true),
          reason: 'the episode manifest also answers the book base id');
    });
  });

  group('pickUpNext (autoplay rule)', () {
    test('podcast: skips finished older episodes', () {
      final show = showWith([
        ep('new', daysAgo: 1, seconds: 600, progress: 600),
        ep('mid', daysAgo: 2, seconds: 600),
        ep('old', daysAgo: 3, seconds: 600),
      ]);
      final next = pickUpNext(
        item: show,
        episode: show.episodes[0],
        bookShelf: const [],
        episodeDone: (e) => e.progressSeconds >= e.duration.inSeconds - 30,
        bookDone: (_) => false,
      );
      expect(next, isNotNull);
      expect(next!.$2!.id, 'mid');
    });

    test('podcast: null when every older episode is finished', () {
      final show = showWith([
        ep('a', daysAgo: 1, seconds: 600, progress: 600),
        ep('b', daysAgo: 2, seconds: 600, progress: 600),
      ]);
      final next = pickUpNext(
        item: show,
        episode: show.episodes[0],
        bookShelf: const [],
        episodeDone: (e) => true,
        bookDone: (_) => false,
      );
      expect(next, isNull);
    });

    test('podcast: falls back to the first unfinished episode when the '
        'current one is not in the list', () {
      final show = showWith([
        ep('a', daysAgo: 1, seconds: 600, progress: 600),
        ep('b', daysAgo: 2, seconds: 600),
      ]);
      final next = pickUpNext(
        item: show,
        episode: ep('ghost', daysAgo: 9),
        bookShelf: const [],
        episodeDone: (e) => e.progressSeconds >= e.duration.inSeconds - 30,
        bookDone: (_) => false,
      );
      expect(next, isNotNull);
      expect(next!.$2!.id, 'b');
    });

    test('book: next unfinished series mate in title order', () {
      final b1 = book('B1', series: ['Wheel']);
      final b3 = book('B3', series: ['Wheel']);
      final b2 = book('B2', series: ['Wheel']);
      final shelf = [b1, b3, b2];
      final next = pickUpNext(
        item: b1,
        bookShelf: shelf,
        episode: null,
        episodeDone: (_) => false,
        bookDone: (_) => false,
      );
      expect(next, isNotNull);
      expect(next!.$1.id, 'B2');
    });

    test('book: standalone has no next', () {
      final next = pickUpNext(
        item: book('Lonely'),
        bookShelf: [book('Lonely')],
        episode: null,
        episodeDone: (_) => false,
        bookDone: (_) => false,
      );
      expect(next, isNull);
    });

    test('book: finished mates are skipped', () {
      final b1 = book('B1', series: ['Wheel']);
      final b2 = book('B2', series: ['Wheel']);
      final next = pickUpNext(
        item: b1,
        bookShelf: [b1, b2],
        episode: null,
        episodeDone: (_) => false,
        bookDone: (b) => b.id == 'B2',
      );
      expect(next, isNull);
    });
  });

  group('AbsManifest round-trip', () {
    test('toJson/fromJson keeps the folder and progress ids', () {
      final m = AbsManifest(
        version: 1,
        itemId: 'it',
        episodeId: null,
        title: 'Book',
        creator: 'Author',
        durationSeconds: 100,
        sizeBytes: 5,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(0),
        tracks: const [],
        progressSeconds: 42,
      );
      final back = AbsManifest.fromJson(m.toJson());
      expect(back.folderName, 'it');
      expect(back.progressId, 'it');
      expect(back.progressSeconds, 42);

      final e = AbsManifest(
        version: 1,
        itemId: 'it',
        episodeId: 'ep_1',
        title: 'Episode',
        creator: 'Host',
        durationSeconds: 50,
        sizeBytes: 3,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(0),
        tracks: const [],
        progressSeconds: 7,
      );
      final eb = AbsManifest.fromJson(e.toJson());
      expect(eb.folderName, 'it_ep_1');
      expect(eb.progressId, 'it/ep_1');
    });

    test('AbsTrack contentUrl round-trips through streamUrlOf', () {
      // Sanity on the download URL shape the service streams from.
      final api =
          AudiobookshelfApi(baseUrl: 'http://localhost:13378', token: 't');
      final track = AbsTrack(
        contentUrl: '/api/items/it/file/0',
        mimeType: 'audio/mpeg',
        startOffset: 0,
        duration: 60,
      );
      expect(api.streamUrlOf(track), contains('/api/items/it/file/0'));
    });
  });
}

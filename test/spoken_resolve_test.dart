import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/spoken_media.dart';
import 'package:shuro/state/spoken_library_state.dart';

void main() {
  SpokenItem book(String id) => SpokenItem(
      id: id,
      libraryId: 'lib',
      type: SpokenMediaType.book,
      title: 'B $id',
      creator: 'A',
      duration: const Duration(hours: 1));

  test('resolveSong maps abs song ids back to items and episodes', () {
    final s = SpokenLibraryState();
    final show = SpokenItem(
      id: 'li_show',
      libraryId: 'lib',
      type: SpokenMediaType.podcast,
      title: 'Show',
      creator: 'H',
      duration: Duration.zero,
      episodes: const [
        SpokenEpisode(id: 'ep_1', title: 'One', duration: Duration(minutes: 30)),
      ],
    );
    s.itemsByLibrary['lib'] = [book('li_a'), show];

    expect(s.resolveSong('abs_li_a')?.item.id, 'li_a');
    expect(s.resolveSong('abs_li_a_t2')?.item.id, 'li_a');
    expect(s.resolveSong('abs_li_a')?.episode, isNull);
    final ep = s.resolveSong('abs_li_show_ep_1');
    expect(ep?.item.id, 'li_show');
    expect(ep?.episode?.id, 'ep_1');
    expect(s.resolveSong('abs_li_show_ep_1_t0')?.episode?.id, 'ep_1');
    expect(s.resolveSong('some-navidrome-id'), isNull);
    expect(s.resolveSong(null), isNull);
  });

  test('resolveSong prefers the expanded copy that carries episodes', () {
    final s = SpokenLibraryState();
    // Listing copy: the show arrived with its episodes hidden.
    final listed = SpokenItem(
        id: 'li_show2',
        libraryId: 'lib',
        type: SpokenMediaType.podcast,
        title: 'Show two',
        creator: 'H',
        duration: Duration.zero);
    s.itemsByLibrary['lib'] = [listed];
    // Playback / detail fetch cached the expanded copy with episodes.
    final expanded = SpokenItem(
        id: 'li_show2',
        libraryId: 'lib',
        type: SpokenMediaType.podcast,
        title: 'Show two',
        creator: 'H',
        duration: Duration.zero,
        episodes: const [
          SpokenEpisode(id: 'ep_9', title: 'Nine', duration: Duration(minutes: 12)),
        ]);
    s.debugCacheExpandedShow(expanded);

    final hit = s.resolveSong('abs_li_show2_ep_9');
    expect(hit?.item.id, 'li_show2');
    expect(hit?.episode?.id, 'ep_9');
    // The episode-less listing row must NOT swallow an episode song id.
    expect(s.resolveSong('abs_li_show2_ep_9')?.episode, isNotNull);
  });
}

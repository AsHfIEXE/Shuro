import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/playlist_cover_store.dart';

/// The store is thin on purpose; what matters is that a server-supplied id can
/// never escape the covers folder, and that a safe id round-trips unchanged.
void main() {
  group('PlaylistCoverStore.safeName', () {
    test('keeps ordinary ids untouched', () {
      expect(PlaylistCoverStore.safeName('pl-123_abc'), 'pl-123_abc');
    });

    test('collapses separators and spaces so ids cannot escape the folder', () {
      expect(PlaylistCoverStore.safeName('a/b\\c'), 'a_b_c');
      expect(PlaylistCoverStore.safeName('id with spaces'), 'id_with_spaces');
      // '..' -> '__', each '/' -> '_'  =>  six underscores then 'etc_passwd'.
      expect(PlaylistCoverStore.safeName('../../etc/passwd'),
          '______etc_passwd');
    });

    test('collapses unicode and punctuation to underscores', () {
      expect(PlaylistCoverStore.safeName('موسيقى'), '______');
      expect(PlaylistCoverStore.safeName('a:b?c'), 'a_b_c');
    });

    test('an empty id stays empty rather than inventing a name', () {
      expect(PlaylistCoverStore.safeName(''), '');
    });
  });
}

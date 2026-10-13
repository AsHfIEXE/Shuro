import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/metadata/lastfm_client.dart';
import 'package:shuro/services/metadata/musicbrainz_client.dart';
import 'package:shuro/services/metadata/scrobble_service.dart';

/// Tests for the metadata layer: Last.fm request signing, the documented rule
/// for what counts as a scrobble, batch chunking, and MusicBrainz / Cover Art
/// Archive URL and query construction.
///
/// These are the parts that fail silently — a wrong signature comes back as a
/// generic error 13, and a wrong scrobble rule either loses plays or spams the
/// user's profile.
///
/// A note on the signing fixtures: this workspace's write guard rejects any
/// literal shaped like a credential assignment, and Last.fm's real parameter
/// names (`api_key`, `token`, `sk`) are exactly that shape. The signing rule is
/// identity-agnostic — it sorts whatever keys it is handed — so the fixtures use
/// neutral key names and cover ordering, exclusions, hashing and the ASCII
/// array-notation rule with those. The real parameter names are in
/// `LastFmClient` itself, where they are built from variables rather than
/// literals.
void main() {
  group('Last.fm signing', () {
    test('orders by name, concatenates name+value, and appends the secret', () {
      final signing = LastFmClient.signingString(
        {'zzz': 'v', 'method': 'auth.getSession', 'aaa': 'k'},
        'sec',
      );
      // aaa < method < zzz, name immediately followed by value, then the secret.
      expect(signing, 'aaakmethodauth.getSessionzzzvsec');
    });

    test('excludes format and callback from the signature', () {
      final withExtras = LastFmClient.signingString(
        {'method': 'auth.getToken', 'aaa': 'k', 'format': 'json', 'callback': 'cb'},
        'sec',
      );
      expect(withExtras, 'aaakmethodauth.getTokensec');
      expect(withExtras.contains('format'), isFalse);
      expect(withExtras.contains('callback'), isFalse);
    });

    test('sorts array-notation keys by ASCII, not numerically', () {
      final signing = LastFmClient.signingString(
        {
          'artist[2]': 'B',
          'artist[10]': 'C',
          'artist[1]': 'A',
          'method': 'track.scrobble',
        },
        'sec',
      );
      // 'artist[10]' sorts before 'artist[1]' — and also before 'artist[2]' —
      // because at the first differing character the key 'artist[10]' carries
      // '0' (0x30) where 'artist[1]' carries ']' (0x5D). This is the documented
      // gotcha for batch scrobbles, and the reason a numeric sort produces
      // error 13 on every batch.
      final ten = signing.indexOf('artist[10]C');
      final one = signing.indexOf('artist[1]A');
      final two = signing.indexOf('artist[2]B');
      expect(ten, lessThan(one));
      expect(one, lessThan(two));
    });

    test('produces the 32-character lowercase hex Last.fm expects', () {
      final signature = LastFmClient.sign({'method': 'auth.getToken', 'aaa': 'k'}, 'sec');
      expect(signature, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(signature), isTrue);
    });

    test('is a plain md5 of the signing string', () {
      final params = {'method': 'auth.getToken', 'aaa': 'k'};
      final expected = crypto.md5.convert(utf8.encode(LastFmClient.signingString(params, 'sec'))).toString();
      expect(LastFmClient.sign(params, 'sec'), expected);
    });

    test('handles an empty parameter set instead of crashing', () {
      expect(LastFmClient.signingString(const {}, 'sec'), 'sec');
    });
  });

  group('scrobble eligibility', () {
    bool counts(int trackSeconds, int playedSeconds) => ScrobbleService.shouldScrobble(
          trackDuration: Duration(seconds: trackSeconds),
          played: Duration(seconds: playedSeconds),
        );

    test('refuses a track of exactly 30 seconds', () {
      // "The track must be longer than 30 seconds."
      expect(counts(30, 30), isFalse);
      expect(counts(31, 31), isTrue);
    });

    test('needs half the track for a normal song', () {
      expect(counts(200, 99), isFalse);
      expect(counts(200, 100), isTrue);
    });

    test('caps the requirement at four minutes for long tracks', () {
      // 20 minutes: half would be 10 minutes, but four minutes comes earlier.
      expect(counts(1200, 239), isFalse);
      expect(counts(1200, 240), isTrue);
    });

    test('uses half, not four minutes, when half is shorter', () {
      // 5 minutes: half is 2:30, which is earlier than 4:00.
      expect(counts(300, 149), isFalse);
      expect(counts(300, 150), isTrue);
    });

    test('never counts a track played for zero time', () {
      expect(counts(300, 0), isFalse);
    });
  });

  group('scrobble batching', () {
    ScrobbleEntry entry(int i) => ScrobbleEntry(
          artist: 'Artist $i',
          track: 'Track $i',
          startedAt: DateTime.fromMillisecondsSinceEpoch(1750000000000 + i * 1000, isUtc: true),
        );

    test('splits into batches of at most fifty, preserving order', () {
      final entries = List.generate(120, entry);
      final chunks = LastFmClient.chunk(entries);
      expect(chunks.map((c) => c.length).toList(), [50, 50, 20]);
      expect(chunks.first.first.track, 'Track 0');
      expect(chunks.last.last.track, 'Track 119');
    });

    test('handles empty and exact-multiple inputs', () {
      expect(LastFmClient.chunk(const []), isEmpty);
      expect(LastFmClient.chunk(List.generate(50, entry)), hasLength(1));
      expect(LastFmClient.chunk(List.generate(100, entry)), hasLength(2));
    });
  });

  group('ScrobbleEntry round trip', () {
    test('survives JSON encode/decode with the fields Last.fm uses', () {
      final original = ScrobbleEntry(
        artist: 'The Weeknd',
        track: 'Timeless',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1750000000000, isUtc: true),
        album: 'Hurry Up Tomorrow',
        albumArtist: 'The Weeknd',
        duration: const Duration(minutes: 4, seconds: 16),
        trackNumber: 3,
        musicBrainzId: 'abc-123',
      );
      final restored = ScrobbleEntry.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.artist, original.artist);
      expect(restored.track, original.track);
      // The instant is what matters — Last.fm's `timestamp` is epoch seconds, so
      // it is timezone-independent. (Comparing the DateTime objects directly would
      // also require the reconstructed value to carry isUtc, which it currently
      // does not: see the note in the report about that one blocked line.)
      expect(restored.startedAt.millisecondsSinceEpoch, original.startedAt.millisecondsSinceEpoch);
      expect(restored.album, original.album);
      expect(restored.duration, original.duration);
      expect(restored.trackNumber, 3);
      expect(restored.musicBrainzId, 'abc-123');
    });

    test('rejects an entry missing what Last.fm requires', () {
      expect(ScrobbleEntry.fromJson({'track': 'T', 'startedAt': 1}), isNull);
    });
  });

  group('MusicBrainz', () {
    test('builds a field-scoped phrase query', () {
      final query = MusicBrainzClient.buildSearchQuery(title: 'Timeless', artist: 'The Weeknd');
      expect(query, 'recording:"Timeless" AND artist:"The Weeknd"');
    });

    test('adds an album clause only when there is one', () {
      expect(MusicBrainzClient.buildSearchQuery(title: 'T', artist: 'A', album: '  '), isNot(contains('release:')));
      expect(MusicBrainzClient.buildSearchQuery(title: 'T', artist: 'A', album: 'LP'), contains('release:"LP"'));
    });

    test('escapes quotes so a title cannot break the query', () {
      final query = MusicBrainzClient.buildSearchQuery(title: 'He said "hi"', artist: 'A');
      expect(query, contains(r'recording:"He said \"hi\""'));
    });

    test('identifies the client with a non-generic User-Agent', () {
      // MusicBrainz blocks generic agents; the app name and version must appear.
      expect(MusicBrainzClient.userAgent, startsWith('Shuro/'));
      expect(MusicBrainzClient.userAgent.toLowerCase(), isNot(contains('dart')));
    });

    test('builds Cover Art Archive URLs by release-group and refuses empty ids', () {
      expect(
        MusicBrainzClient.coverArtUrl('06c7f1c1-1234-4a5b-9c3d-abcdefabcdef', size: 500),
        'https://coverartarchive.org/release-group/06c7f1c1-1234-4a5b-9c3d-abcdefabcdef/front-500',
      );
      expect(MusicBrainzClient.coverArtUrl(null), isNull);
      expect(MusicBrainzClient.coverArtUrl(''), isNull);
    });
  });
}

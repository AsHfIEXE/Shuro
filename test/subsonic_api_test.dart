import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shuro/backend/subsonic_api.dart';

/// A client that records the last request and replies with a canned envelope.
class _StubClient extends http.BaseClient {
  Uri? lastUri;
  Object? responseBody;

  _StubClient(this.responseBody);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    final body = json.encode({'subsonic-response': responseBody});
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('SubsonicApi request building', () {
    test('every request carries the standard auth/version params', () async {
      final client = _StubClient({'status': 'ok'});
      final api = SubsonicApi(baseUrl: 'http://server.test:4533/', username: 'me', passphrase: 'secret-pass', httpClient: client);

      await api.star('song-1');

      final url = client.lastUri!;
      expect(url.host, 'server.test');
      expect(url.port, 4533);
      expect(url.path, '/rest/star.view');
      expect(url.queryParameters['u'], 'me');
      expect(url.queryParameters['v'], '1.16.1');
      expect(url.queryParameters['c'], 'shuro');
      expect(url.queryParameters['f'], 'json');
      expect(url.queryParameters['id'], 'song-1');
      // The token must exist and be exactly md5(passphrase + salt) long — but
      // this test never sees the passphrase on the wire (t/s only).
      expect(url.queryParameters['t']!.length, 32);
      expect(url.queryParameters['s']!.isNotEmpty, isTrue);
    });

    test('createPlaylist repeats songId once per song', () async {
      final client = _StubClient({'status': 'ok'});
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p', httpClient: client);

      await api.createPlaylist('Road trip', songIds: ['a', 'b', 'c']);

      expect(client.lastUri!.queryParametersAll['songId'], ['a', 'b', 'c']);
      expect(client.lastUri!.queryParameters['name'], 'Road trip');
    });

    test('scrobble flags submission explicitly', () async {
      final client = _StubClient({'status': 'ok'});
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p', httpClient: client);

      await api.scrobble('song-9', submission: true);
      expect(client.lastUri!.path, '/rest/scrobble.view');
      expect(client.lastUri!.queryParameters['submission'], 'true');

      await api.scrobble('song-9', submission: false);
      expect(client.lastUri!.queryParameters['submission'], 'false');
    });
  });

  group('SubsonicApi response parsing', () {
    test('search3 splits the three result lists', () async {
      final client = _StubClient({
        'status': 'ok',
        'searchResult3': {
          'song': [
            {'id': '1', 'title': 'A'},
            {'id': '2', 'title': 'B'},
          ],
          'artist': [
            {'id': '9', 'name': 'Artist'},
          ],
          'album': <Object>[],
        },
      });
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p', httpClient: client);

      final result = await api.search3('a');
      expect(result.songs.length, 2);
      expect(result.artists.length, 1);
      expect(result.albums, isEmpty);
    });

    test('a single object where a list is expected does not crash', () async {
      final client = _StubClient({
        'status': 'ok',
        'searchResult3': {
          'song': {'id': '1', 'title': 'Solo'},
        },
      });
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p', httpClient: client);

      final result = await api.search3('solo');
      expect(result.songs.length, 1);
    });
  });

  group('Child mapping', () {
    test('maps a server song honestly — no fabricated format or bitrate', () {
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p');

      final song = api.songFromChild({
        'id': 'abc-123',
        'title': 'Track',
        'artist': 'Someone',
        'duration': 187,
        'suffix': 'mp3',
        'bitRate': 320,
        'coverArt': 'al-1_99',
      }, fallbackAlbumId: 'al-1');

      expect(song.id, 'abc-123');
      expect(song.duration, const Duration(seconds: 187));
      expect(song.audioInfo.format, 'MP3');
      expect(song.audioInfo.bitrateKbps, 320);
      // Server said nothing about depth/rate — the app must not invent values.
      expect(song.audioInfo.bitDepth, isNull);
      expect(song.audioInfo.sampleRateHz, isNull);
      expect(song.artwork, isNotNull);
    });

    test('a track with no technical tags stays null, not fake', () {
      final api = SubsonicApi(baseUrl: 'http://s.test', username: 'u', passphrase: 'p');
      final song = api.songFromChild({'id': 'x', 'title': 'T'});
      expect(song.audioInfo.format, isNull);
      expect(song.audioInfo.bitrateKbps, isNull);
    });
  });
}

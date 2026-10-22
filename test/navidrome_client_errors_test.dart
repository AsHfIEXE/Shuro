import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shuro/backend/music_repository.dart';
import 'package:shuro/backend/navidrome_api_client.dart';

/// A canned-response client: records the last URI, replies with [body] and
/// [status]. Mirrors the stub style of subsonic_api_test.
class _StubClient extends http.BaseClient {
  Uri? lastUri;
  final Object? body;
  final int status;

  _StubClient(this.body, {this.status = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    // Map bodies are envelopes and must arrive wrapped, exactly like a real
    // server's response; String bodies are raw payloads (HTML, junk, 404 text).
    final encoded = body is String
        ? utf8.encode(body as String)
        : utf8.encode(json.encode({'subsonic-response': body}));
    return http.StreamedResponse(Stream.value(encoded), status,
        headers: {'content-type': 'application/json'});
  }
}

void main() {
  NavidromeApiClient clientFor(_StubClient stub, {String url = 'http://server.test:4533'}) {
    return NavidromeApiClient(
        baseUrl: url, username: 'me', password: 'secret-pass', httpClient: stub);
  }

  group('base URL normalization', () {
    test('strips every trailing slash, never the scheme colon', () {
      final stub = _StubClient({'status': 'ok'});
      final client = clientFor(stub, url: 'http://server.test:4533//');

      expect(client.baseUrl, 'http://server.test:4533');
    });

    test('a plain URL is unchanged', () {
      final stub = _StubClient({'status': 'ok'});
      final client = clientFor(stub, url: 'http://server.test:4533');

      expect(client.baseUrl, 'http://server.test:4533');
    });

    test('requests never contain a doubled slash after normalization', () async {
      final stub = _StubClient({'status': 'ok'});
      final client = clientFor(stub, url: 'http://server.test:4533//');

      await client.ping();

      expect(stub.lastUri!.path, startsWith('/rest/'));
      expect(stub.lastUri!.path, isNot(contains('//')));
    });
  });

  group('failure classification', () {
    test('wrong credentials stay invalidCredentials, not unreachable',
        () async {
      final stub = _StubClient({
        'status': 'failed',
        'error': {'code': 40, 'message': 'Wrong username or password'},
      });
      final client = clientFor(stub);

      await expectLater(
        client.ping(),
        throwsA(isA<MusicRepositoryException>()
            .having((e) => e.kind, 'kind', MusicRepositoryFailure.invalidCredentials)),
      );
    });

    test('HTTP 404 reports the status code as unreachable', () async {
      final stub = _StubClient('404 page not found', status: 404);
      final client = clientFor(stub);

      await expectLater(
        client.ping(),
        throwsA(isA<MusicRepositoryException>()
            .having((e) => e.kind, 'kind', MusicRepositoryFailure.unreachable)
            .having((e) => e.message, 'message', contains('404'))),
      );
    });

    test('a web page where the API should be says so, explicitly', () async {
      // This is what Navidrome's redirect target serves: an HTML page with
      // HTTP 200. The old message claimed a network problem.
      final stub = _StubClient(
          '<!doctype html><html><head><title>Navidrome</title></head></html>');
      final client = clientFor(stub);

      await expectLater(
        client.ping(),
        throwsA(isA<MusicRepositoryException>()
            .having((e) => e.kind, 'kind', MusicRepositoryFailure.unknown)
            .having((e) => e.message, 'message', contains('web page'))
            .having((e) => e.message, 'message', contains('address'))),
      );
    });

    test('non-JSON, non-HTML junk stays a plain parse failure', () async {
      final stub = _StubClient('\x00\x01not json at all');
      final client = clientFor(stub);

      await expectLater(
        client.ping(),
        throwsA(isA<MusicRepositoryException>()
            .having((e) => e.message, 'message', 'Unexpected response from server.')),
      );
    });
  });
}

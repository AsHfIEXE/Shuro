import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/stream_probe.dart';

/// Tests for the interpretation of a stream probe's response headers — the part
/// that decides whether the app says "original file" or "the server is
/// transcoding this". The network call itself isn't exercised here; what matters
/// is that the verdict logic can't claim something the headers don't support.
void main() {
  StreamProbe probe({int status = 206, String contentType = '', int? bytes = 1024, bool range = true}) {
    return StreamProbe(
      statusCode: status,
      contentType: contentType,
      totalBytes: bytes,
      supportsRange: range,
      elapsed: const Duration(milliseconds: 42),
    );
  }

  group('servedFormat', () {
    test('maps the media types a Subsonic server actually sends', () {
      expect(probe(contentType: 'audio/flac').servedFormat, 'FLAC');
      expect(probe(contentType: 'audio/x-flac').servedFormat, 'FLAC');
      expect(probe(contentType: 'audio/mpeg').servedFormat, 'MP3');
      expect(probe(contentType: 'audio/mp4').servedFormat, 'M4A/AAC');
      expect(probe(contentType: 'audio/aac').servedFormat, 'M4A/AAC');
      expect(probe(contentType: 'audio/ogg').servedFormat, 'OGG');
      expect(probe(contentType: 'audio/opus').servedFormat, 'Opus');
      expect(probe(contentType: 'audio/wav').servedFormat, 'WAV');
    });

    test('is null when the server declares nothing recognisable', () {
      expect(probe(contentType: '').servedFormat, isNull);
      expect(probe(contentType: 'application/octet-stream').servedFormat, isNull);
    });
  });

  group('matchesFormat', () {
    test('confirms a FLAC library track arriving as FLAC', () {
      expect(probe(contentType: 'audio/flac').matchesFormat('FLAC'), isTrue);
    });

    test('flags a FLAC library track arriving as MP3', () {
      expect(probe(contentType: 'audio/mpeg').matchesFormat('FLAC'), isFalse);
    });

    test('accepts the m4a/alac family across its several media types', () {
      expect(probe(contentType: 'audio/mp4').matchesFormat('M4A'), isTrue);
      expect(probe(contentType: 'audio/x-m4a').matchesFormat('ALAC'), isTrue);
    });

    test('claims no mismatch when the server declared no format', () {
      expect(probe(contentType: '').matchesFormat('FLAC'), isTrue);
    });

    test('claims no mismatch when the library format is unknown', () {
      expect(probe(contentType: 'audio/mpeg').matchesFormat(''), isTrue);
    });
  });

  group('sizeLabel', () {
    test('reports megabytes for a real track', () {
      expect(probe(bytes: 30 * 1024 * 1024).sizeLabel, '30.0 MB');
    });

    test('reports kilobytes below one megabyte', () {
      expect(probe(bytes: 512 * 1024).sizeLabel, '512 KB');
    });

    test('says unknown rather than guessing', () {
      expect(probe(bytes: null).sizeLabel, 'unknown');
      expect(probe(bytes: 0).sizeLabel, 'unknown');
    });
  });
}

import 'dart:async';

import 'package:http/http.dart' as http;

/// What a server actually sends when it's asked to stream a track.
///
/// This exists because "Original" is a request, not a guarantee: a server can
/// honour it, ignore it, or transcode anyway if its own configuration says so,
/// and nothing in the app could previously tell the difference. The probe reads
/// the *response headers* for the real streaming URL and reports what came
/// back, so "am I getting the original file?" becomes an observable fact rather
/// than a hope.
class StreamProbe {
  final int statusCode;

  /// The response's declared media type, e.g. `audio/flac` or `audio/mpeg`.
  final String contentType;

  /// Total size of the track as the server reports it (from `Content-Range`,
  /// or `Content-Length` when the server ignores range requests).
  final int? totalBytes;

  /// Whether the server answered a range request with a 206 — ordinary for
  /// Subsonic servers, and worth surfacing because seeking depends on it.
  final bool supportsRange;

  final Duration elapsed;

  const StreamProbe({
    required this.statusCode,
    required this.contentType,
    required this.totalBytes,
    required this.supportsRange,
    required this.elapsed,
  });

  /// A readable label for the container the server chose, or null when the
  /// response didn't say (or said something unrecognised).
  String? get servedFormat {
    final type = contentType.toLowerCase();
    if (type.contains('flac')) return 'FLAC';
    if (type.contains('mpeg') || type.contains('mp3')) return 'MP3';
    if (type.contains('mp4') || type.contains('m4a') || type.contains('aac')) return 'M4A/AAC';
    if (type.contains('ogg')) return 'OGG';
    if (type.contains('opus')) return 'Opus';
    if (type.contains('wav') || type.contains('wave')) return 'WAV';
    if (type.contains('webm')) return 'WebM';
    return null;
  }

  /// Compares what was served with the format the library reports for the
  /// track. A mismatch is strong evidence of server-side transcoding — e.g. a
  /// FLAC in the library arriving as `audio/mpeg`.
  bool matchesFormat(String taggedFormat) {
    final served = servedFormat;
    if (served == null) return true; // nothing to compare — don't claim a mismatch
    final tagged = taggedFormat.toUpperCase();
    if (tagged.isEmpty) return true;
    if (served == 'M4A/AAC' && (tagged.startsWith('M4A') || tagged.startsWith('AAC') || tagged.startsWith('ALAC') || tagged.startsWith('MP4'))) return true;
    return served.toUpperCase() == tagged || tagged.startsWith(served.toUpperCase());
  }

  String get sizeLabel {
    final bytes = totalBytes;
    if (bytes == null || bytes <= 0) return 'unknown';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).round()} KB';
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Reads a stream's response headers without downloading the audio.
///
/// A single byte is requested (`Range: bytes=0-0`); whatever body the server
/// sends back is discarded immediately by closing the client, so this never
/// buffers a track. Failures are returned as a probe with status 0 rather than
/// thrown — the caller is a diagnostics panel, not a playback path.
class StreamProbeService {
  StreamProbeService._();

  static Future<StreamProbe> probe(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    final client = http.Client();
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Range'] = 'bytes=0-0';
      final response = await client.send(request).timeout(timeout);
      final contentRange = response.headers['content-range'];
      final status = response.statusCode;
      final total = _totalFromContentRange(contentRange) ?? (status == 200 ? response.contentLength : null);
      stopwatch.stop();

      // Don't read the audio: drop the body as soon as the headers are in.
      unawaited(response.stream.drain<void>().catchError((Object _) {}));

      return StreamProbe(
        statusCode: status,
        contentType: response.headers['content-type'] ?? '',
        totalBytes: total,
        supportsRange: contentRange != null,
        elapsed: stopwatch.elapsed,
      );
    } catch (_) {
      stopwatch.stop();
      return StreamProbe(
        statusCode: 0,
        contentType: '',
        totalBytes: null,
        supportsRange: false,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      // Closing while the body is still streaming is the point: it aborts the
      // transfer instead of letting a whole track download for a header check.
      client.close();
    }
  }

  /// `bytes 0-0/1234567` → 1234567.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final total = header.substring(slash + 1).trim();
    if (total == '*') return null;
    return int.tryParse(total);
  }
}

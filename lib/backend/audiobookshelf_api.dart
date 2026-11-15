import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/spoken_media.dart';

class AudiobookshelfApiException implements Exception {
  const AudiobookshelfApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One audio track of a play session. [contentUrl] is server-relative (e.g.
/// `/s/book/..../file/..`); [startOffset] is seconds from the start of the
/// item (or episode) - multi-file audiobooks lay each file on that timeline.
class AbsTrack {
  const AbsTrack(
      {required this.contentUrl,
      required this.mimeType,
      required this.startOffset,
      required this.duration});
  final String contentUrl;
  final String mimeType;
  final double startOffset;
  final double duration;
}

/// A server-side play session (POST /api/items/:id/play). [currentTime] is
/// the server's last-known position in seconds - fresher than the library
/// listing, so resume prefers it.
class AbsSession {
  const AbsSession(
      {required this.id, required this.currentTime, required this.tracks});
  final String id;
  final double currentTime;
  final List<AbsTrack> tracks;
}

/// Narrow, versioned Audiobookshelf client. It only uses current `/api`
/// routes and keeps books and podcast episodes distinct at the boundary.
class AudiobookshelfApi {
  AudiobookshelfApi({required String baseUrl, required this.token})
      : _base = Uri.parse(baseUrl.replaceFirst(RegExp(r'/+$'), ''));

  final Uri _base;
  final String token;

  Uri _uri(String path, [Map<String, String>? query]) => _base.replace(
      path: '${_base.path}/api$path'.replaceAll('//', '/'),
      queryParameters: query);
  Map<String, String> get _headers =>
      {'Authorization': 'Bearer $token', 'Accept': 'application/json'};

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final response = await http
        .get(_uri(path, query), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AudiobookshelfApiException(
          'Audiobookshelf rejected that API token.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AudiobookshelfApiException(
          'Audiobookshelf returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>)
      throw const AudiobookshelfApiException(
          'Audiobookshelf sent an invalid response.');
    return decoded;
  }

  Future<Map<String, dynamic>> _post(String path, Object? body) async {
    final response = await http
        .post(_uri(path),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AudiobookshelfApiException(
          'Audiobookshelf rejected that API token.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AudiobookshelfApiException(
          'Audiobookshelf returned ${response.statusCode}.');
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    return decoded;
  }

  Future<void> _patch(String path, Object body) async {
    final response = await http
        .patch(_uri(path),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AudiobookshelfApiException(
          'Audiobookshelf rejected that API token.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AudiobookshelfApiException(
          'Audiobookshelf returned ${response.statusCode}.');
    }
  }

  Future<void> validate() async => _get('/me');

  Future<List<SpokenLibrary>> libraries() async {
    final data = await _get('/libraries');
    final rows = data['libraries'] as List<dynamic>? ?? const [];
    return rows.whereType<Map<String, dynamic>>().map((row) {
      final type = row['mediaType'] == 'podcast'
          ? SpokenMediaType.podcast
          : SpokenMediaType.book;
      return SpokenLibrary(
          id: row['id'] as String,
          name: row['name'] as String? ?? 'Untitled library',
          type: type);
    }).toList();
  }

  /// Page size for library items. The server reports `numPages`; 100 keeps
  /// each request fast while the loop below still collects everything.
  static const int _itemsPageSize = 100;

  /// Safety cap so a server reporting a pathological page count cannot pin
  /// the app in a fetch loop (200 pages x 100 items = 20,000 items, well past
  /// any real personal library).
  static const int _itemsMaxPages = 200;

  Future<List<SpokenItem>> items(SpokenLibrary library) async {
    // Fetch EVERY page. The single-request version returned the first 100
    // items and silently stopped — the reported "not all data" bug: any
    // library larger than one page looked truncated with no error.
    final all = <SpokenItem>[];
    for (var page = 0; page < _itemsMaxPages; page++) {
      final data = await _get('/libraries/${library.id}/items', {
        'limit': '$_itemsPageSize',
        'page': '$page',
        'sort': 'media.metadata.title'
      });
      final rows = data['results'] as List<dynamic>? ?? const [];
      all.addAll(rows
          .whereType<Map<String, dynamic>>()
          .map((row) => _item(row, library.type)));
      final numPages = data['numPages'];
      final last =
          numPages is num ? page + 1 >= numPages.toInt() : rows.isEmpty;
      if (last || rows.isEmpty) break;
    }
    return all;
  }

  // --- Play sessions, covers, progress --------------------------------------

  /// Mime types just_audio opens natively, sent with the play request so
  /// the server picks direct-play files over transcodes.
  static const List<String> _supportedMimeTypes = [
    'audio/mpeg',
    'audio/mp4',
    'audio/flac',
    'audio/ogg',
    'audio/aac',
    'audio/x-m4a',
  ];

  /// Opens a real play session and returns the server-issued audio tracks.
  /// This is the only playback path: the guessed direct file URL
  /// (`/api/items/:id/file/:index`) hangs on several servers, while the
  /// session's `contentUrl` is what ABS's own clients actually stream.
  Future<AbsSession> startPlayback(String itemId, {String? episodeId}) async {
    final body = <String, dynamic>{
      'deviceInfo': {
        'deviceId': 'shuro-desktop',
        'clientName': 'Shuro',
        'deviceName': 'Shuro',
      },
      'forceTranscode': false,
      'forceDirectPlay': true,
      'mediaPlayer': 'just_audio',
      'supportedMimeTypes': _supportedMimeTypes,
      if (episodeId != null) 'episodeId': episodeId,
    };
    final data = await _post('/items/$itemId/play', body);
    final tracks = <AbsTrack>[];
    for (final row in (data['audioTracks'] as List<dynamic>? ?? const [])) {
      if (row is! Map<String, dynamic>) continue;
      final contentUrl = row['contentUrl'] as String? ?? '';
      if (contentUrl.isEmpty) continue;
      tracks.add(AbsTrack(
        contentUrl: contentUrl,
        mimeType: row['mimeType'] as String? ?? 'audio/mpeg',
        startOffset: (row['startOffset'] as num?)?.toDouble() ?? 0,
        duration: (row['duration'] as num?)?.toDouble() ?? 0,
      ));
    }
    if (tracks.isEmpty) {
      throw const AudiobookshelfApiException(
          'Audiobookshelf returned no audio for this item.');
    }
    return AbsSession(
      id: data['id'] as String? ?? '',
      currentTime: (data['currentTime'] as num?)?.toDouble() ?? 0,
      tracks: tracks,
    );
  }

  /// Full stream URL for a session track - `contentUrl` plus the token the
  /// media endpoint needs (session URLs are not bearer-authenticated).
  String streamUrlOf(AbsTrack track) {
    final raw = track.contentUrl;
    final url = raw.startsWith('http') ? raw : '$_base$raw';
    return '$url${url.contains('?') ? '&' : '?'}token=$token';
  }

  /// Cover URL the UI can load directly (token as a query param - an
  /// Authorization header is impossible inside Image.network).
  Uri coverUrl(String itemId) =>
      _uri('/items/$itemId/cover', {'token': token});

  /// Reports position back to the server (`itemId` or `itemId/episodeId`).
  Future<void> saveProgress(String id,
      {required double currentTime, required double duration}) async {
    final progress =
        duration <= 0 ? 0.0 : (currentTime / duration).clamp(0.0, 1.0);
    await _patch('/me/progress/$id', {
      'currentTime': currentTime,
      'duration': duration,
      'progress': progress,
      'isFinished': progress >= 0.99,
    });
  }

  /// Keeps the open play session aligned with the same position (best
  /// effort - progress still lands via [saveProgress] even when a server
  /// rejects the session sync).
  Future<void> syncSession(String sessionId,
      {required double currentTime, required double duration}) async {
    if (sessionId.isEmpty) return;
    try {
      await _post('/session/$sessionId/sync', {
        'currentTime': currentTime,
        'duration': duration,
        'timeListened': 0,
      });
    } catch (_) {}
  }

  /// Closes a play session, passing the final position so the server cannot
  /// revert progress to a stale session time (best effort).
  Future<void> closeSession(String sessionId,
      {double? currentTime, double? duration}) async {
    if (sessionId.isEmpty) return;
    try {
      final body = <String, dynamic>{};
      if (currentTime != null) {
        final total = duration ?? 0;
        body['currentTime'] = currentTime;
        body['duration'] = total;
        body['progress'] =
            total <= 0 ? 0.0 : (currentTime / total).clamp(0.0, 1.0);
        body['isFinished'] = total > 0 && currentTime / total >= 0.99;
      }
      await _post('/session/$sessionId/close', body.isEmpty ? null : body);
    } catch (_) {}
  }

  SpokenItem _item(Map<String, dynamic> row, SpokenMediaType type) {
    final media = row['media'] as Map<String, dynamic>? ?? const {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? const {};
    final duration = (media['duration'] as num?)?.toDouble() ?? 0;
    final progress = row['userMediaProgress'] as Map<String, dynamic>?;
    final episodes = (media['episodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((episode) => SpokenEpisode(
              id: episode['id'] as String? ?? '',
              title: episode['title'] as String? ?? 'Untitled episode',
              fileIndex: ((episode['audioFile']
                          as Map<String, dynamic>?)?['index'] as num?)
                      ?.toInt() ??
                  0,
              duration: Duration(
                  milliseconds:
                      (((episode['duration'] as num?)?.toDouble() ?? 0) * 1000)
                          .round()),
              description: episode['description'] as String? ?? '',
              progressSeconds: ((episode['userMediaProgress']
                          as Map<String, dynamic>?)?['currentTime'] as num?)
                      ?.toDouble() ??
                  0,
              publishedAt:
                  DateTime.tryParse(episode['publishedAt'] as String? ?? ''),
            ))
        .toList();
    return SpokenItem(
      id: row['id'] as String,
      libraryId: row['libraryId'] as String? ?? '',
      type: type,
      title: metadata['title'] as String? ?? 'Untitled',
      creator: type == SpokenMediaType.book
          ? ((metadata['authorName'] ?? metadata['narratorName']) as String? ??
              'Unknown creator')
          : (metadata['author'] as String? ?? 'Podcast'),
      duration: Duration(milliseconds: (duration * 1000).round()),
      description: metadata['description'] as String? ?? '',
      coverUrl: _uri('/items/${row['id']}/cover').toString(),
      progressSeconds: (progress?['currentTime'] as num?)?.toDouble() ?? 0,
      episodes: episodes,
    );
  }
}

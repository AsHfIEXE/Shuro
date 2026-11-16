import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/spoken_media.dart';
import '../playback/event_log.dart';

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

  /// Status failures carry the server's own error text (ABS sends a plain
  /// reason or {error: ...}) so a 400 names its cause in diagnostics
  /// instead of just its number.
  String _statusMessage(String method, String path, String body) {
    var detail = body.trim();
    if (detail.startsWith('{')) {
      try {
        final decoded = jsonDecode(detail);
        if (decoded is Map && decoded['error'] != null) {
          detail = '${decoded['error']}';
        }
      } catch (_) {}
    }
    detail = detail.replaceAll(RegExp(r'\s+'), ' ');
    if (detail.length > 120) detail = detail.substring(0, 120);
    return detail.isEmpty
        ? 'Audiobookshelf returned ${method.toUpperCase()} $path failed.'
        : 'Audiobookshelf: $detail';
  }

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
      throw AudiobookshelfApiException(_statusMessage(
          'get', path, response.body));
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
      throw AudiobookshelfApiException(_statusMessage(
          'post', path, response.body));
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
      throw AudiobookshelfApiException(_statusMessage(
          'patch', path, response.body));
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
    // m4b audiobooks report audio/x-m4b; when the mime is missing from
    // this list the server decides it must transcode to HLS - which the
    // Windows engine cannot open.
    'audio/x-m4b',
    'audio/m4b',
    'audio/mp4a-latm',
    'audio/aacp',
    'audio/wav',
    'audio/x-wav',
  ];

  /// Opens a real play session and returns the server-issued audio tracks.
  /// This is the only playback path: the guessed direct file URL
  /// (`/api/items/:id/file/:index`) hangs on several servers, while the
  /// session's `contentUrl` is what ABS's own clients actually stream.
  ///
  /// Robust against server shape differences - the first integration only
  /// read `audioTracks` and some servers answer the same POST with the
  /// tracks elsewhere: tracks are accepted from the session's
  /// `audioTracks`, the embedded `libraryItem.media.tracks`, a nested
  /// `session` object, or (1.x style) a top-level `streamUrl`. And when a
  /// forced direct play comes back empty, one retry without the force lets
  /// the server choose its own method. Every attempt is logged with what
  /// came back, so a future failure names the shape instead of guessing.
  Future<AbsSession> startPlayback(String itemId, {String? episodeId}) async {
    AudiobookshelfApiException? lastNoAudio;
    for (var attempt = 0; attempt < 2; attempt++) {
      final body = <String, dynamic>{
        'deviceInfo': {
          'deviceId': 'shuro-desktop',
          'clientName': 'Shuro',
          'deviceName': 'Shuro',
        },
        'forceTranscode': false,
        // Attempt 0 prefers direct play (no server CPU, instant start).
        // Some servers answer a forced direct play with an empty track
        // list when they would rather transcode; attempt 1 lets the
        // server decide.
        'forceDirectPlay': attempt == 0,
        'mediaPlayer': 'just_audio',
        'supportedMimeTypes': _supportedMimeTypes,
        if (episodeId != null) 'episodeId': episodeId,
      };
      final Map<String, dynamic> data;
      try {
        data = await _post('/items/$itemId/play', body);
      } on AudiobookshelfApiException {
        rethrow; // real HTTP errors surface immediately
      } catch (_) {
        continue; // timeout / socket: the other config is still worth one try
      }
      final extracted = _extractTracks(data);
      PlaybackEventLog.instance.add('abs.play', {
        'item': itemId,
        'episode': episodeId,
        'attempt': attempt,
        'playMethod': data['playMethod'],
        'via': extracted.via,
        'tracks': extracted.tracks.length,
      });
      if (extracted.tracks.isNotEmpty) {
        return AbsSession(
          id: data['id'] as String? ?? '',
          currentTime: (data['currentTime'] as num?)?.toDouble() ??
              (data['startTime'] as num?)?.toDouble() ??
              0,
          tracks: extracted.tracks,
        );
      }
      lastNoAudio = AudiobookshelfApiException(_noAudioMessage(data));
    }
    PlaybackEventLog.instance.add('abs.play.fail', {
      'item': itemId,
      'episode': episodeId,
      'msg': lastNoAudio?.message ?? 'no answer',
    });
    throw lastNoAudio ??
        const AudiobookshelfApiException(
            'Audiobookshelf did not answer the play request.');
  }

  /// Pulls playable tracks out of a play response, wherever this server
  /// decided to put them.
  ({List<AbsTrack> tracks, String via}) _extractTracks(
      Map<String, dynamic> data) {
    var via = 'audioTracks';
    var rows = _trackRows(data['audioTracks']);
    if (rows.isEmpty) {
      // The play response embeds the full library item; its media.tracks
      // are the documented direct-play Track objects.
      final embedded = data['libraryItem'] as Map<String, dynamic>?;
      final media = embedded?['media'] as Map<String, dynamic>?;
      rows = _trackRows(media?['tracks']);
      if (rows.isNotEmpty) via = 'libraryItem.media.tracks';
    }
    if (rows.isEmpty) {
      final nested = data['session'] as Map<String, dynamic>?;
      if (nested != null) {
        rows = _trackRows(nested['audioTracks']);
        if (rows.isNotEmpty) via = 'session.audioTracks';
      }
    }
    var tracks = [
      for (final row in rows)
        AbsTrack(
          contentUrl: row['contentUrl'] as String? ?? '',
          mimeType: row['mimeType'] as String? ?? 'audio/mpeg',
          startOffset: (row['startOffset'] as num?)?.toDouble() ?? 0,
          duration: (row['duration'] as num?)?.toDouble() ?? 0,
        ),
    ].where((track) => track.contentUrl.isNotEmpty).toList();
    if (tracks.isEmpty) {
      // 1.x-style single stream URL.
      final stream = data['streamUrl'] as String?;
      if (stream != null && stream.isNotEmpty) {
        tracks = [
          AbsTrack(
            contentUrl: stream,
            mimeType: 'audio/mpeg',
            startOffset: 0,
            duration: (data['duration'] as num?)?.toDouble() ?? 0,
          ),
        ];
        via = 'streamUrl';
      }
    }
    return (tracks: tracks, via: via);
  }

  List<Map<String, dynamic>> _trackRows(dynamic raw) {
    if (raw is Map<String, dynamic>) return [raw];
    if (raw is! List) return const [];
    return [for (final row in raw) if (row is Map<String, dynamic>) row];
  }

  String _noAudioMessage(Map<String, dynamic> data) {
    final tracks = data['audioTracks'];
    return 'Audiobookshelf returned no audio for this item '
        '(playMethod=${data['playMethod'] ?? '?'}, '
        'mediaType=${data['mediaType'] ?? '?'}, '
        'audioTracks=${tracks is List ? tracks.length : 'absent'}). '
        'If this item is ebook-only there is nothing to stream.';
  }

  /// Direct-play tracks from the FULL item (GET /api/items/:id). The
  /// library LISTING omits media.tracks - this is the response that
  /// carries each file's own /s/ contentUrl, i.e. the URLs ABS clients
  /// stream when they direct-play.
  Future<List<AbsTrack>> directTracks(String itemId) async {
    final data = await _get('/items/$itemId');
    final media = data['media'] as Map<String, dynamic>?;
    final trackRows = _trackRows(media?['tracks']);
    final audioFiles =
        (media?['audioFiles'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
    PlaybackEventLog.instance.add('abs.item', {
      'item': itemId,
      'tracks': trackRows.length,
      'audioFiles': audioFiles.length,
    });
    final fromTracks = [
      for (final row in trackRows)
        AbsTrack(
          contentUrl: row['contentUrl'] as String? ?? '',
          mimeType: row['mimeType'] as String? ?? 'audio/mpeg',
          startOffset: (row['startOffset'] as num?)?.toDouble() ?? 0,
          duration: (row['duration'] as num?)?.toDouble() ?? 0,
        ),
    ].where((track) => track.contentUrl.isNotEmpty).toList();
    if (fromTracks.isNotEmpty) return fromTracks;
    // No direct-play Track objects on this server - but the FILES exist.
    // /api/items/:id/file/:index streams each raw file; startOffsets come
    // from the cumulative file durations.
    var offset = 0.0;
    return [
      for (final file in audioFiles)
        () {
          final duration = (file['duration'] as num?)?.toDouble() ?? 0;
          final index = (file['index'] as num?)?.toInt() ?? 0;
          final track = AbsTrack(
            contentUrl: '/api/items/$itemId/file/$index',
            mimeType: 'audio/mpeg',
            startOffset: offset,
            duration: duration,
          );
          offset += duration;
          return track;
        }(),
    ];
  }

  /// One-off status probe for a stream URL (diagnostics: names the exact
  /// HTTP status the engine is failing on). Never throws.
  Future<int?> probeUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 5));
      return response.statusCode;
    } catch (_) {
      return -1;
    }
  }

  /// Full stream URL for a session track. Session contentUrls already carry
  /// their own auth (`?token=<sessionId>`); appending a SECOND `token=`
  /// param makes the server read an array and reject the stream - so the
  /// API token is only appended when the URL has none.
  String streamUrlOf(AbsTrack track) {
    final raw = track.contentUrl;
    final url = raw.startsWith('http') ? raw : '$_base$raw';
    if (url.contains('token=')) return url;
    return '$url${url.contains('?') ? '&' : '?'}token=$token';
  }

  /// Cover URL the UI can load directly (token as a query param - an
  /// Authorization header is impossible inside Image.network).
  Uri coverUrl(String itemId) =>
      _uri('/items/$itemId/cover', {'token': token});

  /// Reports position back to the server (`itemId` or `itemId/episodeId`).
  /// [forceFinished] drives "Mark as played" independent of the fraction.
  Future<void> saveProgress(String id,
      {required double currentTime,
      required double duration,
      bool? forceFinished}) async {
    final progress =
        duration <= 0 ? 0.0 : (currentTime / duration).clamp(0.0, 1.0);
    await _patch('/me/progress/$id', {
      'currentTime': currentTime,
      'duration': duration,
      'progress': progress,
      'isFinished': forceFinished ?? progress >= 0.99,
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

  // --- Bookmarks (ABS user bookmarks, time-keyed per item) -------------------

  Future<void> _delete(String path) async {
    final response = await http
        .delete(_uri(path), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AudiobookshelfApiException(
          'Audiobookshelf rejected that API token.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AudiobookshelfApiException(_statusMessage(
          'delete', path, response.body));
    }
  }

  /// All of the user's bookmarks (raw rows; filtered per item by the state).
  Future<List<Map<String, dynamic>>> bookmarks() async {
    final me = await _get('/me');
    return [
      for (final row in (me['bookmarks'] as List<dynamic>? ?? const []))
        if (row is Map<String, dynamic>) row
    ];
  }

  Future<void> addBookmark(String itemId,
          {required double time, required String title}) =>
      _post('/me/item/$itemId/bookmark', {'time': time, 'title': title});

  Future<void> removeBookmark(String itemId, double time) async {
    // The bookmark's time is its id in the ABS API.
    final key = time == time.roundToDouble()
        ? time.toInt().toString()
        : time.toString();
    await _delete('/me/item/$itemId/bookmark/$key');
  }

  SpokenItem _item(Map<String, dynamic> row, SpokenMediaType type) {
    final media = row['media'] as Map<String, dynamic>? ?? const {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? const {};
    final duration = (media['duration'] as num?)?.toDouble() ?? 0;
    final progress = row['userMediaProgress'] as Map<String, dynamic>?;
    final chapters = (media['chapters'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((chapter) => SpokenChapter(
              id: (chapter['id'] as num?)?.toInt() ?? 0,
              start: (chapter['start'] as num?)?.toDouble() ?? 0,
              end: (chapter['end'] as num?)?.toDouble() ?? 0,
              title: chapter['title'] as String? ?? '',
            ))
        .toList();
    final seriesNames = (metadata['series'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((series) => series['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final directTracks = (media['tracks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((track) => SpokenTrack(
              contentUrl: track['contentUrl'] as String? ?? '',
              mimeType: track['mimeType'] as String? ?? 'audio/mpeg',
              startOffset: (track['startOffset'] as num?)?.toDouble() ?? 0,
              duration: (track['duration'] as num?)?.toDouble() ?? 0,
            ))
        .where((track) => track.contentUrl.isNotEmpty)
        .toList();
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
              publishedAt: _parseDate(episode['publishedAt']),
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
      chapters: chapters,
      seriesNames: seriesNames,
      isFinished: (progress?['isFinished'] as bool? ?? false),
      tracks: directTracks,
    );
  }

  /// ABS sends episode publish stamps as epoch milliseconds; some builds
  /// send ISO strings. Accept both - a wrong assumption here killed every
  /// NEW badge and date in the list.
  DateTime? _parseDate(dynamic value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

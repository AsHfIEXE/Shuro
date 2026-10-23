import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/spoken_media.dart';

class AudiobookshelfApiException implements Exception {
  const AudiobookshelfApiException(this.message);
  final String message;
  @override
  String toString() => message;
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

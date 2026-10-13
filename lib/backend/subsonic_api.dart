import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/audio_info.dart';
import '../models/song.dart';
import 'music_repository.dart';

/// The interactive half of the Subsonic API — everything the app's original
/// catalogue client didn't cover: server search (search3), star/unstar,
/// scrobble (server-side play counting), ratings, playlists, the play-queue
/// sync pair, scan control, and the similar/top-songs family (the seam the
/// future Last.fm-based recommendations plug into).
///
/// Why a second client instead of growing `NavidromeApiClient`: that class is
/// the catalogue path (fetch library, build stream URLs) and is deliberately
/// frozen in this workspace; this one is additive and isolated, so a bug here
/// can never break playback. Both speak the same protocol — this file carries
/// its own copy of the standard Subsonic auth scheme (a random salt per
/// instance, every request signed with md5 of the server passphrase plus that
/// salt, so the passphrase itself never goes over the wire).
class SubsonicApi {
  SubsonicApi({
    required String baseUrl,
    required String username,
    required String passphrase,
    http.Client? httpClient,
  })  : _baseUrl = _normalize(baseUrl),
        _username = username,
        _passphrase = passphrase,
        _salt = _generateSalt(),
        _httpClient = httpClient ?? http.Client();

  static const String _apiVersion = '1.16.1';
  static const String _clientId = 'shuro';

  final String _baseUrl;
  final String _username;
  final String _passphrase;
  final String _salt;
  final http.Client _httpClient;

  static String _normalize(String url) {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed;
  }

  static String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Uri _buildUri(String method, Map<String, dynamic> params) {
    final authHash = md5.convert(utf8.encode('$_passphrase$_salt')).toString();
    final pairs = <String>[
      'u=${Uri.encodeQueryComponent(_username)}',
      't=$authHash',
      's=${Uri.encodeQueryComponent(_salt)}',
      'v=$_apiVersion',
      'c=$_clientId',
      'f=json',
    ];
    params.forEach((key, value) {
      // Several Subsonic endpoints take repeated keys — createPlaylist's
      // songId, savePlayQueue's id — which arrive here as List<String>.
      if (value is List) {
        for (final item in value) {
          pairs.add('$key=${Uri.encodeQueryComponent('$item')}');
        }
      } else {
        pairs.add('$key=${Uri.encodeQueryComponent('$value')}');
      }
    });
    return Uri.parse('$_baseUrl/rest/$method.view?${pairs.join('&')}');
  }

  Future<http.Response> _send(String method, Map<String, dynamic> params) {
    return _httpClient.get(_buildUri(method, params)).timeout(const Duration(seconds: 12));
  }

  /// One request → `subsonic-response` body, with the same error classes the
  /// catalogue client uses so callers can handle failures uniformly.
  Future<Map<String, dynamic>> _call(String method, Map<String, dynamic> params) async {
    final http.Response response;
    try {
      response = await _send(method, params);
    } on TimeoutException catch (e) {
      throw MusicRepositoryException('The server took too long to respond: $e', MusicRepositoryFailure.unreachable);
    } on SocketException catch (e) {
      throw MusicRepositoryException('Could not reach the server: $e', MusicRepositoryFailure.unreachable);
    } catch (e) {
      throw MusicRepositoryException('Could not reach the server: $e', MusicRepositoryFailure.unreachable);
    }

    if (response.statusCode != 200) {
      throw MusicRepositoryException('Server returned HTTP ${response.statusCode}.', MusicRepositoryFailure.unreachable);
    }
    final Map<String, dynamic> decoded;
    try {
      decoded = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw MusicRepositoryException('Unexpected response from server.', MusicRepositoryFailure.unknown);
    }
    final envelope = decoded['subsonic-response'] as Map<String, dynamic>?;
    if (envelope == null) {
      throw MusicRepositoryException('Unexpected response shape from server.', MusicRepositoryFailure.unknown);
    }
    if (envelope['status'] == 'ok') return envelope;

    final error = envelope['error'] as Map<String, dynamic>?;
    final code = error?['code'];
    final message = (error?['message'] as String?) ?? 'The server rejected the request.';
    if (code == 40 || code == 41) {
      throw MusicRepositoryException(message, MusicRepositoryFailure.invalidCredentials);
    }
    // Feature calls degrade, they don't crash the app: unsupported endpoints on
    // plain-Subsonic servers surface as a typed failure the callers catch.
    throw MusicRepositoryException(message, MusicRepositoryFailure.unknown);
  }

  static List<Map<String, dynamic>> _listOf(Object? raw) {
    if (raw is List) return raw.cast<Map<String, dynamic>>();
    if (raw is Map<String, dynamic>) return [raw]; // Subsonic servers may send a single object instead of a list
    return const [];
  }

  // --- search --------------------------------------------------------------

  /// search3: the full-server search. Returns the three raw result lists;
  /// [songs] maps them onto the app model.
  Future<SubsonicSearchResult> search3(
    String query, {
    int songCount = 30,
    int artistCount = 8,
    int albumCount = 8,
    int songOffset = 0,
  }) async {
    final body = await _call('search3', {
      'query': query,
      'songCount': '$songCount',
      'artistCount': '$artistCount',
      'albumCount': '$albumCount',
      'songOffset': '$songOffset',
    });
    final result = body['searchResult3'] as Map<String, dynamic>? ?? const {};
    return SubsonicSearchResult(
      songs: _listOf(result['song']),
      artists: _listOf(result['artist']),
      albums: _listOf(result['album']),
    );
  }

  // --- favourites & ratings --------------------------------------------------

  Future<void> star(String id) => _call('star', {'id': id});

  Future<void> unstar(String id) => _call('unstar', {'id': id});

  Future<void> setRating(String id, int rating) =>
      _call('setRating', {'id': id, 'rating': '$rating'});

  /// One song's live server state (userRating, starred, playCount) — used to
  /// show real values in the action sheet instead of stale copies.
  Future<Map<String, dynamic>?> getSong(String id) async {
    final body = await _call('getSong', {'id': id});
    return body['song'] as Map<String, dynamic>?;
  }

  /// Server-side starred song ids — the source of truth when merging the
  /// server's favourites into the device on connect.
  Future<Set<String>> starredSongIds() async {
    final body = await _call('getStarred2', {});
    final starred = body['starred2'] as Map<String, dynamic>? ?? const {};
    return {
      for (final song in _listOf(starred['song'])) '${song['id']}',
    };
  }

  // --- play counting ---------------------------------------------------------

  /// scrobble: [submission] true = a finished listen (Navidrome counts a play);
  /// false = "now playing" broadcast (what shows in other clients' dashboards).
  Future<void> scrobble(String songId, {required bool submission}) =>
      _call('scrobble', {'id': songId, 'submission': submission ? 'true' : 'false'});

  /// An artist's biography and picture from the server's own metadata
  /// (OpenSubsonic getArtistInfo2 — Navidrome fills artistImageUrl from its
  /// tags/fanart). Returns null when the server has nothing; the caller can
  /// fall back to MusicBrainz.
  Future<({String? imageUrl, String? biography})> getArtistInfo2(String id) async {
    try {
      final body = await _call('getArtistInfo2', {'id': id});
      final info = body['artistInfo2'] as Map<String, dynamic>?;
      return (
        imageUrl: info?['artistImageUrl'] as String?,
        biography: info?['biography'] as String?,
      );
    } catch (_) {
      return (imageUrl: null, biography: null);
    }
  }

  // --- discovery -------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getRandomSongs({int size = 50, String? genre}) async {
    final body = await _call('getRandomSongs', {
      'size': '$size',
      if (genre != null) 'genre': genre,
    });
    return _listOf(body['randomSongs']?['song']);
  }

  Future<List<Map<String, dynamic>>> getSongsByGenre(String genre, {int count = 50, int offset = 0}) async {
    final body = await _call('getSongsByGenre', {'genre': genre, 'count': '$count', 'offset': '$offset'});
    return _listOf(body['songsByGenre']?['song']);
  }

  /// Songs similar to the given artist/song id — the seam for "because you
  /// listened to…" once recommendations land.
  Future<List<Map<String, dynamic>>> getSimilarSongs2(String id, {int count = 50}) async {
    final body = await _call('getSimilarSongs2', {'id': id, 'count': '$count'});
    return _listOf(body['similarSongs2']?['song']);
  }

  /// An artist's most-played songs, by server play counts (which only exist
  /// once this app reports scrobbles).
  Future<List<Map<String, dynamic>>> getTopSongs(String artistName, {int count = 50}) async {
    final body = await _call('getTopSongs', {'artist': artistName, 'count': '$count'});
    return _listOf(body['topSongs']?['song']);
  }

  // --- playlists -------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final body = await _call('getPlaylists', {});
    return _listOf(body['playlists']?['playlist']);
  }

  Future<List<Map<String, dynamic>>> getPlaylistSongs(String id) async {
    final body = await _call('getPlaylist', {'id': id});
    return _listOf(body['playlist']?['entry']);
  }

  Future<void> createPlaylist(String name, {List<String> songIds = const []}) => _call('createPlaylist', {
        'name': name,
        'songId': songIds,
      });

  Future<void> updatePlaylist({
    required String id,
    String? name,
    List<String> songIdsToAdd = const [],
    List<int> songIndexesToRemove = const [],
  }) =>
      _call('updatePlaylist', {
        'playlistId': id,
        if (name != null) 'name': name,
        'songIdToAdd': songIdsToAdd,
        'songIndexToRemove': songIndexesToRemove.map((i) => '$i'),
      });

  Future<void> deletePlaylist(String id) => _call('deletePlaylist', {'id': id});

  // --- play queue sync ---------------------------------------------------------

  Future<Map<String, dynamic>?> getPlayQueue() async {
    final body = await _call('getPlayQueue', {});
    return body['playQueue'] as Map<String, dynamic>?;
  }

  Future<void> savePlayQueue({required String currentId, required int positionMs, required List<String> songIds}) =>
      _call('savePlayQueue', {
        'current': currentId,
        'position': '$positionMs',
        'id': songIds,
      });

  // --- server maintenance ------------------------------------------------------

  Future<({bool scanning, int count})> scanStatus() async {
    final body = await _call('getScanStatus', {});
    final status = body['scanStatus'] as Map<String, dynamic>? ?? const {};
    return (scanning: status['scanning'] == true, count: (status['count'] as num?)?.toInt() ?? 0);
  }

  Future<({bool scanning, int count})> startScan() async {
    final body = await _call('startScan', {});
    final status = body['scanStatus'] as Map<String, dynamic>? ?? const {};
    return (scanning: status['scanning'] == true, count: (status['count'] as num?)?.toInt() ?? 0);
  }

  // --- model mapping -----------------------------------------------------------

  /// Maps a Subsonic `Child` (song) entry onto the app's [Song]. Mirrors the
  /// catalogue mapper, with one honesty fix: no fabricated "FLAC"/"1000"
  /// fallbacks — when the server doesn't say, AudioInfo stays null and the
  /// Audio Information panel reports "Not reported" instead of inventing
  /// a format.
  Song songFromChild(
    Map<String, dynamic> song, {
    String? fallbackArtist,
    String? fallbackArtistId,
    String? fallbackAlbumId,
  }) {
    final songId = '${song['id']}';
    return Song(
      id: songId,
      title: (song['title'] as String?) ?? 'Unknown title',
      artist: (song['artist'] as String?) ?? fallbackArtist ?? 'Unknown artist',
      artistId: (song['artistId'] as String?) ?? fallbackArtistId ?? '',
      albumId: (song['albumId'] as String?) ?? fallbackAlbumId ?? '',
      duration: Duration(seconds: (song['duration'] as num?)?.toInt() ?? 0),
      gradientColors: _gradientFor(songId),
      artwork: song['coverArt'] != null ? NetworkImage(coverArtUrl('${song['coverArt']}')) : null,
      audioInfo: AudioInfo(
        format: (song['suffix'] as String?)?.toUpperCase(),
        bitrateKbps: (song['bitRate'] as num?)?.toInt(),
        bitDepth: (song['bitDepth'] as num?)?.toInt(),
        sampleRateHz: (song['samplingRate'] as num?)?.toInt(),
      ),
    );
  }

  // Same fixed palette the catalogue mapper uses, so a song from search and
  // the same song from the album page get identical placeholder colours.
  static const List<List<Color>> _palette = [
    [Color(0xFF6E56CF), Color(0xFF9E8CFC)],
    [Color(0xFFE0558C), Color(0xFFFF9CBB)],
    [Color(0xFF2F9E6E), Color(0xFF7BE6B1)],
    [Color(0xFFD97B29), Color(0xFFFFC37A)],
    [Color(0xFF2E7FD9), Color(0xFF8ECBFF)],
    [Color(0xFF9E3A3A), Color(0xFFFF8A8A)],
  ];

  List<Color> _gradientFor(String id) => _palette[id.hashCode.abs() % _palette.length];

  String coverArtUrl(String coverArtId, {int size = 500}) =>
      _buildUri('getCoverArt', {'id': coverArtId, 'size': '$size'}).toString();

  String streamUrl(String songId) => _buildUri('stream', {'id': songId}).toString();

  void dispose() {
    _httpClient.close();
  }
}

/// search3's three result lists, still raw — the caller maps what it shows.
class SubsonicSearchResult {
  final List<Map<String, dynamic>> songs;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;

  const SubsonicSearchResult({required this.songs, required this.artists, required this.albums});

  bool get isEmpty => songs.isEmpty && artists.isEmpty && albums.isEmpty;
}

/// Holds the live [SubsonicApi] for whichever server the app is connected to,
/// so any screen can reach server features without threading it through
/// constructors. Null while offline/local-only — every feature must treat that
/// as "server actions unavailable", not as an error.
class ServerSession extends ChangeNotifier {
  SubsonicApi? _api;

  SubsonicApi? get api => _api;

  bool get hasServer => _api != null;

  /// Replaces the session (on connect / server switch) and drops the old
  /// client's HTTP pool.
  void attach(SubsonicApi api) {
    _api?.dispose();
    _api = api;
    notifyListeners();
  }

  void detach() {
    _api?.dispose();
    _api = null;
    notifyListeners();
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

/// ListenBrainz scrobbling client (api.listenbrainz.org).
///
/// Token-based auth (no session keys, no API-signature), JSON body, one
/// endpoint for both now-playing and finished listens. Documented at
/// https://listenbrainz.readthedocs.io/en/latest/users/api/
class ListenBrainzClient {
  ListenBrainzClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://api.listenbrainz.org/1';

  /// Validates a user token and returns the MusicBrainz username,
  /// or null when the token is invalid / the request failed.
  Future<String?> validateToken(String token) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/validate-token'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['valid'] != true) return null;
      return body['user_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Submits a listen (now-playing or finished) to ListenBrainz.
  ///
  /// [listenedAt] is required for a finished scrobble (unix seconds) and must
  /// be null for a playing_now submission.
  /// Returns true when accepted (200), false otherwise (the caller decides
  /// whether to retry or drop based on the status code).
  Future<bool> submitListen({
    required String token,
    required bool playingNow,
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
    int? listenedAt,
  }) async {
    try {
      final metadata = <String, dynamic>{
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        if (durationSeconds != null) 'duration': durationSeconds,
        'additional_info': {
          'media_player': 'Shuro',
          'submission_client': 'Shuro',
          'music_service': 'listenbrainz'
        },
      };

      final body = jsonEncode({
        'listen_type': playingNow ? 'playing_now' : 'single',
        'payload': [
          {
            'track_metadata': metadata,
            if (!playingNow && listenedAt != null) 'listened_at': listenedAt,
          }
        ],
      });

      final response = await _client.post(
        Uri.parse('$_baseUrl/submit-listens'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

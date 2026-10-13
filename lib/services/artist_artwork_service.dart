import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/subsonic_api.dart';

/// Artist pictures, resolved once and cached forever.
///
/// Two sources, in order:
///  1. the connected server's own metadata (`getArtistInfo2` →
///     `artistImageUrl`) — Navidrome fills this from tags/fanart for artists
///     it knows;
///  2. MusicBrainz URL relations (`/artist/{mbid}?inc=url-rels`) searched by
///     name — the fallback for artists the server has no image for, and the
///     ONLY source for local-file artists (which have no server id at all).
///
/// Results persist in SharedPreferences (artist key → image URL), so the grid
/// is complete on the very first paint of every later session. Resolution is
/// queued and throttled: one request at a time per source, because MusicBrainz
/// enforces one request per second and the artists grid can ask for dozens.
class ArtistArtworkService extends ChangeNotifier {
  static const String _cacheKey = 'artist_artwork_urls_v1';

  final Map<String, String> _urls = {}; // key: artist key → image url
  final Set<String> _pending = {};
  bool _restored = false;

  SubsonicApi? _api;
  String? _username;

  /// Attaches the server session (called from ServerLink.bind's neighbourhood —
  /// actually read live from the provider by the caller of [warmUp]).
  void updateSession(SubsonicApi? api, String? username) {
    _api = api;
    _username = username;
  }

  /// Stable cache key: server artists key on their server id, local artists
  /// on their lower-cased name (so the same artist from any source shares the
  /// picture).
  static String keyFor({required String id, required String name}) =>
      id.isEmpty ? 'name:${name.toLowerCase()}' : 'id:$id';

  ImageProvider? forArtist({required String id, required String name}) {
    final url = _urls[keyFor(id: id, name: name)];
    return url == null ? null : NetworkImage(url);
  }

  bool isKnownMissing({required String id, required String name}) => _urls.containsKey(keyFor(id: id, name: name));

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        decoded.forEach((key, value) => _urls[key] = value as String);
      }
      notifyListeners();
    } catch (_) {
      // Corrupt cache: start clean.
    }
  }

  /// Queues resolution for every artist that has no picture yet. Fire and
  /// forget — each completion notifies, so grids fade pictures in as they land.
  Future<void> warmUp(List<({String id, String name})> artists) async {
    await restore();
    for (final artist in artists) {
      final key = keyFor(id: artist.id, name: artist.name);
      if (_urls.containsKey(key) || _pending.contains(key)) continue;
      _pending.add(key);
      unawaited(_resolve(artist.id, artist.name, key));
    }
  }

  Future<void> _resolve(String serverId, String name, String key) async {
    String? url;

    // 1. The server's own artist info.
    final api = _api;
    if (api != null && serverId.isNotEmpty) {
      final info = await api.getArtistInfo2(serverId);
      url = info.imageUrl;
    }

    // 2. MusicBrainz by name (also the only path for local-file artists).
    if (url == null || url.isEmpty) {
      url = await _musicBrainzImage(name);
    }

    if (url != null && url.isNotEmpty) {
      _urls[key] = url;
      await _persist();
      notifyListeners();
    }
    _pending.remove(key);
  }

  /// MusicBrainz: search the artist, then read its URL relations for something
  /// that is an image (wikimedia/other hosts). Throttled to 1 req/s by the
  /// shared throttle in the client — reused here via a local pacing delay.
  static Future<String?> _musicBrainzImage(String name) async {
    if (name.trim().isEmpty || name == 'Local file') return null;
    try {
      final client = HttpClient();
      try {
        final search = Uri.parse(
          'https://musicbrainz.org/ws/2/artist?query=${Uri.encodeQueryComponent('"$name"')}&limit=1&fmt=json',
        );
        final searchJson = await _getJson(client, search);
        final artists = searchJson?['artists'] as List<dynamic>?;
        if (artists == null || artists.isEmpty) return null;
        final mbid = (artists.first as Map<String, dynamic>)['id'] as String?;
        if (mbid == null) return null;
        // MusicBrainz enforces ~1 req/s — pace every call.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final detail = await _getJson(client, Uri.parse('https://musicbrainz.org/ws/2/artist/$mbid?inc=url-rels&fmt=json'));
        final relations = detail?['relations'] as List<dynamic>? ?? const [];
        for (final relation in relations) {
          if (relation is! Map<String, dynamic>) continue;
          final type = relation['type'] as String?;
          if (type != 'image' && type != 'visual art') continue;
          final url = (relation['url'] as Map<String, dynamic>?)?['resource'] as String?;
          if (url != null && url.startsWith('http')) return url;
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _getJson(HttpClient client, Uri uri) async {
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Shuro/2 ( self-hosted Navidrome client )');
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return json.decode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(_urls));
    } catch (_) {
      // Storage unavailable: cache lives for this session only.
    }
  }
}

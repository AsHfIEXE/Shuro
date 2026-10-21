import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/metadata/listenbrainz_client.dart';

/// Owns the ListenBrainz connection: user token, pending-listen queue, and
/// submission. Mirrors the ScrobbleService architecture (ordered persistent
/// queue, flush-on-opportunity, cap) so the two backends stay independent
/// but behave identically from the user's perspective.
class ListenBrainzService extends ChangeNotifier {
  ListenBrainzService._();

  static final ListenBrainzService instance = ListenBrainzService._();

  static const String _kToken = 'shuro_lb_token_v1';
  static const String _kUsername = 'shuro_lb_username_v1';
  static const String _kQueue = 'shuro_lb_queue_v1';
  static const int _queueCap = 500;

  final ListenBrainzClient _client = ListenBrainzClient();

  String? _token;
  String? _username;
  bool _enabled = false;
  List<Map<String, Object?>> _pending = [];
  bool _flushing = false;
  bool _loaded = false;

  String? get token => _token;
  String? get username => _username;
  bool get isEnabled => _enabled;
  bool get isReady => _enabled && _token != null && _token!.isNotEmpty;
  int get pendingCount => _pending.length;

  /// Restores the token + pending queue from storage. Call once at boot.
  Future<void> restore() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_kToken);
      _username = prefs.getString(_kUsername);
      _enabled = prefs.getBool('shuro_lb_enabled_v1') ?? (_token != null);
      final raw = prefs.getString(_kQueue);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _pending = list;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Saves the user's token and validates it against the API.
  /// Returns the MusicBrainz username on success, null on failure.
  Future<String?> setToken(String token) async {
    _token = token.trim();
    _username = await _client.validateToken(_token!);
    if (_username == null) {
      _token = null;
      notifyListeners();
      await _persistQueue();
      return null;
    }
    _enabled = true;
    notifyListeners();
    await _persistToken();
    return _username;
  }

  Future<void> disconnect() async {
    _token = null;
    _username = null;
    _enabled = false;
    notifyListeners();
    await _persistToken();
  }

  /// Feeds a now-playing ping (fire-and-forget, never queued).
  Future<void> nowPlaying({
    required String track,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    if (!isReady) return;
    unawaited(_client.submitListen(
      token: _token!,
      playingNow: true,
      trackName: track,
      artistName: artist,
      albumName: album,
      durationSeconds: durationSeconds,
    ));
  }

  /// Queues a finished scrobble, then flushes.
  Future<void> scrobble({
    required String track,
    required String artist,
    String? album,
    int? durationSeconds,
    required int listenedAtUnix,
  }) async {
    if (!isReady) return;
    _pending.add({
      'track': track,
      'artist': artist,
      if (album != null && album.isNotEmpty) 'album': album,
      'listened_at': listenedAtUnix,
      if (durationSeconds != null) 'duration': durationSeconds,
    });
    if (_pending.length > _queueCap) {
      _pending.removeRange(0, _pending.length - _queueCap);
    }
    await _persistQueue();
    await flush();
  }

  /// Sends queued listens oldest-first, stopping on failure (queue intact).
  Future<void> flush() async {
    if (_flushing || !isReady || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final entry = _pending.first;
        final ok = await _client.submitListen(
          token: _token!,
          playingNow: false,
          trackName: entry['track'] as String? ?? '',
          artistName: entry['artist'] as String? ?? '',
          albumName: entry['album'] as String?,
          durationSeconds: entry['duration'] as int?,
          listenedAt: entry['listened_at'] as int?,
        );
        if (!ok) return; // keep queue intact, retry on next opportunity
        _pending.removeAt(0);
      }
      await _persistQueue();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _persistToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token != null) {
        await prefs.setString(_kToken, _token!);
        if (_username != null) await prefs.setString(_kUsername, _username!);
      } else {
        await prefs.remove(_kToken);
        await prefs.remove(_kUsername);
      }
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQueue, jsonEncode(_pending));
    } catch (_) {}
  }
}

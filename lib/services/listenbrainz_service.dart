import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  /// The token can submit (and delete) listens for the account, so it lives in
  /// OS-backed secure storage like the server passwords — not in
  /// SharedPreferences, which Android backups and file reads expose in clear.
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Earliest time the next submit may be attempted (rate limit / outage
  /// backoff), so a failing endpoint is not hammered on every scrobble.
  DateTime _nextAttempt = DateTime.fromMillisecondsSinceEpoch(0);

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
      try {
        _token = await _secure.read(key: _kToken);
      } catch (_) {
        _token = null; // secure storage unavailable: ask for the token again
      }
      // One-time migration of tokens saved by earlier builds in plain prefs.
      final legacy = prefs.getString(_kToken);
      if (legacy != null) {
        if (_token == null || _token!.isEmpty) {
          _token = legacy;
          try {
            await _secure.write(key: _kToken, value: legacy);
          } catch (_) {}
        }
        await prefs.remove(_kToken);
      }
      _username = prefs.getString(_kUsername);
      _enabled = prefs.getBool('shuro_lb_enabled_v1') ?? (_token != null);
      final raw = prefs.getString(_kQueue);
      if (raw != null) {
        // Per-entry: one malformed entry must not discard the whole queue.
        _pending = [
          for (final e in (jsonDecode(raw) as List))
            if (e is Map<String, dynamic>) e,
        ];
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Saves the user's token and validates it against the API.
  /// Returns the MusicBrainz username on success, null on failure.
  Future<String?> setToken(String token) async {
    final candidate = token.trim();
    if (candidate.isEmpty) return null;
    // Validate with a LOCAL value and commit only on success: assigning first
    // meant a failed re-check (typo, network blip) wiped the working token and
    // let scrobbles go out with an unvalidated one while the await was pending.
    final name = await _client.validateToken(candidate);
    if (name == null) return null;
    // A different account must not inherit the previous account's listens.
    if (_username != null && _username != name) {
      _pending = [];
      await _persistQueue();
    }
    _token = candidate;
    _username = name;
    _enabled = true;
    _nextAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    await _persistToken();
    return name;
  }

  Future<void> disconnect() async {
    _token = null;
    _username = null;
    _enabled = false;
    // Listens queued for the old account must never reach whichever account
    // connects next.
    _pending = [];
    notifyListeners();
    await _persistToken();
    await _persistQueue();
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
    // ListenBrainz rejects a listen without track and artist names (400);
    // queueing one would only block the queue behind it.
    if (track.trim().isEmpty || artist.trim().isEmpty) return;
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
    if (DateTime.now().isBefore(_nextAttempt)) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final entry = _pending.first;
        final result = await _client.submitListenResult(
          token: _token!,
          playingNow: false,
          trackName: entry['track'] as String? ?? '',
          artistName: entry['artist'] as String? ?? '',
          albumName: entry['album'] as String?,
          durationSeconds: entry['duration'] as int?,
          listenedAt: entry['listened_at'] as int?,
        );
        if (result.accepted || result.rejected) {
          // Accepted, or permanently rejected (400): either way this entry is
          // done — a rejected one must not block everything behind it.
          if (result.rejected) {
            debugPrint('[listenbrainz] dropping a rejected listen (400)');
          }
          _pending.removeAt(0);
          continue;
        }
        if (result.unauthorized) {
          // Revoked / wrong token: stop, keep the queue, and make the UI show
          // "not connected" instead of failing silently forever.
          _enabled = false;
          notifyListeners();
          return;
        }
        // Rate limit, server error or offline: back off, keep the queue.
        final wait = result.retryAfterSeconds ??
            (result.status == 429 ? 60 : (result.status == 0 ? 30 : 120));
        _nextAttempt = DateTime.now().add(Duration(seconds: wait.clamp(10, 900)));
        return;
      }
    } finally {
      _flushing = false;
      // Persist whatever was removed, including on a partial flush.
      await _persistQueue();
    }
  }

  Future<void> _persistToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token != null) {
        await _secure.write(key: _kToken, value: _token!);
        if (_username != null) await prefs.setString(_kUsername, _username!);
      } else {
        await _secure.delete(key: _kToken);
        await prefs.remove(_kUsername);
      }
      await prefs.remove(_kToken); // never leave a clear-text copy behind
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kQueue, jsonEncode(_pending));
    } catch (_) {}
  }
}

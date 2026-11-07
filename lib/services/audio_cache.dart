import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_persistence.dart';

/// Song cache: keeps the songs you play (and the next few in the queue) on
/// this device so replays start instantly, skipping never waits on the
/// network, and recently played music still works when the connection drops.
///
/// It is separate from Downloads on purpose. Downloads are explicit, permanent
/// and listed; this cache is automatic, bounded by a size limit, and evicts the
/// least recently played song first.
///
/// Files are written as `<key>.part` and renamed to `<key>.audio` only when
/// complete, so a half-written file is never handed to the player.
class AudioCache extends ChangeNotifier {
  AudioCache._();
  static final AudioCache instance = AudioCache._();

  static const _kEnabled = 'audio_cache_enabled_v1';
  static const _kLimitMb = 'audio_cache_limit_mb_v1';
  static const _kWifiOnly = 'audio_cache_wifi_only_v1';

  /// Limits offered in Settings, in MB.
  static const List<int> limitChoicesMb = [256, 512, 1024, 2048, 5120];

  bool enabled = true;
  bool wifiOnly = true;
  int limitMb = 1024;

  /// Bytes currently on disk (complete files only). Refreshed on init, after a
  /// download finishes, after eviction and on clear.
  int usedBytes = 0;

  /// Songs currently being fetched, so the same one is never fetched twice.
  final Set<String> _inFlight = <String>{};
  final Map<String, http.Client> _clients = <String, http.Client>{};

  Directory? _dir;
  AppPersistence? _persistence;
  bool _ready = false;

  /// Reads settings and the folder size. Safe to call more than once and safe
  /// to fail (platforms without a writable support folder just never cache).
  Future<void> init() async {
    if (_ready) return;
    try {
      _persistence = await AppPersistence.load();
      final p = _persistence!;
      enabled = p.getBool(_kEnabled) ?? enabled;
      wifiOnly = p.getBool(_kWifiOnly) ?? wifiOnly;
      limitMb = int.tryParse(p.getString(_kLimitMb) ?? '') ?? limitMb;
    } catch (_) {
      // No persistence: defaults apply for this session.
    }
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}audio_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      // A previous run may have died mid-download; those files are useless.
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      usedBytes = _measure();
    } catch (_) {
      _dir = null;
    }
    _ready = true;
    notifyListeners();
  }

  int get limitBytes => limitMb * 1024 * 1024;

  String _keyFor(String songId, String qualityTag) {
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$safe-$qualityTag';
  }

  File _fileFor(Directory dir, String key) =>
      File('${dir.path}${Platform.pathSeparator}$key.audio');

  int _measure() {
    final dir = _dir;
    if (dir == null) return 0;
    var total = 0;
    try {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.audio')) total += f.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  /// A complete cached copy of the song at this quality, or null. Cheap and
  /// synchronous: the player asks while resolving a source. A hit refreshes the
  /// file's timestamp so eviction keeps what you actually listen to.
  String? locate(String songId, String qualityTag) {
    if (!enabled) return null;
    final dir = _dir;
    if (dir == null) return null;
    final file = _fileFor(dir, _keyFor(songId, qualityTag));
    try {
      if (!file.existsSync() || file.lengthSync() < 4096) return null;
      file.setLastModifiedSync(DateTime.now());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Fetches [url] into the cache in the background. Returns quietly on any
  /// failure: a missed cache fill must never disturb playback.
  Future<void> prefetch({
    required String songId,
    required String qualityTag,
    required String url,
    bool onWifi = true,
  }) async {
    if (!enabled || !_ready) return;
    if (wifiOnly && !onWifi) return;
    if (!url.startsWith('http')) return;
    final dir = _dir;
    if (dir == null) return;
    final key = _keyFor(songId, qualityTag);
    final done = _fileFor(dir, key);
    if (done.existsSync() || _inFlight.contains(key)) return;
    // Keep at most two fills running so the song being streamed right now is
    // never starved of bandwidth.
    if (_inFlight.length >= 2) return;

    _inFlight.add(key);
    final part = File('${dir.path}${Platform.pathSeparator}$key.part');
    IOSink? sink;
    final client = http.Client();
    _clients[key] = client;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      // Refuse songs bigger than the whole cache.
      final total = response.contentLength;
      if (total != null && total > limitBytes) return;
      sink = part.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (received > limitBytes) throw const FileSystemException('too big');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // Servers that answer with an error page instead of audio are tiny.
      if (received < 4096 || (total != null && received != total)) {
        throw const FileSystemException('incomplete');
      }
      await part.rename(done.path);
      usedBytes += received;
      await _evictIfNeeded(protect: done.path);
      notifyListeners();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
    } finally {
      _inFlight.remove(key);
      _clients.remove(key)?.close();
    }
  }

  /// Removes least-recently-played songs until the cache fits its limit.
  Future<void> _evictIfNeeded({String? protect}) async {
    final dir = _dir;
    if (dir == null || usedBytes <= limitBytes) return;
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.audio') && f.path != protect)
          .toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (usedBytes <= limitBytes) break;
        final len = f.lengthSync();
        try {
          f.deleteSync();
          usedBytes -= len;
        } catch (_) {}
      }
    } catch (_) {}
    usedBytes = _measure();
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    if (!value) _cancelAll();
    notifyListeners();
    await _persistence?.setBool(_kEnabled, value);
  }

  Future<void> setWifiOnly(bool value) async {
    if (wifiOnly == value) return;
    wifiOnly = value;
    notifyListeners();
    await _persistence?.setBool(_kWifiOnly, value);
  }

  Future<void> setLimitMb(int value) async {
    if (limitMb == value) return;
    limitMb = value;
    notifyListeners();
    await _persistence?.setString(_kLimitMb, value.toString());
    await _evictIfNeeded();
    notifyListeners();
  }

  void _cancelAll() {
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
  }

  /// Deletes every cached song. Downloads are untouched.
  Future<void> clear() async {
    _cancelAll();
    final dir = _dir;
    if (dir != null) {
      try {
        for (final f in dir.listSync().whereType<File>()) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      } catch (_) {}
    }
    usedBytes = _measure();
    notifyListeners();
  }
}

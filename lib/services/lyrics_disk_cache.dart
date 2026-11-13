import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Small on-device cache of LRCLIB records for songs the user actually played.
///
/// Why: a replayed or re-queued song should show lyrics instantly with no
/// network call at all - the biggest single thing that keeps the app well under
/// any rate limit. LRCLIB's data is openly published; this stores only the
/// tracks you listen to (bounded), never a bulk mirror.
///
/// One JSON file, loaded once, written at most every couple of seconds.
/// Entries expire after 30 days, oldest dropped past [_limit]. Any storage
/// problem (web, read-only disk) silently disables it - lookups just go to the
/// network as before.
class LyricsDiskCache {
  LyricsDiskCache._();

  static const int _limit = 250;
  static const Duration _ttl = Duration(days: 30);

  static Map<String, dynamic>? _entries;
  static Future<Map<String, dynamic>?>? _loading;
  static Timer? _flush;
  static File? _file;

  static Future<Map<String, dynamic>?> _load() =>
      // A storage read that never answers (seen in the wild: a platform
      // channel wedged at startup) must not stall every lookup behind it.
      // Three seconds, then the cache is simply off for this session.
      (_loading ??= () async {
        if (kIsWeb) return null;
        try {
          final dir = await getApplicationSupportDirectory();
          _file = File('${dir.path}${Platform.pathSeparator}lyrics_cache_v1.json');
          if (await _file!.exists()) {
            final decoded = json.decode(await _file!.readAsString());
            if (decoded is Map<String, dynamic>) {
              _entries = decoded;
              return _entries;
            }
          }
        } catch (_) {
          // Corrupt or unreadable: start empty.
        }
        _entries ??= <String, dynamic>{};
        return _entries;
      }())
          .timeout(const Duration(seconds: 3),
              onTimeout: () => _entries ??= <String, dynamic>{});

  static Future<Map<String, dynamic>?> read(String key) async {
    final entries = await _load();
    final entry = entries?[key];
    if (entry is! Map) return null;
    final t = entry['t'] as int?;
    final record = entry['r'];
    if (t == null || record is! Map) return null;
    if (DateTime.now().millisecondsSinceEpoch - t > _ttl.inMilliseconds) {
      entries!.remove(key);
      return null;
    }
    return record.cast<String, dynamic>();
  }

  static Future<void> write(String key, Map<String, dynamic> record) async {
    final entries = await _load();
    if (entries == null) return;
    entries.remove(key); // re-insert at the end (recency order)
    entries[key] = {'t': DateTime.now().millisecondsSinceEpoch, 'r': record};
    while (entries.length > _limit) {
      entries.remove(entries.keys.first);
    }
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 2), _save);
  }

  static Future<void> _save() async {
    final file = _file;
    final entries = _entries;
    if (file == null || entries == null) return;
    try {
      await file.writeAsString(json.encode(entries), flush: true);
    } catch (_) {}
  }
}

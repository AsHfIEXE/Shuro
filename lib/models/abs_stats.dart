import 'package:flutter/foundation.dart';

/// Parsed `GET /api/me/listening-stats` from Audiobookshelf.
///
/// Shape (server): `{ totalTime, today, days: {"2026-11-14": seconds},
/// dayOfWeek: {...}, items: {id: {id, timeListening, mediaMetadata}},
/// recentSessions: [...] }`. Everything is derived from `days` where
/// possible (weekday totals, streaks) because that map is the one field
/// every server version fills the same way.
@immutable
class AbsListeningStats {
  const AbsListeningStats({
    required this.totalSeconds,
    required this.todaySeconds,
    required this.days,
    required this.top,
    required this.recent,
  });

  final double totalSeconds;
  final double todaySeconds;

  /// Local calendar day (midnight) -> seconds listened.
  final Map<DateTime, double> days;
  final List<AbsTopItem> top;
  final List<AbsRecentSession> recent;

  static const empty = AbsListeningStats(
      totalSeconds: 0, todaySeconds: 0, days: {}, top: [], recent: []);

  factory AbsListeningStats.fromJson(Map<String, dynamic> json) {
    double num_(Object? v) => v is num ? v.toDouble() : 0;

    final days = <DateTime, double>{};
    final rawDays = json['days'];
    if (rawDays is Map) {
      rawDays.forEach((k, v) {
        final d = DateTime.tryParse('$k');
        if (d != null) days[DateTime(d.year, d.month, d.day)] = num_(v);
      });
    }

    final top = <AbsTopItem>[];
    final rawItems = json['items'];
    if (rawItems is Map) {
      for (final v in rawItems.values) {
        if (v is! Map) continue;
        final meta = v['mediaMetadata'];
        top.add(AbsTopItem(
          id: '${v['id'] ?? ''}',
          title: meta is Map ? '${meta['title'] ?? 'Untitled'}' : 'Untitled',
          seconds: num_(v['timeListening']),
        ));
      }
      top.sort((a, b) => b.seconds.compareTo(a.seconds));
    }

    final recent = <AbsRecentSession>[];
    final rawRecent = json['recentSessions'];
    if (rawRecent is List) {
      for (final v in rawRecent) {
        if (v is! Map) continue;
        final at = v['updatedAt'] ?? v['startedAt'];
        recent.add(AbsRecentSession(
          itemId: '${v['libraryItemId'] ?? ''}',
          title: '${v['displayTitle'] ?? 'Untitled'}',
          seconds: num_(v['timeListening']),
          at: at is num
              ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
              : at is String
                  ? DateTime.tryParse(at)
                  : null,
        ));
      }
    }

    return AbsListeningStats(
      totalSeconds: num_(json['totalTime']),
      todaySeconds: num_(json['today']),
      days: days,
      top: top,
      recent: recent,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Seconds for each of the last [n] days, oldest first, today last.
  List<({DateTime day, double seconds})> lastDays(int n, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    return [
      for (var i = n - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          seconds: days[today.subtract(Duration(days: i))] ?? 0,
        ),
    ];
  }

  double secondsInLast(int n, {DateTime? now}) =>
      lastDays(n, now: now).fold(0.0, (a, d) => a + d.seconds);

  /// Today's listening: the server's own `today` when it reports one, else
  /// the day bucket.
  double today({DateTime? now}) {
    final bucket = days[_day(now ?? DateTime.now())] ?? 0;
    return todaySeconds > bucket ? todaySeconds : bucket;
  }

  /// Consecutive days with listening, counted back from today (a quiet
  /// today does not break a streak that was alive yesterday).
  int streak({DateTime? now}) {
    var cursor = _day(now ?? DateTime.now());
    if ((days[cursor] ?? 0) <= 0) cursor = cursor.subtract(const Duration(days: 1));
    var n = 0;
    while ((days[cursor] ?? 0) > 0) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get bestStreak {
    final keys = days.entries.where((e) => e.value > 0).map((e) => e.key).toList()
      ..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in keys) {
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  /// Average seconds per weekday over every recorded day; index 0 = Monday.
  List<double> weekdayAverages() {
    final sum = List<double>.filled(7, 0);
    final count = List<int>.filled(7, 0);
    days.forEach((d, s) {
      if (s <= 0) return;
      sum[d.weekday - 1] += s;
      count[d.weekday - 1]++;
    });
    return [for (var i = 0; i < 7; i++) count[i] == 0 ? 0 : sum[i] / count[i]];
  }
}

@immutable
class AbsTopItem {
  const AbsTopItem({required this.id, required this.title, required this.seconds});
  final String id;
  final String title;
  final double seconds;
}

@immutable
class AbsRecentSession {
  const AbsRecentSession(
      {required this.itemId,
      required this.title,
      required this.seconds,
      required this.at});
  final String itemId;
  final String title;
  final double seconds;
  final DateTime? at;
}

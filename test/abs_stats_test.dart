import 'package:flutter_test/flutter_test.dart';

import 'package:shuro/models/abs_stats.dart';

void main() {
  final monday = DateTime(2026, 11, 9); // a Monday
  DateTime day(int offsetFromMonday) =>
      monday.add(Duration(days: offsetFromMonday));
  String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> payload({
    Map<String, double> daysPerDate = const {},
    double totalTime = 0,
    double today = 0,
    List<Map<String, dynamic>> recent = const [],
    Map<String, Map<String, dynamic>> items = const {},
  }) =>
      {
        'totalTime': totalTime,
        'today': today,
        'days': daysPerDate.map((k, v) => MapEntry(k, v)),
        'dayOfWeek': <String, double>{},
        'items': items,
        'recentSessions': recent,
      };

  group('AbsListeningStats.fromJson', () {
    test('parses days, totals, top items and recent sessions', () {
      final stats = AbsListeningStats.fromJson(payload(
        totalTime: 3600 + 600,
        today: 600,
        daysPerDate: {key(monday): 3600, key(day(1)): 600},
        items: {
          'item_b': {
            'id': 'item_b',
            'timeListening': 600,
            'mediaMetadata': {'title': 'Short Book'},
          },
          'item_a': {
            'id': 'item_a',
            'timeListening': 3600,
            'mediaMetadata': {'title': 'Long Book'},
          },
        },
        recent: [
          {
            'libraryItemId': 'item_a',
            'displayTitle': 'Long Book',
            'timeListening': 1200,
            'updatedAt': 1763300000000, // epoch ms
          },
          {
            'libraryItemId': 'item_b',
            'displayTitle': 'Short Book',
            'timeListening': 300,
            'updatedAt': '2026-11-16T10:30:00.000Z', // ISO string
          },
        ],
      ));

      expect(stats.totalSeconds, 4200);
      expect(stats.todaySeconds, 600);
      expect(stats.days, {
        DateTime(2026, 11, 9): 3600,
        DateTime(2026, 11, 10): 600,
      });
      // Top items are sorted by seconds, most first.
      expect(stats.top.map((t) => t.title).toList(),
          ['Long Book', 'Short Book']);
      expect(stats.recent, hasLength(2));
      expect(stats.recent.first.at, DateTime.fromMillisecondsSinceEpoch(1763300000000));
      expect(stats.recent.last.at, DateTime.utc(2026, 11, 16, 10, 30));
    });

    test('garbage-safe: empty and malformed maps collapse to zeros', () {
      final stats = AbsListeningStats.fromJson({});
      expect(stats.totalSeconds, 0);
      expect(stats.todaySeconds, 0);
      expect(stats.days, isEmpty);
      expect(stats.top, isEmpty);
      expect(stats.recent, isEmpty);
      expect(stats.streak(now: monday), 0);
      expect(stats.weekdayAverages(), everyElement(0));
    });
  });

  group('derivation', () {
    test('lastDays is oldest-first with today last, missing days are zero', () {
      final stats = AbsListeningStats.fromJson(payload(
        daysPerDate: {key(monday): 60, key(day(2)): 120},
      ));
      final week = stats.lastDays(7, now: day(6));
      expect(week, hasLength(7));
      expect(week.first.day, monday);
      expect(week.last.day, day(6)); // "today" in this clock
      expect(week.first.seconds, 60);
      expect(week[2].seconds, 120);
      expect(week[1].seconds, 0);
      expect(stats.secondsInLast(7, now: day(6)), 180);
    });

    test('today() trusts the server number when it beats the bucket', () {
      final stats = AbsListeningStats.fromJson(payload(
        today: 900,
        daysPerDate: {key(DateTime.now()): 300},
      ));
      expect(stats.today(), 900);
      final quiet = AbsListeningStats.fromJson(payload(
        today: 0,
        daysPerDate: {key(DateTime.now()): 300},
      ));
      expect(quiet.today(), 300);
    });

    test('streak counts back and forgives a quiet today', () {
      final stats = AbsListeningStats.fromJson(payload(
        daysPerDate: {
          key(day(1)): 60,
          key(day(2)): 60,
          key(day(3)): 60,
          key(day(4)): 60,
          // day(5) = "today" quiet: the run that was alive yesterday keeps
          // counting.
        },
      ));
      expect(stats.streak(now: day(5)), 4);
      // Listening today extends the run one further.
      final withToday = AbsListeningStats.fromJson(payload(
        daysPerDate: {
          key(day(2)): 60,
          key(day(3)): 60,
          key(day(4)): 60,
          key(day(5)): 60,
        },
      ));
      expect(withToday.streak(now: day(5)), 4);
      // A quiet yesterday (outside today's grace) stops the count.
      final quietYesterday = AbsListeningStats.fromJson(payload(
        daysPerDate: {
          key(day(1)): 60,
          key(day(2)): 60,
          key(day(3)): 60,
          // day(4) quiet, day(5) = "today" quiet
        },
      ));
      expect(quietYesterday.streak(now: day(5)), 0);
    });

    test('bestStreak finds the longest run across all history', () {
      final stats = AbsListeningStats.fromJson(payload(
        daysPerDate: {
          key(day(0)): 60,
          key(day(1)): 60,
          key(day(2)): 60,
          // gap
          key(day(5)): 60,
          key(day(6)): 60,
        },
      ));
      expect(stats.bestStreak, 3);
    });

    test('weekdayAverages average per weekday, Monday is index 0', () {
      // Two Mondays with 3600 and 1800 -> Monday average 2700; one Tuesday 600.
      final stats = AbsListeningStats.fromJson(payload(
        daysPerDate: {
          key(day(0)): 3600, // Mon
          key(day(7)): 1800, // next Mon
          key(day(1)): 600, // Tue
        },
      ));
      final avg = stats.weekdayAverages();
      expect(avg[0], 2700);
      expect(avg[1], 600);
      expect(avg[2], 0);
    });
  });

  test('empty constant is safe to read', () {
    expect(AbsListeningStats.empty.totalSeconds, 0);
    expect(AbsListeningStats.empty.days, isEmpty);
  });
}

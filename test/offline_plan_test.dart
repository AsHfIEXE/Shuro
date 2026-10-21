import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/offline_plan.dart';

void main() {
  test('offline plan persists its name, ordered song IDs, and creation time',
      () {
    const plan = OfflinePlan(
      id: 'flight-mix',
      name: 'Flight mix',
      songIds: ['song-3', 'song-1', 'song-2'],
      createdAtMs: 1234,
    );

    final restored = OfflinePlan.fromJson(plan.toJson());
    expect(restored.id, plan.id);
    expect(restored.name, plan.name);
    expect(restored.songIds, plan.songIds);
    expect(restored.createdAtMs, plan.createdAtMs);
  });

  test('offline plan accepts older stored plans with no creation timestamp',
      () {
    final plan = OfflinePlan.fromJson({
      'id': 'legacy',
      'name': 'Legacy plan',
      'songIds': ['song-1'],
    });

    expect(plan.createdAtMs, 0);
    expect(plan.songIds, ['song-1']);
  });
}

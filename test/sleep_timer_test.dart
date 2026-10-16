import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/state/player_controller.dart';

/// Sleep-timer timing math (the spec's quality bar): the countdown label
/// format used on the Sleep chip, including the guards around zero/negative.
void main() {
  group('formatSleepCountdown', () {
    test('minutes and seconds under an hour', () {
      expect(formatSleepCountdown(const Duration(minutes: 5)), '5:00');
      expect(formatSleepCountdown(const Duration(minutes: 23, seconds: 10)), '23:10');
      expect(formatSleepCountdown(const Duration(seconds: 9)), '0:09');
    });

    test('hours format with zero-padded minutes and seconds', () {
      expect(formatSleepCountdown(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
      expect(formatSleepCountdown(const Duration(hours: 12)), '12:00:00');
    });

    test('zero and negative clamp to 0:00 (never "-1:-30")', () {
      expect(formatSleepCountdown(Duration.zero), '0:00');
      expect(formatSleepCountdown(const Duration(seconds: -90)), '0:00');
    });
  });
}

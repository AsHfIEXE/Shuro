import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/services/device_profile.dart';
import 'package:shuro/state/appearance_settings.dart';

/// Phase 3 exit criteria: mapping device → profile and the preset table are
/// pure functions, pinned here. No channels, no plugins — these run anywhere.
void main() {
  group('device class classification', () {
    test('2 GB phone is Low', () {
      expect(
        DeviceProfileService.classify(totalRamMb: 2048, isLowRamDevice: false),
        DeviceClass.low,
      );
    });

    test('exactly 3 GB is Low (the brief boundary)', () {
      expect(
        DeviceProfileService.classify(totalRamMb: 3072, isLowRamDevice: false),
        DeviceClass.low,
      );
    });

    test('lowRamDevice flag forces Low even with 6 GB', () {
      expect(
        DeviceProfileService.classify(totalRamMb: 6144, isLowRamDevice: true),
        DeviceClass.low,
      );
    });

    test('4 GB is Low (weak-CPU budget class)', () {
      expect(
        DeviceProfileService.classify(totalRamMb: 4096, isLowRamDevice: false),
        DeviceClass.low,
      );
    });

    test('5 GB is Mid, 6 GB is Mid, 8 GB is High', () {
      expect(
        DeviceProfileService.classify(totalRamMb: 5120, isLowRamDevice: false),
        DeviceClass.mid,
      );
      expect(
        DeviceProfileService.classify(totalRamMb: 6144, isLowRamDevice: false),
        DeviceClass.mid,
      );
      expect(
        DeviceProfileService.classify(totalRamMb: 8192, isLowRamDevice: false),
        DeviceClass.high,
      );
    });
  });

  group('preset mapping', () {
    test('Low → Performance, Mid → Balanced, High → Quality', () {
      expect(DeviceProfileService.presetProfileFor(DeviceClass.low), ShuroProfile.performance);
      expect(DeviceProfileService.presetProfileFor(DeviceClass.mid), ShuroProfile.balanced);
      expect(DeviceProfileService.presetProfileFor(DeviceClass.high), ShuroProfile.quality);
    });
  });

  group('presets change real settings', () {
    test('Performance: still backdrop, zero blur, reduced motion, 40 MB cache', () {
      const p = DeviceProfileService.performancePreset;
      expect(p.backgroundStyle, BackgroundStyle.staticArtwork);
      expect(p.backdropMotion, BackdropMotion.still);
      expect(p.backdropBlurScale, 0);
      expect(p.reduceMotion, isTrue);
      expect(p.imageCacheBytes, 40 * 1024 * 1024);
    });

    test('Quality: animated backdrop, full blur, full motion, 150 MB cache', () {
      const p = DeviceProfileService.qualityPreset;
      expect(p.backgroundStyle, BackgroundStyle.animatedBlur);
      expect(p.backdropMotion, BackdropMotion.normal);
      expect(p.backdropBlurScale, 1.0);
      expect(p.reduceMotion, isFalse);
      expect(p.imageCacheBytes, 150 * 1024 * 1024);
    });

    test('Balanced sits between the two on cache size', () {
      const b = DeviceProfileService.balancedPreset;
      expect(b.imageCacheBytes, greaterThan(DeviceProfileService.performancePreset.imageCacheBytes));
      expect(b.imageCacheBytes, lessThan(DeviceProfileService.qualityPreset.imageCacheBytes));
    });

    test('every preset has a non-empty summary and changes list', () {
      for (final p in [DeviceProfileService.performancePreset, DeviceProfileService.balancedPreset, DeviceProfileService.qualityPreset]) {
        expect(p.summary, isNotEmpty);
        expect(p.changes.length, 6);
      }
    });

    test('image cache arithmetic in the summary is right', () {
      expect(DeviceProfileService.performancePreset.summary, contains('40 MB'));
      expect(DeviceProfileService.qualityPreset.summary, contains('150 MB'));
    });
  });
}

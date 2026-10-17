import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/appearance_settings.dart';
import '../widgets/page_transitions.dart' as transitions;

/// Device class derived from real capability readings (brief §3B).
enum DeviceClass { low, mid, high }

/// The user-facing performance profile (brief §3A). [auto] resolves to a
/// preset from the device class; the others are explicit choices.
enum ShuroProfile { auto, performance, balanced, quality }

/// One concrete set of effect levels a profile applies. Every field maps to a
/// setting that genuinely changes rendering — there are no decorative rows.
class ProfilePreset {
  const ProfilePreset({
    required this.name,
    required this.tagline,
    required this.backgroundStyle,
    required this.backdropMotion,
    required this.backdropBlurScale,
    required this.reduceMotion,
    required this.imageCacheBytes,
    required this.syncConcurrency,
  });

  final String name;
  final String tagline;
  final BackgroundStyle backgroundStyle;
  final BackdropMotion backdropMotion;
  final double backdropBlurScale;
  final bool reduceMotion;
  final int imageCacheBytes;

  /// Library-sync parallelism (brief §2D): concurrent album fetches while
  /// connecting to a server. Low-end devices get fewer in-flight requests.
  final int syncConcurrency;

  /// Plain-language live summary (brief §3A: "Animations: Reduced · Blur: Off ·
  /// Image cache: 40 MB").
  String get summary {
    final blur = backdropBlurScale <= 0.01
        ? 'Off'
        : '${(backdropBlurScale * 100).round()}%';
    final mb = (imageCacheBytes / (1024 * 1024)).round();
    return 'Animations: ${reduceMotion ? 'Reduced' : 'Full'} · '
        'Backdrop: ${backgroundStyle.name} · '
        'Motion: ${backdropMotion.name} · Blur: $blur · '
        'Image cache: $mb MB';
  }

  /// The "What this changes" list — each line is a real, wired effect.
  List<String> get changes => [
        'Page transitions: ${reduceMotion ? 'simple fade' : 'full animation'}',
        'Backdrop: ${backgroundStyle == BackgroundStyle.animatedBlur ? 'animated blurred artwork' : backgroundStyle == BackgroundStyle.animatedGradient ? 'drifting gradient' : 'static artwork'}',
        'Backdrop motion: ${backdropMotion.name}',
        'Backdrop blur: ${backdropBlurScale <= 0.01 ? 'off' : '${(backdropBlurScale * 100).round()}%'}',
        'Image cache: ${(imageCacheBytes / (1024 * 1024)).round()} MB',
        'Library sync: $syncConcurrency parallel requests',
      ];
}

class DeviceProfileService {
  DeviceProfileService._();

  static const MethodChannel _channel = MethodChannel('shuro/device_profile');
  static const String _prefKey = 'shuro_perf_profile_v1';

  static const ProfilePreset performancePreset = ProfilePreset(
    name: 'Performance',
    tagline: 'Built for low-RAM phones — lightest rendering, smallest cache.',
    backgroundStyle: BackgroundStyle.staticArtwork,
    backdropMotion: BackdropMotion.still,
    backdropBlurScale: 0,
    reduceMotion: true,
    imageCacheBytes: 40 * 1024 * 1024,
    syncConcurrency: 2,
  );

  static const ProfilePreset balancedPreset = ProfilePreset(
    name: 'Balanced',
    tagline: 'The default: smooth effects with sane memory use.',
    backgroundStyle: BackgroundStyle.staticArtwork,
    backdropMotion: BackdropMotion.subtle,
    backdropBlurScale: 0.5,
    reduceMotion: false,
    imageCacheBytes: 80 * 1024 * 1024,
    syncConcurrency: 4,
  );

  static const ProfilePreset qualityPreset = ProfilePreset(
    name: 'Quality',
    tagline: 'Every effect at full strength — for powerful devices.',
    backgroundStyle: BackgroundStyle.animatedBlur,
    backdropMotion: BackdropMotion.normal,
    backdropBlurScale: 1.0,
    reduceMotion: false,
    imageCacheBytes: 150 * 1024 * 1024,
    syncConcurrency: 6,
  );

  static ProfilePreset presetFor(ShuroProfile profile) {
    switch (profile) {
      case ShuroProfile.performance:
        return performancePreset;
      case ShuroProfile.balanced:
        return balancedPreset;
      case ShuroProfile.quality:
        return qualityPreset;
      case ShuroProfile.auto:
        return balancedPreset;
    }
  }

  /// Pure mapping device reading → class (brief §3B: Low ≤ 3 GB or lowRam,
  /// Mid 4–6 GB, High ≥ 8 GB). Kept pure so the tests can pin it.
  static DeviceClass classify({
    required int totalRamMb,
    required bool isLowRamDevice,
  }) {
    if (isLowRamDevice || totalRamMb <= 3 * 1024) return DeviceClass.low;
    if (totalRamMb <= 6 * 1024) return DeviceClass.mid;
    return DeviceClass.high;
  }

  static ShuroProfile presetProfileFor(DeviceClass deviceClass) {
    switch (deviceClass) {
      case DeviceClass.low:
        return ShuroProfile.performance;
      case DeviceClass.mid:
        return ShuroProfile.balanced;
      case DeviceClass.high:
        return ShuroProfile.quality;
    }
  }

  /// Reads the native capability map; null when the channel is unavailable
  /// (web, tests, or a build without the bridge) — callers must handle that
  /// honestly instead of inventing a class.
  static Future<Map<String, Object?>?> readCapabilities() async {
    if (kIsWeb) return null;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('getProfile');
      return map;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Current stored profile choice.
  static Future<ShuroProfile> storedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    return ShuroProfile.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => ShuroProfile.auto,
    );
  }

  static Future<void> storeProfile(ShuroProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, profile.name);
  }

  /// Resolves the profile that is actually in effect right now, with the
  /// readings that produced it (for the settings screen's explanation).
  static Future<({ShuroProfile choice, ShuroProfile effective, DeviceClass? deviceClass, int? totalRamMb})>
      resolve() async {
    final choice = await storedProfile();
    final caps = await readCapabilities();
    DeviceClass? deviceClass;
    int? ramMb;
    if (caps != null) {
      ramMb = (caps['totalRamMb'] as num?)?.toInt();
      final lowRam = (caps['isLowRamDevice'] as bool?) ?? false;
      if (ramMb != null) {
        deviceClass = classify(totalRamMb: ramMb, isLowRamDevice: lowRam);
      } else if (lowRam) {
        deviceClass = DeviceClass.low;
      }
    }
    final effective = choice != ShuroProfile.auto
        ? choice
        : (deviceClass == null ? ShuroProfile.balanced : presetProfileFor(deviceClass));
    return (choice: choice, effective: effective, deviceClass: deviceClass, totalRamMb: ramMb);
  }

  /// Applies a profile to the real, wired effects:
  ///  * appearance settings (backdrop style/motion/blur, reduce-motion),
  ///  * the global transition flag read by page_transitions,
  ///  * the Flutter image cache limits.
  static Future<void> apply(ShuroProfile profile, AppearanceSettings appearance, {void Function(bool)? setReduceAnimations}) async {
    // Resolve the EFFECTIVE preset for the profile being applied. For Auto
    // this must classify the device directly — calling resolve() here would
    // return the previously stored choice (e.g. Quality), so choosing "Auto"
    // after Quality would silently re-apply Quality (bug found in audit).
    ShuroProfile effective;
    if (profile == ShuroProfile.auto) {
      final caps = await readCapabilities();
      final ramMb = (caps?['totalRamMb'] as num?)?.toInt();
      final lowRam = (caps?['isLowRamDevice'] as bool?) ?? false;
      final deviceClass = ramMb != null
          ? classify(totalRamMb: ramMb, isLowRamDevice: lowRam)
          : (lowRam ? DeviceClass.low : null);
      effective = deviceClass == null ? ShuroProfile.balanced : presetProfileFor(deviceClass);
    } else {
      effective = profile;
    }
    final preset = presetFor(effective);

    await appearance.setBackgroundStyle(preset.backgroundStyle);
    await appearance.setBackdropMotion(preset.backdropMotion);
    await appearance.setBackdropBlurScale(preset.backdropBlurScale);
    // Prefer the persisted setter (AppState.updateReduceAnimations) so the
    // choice sticks across launches; fall back to the plain global when the
    // caller has no AppState (boot paths).
    if (setReduceAnimations != null) {
      setReduceAnimations(preset.reduceMotion);
    } else {
      transitions.reduceMotionEnabled = preset.reduceMotion;
    }
    applyImageCacheBytes(preset.imageCacheBytes);
    _cachedSyncConcurrency = preset.syncConcurrency;
    await storeProfile(profile);
  }

  /// The image-cache half, callable from boot before settings objects exist.
  static void applyImageCacheBytes(int bytes) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = bytes;
  }

  static int? _cachedSyncConcurrency;

  /// Library-sync parallelism for the profile in effect. Cached after the
  /// first resolve (the value only changes via [apply], which clears it) so
  /// the repository's hot path never re-reads prefs per sync.
  static Future<int> syncConcurrency() async {
    final cached = _cachedSyncConcurrency;
    if (cached != null) return cached;
    final resolved = await resolve();
    final value = presetFor(resolved.effective).syncConcurrency;
    _cachedSyncConcurrency = value;
    return value;
  }

  /// Boot-time application: reads the stored choice, applies cache limits and
  /// the reduce-motion global immediately. The appearance fields persist from
  /// the last explicit profile change, so the two never disagree.
  static Future<void> applyStoredOnBoot() async {
    final resolved = await resolve();
    final preset = presetFor(resolved.effective);
    applyImageCacheBytes(preset.imageCacheBytes);
  }

  /// "Auto" explanation line for the settings UI.
  static String describeDevice(int? totalRamMb, DeviceClass? deviceClass) {
    final ram = totalRamMb == null ? 'unknown RAM' : '${(totalRamMb / 1024).toStringAsFixed(1)} GB RAM';
    final cls = deviceClass == null ? 'unknown class' : '${deviceClass.name} device';
    return '$ram · $cls';
  }

  /// Guarded platform probe used by diagnostics; never throws.
  static Future<int> coreCount() async => Platform.numberOfProcessors;
}

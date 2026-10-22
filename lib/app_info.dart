import 'package:package_info_plus/package_info_plus.dart';

/// Version shown in the app (Settings → About, consent, licences).
///
/// This used to be a hardcoded const and drifted (it still said 2.3.0 while
/// 2.4.1 was installed). [resolveAppVersion] overwrites it at boot with the
/// version actually installed, and the literal below is only the fallback for
/// environments without plugin support (tests, web without the plugin).
String kAppVersion = '2.5.1';

/// Reads the running build's version from the platform. Call once at boot
/// (non-fatal: a failure keeps the fallback).
Future<void> resolveAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    kAppVersion = info.version;
  } catch (_) {
    // Keep the compile-time fallback.
  }
}

const int kAppBuild = 1;

// --- Brand identity -------------------------------------------------------
// Shuro's product identity, in one place so every screen that shows a
// tagline or description (Welcome, Settings → About) stays in sync instead
// of each hardcoding its own copy of the same lines.
const String kAppName = 'Shuro';
const String kAppType = 'Premium self-hosted music player';
const String kAppTagline = 'Your music. Your server. Your sound.';
const String kAppTaglineAlt = 'Music, your way.';
const String kAppDescription =
    'A modern, high-quality music player for your personal, self-hosted library — built on Navidrome and OpenSubsonic.';

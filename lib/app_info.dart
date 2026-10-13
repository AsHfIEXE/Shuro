/// Single source of truth for the version shown in the app (Settings →
/// About). Keep in step with `version:` in pubspec.yaml — bump both on
/// every release ("2.0.3+1" in pubspec = [kAppVersion]+[kAppBuild]).
const String kAppVersion = '2.2.0';
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

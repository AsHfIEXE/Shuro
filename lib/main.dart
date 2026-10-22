import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'app_info.dart';
import 'backend/subsonic_api.dart';
import 'screens/splash/splash_screen.dart';
import 'services/artist_artwork_service.dart';
import 'services/device_profile.dart';
import 'services/desktop_lifecycle.dart';
import 'services/download_service.dart';
import 'services/image_disk_cache.dart';
import 'services/playback_prefs.dart';
import 'services/stream_proxy.dart';
import 'state/app_state.dart';
import 'state/appearance_settings.dart';
import 'state/player_controller.dart';
import 'state/spoken_library_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Must run before anything else touches a plugin (JustAudioBackground
  // talks to platform channels during init) — and JustAudioBackground
  // itself must be initialized before any AudioPlayer is created.
  WidgetsFlutterBinding.ensureInitialized();
  // Real installed version for Settings → About (the hardcoded fallback had
  // drifted three releases behind). Non-fatal and unawaited.
  unawaited(resolveAppVersion());
  // Performance profile (brief §3): apply the stored choice's image-cache
  // limits before any artwork decodes. Non-fatal — a missing prefs store
  // must never block boot.
  unawaited(DeviceProfileService.applyStoredOnBoot());

  // Desktop audio is libmpv through Media Kit on both supported desktop
  // platforms. It keeps the existing just_audio controller API while giving
  // Windows and Linux the same decoder and stream/file playback path.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows)) {
    JustAudioMediaKit.title = 'Shuro';
    // Desktop streams are buffered by libmpv, not transcoded by the UI.
    // A larger bounded cache prevents ordinary Wi-Fi jitter from interrupting
    // original-quality files while leaving the server's selected quality alone.
    JustAudioMediaKit.bufferSize = 64 * 1024 * 1024;
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    // Native lifecycle is intentionally independent from the player: failure
    // to get a tray on a particular Linux shell must never prevent playback.
    // Bounded: a tray/DBus call that never answers must not hold up runApp.
    await DesktopLifecycle.instance
        .initialize()
        .timeout(const Duration(seconds: 3), onTimeout: () {});
  }
  debugPrint('[boot] binding ready');

  // Persistent image cache + DoH + loopback proxy are IO-platform machinery;
  // on web the browser owns caching and DNS, and the dart:io surface is a
  // throwing stub — skip all of it there (Chrome testing path).
  if (!kIsWeb) {
    HttpOverrides.global = CachingHttpOverrides();

    // DNS health check BEFORE any request goes out: decides whether the DoH
    // fallback connector engages this session. On a healthy device resolver it
    // answers in milliseconds and the default (TLS-safe) connect path is kept;
    // only a genuinely broken resolver gets the DoH treatment. Time-boxed with
    // an outer guard as well — startup must never stall on it.
    // DNS health check — deliberately NOT awaited before runApp. It only
    // decides whether the DoH fallback engages, and awaiting it put a call
    // with a 6 s ceiling on the path to the first frame (a genuine worst-case
    // stall on a broken resolver). Measurement note: deferring it changed
    // cold start by ~0 ms — the ~3.0 s on the A13 is engine/audio-service
    // host init, not Dart boot — so this is a worst-case guard, not a
    // claimed speed-up. Requests started before the probe finishes take the
    // default TLS-safe path.
    unawaited(
      StreamProxy.checkDeviceDns()
          .timeout(const Duration(seconds: 6))
          .catchError((Object _) {
        // Leave DoH disabled (healthy default); DNS itself is unchanged.
      }),
    );
    debugPrint('[boot] dns check dispatched (not awaited)');

    // Loopback stream proxy: audio streams are rewritten to 127.0.0.1 and
    // forwarded, so playback survives device DNS failures for DDNS/server
    // names.
    unawaited(StreamProxy.start());
  }

  // Deliberately non-fatal. This call is awaited before runApp, and it throws on
  // a platform whose manifest hasn't declared the audio service and
  // media-button receiver (audio_service validates that at runtime). In that
  // state the earlier version of this file left the app on a blank screen: no
  // first frame, no error message, nothing to act on — observed on an Android 9
  // device. Background/lock-screen controls are an enhancement; playback inside
  // the app must not depend on them, so a failure here is logged and the app
  // starts anyway.
  //
  // TIMEOUT: when the app is re-launched while the previous audio service is
  // still alive (tapping the media notification, an emulator recreating the
  // activity), this init can WAIT FOREVER on a service that will never answer
  // the new engine — leaving the native splash window on screen while the old
  // service keeps playing: the reported "music is playing but the screen is
  // blank" freeze. After 8 s we give up on the media session and start the
  // app anyway; in-app playback still works, and a user can always stop the
  // stray service from the notification.
  // The media-session layer (audio_service) exists on Android and iOS only.
  // On Windows/macOS/Linux playback stays in-app and there is no notification
  // service to start, so skip it instead of letting a missing plugin throw.
  final bool hasMediaSession = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  try {
    if (hasMediaSession) {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.shuro.audio.channel',
        androidNotificationChannelName: 'Shuro playback',
        // Shown in Android's notification settings under the channel, where the
        // per-app look of the media notification is also controlled.
        androidNotificationChannelDescription:
            'Now playing information and playback controls.',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidShowNotificationBadge: true,
      ).timeout(const Duration(seconds: 8));
    }
  } on TimeoutException {
    debugPrint(
        'JustAudioBackground.init timed out — starting without system media controls; is an old audio service still running?');
  } catch (error, stack) {
    // Release builds get no logging that a user could act on, but the app still
    // runs: in-app playback, the queue, lyrics and diagnostics are unaffected.
    debugPrint(
        'JustAudioBackground.init failed — continuing without system media controls: $error');
    debugPrint('$stack');
  }
  debugPrint('[boot] audio init done');
  debugPrint('[boot] runApp');
  runApp(const MusicStreamApp());
}

class MusicStreamApp extends StatelessWidget {
  const MusicStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AppState owns the app's single undo stack (roadmap #29); the player
        // controller attaches to the same instance for queue edits.
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(
          create: (context) =>
              PlayerController(undoStack: context.read<AppState>().undoStack),
        ),
        ChangeNotifierProvider(create: (_) => SpokenLibraryState()..restore()),
        // The connected server's feature API (search3, star, scrobble,
        // ratings, playlists…) — attached when a connection goes live, null
        // while offline. See backend/subsonic_api.dart and ServerLink.
        ChangeNotifierProvider(create: (_) => ServerSession()),
        // Artist pictures, resolved once (server metadata first, MusicBrainz
        // fallback) and cached permanently.
        ChangeNotifierProvider(
            create: (_) => ArtistArtworkService()..restore()),
        // Real offline downloads (files on disk, persistent across updates).
        ChangeNotifierProvider(create: (_) => DownloadService()..restore()),
        // Playback settings (fade, replay gain, speed, skip silence).
        ChangeNotifierProvider(create: (_) => PlaybackPrefs()..restore()),
        // View preferences that live outside AppState (see the class doc): the
        // background style for Now Playing / Lyrics, and the immersive-screens
        // toggle. Restored from storage in the background — a failure just keeps
        // the defaults.
        ChangeNotifierProvider(create: (_) => AppearanceSettings()..restore()),
      ],
      // Only the font choice needs a full remount (every text style reads
      // the global `currentFontFamily` at build time — see app_theme.dart)
      // — selecting `fontFamily` here means everything else in AppState
      // changing does NOT tear the app down, only an actual font change.
      // Selector (not Consumer) so this only rebuilds when the font
      // actually changes — other AppState updates (favorites, downloads,
      // settings toggles) don't touch this at all.
      child: Selector<AppState, String>(
        selector: (_, appState) => appState.fontFamily,
        builder: (context, fontFamily, _) {
          return MaterialApp(
            key: ValueKey(fontFamily),
            title: 'Shuro',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(fontFamily: fontFamily),
            // Deliberately no `builder:` here. An earlier version wrapped
            // `child` in Center + ConstrainedBox(maxWidth: 460) to cap
            // width on a wide desktop browser — but that never actually
            // fixed the reported off-center splash logo (it kept showing
            // up on a native APK too, where that wrapper is a no-op), so
            // it was a red herring and has been removed rather than left
            // in as unverified "maybe it helps" code. See
            // screens/splash/splash_screen.dart for the actual fix.
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

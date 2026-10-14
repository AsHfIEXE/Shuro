import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'backend/subsonic_api.dart';
import 'screens/splash/splash_screen.dart';
import 'services/artist_artwork_service.dart';
import 'services/download_service.dart';
import 'services/image_disk_cache.dart';
import 'services/playback_prefs.dart';
import 'services/stream_proxy.dart';
import 'state/app_state.dart';
import 'state/appearance_settings.dart';
import 'state/player_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Must run before anything else touches a plugin (JustAudioBackground
  // talks to platform channels during init) — and JustAudioBackground
  // itself must be initialized before any AudioPlayer is created.
  WidgetsFlutterBinding.ensureInitialized();

  // Persistent image cache: every cover/artist picture fetched once is served
  // from disk on every later launch — the single biggest "library loads asap"
  // win, since covers are most of the bytes. Guarded: any cache-layer failure
  // falls through to plain networking.
  HttpOverrides.global = CachingHttpOverrides();

  // DNS health check BEFORE any request goes out: decides whether the DoH
  // fallback connector engages this session. On a healthy device resolver it
  // answers in milliseconds and the default (TLS-safe) connect path is kept;
  // only a genuinely broken resolver gets the DoH treatment.
  await StreamProxy.checkDeviceDns();

  // Loopback stream proxy: audio streams are rewritten to 127.0.0.1 and
  // forwarded, so playback survives device DNS failures for DDNS/server
  // names.
  unawaited(StreamProxy.start());

  // Deliberately non-fatal. This call is awaited before runApp, and it throws on
  // a platform whose manifest hasn't declared the audio service and
  // media-button receiver (audio_service validates that at runtime). In that
  // state the earlier version of this file left the app on a blank screen: no
  // first frame, no error message, nothing to act on — observed on an Android 9
  // device. Background/lock-screen controls are an enhancement; playback inside
  // the app must not depend on them, so a failure here is logged and the app
  // starts anyway.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.shuro.audio.channel',
      androidNotificationChannelName: 'Shuro playback',
      // Shown in Android's notification settings under the channel, where the
      // per-app look of the media notification is also controlled.
      androidNotificationChannelDescription: 'Now playing information and playback controls.',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidShowNotificationBadge: true,
    );
  } catch (error, stack) {
    // Release builds get no logging that a user could act on, but the app still
    // runs: in-app playback, the queue, lyrics and diagnostics are unaffected.
    debugPrint('JustAudioBackground.init failed — continuing without system media controls: $error');
    debugPrint('$stack');
  }
  runApp(const MusicStreamApp());
}

class MusicStreamApp extends StatelessWidget {
  const MusicStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => PlayerController()),
        // The connected server's feature API (search3, star, scrobble,
        // ratings, playlists…) — attached when a connection goes live, null
        // while offline. See backend/subsonic_api.dart and ServerLink.
        ChangeNotifierProvider(create: (_) => ServerSession()),
        // Artist pictures, resolved once (server metadata first, MusicBrainz
        // fallback) and cached permanently.
        ChangeNotifierProvider(create: (_) => ArtistArtworkService()..restore()),
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

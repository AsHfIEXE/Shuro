import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend/subsonic_api.dart';
import 'models/download_state.dart';
import 'models/server_config.dart';
import 'models/song.dart';
import 'playback/audio_capability.dart';
import 'playback/audio_diagnostics.dart';
import 'playback/event_log.dart';
import 'playback/playback_engine.dart';
import 'services/app_persistence.dart';
import 'services/download_service.dart';
import 'services/local_tag_enrichment.dart';
import 'services/metadata/lastfm_client.dart';
import 'services/playback_prefs.dart';
import 'services/metadata/scrobble_service.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/favorites/favorites_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/library/library_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/consent_screen.dart' show ConsentScreen, kTermsAcceptedKey;
import 'screens/onboarding/server_setup_screen.dart';
import 'screens/search/search_screen.dart';
import 'services/device_profile.dart';
import 'state/app_state.dart';
import 'state/appearance_settings.dart';
import 'state/player_controller.dart';
import 'theme/app_theme.dart';
import 'services/server_link.dart';
import 'services/stream_proxy.dart';
import 'widgets/app_logo.dart';
import 'widgets/shuro_nav.dart';
import 'widgets/mini_player.dart';
import 'widgets/page_transitions.dart';
import 'widgets/state_views.dart';

/// The app-level Last.fm scrobbler.
///
/// Lives here because this file is the app's composition root — the same reason
/// `just_audio`'s background service, the audio-source resolver and the
/// diagnostics resolver are all wired from here. One instance per process: the
/// pending-scrobble queue and the stored session key need a single owner, and
/// Last.fm requires cached scrobbles to be sent in order.
///
/// Inert unless the build supplies Last.fm application credentials *and* the user
/// has granted this app access — see `ScrobbleService.isReady`. The wiring below
/// reports what is played; it never asks the user for a key.
final ScrobbleService sharedScrobbleService = ScrobbleService();

/// Chooses between onboarding and the main shell — and, just as importantly,
/// does **not** flash onboarding at someone who has already finished it.
///
/// The old version returned `WelcomeScreen` for any status that wasn't
/// connected/localOnly. On a relaunch that meant a returning user saw the server
/// picker while `AppState` restored persisted state and reconnected — and for as
/// long as that reconnect attempt ran (its own HTTP timeout is 15 s) — before the
/// shell appeared. With saved servers the app now shows a branded "connecting"
/// screen instead, and if the reconnect genuinely fails it says so and offers a
/// way forward, rather than silently presenting first-run onboarding.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Whether a terminal connection status has been observed at least once
  /// this session. Until restore finishes, the status sits at `disconnected`/
  /// `connecting` — showing Welcome at that moment flashed first-run onboarding
  /// at returning users (the boot-sequence bug). Once any terminal status is
  /// seen, the gate trusts statuses as-is.
  bool _sawTerminalStatus = false;

  /// Whether the app shell has ever been shown. Once it has, background
  /// reconnects (the quiet offline retry loop) must never replace the user's
  /// library with the restoring screen — `connecting`/`unreachable` after
  /// the shell has been up keeps the shell, with the offline state carried
  /// in the session flags instead.
  bool _hasShownShell = false;

  /// Boot diagnostics: logged once per branch change so the next freeze's
  /// logcat alone shows how far startup got ([gate] shell / restoring /
  /// welcome / shell(offline-retry)).
  String? _lastBranch;

  void _mark(String branch) {
    if (_lastBranch == branch) return;
    _lastBranch = branch;
    debugPrint('[gate] $branch');
  }

  /// Terms acceptance: null = still loading from prefs, false = not yet
  /// accepted (first launch), true = accepted. The gate shows the consent
  /// screen whenever it is exactly false.
  bool? _termsAccepted;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _termsAccepted = prefs.getString(kTermsAcceptedKey) == 'true');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Terms gate runs first: a fresh install must accept before anything
    // else loads. While prefs are being read (fast), the normal flow renders
    // underneath for a frame.
    if (_termsAccepted == false) {
      return ConsentScreen(onAccepted: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kTermsAcceptedKey, 'true');
        if (mounted) setState(() => _termsAccepted = true);
      });
    }

    final appState = context.watch<AppState>();
    final status = appState.connectionStatus;
    final terminal = status == ConnectionStatus.connected ||
        status == ConnectionStatus.localOnly ||
        status == ConnectionStatus.unreachable ||
        status == ConnectionStatus.invalidCredentials;
    if (terminal) _sawTerminalStatus = true;

    if (status == ConnectionStatus.connected || status == ConnectionStatus.localOnly) {
      // A connected server is the one moment server features get bound: the
      // feature API joins the provider tree, play reporting is wired, and
      // favourites merge. Cheap and idempotent per server — see ServerLink.
      _hasShownShell = true;
      _mark('shell');
      if (status == ConnectionStatus.connected) {
        scheduleServerLink(context);
      }
      return const AppShell();
    }
    // Background reconnect in flight, or still offline, AFTER the shell has
    // been up once: keep the library visible (cached/offline mode).
    if (_hasShownShell &&
        (status == ConnectionStatus.connecting || status == ConnectionStatus.unreachable)) {
      _mark('shell(offline-retry)');
      return const AppShell();
    }
    // Saved servers + restore still in flight (or failed): restoring screen —
    // never Welcome — until a terminal status has been seen.
    if (appState.servers.isNotEmpty) {
      _mark('restoring');
      return _RestoringScreen(appState: appState);
    }
    _mark('welcome');
    return const WelcomeScreen();
  }
}

/// Shown while a saved server is being reconnected at startup, and if that
/// fails. Dark and branded so startup never looks like a blank or white screen,
/// which is what the platform's own launch window used to show.
class _RestoringScreen extends StatelessWidget {
  final AppState appState;
  const _RestoringScreen({required this.appState});

  @override
  Widget build(BuildContext context) {
    final failed = appState.connectionErrorMessage != null &&
        (appState.connectionStatus == ConnectionStatus.unreachable || appState.connectionStatus == ConnectionStatus.invalidCredentials);
    // The retry target: the ACTIVE server, falling back to the first SAVED
    // one. activeServerId is only assigned on a successful connect — after a
    // failed startup reconnect it is null, and the Try-again button used to
    // read it directly and silently do nothing (the "button doesn't work"
    // report). The saved list is the honest source of what to retry.
    final retryServer = appState.activeServer ?? (appState.servers.isNotEmpty ? appState.servers.first : null);
    final serverName = retryServer?.name ?? 'your server';
    // Raw socket text ("Failed host lookup … errno = 7") is meaningless to a
    // person — translated here into what it actually means and what to do.
    final friendlyError = friendlyConnectionError(appState.connectionErrorMessage);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 84),
                  const SizedBox(height: 26),
                  if (!failed) ...[
                    Text('Connecting to $serverName',
                        textAlign: TextAlign.center,
                        style: headingFont(color: kTextColor, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: kBrandColor)),
                    const SizedBox(height: 16),
                    Text('Reconnecting to your saved library',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
                  ] else ...[
                    Text("Couldn't reach $serverName",
                        textAlign: TextAlign.center,
                        style: headingFont(color: kTextColor, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(friendlyError,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13, height: 1.5)),
                    if (appState.connectionErrorMessage != null && appState.connectionErrorMessage != friendlyError) ...[
                      const SizedBox(height: 8),
                      Text(sanitizeAuthParams(appState.connectionErrorMessage!),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white24, fontSize: 10, height: 1.4)),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final id = retryServer?.id;
                          if (id != null) unawaited(appState.switchServer(id));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text('Try again', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(drillDownRoute(const ServerSetupScreen())),
                      child: Text('Choose another server',
                          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: () => context.read<AppState>().continueWithoutServer(),
                      child: Text('Continue with local files only',
                          style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-nav shell: Home / Library / Search / Discover / Favorites —
/// Discover earns its slot because it's backed by real library-based
/// recommendations (ShuroPulse), not added just to mirror Spotify. Settings
/// lives behind the profile avatar on Home rather than taking a nav slot of
/// its own, and Downloads is reachable from Home/Library.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {

  /// Quiet background reconnect: while the session is offline (server was
  /// down at startup or dropped mid-session) the shell keeps retrying every
  /// 25 s. Without this, a user who started their server AFTER the app did
  /// sat on a dead session forever — nothing ever re-connected. The retry
  /// never tears down the UI (AuthGate keeps the shell while
  /// connecting/unreachable once shown) and stops trying the moment the
  /// session is healthy again.
  Timer? _reconnectTimer;
  bool _reconnecting = false;

  void _maybeReconnect() {
    final appState = _boundAppState;
    if (appState == null || _reconnecting) return;
    final offline = appState.libraryOffline || appState.connectionStatus == ConnectionStatus.unreachable;
    if (!offline) return;
    final id = appState.activeServerId ?? (appState.servers.isNotEmpty ? appState.servers.first.id : null);
    if (id == null) return;
    _reconnecting = true;
    appState.switchServer(id).whenComplete(() => _reconnecting = false);
  }

  int _tabIndex = 0;
  AppState? _boundAppState;
  PlayerController? _boundPlayer;
  String? _lastRecordedSongId;

  /// Tabs materialize on first visit (brief §2B): the shell used to build all
  /// five screens — with their library listeners and lists — before the user
  /// had seen any of them. Visited tabs stay alive in the IndexedStack (scroll
  /// state preserved, exactly as before); unvisited ones cost a const
  /// SizedBox until first opened.
  final Set<int> _visitedTabs = {0};

  static Widget _tabAt(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const LibraryScreen();
      case 2:
        return const SearchScreen();
      case 3:
        return const DiscoverScreen();
      default:
        return const FavoritesScreen();
    }
  }

  List<Widget> get _tabChildren => List<Widget>.generate(
        5,
        (i) => _visitedTabs.contains(i) ? _tabAt(i) : const SizedBox.shrink(),
      );

  void _selectTab(int index) {
    setState(() {
      _tabIndex = index;
      _visitedTabs.add(index);
    });
  }

  @override
  void initState() {
    super.initState();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 25), (_) => _maybeReconnect());
    WidgetsBinding.instance.addObserver(this);
    // Performance profile, appearance half: applied once providers exist so a
    // stored Performance choice actually stops painting the heavy backdrop
    // (before this, only the image-cache limit was applied at boot).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appearance = context.read<AppearanceSettings>();
      final appState = context.read<AppState>();
      unawaited(DeviceProfileService.applyStoredPresetOnBoot(
        appearance,
        setReduceAnimations: appState.updateReduceAnimations,
      ));
    });
    // Wire Settings → Behavior → Autoplay into the player, give it a real
    // (if simple) source of "what to play next" once the queue runs out,
    // and feed every played song into AppState's listening history so
    // ShuroPulse has something to work with.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final appState = context.read<AppState>();
      final player = context.read<PlayerController>();
      _boundAppState = appState;
      _boundPlayer = player;
      player.autoplay = appState.autoplay;

      // One-time migration: mobile data used to default to "High (320 kbps)".
      // The owner wants the original file on every connection unless they
      // change it themselves after this — so flip the old default once, set a
      // flag, and never touch the setting again (later user choices stick).
      try {
        final persistence = await AppPersistence.load();
        if (persistence.getBool('mobile_quality_original_migration_v1') != true) {
          if (appState.mobileQuality == StreamingQuality.high) {
            appState.updateMobileQuality(StreamingQuality.original);
          }
          await persistence.setBool('mobile_quality_original_migration_v1', true);
        }
      } catch (_) {
        // No persistence on this platform: defaults still apply in memory.
      }

      // Local files imported before the tag reader existed got file names for
      // titles and "Local file" for artists — enrich them once at startup so
      // genres/artists/lyrics lookups work for the whole library.
      try {
        await LocalTagEnrichment.enrich(appState);
      } catch (_) {/* enrichment is best-effort */}
      player.suggestionProvider = (song) => appState.allSongs.where((s) => s.artistId == song.artistId && s.id != song.id).toList();
      // The one place PlayerController learns how to actually play a
      // song — a downloaded file, a local file path, or a connected backend's
      // stream URL — without ever knowing AppState or a repository exists.
      // Downloaded files win: offline playback straight from disk.
      final downloads = context.read<DownloadService>();
      player.audioSourceResolver = (song) {
        final local = downloads.locate(song.id);
        if (local != null) return local;
        // Remote streams go through the loopback proxy: its own resolution
        // has a DNS-over-HTTPS fallback, so device DNS failures for DDNS
        // names cannot break playback.
        final remote = appState.audioSourceFor(song);
        if (remote == null) return null;
        return StreamProxy.wrap(remote);
      };

      // Settings → Playback: fade between songs, replay gain, speed, skip
      // silence. Pushed to the player on change so effects are immediate;
      // replay gain resolves the dB from the server's own tags (memoised per
      // song id, fire-and-forget).
      final playbackPrefs = context.read<PlaybackPrefs>();
      final gainMemo = <String, double?>{};
      void pushPlaybackSettings() {
        player.crossfadeSeconds = playbackPrefs.crossfadeSeconds;
        player.replayGainEnabled = playbackPrefs.replayGain;
        player.playbackSpeed = playbackPrefs.playbackSpeed;
        player.skipSilence = playbackPrefs.skipSilence;
        unawaited(player.applyPlaybackTweaksNow());
      }

      pushPlaybackSettings();
      playbackPrefs.addListener(pushPlaybackSettings);
      player.replayGainResolver = (song) async {
        if (gainMemo.containsKey(song.id)) return gainMemo[song.id];
        final api = context.read<ServerSession>().api;
        if (api == null) return null;
        try {
          final info = await api.getSong(song.id);
          final db = ((info?['replayGain'] as Map<String, dynamic>?)?['trackGain'] as num?)?.toDouble();
          gainMemo[song.id] = db;
          return db;
        } catch (_) {
          return null;
        }
      };
      player.metadataResolver = appState.nowPlayingMetadataFor;

      // §3.1 / §6 of the playback plan: the source policy the request is built
      // from, and the resolver that turns everything the app knows into the
      // diagnostics model the Audio Information panel renders.
      //
      // The policy is what makes "Original" auditable rather than aspirational:
      // diagnostics re-check the URL the app actually produced against it
      // (verifyStreamUrl), so a request that quietly carried a bitrate cap is
      // visible instead of silent.
      player.setSourcePolicy(SourcePolicy(quality: appState.effectiveStreamingQuality));
      player.diagnosticsResolver = (song, policy, processing) => AudioDiagnostics.forSong(
            song: song,
            policy: policy,
            processing: processing,
            requestCheck: verifyStreamUrl(appState.audioSourceFor(song), policy),
            capability: sharedAudioCapabilityMonitor.reportOrUnknown().toDiagnostics(),
            route: sharedAudioCapabilityMonitor.reportOrUnknown().toRouteDiagnostics(),
          );

      // One capability read at startup, so the panel has an answer without ever
      // querying from a widget build() or a position listener (§5.1 rule 3).
      // Where the platform can't answer, this resolves to `unknown` and the UI
      // says "not reported" — diagnostics never block playback (§5.1 rule 4).
      unawaited(sharedAudioCapabilityMonitor.refresh());

      // Debug-only: print what the platform actually answered, once, so a device
      // report (the plan's Phase 0 artifact) can be captured from `adb logcat`
      // without the UI being driven by hand. Never runs in a release build, and
      // carries no credentials or URLs — see describeDiagnostics' contract.
      if (kDebugMode) {
        unawaited(sharedAudioCapabilityMonitor.refresh().then((report) {
          debugPrint(
            '[capability] route=${report.routeKind.name} label=${report.routeLabel ?? '-'} '
            'direct=${report.directPlayback.name} mode=${report.directPlaybackMode.name} '
            'source=${report.source} reason=${report.reason ?? '-'}',
          );
        }));
      }

      // Native route changes (a headset or DAC plugged in) drop the cached
      // answer instead of leaving it stale until the next resume (§5.1 rule 2).
      // Where there is no native half, the callback simply never fires.
      attachNativeRouteListener();
      appState.addListener(_syncAutoplay);
      player.addListener(_recordListeningHistory);
      player.addListener(_showPlaybackErrors);
      player.addListener(_trackScrobbles);

      // Last.fm: restore the stored session key and any scrobbles a previous run
      // couldn't deliver, then try to deliver them. All of it is inert unless an
      // application key was configured at build time AND the user has authorized
      // this app — see ScrobbleService.
      try {
        final scrobblePersistence = await AppPersistence.load();
        await sharedScrobbleService.restore(scrobblePersistence);
        unawaited(sharedScrobbleService.flushPending());
      } catch (_) {
        // Storage unavailable on this platform: scrobbling stays off, playback
        // is unaffected.
      }

      // Settings → Behavior → "Remember queue"/"Resume playback": reload
      // whatever queue/position was saved when the app was last
      // backgrounded (see _saveQueueState below). Best-effort — if
      // AppState's own persistence load or a saved server's reconnect is
      // still in flight when this runs, there's nothing to restore yet
      // and the app just starts empty, same as it always has.
      final saved = appState.takeSavedQueue();
      if (saved != null) {
        await player.restoreQueue(saved.queue, saved.index, saved.position);
      }
    });
  }

  /// Settings → Behavior → "Remember queue"/"Resume playback" made real:
  /// snapshots the current queue/position into AppState's persistence
  /// whenever the app is about to stop being visible, so [AppState
  /// .takeSavedQueue] has something to hand back on the next launch.
  /// AppState itself decides whether either toggle is actually on —
  /// this just reports the current playback state unconditionally.
  @override
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // Brief §2B: on Android's onTrimMemory the caches must yield before the
    // OS kills the app — playback itself must not be touched. Dropping the
    // image cache costs a re-decode of visible art, nothing more.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    PlaybackEventLog.instance.add('memory.pressure', {'cacheCleared': true});
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The output route may have changed while the app was backgrounded (a
      // headset or car kit connected, a USB adapter removed). The cached
      // capability answer is stale, so drop it and read again (§5.1 rule 2).
      unawaited(sharedAudioCapabilityMonitor.recheck());
      return;
    }
    if (state != AppLifecycleState.paused && state != AppLifecycleState.detached) return;
    final appState = _boundAppState;
    final player = _boundPlayer;
    if (appState == null || player == null) return;
    appState.persistQueueState(player.queue, player.queueIndex, player.position);
  }

  void _syncAutoplay() {
    final appState = _boundAppState;
    if (appState == null || !mounted) return;
    final player = context.read<PlayerController>();
    player.autoplay = appState.autoplay;
    // Settings → Wi-Fi/Mobile data quality, resolved against the connection the
    // device is actually on — the same value the stream URL is built from, so
    // the diagnostics panel reports against the policy that really applied.
    player.setSourcePolicy(SourcePolicy(quality: appState.effectiveStreamingQuality));
  }

  void _recordListeningHistory() {
    final player = _boundPlayer;
    final appState = _boundAppState;
    if (player == null || appState == null) return;
    final song = player.currentSong;
    if (song == null || song.id == _lastRecordedSongId) return;
    _lastRecordedSongId = song.id;
    appState.recordPlay(song.id);
  }

  Song? _scrobblingSong;
  DateTime? _scrobblingStartedAt;
  Duration _scrobblingLastPosition = Duration.zero;

  /// Feeds Last.fm: a now-playing ping when a track starts, and a scrobble for
  /// the outgoing track when it had been played long enough to count.
  ///
  /// "Played" is measured from the engine's own position, sampled on this
  /// listener's ~1 Hz notifications — which is all the documented
  /// half-or-four-minutes rule needs, and deliberately not a per-frame hook
  /// (§8's "don't do work in position listeners").
  void _trackScrobbles() {
    final player = _boundPlayer;
    final appState = _boundAppState;
    if (player == null || appState == null) return;
    if (!sharedScrobbleService.isReady && !sharedScrobbleService.needsAuthorization) return;

    final song = player.currentSong;
    if (song == null) return;

    if (song.id != _scrobblingSong?.id) {
      final previous = _scrobblingSong;
      final startedAt = _scrobblingStartedAt;
      if (previous != null && startedAt != null) {
        // A track that ran out because the user skipped early is simply not
        // scrobbled — the rule decides, not the skip.
        if (ScrobbleService.shouldScrobble(trackDuration: previous.duration, played: _scrobblingLastPosition)) {
          unawaited(sharedScrobbleService.submit(ScrobbleEntry(
            artist: previous.artist,
            track: previous.title,
            startedAt: startedAt,
            album: appState.albumById(previous.albumId)?.title,
            albumArtist: appState.albumById(previous.albumId)?.artist,
            duration: previous.duration,
          )));
        }
      }

      _scrobblingSong = song;
      _scrobblingStartedAt = DateTime.now().toUtc();
      _scrobblingLastPosition = Duration.zero;
      unawaited(sharedScrobbleService.nowPlaying(ScrobbleEntry(
        artist: song.artist,
        track: song.title,
        startedAt: _scrobblingStartedAt!,
        album: appState.albumById(song.albumId)?.title,
        albumArtist: appState.albumById(song.albumId)?.artist,
        duration: song.duration,
      )));
      return;
    }

    final position = player.position;
    if (position > _scrobblingLastPosition) _scrobblingLastPosition = position;
  }

  /// Surfaces [PlayerController.lastPlaybackError] as a snackbar — the
  /// graceful-failure path for a song with no real audio behind it (no
  /// server connected, a demo/mock entry, a dropped connection, …) instead
  /// of the app silently doing nothing or crashing.
  void _showPlaybackErrors() {
    final player = _boundPlayer;
    final error = player?.lastPlaybackError;
    if (error == null || !mounted) return;
    player!.clearPlaybackError();
    showErrorSnackBar(context, error);
    // A play that failed with no source while the session is offline is
    // usually "the server just came back but nothing retried yet" — try to
    // reconnect right now instead of making the user wait for the timer.
    _maybeReconnect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _boundAppState?.removeListener(_syncAutoplay);
    _boundPlayer?.removeListener(_recordListeningHistory);
    _boundPlayer?.removeListener(_showPlaybackErrors);
    _boundPlayer?.removeListener(_trackScrobbles);
    super.dispose();
  }

  /// Above this width the shell uses a navigation rail instead of a bottom bar,
  /// and the content keeps its own scroll (nothing is lost vertically). 1024 is
  /// the smallest common tablet-landscape / TV width, so one number covers
  /// tablets, desktop windows and Android TV.
  static const double kWideShellBreakpoint = 1024;

  @override
  Widget build(BuildContext context) {
    final useRail = MediaQuery.of(context).size.width >= kWideShellBreakpoint;

    // Wide layout: a rail down the side, content to the right, mini player at the
    // bottom of the content column. This is what makes a 1920×1080 window (or a
    // TV) look like an app rather than a stretched phone — and it removes the
    // bottom bar's fixed height from the vertical budget.
    if (useRail) {
      return Scaffold(
        backgroundColor: kSurfaceColor,
        body: Row(
          children: [
            ShuroRail(
              currentIndex: _tabIndex,
              onTap: _selectTab,
            ),
            const VerticalDivider(width: 1, color: kDividerColor),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: IndexedStack(index: _tabIndex, children: _tabChildren)),
                  const MiniPlayer(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: IndexedStack(index: _tabIndex, children: _tabChildren),
      bottomNavigationBar: ShuroNavBar(
        currentIndex: _tabIndex,
        onTap: _selectTab,
        header: const MiniPlayer(),
      ),
    );
  }
}

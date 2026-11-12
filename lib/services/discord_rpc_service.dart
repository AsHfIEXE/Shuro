import 'dart:async';
import 'dart:io' show Platform;

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/foundation.dart';

import 'app_persistence.dart';
import '../state/player_controller.dart';

/// Desktop Discord Rich Presence for Shuro.
///
/// Subscribes to [PlayerController]'s notifications and re-pushes only when
/// the signature changes — Discord renders the progress bar client-side from
/// the timestamps, so no per-second traffic is needed. The controller never
/// knows this exists (same decoupling as the resolvers wired in app.dart);
/// the one position-only event, a seek, arrives through [onSeek] via the
/// controller's `onUserSeeked` callback.
///
/// Lifecycle: [startFor] is called once from app.dart's post-frame wiring;
/// [setEnabled] (Settings → Integrations → Discord presence) starts/stops it
/// live. Everything is gated statically, so Android, iOS and web pay
/// nothing: [supported] is false there and the settings row reads
/// "Desktop only".
class DiscordRpcService {
  DiscordRpcService._();

  /// AppPersistence key for the Settings toggle. A missing key means enabled
  /// (default ON); the service still stays off until a real Application ID
  /// is compiled in below.
  static const String kEnabledKey = 'discord_rpc_enabled';

  /// Application ID of the "Shuro" application on
  /// https://discord.com/developers/applications. Rich Presence art assets
  /// with the keys `shuro_logo`, `play_icon`, `pause_icon` can still be
  /// uploaded there (optional — album art is sent as a URL and works without
  /// any portal assets; until they exist the small play/pause glyph and the
  /// logo fallback simply don't render).
  static const String _clientId = '1570562227600367746';

  static bool get _configured =>
      _clientId.isNotEmpty && !_clientId.contains('YOUR_');

  /// Discord's IPC pipe/socket only exists on desktop. The package itself
  /// also supports macOS, but Shuro only ships Windows/Linux.
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// "Listen along" button target — wired from app.dart to the active
  /// Navidrome server's web UI. Null (local-only session) → that button is
  /// omitted and only the project button shows.
  static Uri? Function()? listenUrlResolver;

  static const String _projectUrl = 'https://github.com/AsHfIEXE/Shuro';

  // ---- static registry: Settings needs live access without Provider ----

  static DiscordRpcService? _active;
  static PlayerController? _lastPlayer;

  /// Reactive mirror of the persisted toggle (default ON when never set).
  /// Settings renders its row from this, so a tap there rebuilds without
  /// the settings screen exposing any of its own state.
  static final ValueNotifier<bool> _toggle = ValueNotifier<bool>(true);

  static bool get toggleOn => _toggle.value;

  /// Listen-side view for Settings.
  static ValueListenable<bool> get toggle => _toggle;

  /// The running instance, or null. app.dart's seek listener reads this so
  /// the Settings toggle can start presence live without re-wiring.
  static DiscordRpcService? get active => _active;

  /// Called from app.dart with the persisted value (null = never set).
  static void initFromPersistence(bool? persisted) {
    _toggle.value = persisted ?? true;
  }

  /// Settings toggle: persists the choice and starts/stops presence live.
  static Future<void> setEnabled(bool on) async {
    _toggle.value = on;
    try {
      final persistence = await AppPersistence.load();
      await persistence.setBool(kEnabledKey, on);
    } catch (_) {
      // No persistence on this platform: the in-memory value rules this run.
    }
    if (!on) {
      await _active?.stop();
    } else {
      startFor(_lastPlayer);
    }
  }

  /// Boots the service for [player] unless it's off, unsupported,
  /// unconfigured or already running. Safe to call repeatedly.
  static void startFor(PlayerController? player) {
    if (player == null || !supported || !toggleOn || !_configured) return;
    if (_active != null) return;
    _lastPlayer = player;
    _active = DiscordRpcService._().._start(player);
  }

  /// App-shell disposal: clears Discord's presence so Shuro doesn't linger
  /// on the user's profile after the app closes.
  static Future<void> shutdownActive() =>
      _active?.stop() ?? Future<void>.value();

  // ---- instance ----

  /// Nullable on purpose: a single [DiscordRPC] instance can only ever be
  /// initialized once (the package throws StateError on a second
  /// initialize), and a pipe that died mid-session leaves it half-dead. So
  /// every (re)connect builds a fresh instance and disposes the old one.
  DiscordRPC? _discord;
  PlayerController? _player;
  Timer? _heartbeat;
  bool _connected = false;
  bool _running = false;
  String? _lastSignature;

  void _start(PlayerController player) {
    if (_running) return;
    _running = true;
    _player = player;
    player.addListener(_push);
    // Heartbeat doubles as the reconnect path: if Discord launches after
    // Shuro did (or quit and came back), the next tick within 30 s picks the
    // connection up and re-pushes.
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_connected) {
        unawaited(_connect());
        return;
      }
      _push();
    });
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _connected) return;
    final old = _discord;
    _discord = null;
    _connected = false;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {/* already dead — that's why we're reconnecting */}
    }
    final rpc = DiscordRPC();
    try {
      await rpc.initialize(_clientId);
      _discord = rpc;
      _connected = true;
      _lastSignature = null; // force a fresh push on the next tick
      _push();
    } on DiscordNotRunningException {
      // Discord is closed: fine, keep playing without it.
      _connected = false;
    } catch (_) {
      // Any other handshake failure: stay quiet, retry on the heartbeat.
      _connected = false;
    }
  }

  void _push() {
    if (!_connected) return;
    final player = _player;
    if (player == null) return;
    final song = player.currentSong;
    if (song == null) {
      _send(null, _idleSignature);
      return;
    }
    // Signature covers everything Discord renders. Position is deliberately
    // NOT in it: the bar advances client-side from the timestamps between
    // pushes, and seeks arrive through [onSeek].
    final sig =
        '${song.id}|${player.isPlaying}|${player.queueIndex}|${player.queue.length}';
    if (sig == _lastSignature) return;

    final meta = player.metadataResolver?.call(song);
    final now = DateTime.now();
    final dur = player.duration;
    var pos = player.position;
    if (pos < Duration.zero) pos = Duration.zero;
    if (dur > Duration.zero && pos > dur) pos = dur;
    final queueLength = player.queue.length;
    final index = player.queueIndex < 0 ? 0 : player.queueIndex;

    _send(
      DiscordPresence(
        type: DiscordActivityType.listening, // "Listening to Shuro"
        details: song.title,
        state: song.artist,
        largeAsset: (meta?.artUri != null)
            ? DiscordAsset.fromUrl(meta!.artUri!.toString(),
                text: meta.albumTitle == null
                    ? song.artist
                    : '${meta.albumTitle} · ${song.artist}')
            : DiscordAsset.fromKey('shuro_logo',
                text: meta?.albumTitle ?? 'Shuro'),
        smallAsset: DiscordAsset.fromKey(
          player.isPlaying ? 'play_icon' : 'pause_icon',
          text: player.isPlaying ? 'Playing' : 'Paused',
        ),
        timestamps: (player.isPlaying && dur > Duration.zero)
            ? DiscordTimestamps.range(now.subtract(pos), now.add(dur - pos))
            : null,
        // Only meaningful for more than one song; the id scopes the party to
        // this queue so two machines don't share a badge.
        party: queueLength > 1
            ? DiscordParty(
                id: 'shuro-queue-${song.id}',
                currentSize: index + 1,
                maxSize: queueLength,
              )
            : null,
        buttons: _buttons,
      ),
      sig,
    );
  }

  /// Both widget slots Discord offers. Buttons always need http(s) targets:
  /// "Listen along" opens the active server's web player (same library, no
  /// extra hosting needed), "Get Shuro" links the project page.
  List<DiscordButton> get _buttons {
    final buttons = <DiscordButton>[];
    final listen = listenUrlResolver?.call();
    if (listen != null &&
        (listen.scheme == 'http' || listen.scheme == 'https')) {
      buttons.add(DiscordButton(label: 'Listen along', url: listen.toString()));
    }
    buttons.add(const DiscordButton(label: 'Get Shuro', url: _projectUrl));
    return buttons;
  }

  void _send(DiscordPresence? presence, String signature) {
    _lastSignature = signature;
    final rpc = _discord;
    if (rpc == null) return;
    unawaited(
      (presence == null ? rpc.clearPresence() : rpc.setPresence(presence))
          .catchError((Object _) => _onConnectionLost()),
    );
  }

  /// A failed push means the pipe died (Discord quit mid-session). Drop the
  /// instance; the heartbeat reconnects with a fresh one and re-pushes.
  void _onConnectionLost() {
    if (!_running || !_connected) return;
    _connected = false;
    final rpc = _discord;
    _discord = null;
    if (rpc != null) {
      unawaited(rpc.dispose().catchError((Object _) {}));
    }
  }

  /// Fired from app.dart's seek listener. A scrub moves the progress bar but
  /// changes nothing in the signature, so it needs this explicit nudge.
  void onSeek() {
    _lastSignature = null;
    _push();
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _player?.removeListener(_push);
    _player = null;
    _running = false;
    _connected = false;
    if (identical(_active, this)) _active = null;
    final rpc = _discord;
    _discord = null;
    _lastSignature = null;
    if (rpc != null) {
      try {
        await rpc.clearPresence();
      } catch (_) {/* best-effort */}
      try {
        await rpc.dispose();
      } catch (_) {/* best-effort */}
    }
  }

  static const String _idleSignature = '__idle__';
}

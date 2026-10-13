import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/subsonic_api.dart';
import '../models/server_config.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import 'artist_artwork_service.dart';

/// One-time binding between the app and the connected server's feature API.
///
/// Runs whenever the AuthGate observes a *connected* server: attaches a
/// [SubsonicApi] to the [ServerSession] provider (which every server-feature
/// surface reads), wires the player's play-reporting callbacks, and merges the
/// server's starred songs with the device's favourites.
///
/// Everything here is fire-and-forget by design: server features must enrich
/// the app, never block startup or playback. A merge that fails on a flaky LAN
/// just means this device stays as it is until the next connect.
/// Called from AuthGate's build: defers the bind to after the current frame,
/// so providers are never mutated mid-build.
void scheduleServerLink(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) ServerLink.bind(context);
  });
}

class ServerLink {
  static String? _boundKey;

  static Future<void> bind(BuildContext context) async {
    final appState = context.read<AppState>();
    if (appState.connectionStatus != ConnectionStatus.connected || appState.activeServerId == null) {
      return;
    }
    final server = appState.servers.firstWhere(
      (s) => s.id == appState.activeServerId,
      orElse: () => appState.servers.first,
    );
    // Already bound to this exact server (rebuilds of AuthGate must not
    // re-merge favourites or re-create clients on every frame).
    final key = '${server.id}|${server.url}|${server.username}';
    if (_boundKey == key) return;
    _boundKey = key;

    final session = context.read<ServerSession>();
    final api = SubsonicApi(baseUrl: server.url, username: server.username, passphrase: server.password);
    session.attach(api);

    // Artist pictures resolve against this server's metadata — tell the
    // service which server (and user) is live.
    context.read<ArtistArtworkService>().updateSession(api, server.username);

    // Play reporting: "now playing" on track start, a counted play at the
    // listen threshold (past half the track or four minutes). Both
    // fire-and-forget — a failed report is silent, playback is untouched.
    final player = context.read<PlayerController>();
    player.onTrackStarted = (song) {
      api.scrobble(song.id, submission: false).catchError((_) {});
    };
    player.onListenThresholdReached = (song) {
      api.scrobble(song.id, submission: true).catchError((_) {});
    };

    // Favourites converge both ways: server stars appear on this device,
    // device-only hearts are pushed to the server.
    try {
      final starred = await api.starredSongIds();
      if (!identical(session.api, api)) return; // server switched mid-merge
      for (final id in starred) {
        if (!appState.favoriteSongIds.contains(id)) appState.toggleFavoriteSong(id);
      }
      for (final id in appState.favoriteSongIds.toList()) {
        if (!starred.contains(id)) api.star(id).catchError((_) {});
      }
    } catch (_) {
      // Offline blip mid-merge — keep the local state as it is.
    }
  }
}

/// Favourites that stay in step with the server. Every UI entry point calls
/// this instead of [AppState.toggleFavoriteSong] directly: the local toggle is
/// immediate (the UI must feel instant), then the matching star/unstar goes to
/// the server in the background. No server connected = local-only, exactly as
/// before.
class Favorites {
  static void toggle(BuildContext context, String songId) {
    final appState = context.read<AppState>();
    final willBeFavorite = !appState.isFavoriteSong(songId);
    appState.toggleFavoriteSong(songId);

    final api = context.read<ServerSession>().api;
    if (api == null) return;
    final request = willBeFavorite ? api.star(songId) : api.unstar(songId);
    request.catchError((_) {});
  }
}

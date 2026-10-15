import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/subsonic_api.dart';
import '../models/server_config.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import 'artist_artwork_service.dart';
import 'multi_server.dart';

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
    if (appState.connectionStatus != ConnectionStatus.connected || appState.servers.isEmpty) {
      return;
    }
    final active = appState.servers.where((s) => s.id == appState.activeServerId).firstOrNull ?? appState.servers.first;

    // One client per SAVED server: the library may combine several servers
    // (enabledServerIds), and favourites/scrobbles must reach each item's OWN
    // server no matter which ones are enabled for browsing.
    final apis = <String, SubsonicApi>{
      for (final server in appState.servers)
        server.id: SubsonicApi(baseUrl: server.url, username: server.username, passphrase: server.password),
    };

    // Already bound to this exact set (rebuilds of AuthGate must not re-merge
    // favourites or re-create clients on every frame).
    final key = '${appState.servers.map((s) => '${s.id}|${s.url}|${s.username}').join('~')}|${appState.activeServerId}';
    if (_boundKey == key) return;
    _boundKey = key;

    final session = context.read<ServerSession>();
    final api = apis[active.id]!;
    session.attachAll(apis, primaryId: active.id);

    // Artist pictures resolve against the active server's metadata — tell the
    // service which server (and user) is live.
    context.read<ArtistArtworkService>().updateSession(api, active.username);

    // Play reporting: "now playing" on track start, a counted play at the
    // listen threshold. Routed to the song's OWN server — the remote id goes
    // out in that server's namespace (a qualified id would 404).
    final player = context.read<PlayerController>();
    player.onTrackStarted = (song) {
      final owner = session.apiForId(song.id);
      owner?.scrobble(MultiServerLibrary.remoteIdOf(song.id), submission: false).catchError((_) {});
    };
    player.onListenThresholdReached = (song) {
      final owner = session.apiForId(song.id);
      owner?.scrobble(MultiServerLibrary.remoteIdOf(song.id), submission: true).catchError((_) {});
    };

    // Favourites converge both ways, per server: every server's stars appear
    // on this device (qualified with the server's namespace); device-only
    // hearts are pushed back to the server that owns the song.
    try {
      final starredByServer = <String, Set<String>>{};
      await Future.wait(apis.entries.map((entry) async {
        try {
          starredByServer[entry.key] = await entry.value.starredSongIds();
        } catch (_) {
          // That server is down — its stars are simply unknown right now.
        }
      }));
      for (final entry in starredByServer.entries) {
        for (final remoteId in entry.value) {
          final qualified = MultiServerLibrary.qualify(entry.key, remoteId);
          if (!appState.favoriteSongIds.contains(qualified)) appState.toggleFavoriteSong(qualified);
        }
      }
      for (final id in appState.favoriteSongIds.toList()) {
        final serverId = MultiServerLibrary.serverIdOf(id);
        if (serverId == null) continue; // legacy un-migrated id — next bind covers it
        final target = apis[serverId];
        if (target == null) continue;
        if (starredByServer[serverId]?.contains(MultiServerLibrary.remoteIdOf(id)) ?? false) continue;
        target.star(MultiServerLibrary.remoteIdOf(id)).catchError((_) {});
      }
    } catch (_) {
      // Offline blip mid-merge — keep the local state as it is.
    }
  }
}

/// Translates raw socket/Dart connection errors into one plain sentence, plus
/// keeps the technical detail available separately (the restoring screen shows
/// the friendly line up top and the raw text small below).
String friendlyConnectionError(String? raw) {
  final error = sanitizeAuthParams(raw ?? '');
  final lower = error.toLowerCase();
  if (lower.contains('failed host lookup') || lower.contains('no address associated') || lower.contains('unknownhost')) {
    return 'Your device could not look up that server name (DNS). DDNS names like yours often fail here while working in a browser: set this device DNS to 1.1.1.1 or 8.8.8.8, or use the local address (http://192.168.x.x:4533) while at home. — and note that some DDNS names only resolve inside your own network.';
  }
  if (lower.contains('connection refused')) {
    return 'The server refused the connection — is it running, and is the port correct?';
  }
  if (lower.contains('cleartext') || lower.contains('not permitted by network security policy')) {
    return 'This server uses plain HTTP, which this build blocks. Use an HTTPS address.';
  }
  if (lower.contains('connection reset') || lower.contains('connection abort')) {
    return 'The connection was cut off mid-request — check your network and try again.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The server took too long to respond — it may be offline or asleep.';
  }
  if (lower.contains('handshake') || lower.contains('certificate') || lower.contains('ssl') || lower.contains('tls')) {
    return 'The secure connection to the server failed (certificate problem).';
  }
  if (lower.contains('unreachable')) {
    return 'This network has no route to the server — are you connected?';
  }
  return error.isEmpty ? 'The server did not respond.' : error;
}

/// Strips Subsonic auth parameters (`u=`, `t=`, `s=` and friends) from any
/// error text before it reaches the screen or the log — a raw URL in an
/// exception leaks the user's credentials (plan §4.1).
String sanitizeAuthParams(String text) => text.replaceAllMapped(
      RegExp('([?&])(?:u|t|s|v|c|f)=[^&"\\s]*'),
      (m) => '${m.group(1)}<redacted>',
    );

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

    // Route to the song's OWN server (multi-server libraries mix servers in
    // one queue); the remote id goes out in that server's namespace.
    final api = context.read<ServerSession>().apiForId(songId);
    if (api == null) return;
    final remoteId = MultiServerLibrary.remoteIdOf(songId);
    final request = willBeFavorite ? api.star(remoteId) : api.unstar(remoteId);
    request.catchError((_) {});
  }
}

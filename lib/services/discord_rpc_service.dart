import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpException, Platform;
import 'dart:math' as math;

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImage;

import 'app_persistence.dart';
import '../models/song.dart';
import '../playback/event_log.dart';
import '../screens/settings/settings_prefs.dart';
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
  static const String _caaFront = 'https://coverartarchive.org/release-group';
  // MusicBrainz requires a descriptive UA on anonymous calls.
  static const String _userAgent =
      'Shuro/2.6.2 ( https://github.com/AsHfIEXE/Shuro )';

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

  /// song id -> publicly-fetchable cover URL (null = none found, use the
  /// shuro_logo key). Absent = not resolved yet.
  final Map<String, String?> _artCache = <String, String?>{};

  /// Drops every cached artwork decision so the next presence re-resolves
  /// - called when the public server URL setting changes, so songs that
  /// were already resolved (or definitively missed) get another chance
  /// against the new source.
  void clearArtCache() {
    _artCache.clear();
  }

  // ---- smart artwork fetcher ----
  // MusicBrainz allows ~1 request per second sustained; burst past that and
  // it answers 503. A skip-heavy session could easily do worse, so every
  // lookup goes through one serialized queue that:
  //   • spaces requests >= 1.2 s apart,
  //   • backs off exponentially (30 s doubling to 5 min) when MusicBrainz
  //     rate-limits or the network errors, retrying the same pair after,
  //   • gives up on a pair only after 4 failed attempts — and then records
  //     the miss for the session so it never hammers again,
  //   • dedupes identical artist+title pairs (same song, two queues),
  //   • prefetches the next queue item so covers are ready on auto-advance.
  /// artist|title -> cover URL (null = definitive miss for this session).
  final Map<String, String?> _pairCache = <String, String?>{};
  /// artist|title -> song ids waiting on that pair's result.
  final Map<String, List<String>> _pairWaiters = <String, List<String>>{};
  /// artist|title -> the job (first-seen song + attempt count).
  final Map<String, _ArtJob> _pairJobs = <String, _ArtJob>{};
  /// pair keys in lookup order.
  final List<String> _pairQueue = <String>[];
  DateTime _lastMbRequest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _mbCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _mbBackoff = Duration.zero;
  bool _drainingArt = false;

  /// Waveform phase, advanced by the 10 s refresh tick so the state line
  /// dances like a visualizer.
  int _frame = 0;

  void _start(PlayerController player) {
    if (_running) return;
    _running = true;
    _player = player;
    player.addListener(_push);
    // Heartbeat doubles as the reconnect path: if Discord launches after
    // Shuro did (or quit and came back), the next tick within 30 s picks the
    // connection up and re-pushes.
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_connected) {
        unawaited(_connect());
        return;
      }
      final player = _player;
      if (player != null && player.isPlaying) {
        _frame++; // next waveform frame...
        _lastSignature = null; // ...which needs an actual push
      }
      // Re-push even mid-track: re-syncs Discord's progress bar with fresh
      // timestamps, so the card never drifts or feels stale.
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
        '${song.id}|${player.isPlaying}|${player.queueIndex}|${player.queue.length}|$_frame';
    if (sig == _lastSignature) return;

    final meta = player.metadataResolver?.call(song);
    final now = DateTime.now();
    final dur = player.duration;
    var pos = player.position;
    if (pos < Duration.zero) pos = Duration.zero;
    if (dur > Duration.zero && pos > dur) pos = dur;
    final queueLength = player.queue.length;
    final index = player.queueIndex < 0 ? 0 : player.queueIndex;

    // The card goes out immediately with the logo, then upgrades to the real
    // cover once the fetcher resolves a publicly-fetchable URL.
    if (!_artCache.containsKey(song.id)) _resolvePublicArt(song);
    // Prefetch the next queue item so covers are ready on auto-advance.
    if (player.isPlaying && queueLength > 1) {
      final nextIndex = index + 1;
      if (nextIndex < queueLength) {
        final nextSong = player.queue[nextIndex];
        if (!_artCache.containsKey(nextSong.id) &&
            !_pairCache.containsKey(_pairKeyOf(nextSong))) {
          _resolvePublicArt(nextSong);
        }
      }
    }

    _send(
      DiscordPresence(
        type: DiscordActivityType.listening, // "Listening to Shuro"
        details: song.title,
        state: '${song.artist} · ${_waveform(song)}',
        largeAsset: (_artCache[song.id] != null)
            ? DiscordAsset.fromUrl(_artCache[song.id]!,
                text: meta?.albumTitle == null
                    ? song.artist
                    : '${meta!.albumTitle} · ${song.artist}')
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

  /// A tiny per-track "spectrum": deterministic pseudo-bars from the song's
  /// identity, phase-advanced by the 10 s tick so the state line moves like
  /// a visualizer. Unicode blocks render in every Discord theme.
  String _waveform(Song song) {
    const bars = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
    final seed = song.id.hashCode ^ song.title.length;
    final out = StringBuffer();
    for (var i = 0; i < 10; i++) {
      final w1 = math.sin(i * 1.7 + _frame * 0.9 + seed * 0.001);
      final w2 = math.sin(i * 0.53 + _frame * 0.35 + seed * 0.017);
      var v = (w1 * 0.5 + w2 * 0.5 + 1.0) / 2.0;
      if (v < 0) v = 0;
      if (v > 1) v = 1;
      out.write(bars[(v * 7.99).floor()]);
    }
    return out.toString();
  }

  /// Discord's servers build the presence card cloud-side, so a LAN or
  /// localhost Navidrome URL can never render there. These hosts need the
  /// public Cover Art Archive route instead.
  bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' ||
        h == '::1' ||
        h.endsWith('.local') ||
        h.endsWith('.lan') ||
        h.endsWith('.home')) {
      return true;
    }
    final parts = h.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      final a = int.parse(parts[0]);
      final b = int.parse(parts[1]);
      if (a == 127 || a == 10 || a == 0) return true;
      if (a == 169 && b == 254) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
    }
    return false;
  }

  /// Resolves the cover Discord should show for [song]. Public server URLs
  /// go straight through; everything else is queued for a MusicBrainz →
  /// Cover Art Archive lookup (the same public database ListenBrainz wraps,
  /// no account needed). When a cover lands, the card is re-pushed so it
  /// upgrades from the logo.
  void _resolvePublicArt(Song song) {
    // A cover URL that Discord's servers can actually fetch: use it as-is.
    final uri = _player?.metadataResolver?.call(song)?.artUri;
    if (uri != null && uri.host.isNotEmpty && !_isPrivateHost(uri.host)) {
      _artCache[song.id] = uri.toString();
      PlaybackEventLog.instance
          .add('rpc.art', {'stage': 'direct', 'song': song.id});
      _nudge();
      return;
    }
    final key = _pairKeyOf(song);
    final cached = _pairCache[key];
    if (_pairCache.containsKey(key)) {
      _artCache[song.id] = cached;
      _nudge();
      return;
    }
    final waiters = _pairWaiters[key];
    if (waiters != null) {
      if (!waiters.contains(song.id)) waiters.add(song.id);
      return; // this pair is already queued; the drain loop distributes it
    }
    _pairWaiters[key] = <String>[song.id];
    _pairJobs[key] = _ArtJob(pairKey: key, song: song);
    _pairQueue.add(key);
    PlaybackEventLog.instance
        .add('rpc.art', {'stage': 'queued', 'song': song.id});
    unawaited(_drainArtQueue());
  }

  /// One long-lived consumer for the lookup queue. Waits out rate-limit
  /// cooldowns and spacing, retries the same pair on transient failures,
  /// and moves on to newer tracks while an old pair cools down.
  Future<void> _drainArtQueue() async {
    if (_drainingArt) return;
    _drainingArt = true;
    try {
      while (_pairQueue.isNotEmpty) {
        final key = _pairQueue.first;
        final waiters = _pairWaiters[key];
        if (waiters == null || waiters.isEmpty) {
          _pairQueue.removeAt(0);
          _pairJobs.remove(key);
          continue;
        }
        final job = _pairJobs[key];
        if (job == null) {
          _pairQueue.removeAt(0);
          continue;
        }
        // Politeness: honor the cooldown and keep >= 1.2 s between requests.
        final now = DateTime.now();
        final cooldownWait = _mbCooldownUntil.difference(now);
        final spacingWait =
            _lastMbRequest.add(const Duration(milliseconds: 1200)).difference(now);
        final wait = cooldownWait > spacingWait ? cooldownWait : spacingWait;
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
          continue;
        }
        _lastMbRequest = DateTime.now();
        String? resolved;
        var failed = false;
        try {
          resolved = await _lookupCoverArt(job.song);
        } catch (_) {
          failed = true;
        }
        if (!failed) {
          _mbBackoff = Duration.zero;
          _mbCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
          _finishPair(key, resolved); // null = definitive miss (no archive art)
          continue;
        }
        job.attempts++;
        if (job.attempts >= 4) {
          // Enough attempts: record the miss so this pair never hammers
          // MusicBrainz again this session.
          PlaybackEventLog.instance
              .add('rpc.art', {'stage': 'gave-up', 'pair': key});
          _finishPair(key, null);
          continue;
        }
        // Rate-limited or network error: exponential backoff, then retry the
        // same pair — moved to the END of the queue so a track the user is
        // actually looking at goes first.
        _mbBackoff = _mbBackoff == Duration.zero
            ? const Duration(seconds: 30)
            : (_mbBackoff * 2 > const Duration(minutes: 5)
                ? const Duration(minutes: 5)
                : _mbBackoff * 2);
        _mbCooldownUntil = DateTime.now().add(_mbBackoff);
        PlaybackEventLog.instance.add('rpc.art', {
          'stage': 'backoff',
          'attempt': job.attempts,
          'waitS': _mbBackoff.inSeconds,
        });
        _pairQueue.removeAt(0);
        _pairQueue.add(key);
      }
    } finally {
      _drainingArt = false;
    }
  }

  /// Distributes a finished pair to every song that was waiting on it and
  /// nudges the presence so the visible card upgrades immediately.
  void _finishPair(String key, String? resolved) {
    _pairQueue.remove(key);
    _pairJobs.remove(key);
    _pairCache[key] = resolved;
    PlaybackEventLog.instance.add('rpc.art', {
      'stage': resolved == null ? 'miss' : 'found',
      'pair': key,
    });
    final waiters = _pairWaiters.remove(key) ?? const <String>[];
    for (final id in waiters) {
      _artCache[id] = resolved;
    }
    _nudge();
  }

  /// Re-pushes the presence so a freshly resolved cover (or a new waveform
  /// frame) actually reaches Discord. Deduped by the signature otherwise.
  void _nudge() {
    if (_connected) {
      _lastSignature = null;
      _push();
    }
  }

  String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _pairKeyOf(Song song) =>
      '${_norm(song.artist)}|${_norm(song.title)}';

  /// title + artist -> MusicBrainz recording -> first release group whose
  /// Cover Art Archive front image exists; falls back to an album-level
  /// (release-group) search when the recording doesn't match. THROWS on
  /// transient errors so the fetcher can back off and retry — a 503 must
  /// never be recorded as "no art".
  Future<String?> _lookupCoverArt(Song song) async {
    final client = HttpClient();
    client.userAgent = _userAgent;
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      // The user's own public server first: their covers, their choice
      // (Discord cannot reach a LAN address). Verified with a HEAD before
      // use; any failure falls through to MusicBrainz and finally the
      // shuro_logo asset.
      // Feishin-style public art: the song's own artwork URL already
      // carries the server credentials (u/t/s) - swapping its base to the
      // user's public address yields a URL Discord's clients can fetch
      // directly, no anonymous-access rule needed. Verified with a HEAD
      // before use; any failure falls through to MusicBrainz / shuro_logo.
      final publicBase = SettingsExtras.instance.rpcPublicServerUrl;
      final art = song.artwork;
      if (publicBase.isNotEmpty && art is NetworkImage && !song.id.startsWith('local_')) {
        final original = Uri.tryParse(art.url);
        final base = Uri.tryParse(publicBase);
        if (original != null &&
            base != null &&
            base.hasScheme &&
            base.host.isNotEmpty &&
            base.host != original.host) {
          final publicArt = original.replace(
            scheme: base.scheme,
            host: base.host,
            port: base.hasPort
                ? base.port
                : (base.scheme == 'https' ? 443 : 80),
          );
          try {
            final check = await (await client.headUrl(publicArt))
                .close()
                .timeout(const Duration(seconds: 5));
            if (check.statusCode >= 200 && check.statusCode < 400) {
              return publicArt.toString();
            }
          } catch (_) {}
        }
      }
      final artistQ = _q(_primaryArtist(song.artist));
      final recordingIds = await _searchReleaseGroups(
        client,
        '/ws/2/recording',
        'recording:"${_q(song.title)}" AND artist:"$artistQ"',
        itemsKey: 'recordings',
        expectArtist: artistQ,
        expectTitle: song.title,
      );
      for (final id in recordingIds.take(6)) {
        final url = await _caaFrontIfReal(client, id);
        if (url != null) return url;
      }
      // Album-level fallback: recording metadata drifts (live versions,
      // remasters, messy tags) while the album still matches cleanly.
      final album = _player?.metadataResolver?.call(song)?.albumTitle;
      if (album != null && album.isNotEmpty) {
        final albumIds = await _searchReleaseGroups(
          client,
          '/ws/2/release-group',
          'releasegroup:"${_q(album)}" AND artist:"$artistQ"',
          itemsKey: 'release-groups',
          expectArtist: artistQ,
          expectTitle: album,
        );
        for (final id in albumIds.take(4)) {
          final url = await _caaFrontIfReal(client, id);
          if (url != null) return url;
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// Quotes break the Lucene query; strip them instead of failing the lookup.
  String _q(String s) => s.replaceAll('"', ' ').trim();

  /// Multi-artist tags arrive as "Zedd • Katy Perry" or "A, B & C". The
  /// MusicBrainz query (and the result check) want the primary artist alone -
  /// searching the joined string mostly returns noise.
  String _primaryArtist(String artist) {
    final split =
        RegExp(r'\s*[•,;&/]\s+|\s+[x&]\s+|\s+feat\.?\s+|\s+with\s+', caseSensitive: false);
    for (final part in artist.split(split)) {
      final p = part.trim();
      if (p.isNotEmpty) return p;
    }
    return artist.trim();
  }

  /// Join an artist-credit structure ("names" plus join phrases) to text.
  String _creditNames(dynamic credit) {
    if (credit is List) {
      return credit
          .map((c) => c is Map ? (c['name'] as String? ?? '') : '')
          .join(' ');
    }
    if (credit is Map) return (credit['name'] as String? ?? '');
    return '';
  }

  /// Either-way containment on normalized text - "Katy Perry" matches
  /// "katy perry", "NF" matches "nf", "Zedd" does NOT match "katy perry".
  bool _looseMatch(String a, String b) {
    final na = _norm(a), nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na.contains(nb) || nb.contains(na);
  }

  /// Runs a MusicBrainz search and returns unique release-group ids,
  /// best-scored first. [itemsKey] is 'recordings' (ids nested under each
  /// recording's releases) or 'release-groups' (ids at the top level).
  Future<List<String>> _searchReleaseGroups(
    HttpClient client,
    String path,
    String lucene, {
    required String itemsKey,
    String? expectArtist,
    String? expectTitle,
  }) async {
    final query = Uri.https('musicbrainz.org', path, {
      'query': lucene,
      'fmt': 'json',
      'limit': '5',
    });
    final res =
        await (await client.getUrl(query)).close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      // 503/429 = rate limiting, not "no art" — throw so the fetcher backs
      // off and retries; swallowing it here would cache a false miss.
      throw HttpException('musicbrainz ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final items = data[itemsKey];
    final ids = <String>[];
    if (items is! List) return ids;
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      // MusicBrainz' Lucene search is loose: the top results for a query can
      // still be a different artist's song with the same-ish title. Taking
      // the first one with a cover is exactly how wrong album art ended up
      // on Discord - so every candidate is verified against the song's own
      // (primary) artist and title before its art is considered.
      if (expectArtist != null || expectTitle != null) {
        final itemTitle = (item['title'] as String?) ?? '';
        final credit = _creditNames(item['artist-credit']);
        if (expectArtist != null && !_looseMatch(credit, expectArtist)) continue;
        if (expectTitle != null && !_looseMatch(itemTitle, expectTitle)) continue;
      }
      if (itemsKey == 'recordings') {
        final releases = item['releases'];
        if (releases is! List) continue;
        for (final rel in releases) {
          final rg = rel is Map<String, dynamic> ? rel['release-group'] : null;
          final id = rg is Map<String, dynamic> ? rg['id'] : null;
          if (id is String && id.isNotEmpty && !ids.contains(id)) ids.add(id);
        }
      } else {
        final id = item['id'];
        if (id is String && id.isNotEmpty && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }

  /// Cover Art Archive answers 307 (redirect to the Internet Archive) when
  /// the art exists and 404 when the release group has no front image.
  Future<String?> _caaFrontIfReal(HttpClient client, String rgId) async {
    final caa = Uri.parse('$_caaFront/$rgId/front-500');
    try {
      final head =
          await (await client.headUrl(caa)).close().timeout(const Duration(seconds: 6));
      final code = head.statusCode;
      if (code >= 200 && code < 400) return caa.toString();
    } catch (_) {
      // network hiccup on archive.org — treat as "not this one"
    }
    return null;
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


/// One pending artist+title lookup in the artwork fetcher's queue — see the
/// fetcher docs on [DiscordRpcService]'s fields.
class _ArtJob {
  _ArtJob({required this.pairKey, required this.song});

  final String pairKey;
  final Song song;

  /// Transient failures so far; 4 strikes = the pair is recorded as a miss.
  int attempts = 0;
}

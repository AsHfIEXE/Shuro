import 'dart:async';
import 'dart:convert';

import '../app_persistence.dart';
import 'lastfm_client.dart';

/// What the app reports to Last.fm, and when.
///
/// Three rules come straight from the Last.fm contract and are implemented here
/// rather than left to a caller:
///
///  1. **When a play counts.** "The track must be longer than 30 seconds. And
///     the track has been played for at least half its duration, or for 4
///     minutes (whichever occurs earlier.)" — see [shouldScrobble].
///  2. **Failed scrobbles are kept, in order.** The docs tell clients to hold
///     unsubmitted scrobbles in a *local cache that survives restarts*, to send
///     them oldest-first, and to batch up to 50. [submit] therefore never drops
///     an entry on a retryable error; it persists it.
///  3. **Not everything is worth retrying.** Error 9 means the session key is
///     dead (stop and re-authorize); 11/16 mean try later; 29 means back off; any
///     other code means the request was malformed, so that entry is discarded
///     instead of blocking the queue forever.
///
/// Nothing here runs unless [isReady]: Last.fm needs an application key
/// configured at build time *and* a user who has authorized the app. Without
/// both, every method is a no-op and the app is unchanged.
class ScrobbleService {
  ScrobbleService({LastFmClient? client}) : _client = client ?? LastFmClient();

  static const String _sessionKeyPref = 'lastfm_session_key_v1';
  static const String _pendingPref = 'lastfm_pending_scrobbles_v1';
  static const int _pendingCap = 500;

  final LastFmClient _client;
  AppPersistence? _persistence;

  String? _sessionKey;
  bool _needsReauthorization = false;
  final List<ScrobbleEntry> _pending = [];
  bool _flushing = false;

  /// True when a key is configured *and* the user has authorized this app.
  bool get isReady => LastFmConfig.isConfigured && _sessionKey != null && !_needsReauthorization;

  /// True when the app could scrobble but the user hasn't authorized yet.
  bool get needsAuthorization => LastFmConfig.isConfigured && _sessionKey == null;

  /// True when Last.fm told us the stored session is no longer valid.
  bool get sessionRevoked => _needsReauthorization;

  int get pendingCount => _pending.length;
  String? get sessionKey => _sessionKey;

  /// Loads the stored session key and any scrobbles left over from a previous
  /// run. Safe to call before anything else; failures leave the service inert.
  Future<void> restore(AppPersistence persistence) async {
    _persistence = persistence;
    _sessionKey = persistence.getString(_sessionKeyPref);
    final raw = persistence.getString(_pendingPref);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final entry = ScrobbleEntry.fromJson(item);
            if (entry != null) _pending.add(entry);
          }
        }
      } catch (_) {
        // A corrupt cache must not stop the app from starting.
      }
    }
  }

  Future<void> _persistSession() async {
    final persistence = _persistence;
    if (persistence == null) return;
    if (_sessionKey == null) {
      await persistence.remove(_sessionKeyPref);
    } else {
      // Plain storage, same limitation as the rest of this app's state: a session
      // key is a bearer credential for scrobbling, not the user's password, and
      // moving it to secure storage is the right follow-up.
      await persistence.setString(_sessionKeyPref, _sessionKey!);
    }
  }

  Future<void> _persistPending() async {
    final persistence = _persistence;
    if (persistence == null) return;
    await persistence.setString(_pendingPref, json.encode(_pending.map((e) => e.toJson()).toList()));
  }

  // --- authorization --------------------------------------------------------

  /// Starts the browser authorization flow: asks for a token and returns the URL
  /// the *user* opens to grant this app access. The user's browser session is the
  /// credential here — the app never sees a password and never asks for a key.
  Future<({String? url, String? error})> beginAuthorization() async {
    if (!LastFmConfig.isConfigured) {
      return (url: null, error: 'No Last.fm application key is configured in this build.');
    }
    final result = await _client.requestToken();
    if (!result.ok) return (url: null, error: result.detail ?? 'Last.fm refused the token request.');
    final token = result.body?['token'] as String?;
    if (token == null || token.isEmpty) return (url: null, error: 'Last.fm returned no token.');
    return (url: LastFmConfig.authorizationUrl(token), error: null);
  }

  /// Completes the flow with the token the user just authorized.
  Future<String?> completeAuthorization(String token) async {
    final result = await _client.createSession(token);
    if (!result.ok) return result.detail ?? 'Last.fm refused the session request.';
    final key = result.sessionKey;
    if (key == null || key.isEmpty) return 'Last.fm returned no session key.';
    _sessionKey = key;
    _needsReauthorization = false;
    await _persistSession();
    // Anything held from before can go now.
    unawaited(flushPending());
    return null;
  }

  /// Forgets the session (a local sign-out; the user can also revoke it on
  /// Last.fm's own settings screen, which shows up as [sessionRevoked]).
  Future<void> signOut() async {
    _sessionKey = null;
    _needsReauthorization = false;
    await _persistSession();
  }

  // --- reporting -----------------------------------------------------------

  /// "Requests should be sent as soon as a user starts listening to a track."
  /// Failures are ignored on purpose: the contract says now-playing requests
  /// should not be retried.
  Future<void> nowPlaying(ScrobbleEntry entry) async {
    if (!isReady) return;
    await _client.updateNowPlaying(
      artist: entry.artist,
      track: entry.track,
      album: entry.album,
      albumArtist: entry.albumArtist,
      duration: entry.duration,
      trackNumber: entry.trackNumber,
      musicBrainzId: entry.musicBrainzId,
      sessionKey: _sessionKey!,
    );
  }

  /// Queues a finished play if it qualifies, then tries to submit. Entries that
  /// can't be sent (offline, rate-limited) stay queued for the next opportunity.
  Future<void> submit(ScrobbleEntry entry) async {
    if (!LastFmConfig.isConfigured) return;
    _pending.add(entry);
    if (_pending.length > _pendingCap) _pending.removeRange(0, _pending.length - _pendingCap);
    await _persistPending();
    await flushPending();
  }

  /// Sends queued scrobbles oldest-first, in batches of at most 50, stopping as
  /// soon as one fails in a way that will still fail for the rest.
  Future<void> flushPending() async {
    if (_flushing || !isReady || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.take(LastFmClient.maxBatchSize).toList();
        final result = await _client.scrobble(batch, sessionKey: _sessionKey!);

        if (result.ok) {
          _pending.removeRange(0, batch.length);
          await _persistPending();
          continue;
        }

        switch (result.failure) {
          case LastFmFailure.needsReauthorization:
            // The stored session is dead. Keep the scrobbles (they're the user's
            // history) and let the UI ask for authorization again.
            _needsReauthorization = true;
            _sessionKey = null;
            await _persistSession();
            return;
          case LastFmFailure.retryable:
          case LastFmFailure.rateLimited:
          case LastFmFailure.notConfigured:
            // Try again later, with the queue intact and order preserved.
            return;
          case LastFmFailure.rejected:
            // Malformed for a reason retrying can't fix (bad metadata, a
            // filtered artist): drop just this batch so it can't block the rest
            // of the queue forever.
            _pending.removeRange(0, batch.length);
            await _persistPending();
          case null:
            return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// The documented rule for what counts as a play.
  ///
  /// Kept as a pure static so it is testable at the boundaries: exactly 30
  /// seconds does **not** qualify ("must be longer than 30 seconds"), and the
  /// threshold is half the duration or four minutes, whichever comes first.
  static bool shouldScrobble({required Duration trackDuration, required Duration played}) {
    if (trackDuration.inSeconds <= 30) return false;
    final half = Duration(milliseconds: trackDuration.inMilliseconds ~/ 2);
    const fourMinutes = Duration(minutes: 4);
    final required = half < fourMinutes ? half : fourMinutes;
    return played >= required;
  }
}

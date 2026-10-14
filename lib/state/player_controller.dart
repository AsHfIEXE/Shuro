import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../playback/audio_diagnostics.dart';
import '../playback/playback_engine.dart';

/// Resolves the real album title / artwork URL for a song's lock-screen
/// notification entry — see [NowPlayingMetadata]. Wired from app.dart to
/// [AppState.nowPlayingMetadataFor], the same decoupling pattern as
/// [AudioSourceResolver] and [SuggestionProvider].
typedef NowPlayingMetadataResolver = NowPlayingMetadata? Function(Song song);

/// Given the song that just ran out of queue, returns candidates to keep
/// playing (autoplay). The controller filters out anything already queued.
typedef SuggestionProvider = List<Song> Function(Song current);

/// Resolves a [Song] to something `just_audio` can actually open: a local
/// file path, or a backend-provided stream URL. Returning null means there
/// is genuinely nothing to play (no server connected, or the connected
/// backend has no audio behind this particular song) — [PlayerController]
/// surfaces that as [lastPlaybackError] rather than crashing.
typedef AudioSourceResolver = String? Function(Song song);

/// Drives playback state shared across the mini player, Now Playing, Lyrics
/// and Queue screens. Backed by a real [AudioPlayer] (just_audio) — local
/// files play via their own path, server songs via a URL from
/// [audioSourceResolver] (wired to [AppState.audioSourceFor] in app.dart,
/// mirroring how [suggestionProvider] is wired).
///
/// [position] reads straight through to the audio player's own cached
/// position (cheap, synchronous, safe to call every frame for smooth UI
/// like the progress ring or lyric sync — just_audio interpolates it with a
/// stopwatch between platform updates, so it genuinely advances every
/// frame); [notifyListeners] itself is only fired about once a second from
/// the position stream, plus immediately on every state-changing action, so
/// listeners aren't rebuilt 60x/sec for no reason.
///
/// Two invariants keep the UI and the queue honest while the user skips
/// around faster than the network loads (the bug class this class used to
/// lose track of):
///  - **One load wins.** Every load takes a [_loadGeneration]; async steps
///    re-check it, so a slow `setUrl` for a track the user already skipped
///    away from can neither publish its state nor start playing over the
///    newer one.
///  - **Only the loaded track ends.** A `completed` event is acted on only
///    when it belongs to the song the engine actually finished
///    ([_loadedSongId]) — a stale source completing mid-switch no longer
///    auto-advances the song the user just picked.
class PlayerController extends ChangeNotifier implements PlaybackEngine {
  PlayerController() {
    // Both streams need an onError handler, not just a data callback: a
    // stream that drops mid-playback (LAN connection lost, server
    // restarted, phone roamed off Wi-Fi) surfaces as an error on these
    // just_audio streams, not as a thrown exception anywhere we already
    // have a try/catch — without a handler here, that error would go to
    // the zone's uncaught-error handler instead of the user, leaving the
    // UI stuck showing "playing" over audio that's actually gone silent.
    _positionSub = _audioPlayer.positionStream.listen((pos) {
      final sec = pos.inSeconds;
      if (sec != _lastNotifiedSecond) {
        _lastNotifiedSecond = sec;
        notifyListeners();
      }
      _checkListenThreshold(pos);
      _checkCrossfade(pos);
    }, onError: _onPlaybackStreamError);
    // The native playlist's index changes are how notification skip buttons
    // move the app forward: when the system notification (or a headset)
    // skips, the engine's index moves and the app follows it here.
    _currentIndexSub = _audioPlayer.currentIndexStream.listen(_onNativeIndexChanged, onError: _onPlaybackStreamError);
    _playerStateSub = _audioPlayer.playerStateStream.listen(_onPlayerStateChanged, onError: _onPlaybackStreamError);
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<int?>? _currentIndexSub;

  /// True when a native playlist is loaded (see the whole-queue/window
  /// branch of [_jumpTo]). The system media notification shows previous/next
  /// only when the native playlist actually has a previous/next — the
  /// single-song load is why the notification only ever had pause + stop.
  bool _nativeQueueActive = false;

  /// The live native playlist, when one is loaded — kept so the window can
  /// slide forward/backward via runtime insert/remove (gapless, no reload).
  ConcatenatingAudioSource? _nativeSource;

  /// The id sequence actually loaded into the native playlist — a WINDOW of
  /// the app queue when the queue is large (loading thousands of sources
  /// before the first note was the multi-second "tap → sound" delay), the
  /// whole queue when it is small. Native↔app index translation always goes
  /// through this list, never raw indexes.
  List<String>? _nativeQueueIds;

  /// Window geometry: how many songs before/after the playhead are loaded
  /// natively, and below which queue size the whole queue loads instead.
  static const int _kNativeWindowBefore = 12;
  static const int _kNativeWindowAfter = 15;
  static const int _kNativeWindowFullLimit = 60;

  /// True only when a native playlist is loaded AND it still contains the
  /// song the app considers current. Containment, not equality — the window
  /// moves.
  bool get _nativeInSync {
    final ids = _nativeQueueIds;
    if (!_nativeQueueActive || ids == null || ids.isEmpty) return false;
    final currentId = _currentSong?.id;
    return currentId != null && ids.contains(currentId);
  }

  /// Maps an app-queue index onto the native window's index — null when that
  /// song is outside the window right now.
  int? _nativeIndexOf(int appIndex) {
    if (appIndex < 0 || appIndex >= _queue.length) return null;
    final ids = _nativeQueueIds;
    if (ids == null) return null;
    final native = ids.indexOf(_queue[appIndex].id);
    return native >= 0 ? native : null;
  }

  /// Loads exactly one song — the pre-native-queue path, kept as the fallback
  /// whenever the whole-queue load can't happen (single item, an unresolved
  /// queue entry, or any native-load failure).
  Future<void> _loadSingle(String source, MediaItem tag, Duration? startAt) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      await _audioPlayer.setUrl(source, tag: tag, initialPosition: startAt);
    } else {
      await _audioPlayer.setFilePath(source, tag: tag, initialPosition: startAt);
    }
  }
  int _lastNotifiedSecond = -1;

  // --- server play reporting -------------------------------------------------
  // Wired by the composition root (app.dart) when a server session is live;
  // null while offline, so a local-files session never reports anything.
  // The threshold fires once per loaded track, at the Subsonic/Last.fm "a
  // real listen" bar: past half the track, or past four minutes for very
  // long tracks — then the server counts a play (scrobble submission).
  void Function(Song song)? onTrackStarted;
  void Function(Song song)? onListenThresholdReached;
  bool _listenThresholdDone = true;

  void _checkListenThreshold(Duration pos) {
    if (_listenThresholdDone) return;
    final song = _currentSong;
    if (song == null || _loadedSongId != song.id) return;
    final duration = _audioPlayer.duration;
    final half = duration != null && duration > Duration.zero ? pos >= duration * 0.5 : false;
    final fourMinutes = pos >= const Duration(minutes: 4);
    if (half || fourMinutes) {
      _listenThresholdDone = true;
      onListenThresholdReached?.call(song);
    }
  }

  /// Interpolated position for UI that must move smoothly — the lyrics karaoke
  /// fill and the progress ring. Everything else can keep listening to
  /// [notifyListeners]' ~1 Hz rate.
  ///
  /// The period here is `clamp(trackDuration / steps, minPeriod, maxPeriod)`, so
  /// the defaults matter more than they look. With `steps: 4000` the period is
  /// 32 ms only for tracks of about two minutes or less, and then worsens with
  /// length — 60 ms at 4:00, 90 ms at 6:00, the 120 ms cap beyond 8:00. That is
  /// 8–16 fps, which reads as a visibly stepping highlight on exactly the tracks
  /// people listen to most. `steps: 20000` with a 16 ms floor keeps every normal
  /// track at ~60 fps (16 ms up to about 5:20, 24 ms at 8:00) while the cap still
  /// protects very long files.
  ///
  /// The *value* is already smooth: just_audio interpolates `position` with its
  /// own stopwatch between platform updates, so a consumer reading [position] at
  /// any moment gets an up-to-date figure — this only controls how often a
  /// listener is told about it.
  late final Stream<Duration> _smoothPositions = _audioPlayer.createPositionStream(
    steps: 20000,
    minPeriod: const Duration(milliseconds: 16),
    maxPeriod: const Duration(milliseconds: 120),
  );

  Song? _currentSong;
  List<Song> _queue = [];
  int _queueIndex = 0;
  bool _isPlaying = false;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  String? _lastError;
  final Random _random = Random();

  /// Monotonic id of the newest load request — see the class doc's "one
  /// load wins" invariant.
  int _loadGeneration = 0;

  /// True while a load for the current generation is still in flight, so
  /// UI can show a real buffering state and `completed` events from the
  /// outgoing source are ignored.
  bool _isLoading = false;

  /// The song id whose audio the engine has actually finished loading.
  /// Null until the first successful load, and reset when one fails.
  String? _loadedSongId;

  /// A seek requested while the load it belongs to was still in flight —
  /// applied the instant that load lands. Without this, tapping a lyric
  /// line (or restoring a saved position) on a track that hadn't finished
  /// loading either seeked the *previous* track or silently did nothing.
  Duration? _pendingSeek;

  /// Loads run one at a time, chained through this future.
  ///
  /// Overlapping load requests are not just wasteful, they actively break
  /// playback on some platforms: a second load while a `play()` is still
  /// pending is aborted by the media element itself, which surfaces (on web,
  /// as seen in a real run) as "AbortError: The play() request was interrupted
  /// by a new load request". Letting each load settle before starting the next
  /// means that interruption is never created — and a superseded load is still
  /// ignored by the generation guard, so chaining costs nothing but the wait.
  Future<void> _loadChain = Future<void>.value();

  /// True when the current song has no usable audio behind it (no source
  /// resolved, or the load threw), so the next play press retries the load
  /// instead of flipping an icon over silence.
  bool _needsReload = false;

  ProcessingState? _lastNotifiedProcessingState;

  /// When the queue runs out, keep going with [suggestionProvider]'s
  /// picks instead of stopping. Wired to Settings → Behavior → Autoplay.
  bool autoplay = true;
  SuggestionProvider? suggestionProvider;

  /// Wired once, from app.dart, to whatever can turn a [Song] into a
  /// playable source right now (local file path or a repository's stream
  /// URL) — see [AudioSourceResolver]. Kept decoupled from AppState the
  /// same way [suggestionProvider] is, so this class never needs to know
  /// a repository or AppState exists.
  AudioSourceResolver? audioSourceResolver;

  /// Wired once, from app.dart, the same way [audioSourceResolver] is —
  /// gives the lock-screen/notification entry a real album title and
  /// artwork URL. Null (or returning null) just means a plainer
  /// notification (song title/artist only, no art), never a crash.
  NowPlayingMetadataResolver? metadataResolver;

  /// Wired once, from app.dart, the same way [audioSourceResolver] is — turns
  /// the app's knowledge (the song's reported metadata, the last capability
  /// answer, the request check) into the diagnostics object the Audio
  /// Information panel shows. Kept out of this class so it never needs to
  /// import AppState (playback plan §6).
  AudioDiagnosticsResolver? diagnosticsResolver;

  /// What the server is asked for — see [SourcePolicy] and §3.1 of the plan.
  /// Set from app.dart off Settings, so the policy that *built* the request is
  /// the same policy the diagnostics panel reports against.
  SourcePolicy _sourcePolicy = const SourcePolicy();

  /// ReplayGain/EQ/crossfade state. Its own axis, deliberately: processing
  /// changes PCM without making the source any less original (§4.2).
  ProcessingOptions _processingOptions = ProcessingOptions.none;

  SourcePolicy get sourcePolicy => _sourcePolicy;
  ProcessingOptions get processingOptions => _processingOptions;

  Song? get currentSong => _currentSong;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  bool get isPlaying => _isPlaying;
  bool get shuffle => _shuffle;
  PlayerRepeatMode get repeatMode => _repeatMode;
  bool get hasSong => _currentSong != null;

  /// True while the current song's audio is still being loaded or the
  /// engine is refilling its buffer — lets a screen show a spinner instead
  /// of a play button that looks idle while nothing is audible yet.
  bool get isBuffering =>
      _isLoading ||
      _audioPlayer.processingState == ProcessingState.loading ||
      _audioPlayer.processingState == ProcessingState.buffering;

  /// Real-clock position updates (~30 fps while playing) for UI that needs
  /// to move smoothly — the lyrics karaoke fill and the progress ring.
  /// Everything else can keep listening to [notifyListeners]' ~1 Hz rate.
  Stream<Duration> get smoothPositionStream => _smoothPositions;

  /// The most recent "couldn't play this" message (no source, network
  /// error, unsupported format, …), or null once it's been shown/cleared.
  /// Surfaced as a snackbar from app.dart; a song with no real audio
  /// behind it (e.g. anything from a demo/mock catalog) always ends up
  /// here instead of crashing or silently doing nothing.
  String? get lastPlaybackError => _lastError;

  void clearPlaybackError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// True playback position — reads straight through to the audio engine.
  Duration get position => _audioPlayer.position;

  /// The length of what's *actually* loaded: the engine's own decoded
  /// duration when it has one, falling back to the server's tagged
  /// duration so a track still shows a total time before its audio loads.
  /// These two genuinely differ (a VBR stream, a transcoded copy, a file
  /// whose tags were wrong) — using the tag alone is what made the progress
  /// ring and lyric offset drift against the real audio.
  Duration get duration {
    final live = _audioPlayer.duration;
    if (live != null && live > Duration.zero) return live;
    return _currentSong?.duration ?? Duration.zero;
  }

  /// Whether [duration] came from the engine rather than the song's tags —
  /// lets the UI (Audio Information) say which one it's reporting.
  bool get hasEngineDuration {
    final live = _audioPlayer.duration;
    return live != null && live > Duration.zero;
  }

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    final value = position.inMilliseconds / total;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  // --- internals -------------------------------------------------------

  void _onPlayerStateChanged(PlayerState state) {
    final playingChanged = _isPlaying != state.playing;
    _isPlaying = state.playing;
    final processingChanged = _lastNotifiedProcessingState != state.processingState;
    _lastNotifiedProcessingState = state.processingState;

    if (state.processingState == ProcessingState.completed) {
      // Only the track the engine actually finished is allowed to move the
      // queue on. While a new song is loading — or a load has already been
      // superseded — `completed` belongs to the *outgoing* source, and
      // acting on it here is exactly what made picking a new song
      // sometimes jump straight past it.
      final belongsToLoadedTrack = !_isLoading && _loadedSongId != null && _loadedSongId == _currentSong?.id;
      if (belongsToLoadedTrack) {
        _advance(fromTrackEnd: true);
        return;
      }
      if (playingChanged || processingChanged) notifyListeners();
      return;
    }

    if (playingChanged || processingChanged) notifyListeners();
  }

  /// A playback stream (position or player-state) threw instead of
  /// delivering a value — in practice, a stream that was playing fine and
  /// then lost its connection. Stops cleanly and surfaces it the same way
  /// a failure in [_jumpTo] does, rather than leaving the UI showing
  /// "playing" over audio that silently died.
  /// The native playlist's index moved (notification skip, headset,
  /// Android Auto): follow it so the app's current song, lyrics and
  /// palette track whatever is actually audible. Ignored while the app
  /// itself is driving a load — during _jumpTo the index changes are our
  /// own doing.
  void _onNativeIndexChanged(int? index) {
    if (!_nativeInSync || _isLoading || index == null) return;
    final ids = _nativeQueueIds!;
    if (index < 0 || index >= ids.length) return;
    // The engine speaks native-window indexes; translate to the app queue by
    // id before touching any app state.
    final id = ids[index];
    final appIndex = _queue.indexWhere((s) => s.id == id);
    if (appIndex < 0) return;
    if (appIndex == _queueIndex && _loadedSongId == id) return;
    _queueIndex = appIndex;
    final song = _queue[appIndex];
    _currentSong = song;
    _loadedSongId = song.id;
    _lastNotifiedSecond = -1;
    _lastError = null;
    _listenThresholdDone = false;
    // The engine moved on by itself (auto-advance or a notification skip):
    // the fade/volume/speed state must follow the new track, or the volume
    // faded down for the previous crossfade sticks on everything after it.
    _fadingOut = false;
    unawaited(_applyPlaybackTweaks(song));
    unawaited(_slideNativeWindow(appIndex));
    onTrackStarted?.call(song);
    notifyListeners();
  }

  // --- advanced playback settings (Settings → Playback) ----------------------

  /// Fade-out window at the end of each track, in seconds. 0 = off.
  int crossfadeSeconds = 0;

  /// Normalise loudness from the server's ReplayGain tag.
  bool replayGainEnabled = false;

  /// Resolves a track's ReplayGain in dB (from the server's own tags),
  /// wired in app.dart. Returns null when unknown.
  Future<double?> Function(Song song)? replayGainResolver;

  double playbackSpeed = 1.0;

  bool skipSilence = false;

  bool _fadingOut = false;

  double _targetVolume = 1.0;

  /// Applies the per-track playback settings: speed, skip-silence (Android),
  /// replay-gain volume and the crossfade fade-in. Everything guarded — a
  /// failed tweak is cosmetic, never a playback failure.
  Future<void> _applyPlaybackTweaks(Song song) async {
    _fadingOut = false;
    try {
      // Always set — including back to 1.0× — so leaving the speed setting
      // actually restores normal playback (skipping 1.0× left the old speed
      // stuck on the engine).
      await _audioPlayer.setSpeed(playbackSpeed);
      try {
        await _audioPlayer.setSkipSilenceEnabled(skipSilence);
      } catch (_) {
        // Not supported on this platform (web/iOS) — cosmetic.
      }

      var volume = 1.0;
      if (replayGainEnabled && replayGainResolver != null) {
        final db = await replayGainResolver?.call(song);
        if (db != null) {
          // dB → linear gain, clamped: never silence a track, never blast one.
          volume = pow(10.0, db.clamp(-24.0, 12.0) / 20.0).toDouble().clamp(0.0, 1.25);
        }
      }
      _targetVolume = volume;

      if (crossfadeSeconds > 0) {
        // Fade-in over the crossfade window, in a few steps.
        const steps = 5;
        try {
          await _audioPlayer.setVolume(0.0);
        } catch (_) {}
        for (var s = 1; s <= steps; s++) {
          await Future<void>.delayed(Duration(milliseconds: crossfadeSeconds * 1000 ~/ steps));
          try {
            await _audioPlayer.setVolume(volume * (s / steps));
          } catch (_) {}
        }
      } else {
        try {
          await _audioPlayer.setVolume(volume);
        } catch (_) {}
      }
    } catch (_) {
      try {
        await _audioPlayer.setVolume(1.0);
      } catch (_) {}
    }
  }

  /// Public re-apply, used by Settings changes so they take effect on the
  /// currently playing track immediately.
  Future<void> applyPlaybackTweaksNow() async {
    final song = _currentSong;
    if (song != null && _loadedSongId == song.id) {
      await _applyPlaybackTweaks(song);
    }
  }

  void _checkCrossfade(Duration pos) {
    if (crossfadeSeconds <= 0 || _fadingOut || !_isPlaying) return;
    final song = _currentSong;
    if (song == null || _loadedSongId != song.id) return;
    final total = _audioPlayer.duration;
    if (total == null || total <= Duration.zero) return;
    final remaining = total - pos;
    if (remaining <= Duration.zero || remaining > Duration(seconds: crossfadeSeconds)) return;
    _fadingOut = true;
    unawaited(_fadeOutOver(remaining));
  }

  /// Ramps the volume down over the fade window. The engine then advances on
  /// its own (native queue) or via the completed handler — and the new
  /// track's load resets the volume with a quick fade-in.
  Future<void> _fadeOutOver(Duration remaining) async {
    const steps = 8;
    for (var s = steps - 1; s >= 1; s--) {
      try {
        await _audioPlayer.setVolume(_targetVolume * (s / steps));
      } catch (_) {
        return;
      }
      await Future<void>.delayed(remaining * (1 / steps));
      if (!_isPlaying) {
        try {
          await _audioPlayer.setVolume(_targetVolume);
        } catch (_) {}
        return;
      }
    }
  }

  void _onPlaybackStreamError(Object error) {    _isPlaying = false;
    _needsReload = true;
    final song = _currentSong;
    _lastError = song != null
        ? 'Playback of "${song.title}" stopped — the connection was lost.'
        : 'Playback stopped — the connection was lost.';
    notifyListeners();
  }

  /// Loads [index]'s song into the audio engine and (optionally) starts
  /// it. Always updates [_currentSong]/[_queueIndex] and notifies
  /// immediately — even before the audio itself has loaded — so the UI
  /// (title, artwork, controls) switches right away instead of waiting on
  /// the network.
  Future<void> _jumpTo(int index, {required bool startPlaying, Duration? initialPosition}) async {
    if (_queue.isEmpty) return;
    final clamped = index.clamp(0, _queue.length - 1);
    _queueIndex = clamped;
    final song = _queue[clamped];
    final generation = ++_loadGeneration;

    _currentSong = song;
    _lastNotifiedSecond = -1;
    _lastError = null;
    _pendingSeek = null;
    _needsReload = false;
    if (startPlaying) _isPlaying = true;
    notifyListeners();

    final source = audioSourceResolver?.call(song);
    if (source == null) {
      _isPlaying = false;
      _needsReload = true;
      _loadedSongId = null;
      _lastError = 'Can\'t play "${song.title}" — no audio source is available for it.';
      notifyListeners();
      return;
    }

    _isLoading = true;

    // The `tag` is what JustAudioBackground reads to populate the real
    // Android lock-screen/notification media control (title, artist,
    // artwork) — without it, playback still works but no system media
    // session gets published, so there's nothing for a lock screen,
    // Bluetooth headset, or Android Auto to show or control.
    final meta = metadataResolver?.call(song);
    final tag = MediaItem(
      id: song.id,
      album: meta?.albumTitle ?? song.artist,
      title: song.title,
      artist: song.artist,
      duration: song.duration,
      artUri: meta?.artUri,
    );

    final startAt = (initialPosition != null && initialPosition > Duration.zero) ? initialPosition : null;

    // Wait for any in-flight load first — see [_loadChain].
    final previousLoad = _loadChain;
    final settle = Completer<void>();
    _loadChain = settle.future;

    try {
      await previousLoad;
      if (generation == _loadGeneration) _isLoading = true;
    } catch (_) {
      // The previous load's own failure is already reported by its own call.
    }

    try {
      // Native queue window: load the current song plus a margin around it
      // as one playlist — NOT the whole queue. Resolving thousands of audio
      // sources before the first note was the multi-second "tap → sound"
      // delay on big libraries. The window slides at runtime (see
      // [_slideNativeWindow]) so the system notification keeps prev/next and
      // playback stays gapless. Small queues load whole.
      var loadedNatively = false;
      if (_queue.length > 1) {
        try {
          final whole = _queue.length <= _kNativeWindowFullLimit;
          final windowStart = whole
              ? 0
              : (clamped - _kNativeWindowBefore)
                  .clamp(0, _queue.length - (_kNativeWindowBefore + 1 + _kNativeWindowAfter))
                  .toInt();
          final windowEnd = whole
              ? _queue.length
              : min(_queue.length, windowStart + _kNativeWindowBefore + 1 + _kNativeWindowAfter);
          final children = <AudioSource>[];
          final windowIds = <String>[];
          var playheadNative = -1;
          for (var i = windowStart; i < windowEnd; i++) {
            final qSong = _queue[i];
            final qSource = identical(qSong, song) ? source : audioSourceResolver?.call(qSong);
            if (qSource == null) continue; // unresolvable item — not in the native queue
            final qMeta = identical(qSong, song) ? meta : metadataResolver?.call(qSong);
            children.add(
              (qSource.startsWith('http://') || qSource.startsWith('https://'))
                  ? AudioSource.uri(Uri.parse(qSource), tag: _mediaItemFor(qSong, qMeta))
                  : AudioSource.file(qSource, tag: _mediaItemFor(qSong, qMeta)),
            );
            if (i == clamped) playheadNative = children.length - 1;
            windowIds.add(qSong.id);
          }
          if (children.length > 1 && children.length == windowEnd - windowStart && playheadNative >= 0) {
            final native = ConcatenatingAudioSource(children: children);
            await _audioPlayer.setAudioSource(
              native,
              initialIndex: playheadNative,
              initialPosition: startAt,
            );
            loadedNatively = true;
            _nativeSource = native;
            // The native playlist's identity: only while the loaded id window
            // contains what's playing do native seeks and index changes map
            // back onto the app queue.
            _nativeQueueIds = windowIds;
          }
        } on PlayerInterruptedException {
          if (generation == _loadGeneration) {
            _isLoading = false;
            _loadedSongId = null;
          }
          return;
        } catch (_) {
          loadedNatively = false; // fall back to the single-song load
        }
      }
      _nativeQueueActive = loadedNatively;
      if (loadedNatively) {
        // Mirror AFTER the flag flips — _syncNativeModes early-returns while
        // _nativeQueueActive is still false, which left the engine un-shuffled
        // on the first native load.
        await _syncNativeModes();
      } else {
        _nativeQueueIds = null;
        _nativeSource = null;
      }

      if (!loadedNatively) {
        await _loadSingle(source, tag, startAt);
      }
    } on PlayerInterruptedException {
      // A newer load aborted this one on purpose (the user picked another
      // song) — that's the designed behavior, not a playback failure, so
      // it must not surface an error over the track they actually chose.
      if (generation == _loadGeneration) {
        _isLoading = false;
        _loadedSongId = null;
      }
      return;
    } catch (e) {
      if (generation != _loadGeneration) return; // superseded — the newer load owns the UI now
      if (_isAbortArtifact(e)) return; // the media element refused a load it was already replacing
      _isLoading = false;
      _isPlaying = false;
      _needsReload = true;
      _loadedSongId = null;
      _lastError = 'Couldn\'t play "${song.title}". Check your connection and try again.';
      notifyListeners();
      return;
    } finally {
      settle.complete();
    }
    if (generation != _loadGeneration) return; // superseded while the audio was loading

    _isLoading = false;
    _loadedSongId = song.id;
    _listenThresholdDone = false;
    _fadingOut = false;
    // Server play reporting: "now playing" broadcast. Fire-and-forget —
    // reporting must never block or break playback.
    onTrackStarted?.call(song);

    // Per-track playback tweaks: speed, skip-silence, replay-gain volume and
    // the crossfade fade-in. All guarded — a failed tweak is cosmetic, never
    // a playback failure.
    unawaited(_applyPlaybackTweaks(song));

    // A seek that arrived while this song was still loading (tapping a
    // lyric line, restoring a saved position) — apply it now that there's
    // real audio to seek within.
    final pending = _pendingSeek;
    _pendingSeek = null;
    if (pending != null) {
      try {
        await _audioPlayer.seek(pending);
      } catch (_) {
        // A seek that fails here isn't worth failing the whole load over.
      }
    }

    try {
      if (startPlaying) await _startPlayback();
    } catch (e) {
      if (generation != _loadGeneration) return;
      _isPlaying = false;
      _needsReload = true;
      _lastError = 'Couldn\'t play "${song.title}". Check your connection and try again.';
    }
    notifyListeners();
  }

  /// `play()` that treats an interrupted request as what it is — the media
  /// element declining to start audio it is no longer being asked to play —
  /// rather than as a playback failure to report to the user. This is the
  /// exact shape of the HTML5 `AbortError` seen in a real Chrome run when a
  /// new source replaced a pending play.
  Future<void> _startPlayback() async {
    try {
      await _audioPlayer.play();
    } on PlayerInterruptedException {
      return;
    } catch (e) {
      if (_isAbortArtifact(e)) return;
      rethrow;
    }
  }

  /// True for the platform's "this request was replaced" errors, which are
  /// noise rather than failures. Matching on the message is ugly but honest:
  /// the web player raises a raw browser `AbortError` with no Dart type of its
  /// own to catch.
  bool _isAbortArtifact(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('aborterror') ||
        text.contains('interrupted by a new load request') ||
        text.contains('interrupted by a call to pause');
  }

  bool _appendSuggestions() {
    final provider = suggestionProvider;
    final current = _currentSong;
    if (provider == null || current == null) return false;
    final existing = _queue.map((s) => s.id).toSet();
    final fresh = provider(current).where((s) => !existing.contains(s.id)).take(10).toList();
    if (fresh.isEmpty) return false;
    _queue = [..._queue, ...fresh];
    return true;
  }

  Future<void> _advance({required bool fromTrackEnd}) async {
    if (_queue.isEmpty) return;

    if (fromTrackEnd && _repeatMode == PlayerRepeatMode.one) {
      await _audioPlayer.seek(Duration.zero);
      await _startPlayback();
      notifyListeners();
      return;
    }

    int? nextIndex;
    if (_shuffle && _queue.length > 1) {
      do {
        nextIndex = _random.nextInt(_queue.length);
      } while (nextIndex == _queueIndex);
    } else if (_queueIndex < _queue.length - 1) {
      nextIndex = _queueIndex + 1;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      nextIndex = 0;
    } else if (autoplay && !_shuffle && _appendSuggestions()) {
      // Autoplay only widens the queue when shuffle is OFF. With shuffle on,
      // "next" means "another song from THIS queue" — appending same-artist
      // suggestions played songs the user never queued, which is what "why is
      // it playing outside the queue?" was.
      nextIndex = _queueIndex + 1;
    }

    if (nextIndex == null) {
      // Nothing left to play. Stop cleanly at the start of the last track
      // so pressing play replays it.
      if (fromTrackEnd) {
        _isPlaying = false;
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration.zero);
        notifyListeners();
      }
      return;
    }

    // With the queue loaded natively, moving between songs is a plain
    // engine seek to a (translated) index — no reload. If the seek can't
    // land (target outside the window, autoplay appended songs the native
    // playlist doesn't know about), fall back to the full reload path,
    // which rebuilds the window around the target.
    if (_nativeInSync && !_isLoading) {
      final native = _nativeIndexOf(nextIndex);
      if (native != null) {
        try {
          await _audioPlayer.seek(Duration.zero, index: native);
          unawaited(_slideNativeWindow(nextIndex));
          return;
        } catch (_) {
          // Fall through to the full reload.
        }
      }
    }
    await _jumpTo(nextIndex, startPlaying: true);
  }

  // --- public API ------------------------------------------------------

  /// Plays [song], optionally from [startAt] (used by "tap a lyric line to
  /// jump there"). With no [queue], an already-queued song just becomes the
  /// current one (keeping the queue intact); otherwise it plays on its own.
  Future<void> playSong(Song song, {List<Song>? queue, Duration? startAt}) async {
    if (queue != null) {
      _queue = List.of(queue);
    } else if (!_queue.any((s) => s.id == song.id)) {
      _queue = [song];
    }
    var index = _queue.indexWhere((s) => s.id == song.id);
    if (index < 0) {
      _queue = [..._queue, song];
      index = _queue.length - 1;
    }
    // Already the current, loaded track: a "play" that only wanted a
    // position applied must not restart it from zero.
    if (index == _queueIndex && _currentSong?.id == song.id && startAt != null && !_needsReload) {
      if (!_isPlaying) await togglePlayPause();
      await seekTo(startAt);
      return;
    }
    // The queue is already loaded natively and this song is in the window:
    // a plain seek to its translated index — no rebuild, no interruption of
    // the notification's playlist view.
    if (_nativeInSync && !_isLoading) {
      final native = _nativeIndexOf(index);
      if (native != null) {
        try {
          await _audioPlayer.seek(Duration.zero, index: native);
          if (startAt != null && startAt > Duration.zero) await _audioPlayer.seek(startAt);
          unawaited(_slideNativeWindow(index));
          return;
        } catch (_) {
          // Fall through to the full reload.
        }
      }
    }
    await _jumpTo(index, startPlaying: true, initialPosition: startAt);
  }

  Future<void> togglePlayPause() async {
    final song = _currentSong;
    if (song == null) return;
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
      await _audioPlayer.pause();
      return;
    }
    // Nothing loaded behind this song (the first play, a failed load, or a
    // track switch interrupted mid-flight) — a resume press has to actually
    // (re)load it, otherwise the icon flips over silence.
    if (_needsReload || _loadedSongId != song.id) {
      await _jumpTo(_queueIndex, startPlaying: true);
      return;
    }
    _isPlaying = true;
    notifyListeners();
    if (_audioPlayer.processingState == ProcessingState.completed) {
      await _audioPlayer.seek(Duration.zero);
    }
    try {
      await _startPlayback();
    } catch (_) {
      // Surfaced through the player-state stream instead of throwing into a
      // button callback.
    }
  }

  /// Plays [song], or pauses it if it's already the current track.
  ///
  /// This is what a tap on a song card should do: without it, tapping a card
  /// for the track you're already listening to reloads it from the beginning,
  /// which reads as the app restarting your song for no reason.
  Future<void> playOrToggle(Song song, {List<Song>? queue}) async {
    if (_currentSong?.id == song.id) {
      await togglePlayPause();
      return;
    }
    await playSong(song, queue: queue);
  }

  Future<void> seekTo(Duration target) async {
    final song = _currentSong;
    if (song == null) return;
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    final total = duration;
    if (total > Duration.zero && t > total) t = total;

    final loadedForCurrent = !_isLoading && _loadedSongId == song.id;
    if (!loadedForCurrent) {
      // There's nothing loaded to seek yet. Remember it and apply it when
      // this song's load lands (see _jumpTo) — this is what makes
      // "tap a lyric line on a track that's still starting" work.
      _pendingSeek = t;
      _lastNotifiedSecond = -1;
      notifyListeners();
      return;
    }

    await _audioPlayer.seek(t);
    _lastNotifiedSecond = -1;
    notifyListeners();
  }

  Future<void> seekToProgress(double value) {
    if (_currentSong == null) return Future.value();
    return seekTo(Duration(milliseconds: (duration.inMilliseconds * value).round()));
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
    // The native playlist must shuffle too: with a whole queue loaded, the
    // engine itself decides what plays next (that is what makes track-end and
    // notification skips work), so an app-only flag would be ignored at
    // exactly the moment shuffle matters.
    unawaited(_syncNativeModes());
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    notifyListeners();
    unawaited(_syncNativeModes());
  }

  /// Mirrors the app's shuffle/repeat onto the native playlist. Without this,
  /// the engine advances linearly at every track end — repeat-one never loops
  /// and shuffle never randomises — because with a playlist loaded just_audio
  /// auto-advances on its own instead of reporting `completed` per track.
  Future<void> _syncNativeModes() async {
    if (!_nativeQueueActive) return;
    try {
      await _audioPlayer.setLoopMode(switch (_repeatMode) {
        PlayerRepeatMode.off => LoopMode.off,
        PlayerRepeatMode.all => LoopMode.all,
        PlayerRepeatMode.one => LoopMode.one,
      });
      await _audioPlayer.setShuffleModeEnabled(_shuffle);
    } catch (_) {
      // Single-load path in use; nothing to mirror.
    }
  }

  /// Manual skip. Always moves on (even under repeat-one), starts playback
  /// if paused, and — with autoplay on — keeps going past the end of the
  /// queue instead of doing nothing.
  Future<void> next() async {
    // Native queue: the engine owns the order (it honours shuffle and loop),
    // so the in-app button must ask it, not run the app's own index math —
    // otherwise the two disagree and skips jump against what's playing.
    if (_nativeInSync && !_isLoading) {
      try {
        await _audioPlayer.seekToNext();
        if (!_isPlaying) await _startPlayback();
        return;
      } catch (_) {
        // At the boundary (no next) or mid-load: fall through to app logic.
      }
    }
    await _advance(fromTrackEnd: false);
  }

  /// Previous: restart the current track once it's actually been playing
  /// for a moment, otherwise step back one. The engine's position is only
  /// trusted when it's reporting *this* song — right after a switch it
  /// still holds the previous track's position, which used to make
  /// "previous" restart the track the user had just moved to instead of
  /// going back.
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    final song = _currentSong;
    final loadedForCurrent = song != null && !_isLoading && _loadedSongId == song.id;
    if (loadedForCurrent && position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    if (_queueIndex == 0) {
      if (loadedForCurrent) await seekTo(Duration.zero);
      return;
    }
    // Native queue: step back through the engine so shuffle/loop order stays
    // consistent with what the notification shows and plays.
    if (_nativeInSync && !_isLoading) {
      try {
        await _audioPlayer.seekToPrevious();
        if (!_isPlaying) await _startPlayback();
        return;
      } catch (_) {
        // Fall through to app logic.
      }
    }
    await _jumpTo(_queueIndex - 1, startPlaying: true);
  }

  void playNext(Song song) {
    if (_queue.isEmpty) {
      playSong(song);
      return;
    }
    _queue.insert(_queueIndex + 1, song);
    _invalidateNativeQueue();
    notifyListeners();
  }

  void addToQueue(Song song) {
    if (_queue.isEmpty) {
      playSong(song);
      return;
    }
    _queue.add(song);
    _invalidateNativeQueue();
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    _invalidateNativeQueue();
    if (_queue.isEmpty) {
      _currentSong = null;
      _isPlaying = false;
      _loadedSongId = null;
      _needsReload = false;
      await _audioPlayer.stop();
      notifyListeners();
      return;
    }
    if (index < _queueIndex) {
      _queueIndex--;
      notifyListeners();
    } else if (index == _queueIndex) {
      final newIndex = _queueIndex >= _queue.length ? _queue.length - 1 : _queueIndex;
      await _jumpTo(newIndex, startPlaying: _isPlaying);
    } else {
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0 || newIndex >= _queue.length) return;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _invalidateNativeQueue();
    if (oldIndex == _queueIndex) {
      _queueIndex = newIndex;
    } else if (oldIndex < _queueIndex && newIndex >= _queueIndex) {
      _queueIndex--;
    } else if (oldIndex > _queueIndex && newIndex <= _queueIndex) {
      _queueIndex++;
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue = _currentSong == null ? [] : [_currentSong!];
    _queueIndex = 0;
    _invalidateNativeQueue();
    notifyListeners();
  }

  /// Any direct _queue mutation invalidates the loaded native playlist: the
  /// sync guards then route skips through the full-reload path, which rebuilds
  /// the native source from the new queue. Without this the engine advanced in
  /// the OLD order while the app showed the new one.
  void _invalidateNativeQueue() {
    _nativeQueueIds = null;
    _nativeSource = null;
  }

  MediaItem _mediaItemFor(Song song, NowPlayingMetadata? meta) => MediaItem(
        id: song.id,
        album: meta?.albumTitle ?? song.artist,
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        artUri: meta?.artUri,
      );

  /// Slides the native window so the playhead never runs off the loaded
  /// edge — runtime insert/remove on the live playlist, which does not
  /// interrupt playback (that's the point of the window: gapless keeps
  /// working on huge queues). Failures are harmless: an out-of-window jump
  /// simply rebuilds via [_jumpTo].
  Future<void> _slideNativeWindow(int appIndex) async {
    final source = _nativeSource;
    final ids = _nativeQueueIds;
    if (source == null || ids == null || _queue.length <= _kNativeWindowFullLimit) return;
    try {
      final native = _nativeIndexOf(appIndex);
      if (native == null) return;
      final windowStartApp = appIndex - native; // app index of ids.first

      // Append ahead when the playhead nears the tail.
      if (native >= ids.length - 6) {
        var appended = 0;
        for (var i = windowStartApp + ids.length; i < _queue.length && appended < _kNativeWindowAfter; i++) {
          final qSong = _queue[i];
          final qSource = audioSourceResolver?.call(qSong);
          if (qSource == null) break;
          await source.insert(
            ids.length,
            (qSource.startsWith('http://') || qSource.startsWith('https://'))
                ? AudioSource.uri(Uri.parse(qSource), tag: _mediaItemFor(qSong, metadataResolver?.call(qSong)))
                : AudioSource.file(qSource, tag: _mediaItemFor(qSong, metadataResolver?.call(qSong))),
          );
          ids.add(qSong.id);
          appended++;
        }
        // Trim the head so the window stays bounded — never the playing side.
        while (ids.length > _kNativeWindowBefore + 1 + _kNativeWindowAfter && _nativeIndexOf(appIndex)! > _kNativeWindowBefore) {
          await source.removeAt(0);
          ids.removeAt(0);
        }
        return;
      }

      // Prepend behind when the playhead nears the head.
      if (native <= 5 && windowStartApp > 0) {
        var prepended = 0;
        for (var i = windowStartApp - 1; i >= 0 && prepended < _kNativeWindowBefore; i--) {
          final qSong = _queue[i];
          final qSource = audioSourceResolver?.call(qSong);
          if (qSource == null) break;
          await source.insert(
            0,
            (qSource.startsWith('http://') || qSource.startsWith('https://'))
                ? AudioSource.uri(Uri.parse(qSource), tag: _mediaItemFor(qSong, metadataResolver?.call(qSong)))
                : AudioSource.file(qSource, tag: _mediaItemFor(qSong, metadataResolver?.call(qSong))),
          );
          ids.insert(0, qSong.id);
          prepended++;
        }
        // Trim the tail.
        while (ids.length > _kNativeWindowBefore + 1 + _kNativeWindowAfter && _nativeIndexOf(appIndex)! < ids.length - 1 - _kNativeWindowAfter) {
          await source.removeAt(ids.length - 1);
          ids.removeLast();
        }
      }
    } catch (_) {
      // Window slide failed: the next out-of-window jump rebuilds cleanly.
    }
  }

  /// Restores a queue and position saved from a previous session —
  /// Settings → Behavior → "Remember queue"/"Resume playback". Loads
  /// [index]'s song *paused* (never auto-starts playback on app open) and
  /// seeks to [position] as part of that same load, so the seek can't land
  /// on the wrong track. See AppState.takeSavedQueue, which is what
  /// actually reads the saved data back out of storage.
  Future<void> restoreQueue(List<Song> queue, int index, Duration position) async {
    if (queue.isEmpty) return;
    _queue = List.of(queue);
    final clamped = index.clamp(0, _queue.length - 1);
    await _jumpTo(clamped, startPlaying: false, initialPosition: position);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _currentIndexSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- PlaybackEngine (§6) ---------------------------------------------
  // Thin adapters over the methods above, so the app has one named contract a
  // native Media3 engine could satisfy later without a screen changing. Nothing
  // here promises output fidelity: quality is a request ([SourcePolicy]), and
  // what the device does with the samples is reported separately and honestly
  // ([getOutputDiagnostics]).

  @override
  Future<void> setQueue(List<Song> items, {required int startIndex, Duration? startAt}) async {
    if (items.isEmpty) return;
    final index = startIndex.clamp(0, items.length - 1);
    await playSong(items[index], queue: items, startAt: startAt);
  }

  @override
  Future<void> play() async {
    if (!_isPlaying) await togglePlayPause();
  }

  @override
  Future<void> pause() async {
    if (_isPlaying) await togglePlayPause();
  }

  @override
  Future<void> seek(Duration position) => seekTo(position);

  @override
  void setSourcePolicy(SourcePolicy policy) {
    if (_sourcePolicy.quality == policy.quality && _sourcePolicy.allowServerFallback == policy.allowServerFallback) return;
    _sourcePolicy = policy;
    notifyListeners();
  }

  @override
  void setProcessingOptions(ProcessingOptions options) {
    if (_processingOptions.replayGainEnabled == options.replayGainEnabled &&
        _processingOptions.equalizerEnabled == options.equalizerEnabled &&
        _processingOptions.crossfadeEnabled == options.crossfadeEnabled) {
      return;
    }
    _processingOptions = options;
    notifyListeners();
  }

  @override
  PlaybackStateSnapshot getPlaybackState() => PlaybackStateSnapshot(
        currentSong: _currentSong,
        queueIndex: _queueIndex,
        queueLength: _queue.length,
        isPlaying: _isPlaying,
        isBuffering: isBuffering,
        position: position,
        duration: duration,
        hasEngineDuration: hasEngineDuration,
        shuffle: _shuffle,
        repeatMode: _repeatMode,
      );

  @override
  SourceInfo getSourceInfo() {
    final song = _currentSong;
    if (song == null) return const SourceInfo();
    final info = song.audioInfo;
    return SourceInfo(
      kind: song.isLocal ? SourceKind.local : SourceKind.navidrome,
      codec: info.hasFormat ? info.format : null,
      sampleRateHz: info.hasSampleRate ? info.sampleRateHz : null,
      bitDepth: info.hasBitDepth ? info.bitDepth : null,
      channels: info.hasChannels ? _channelCount(info.channels) : null,
      // A capped policy means the server was *asked* to transcode. Whether it
      // actually did can only be known from a response, so this stays unknown
      // until a probe has seen one.
      streamMode: _sourcePolicy.isOriginal ? StreamMode.unknown : StreamMode.transcoded,
      policy: _sourcePolicy,
    );
  }

  @override
  AudioDiagnostics? getOutputDiagnostics() {
    final song = _currentSong;
    if (song == null) return null;
    final resolver = diagnosticsResolver;
    if (resolver != null) return resolver(song, _sourcePolicy, _processingOptions);
    // No resolver wired (nothing playing from the app shell, or a unit test):
    // report the source facts and leave route/capability unknown rather than
    // inventing them.
    return AudioDiagnostics.forSong(song: song, policy: _sourcePolicy, processing: _processingOptions);
  }

  int? _channelCount(String label) {
    final lower = label.toLowerCase().trim();
    if (lower == 'mono') return 1;
    if (lower == 'stereo') return 2;
    final match = RegExp(r'^(\d+)\s*ch').firstMatch(lower);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

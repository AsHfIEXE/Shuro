// Chaos-harness fake for just_audio's platform interface (v4.6.0).
//
// This is TEST TOOLING ONLY — it never ships in the app. It sits where the
// real Android/iOS/web platform sits, so the REAL just_audio player and the
// REAL PlayerController run their full logic on top of it. Controllable
// latency and injectable load failures let the chaos driver reproduce race
// conditions that need specific timings.
//
// The fake keeps one source of truth for position: a stopwatch + base
// offset, so position advances in real time while "playing" and freezes on
// pause/stop — close enough to native behaviour for invariant checking.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Global knobs for every fake player created by [FakeJustAudioPlatform].
class FakeAudioConfig {
  FakeAudioConfig({
    this.latency = const Duration(milliseconds: 2),
    this.defaultDuration = const Duration(seconds: 180),
  });

  /// Artificial delay added to every platform call (load/play/pause/seek),
  /// exposing completions that land after newer commands.
  final Duration latency;

  /// Duration reported for each loaded source.
  final Duration defaultDuration;
}

class FakeJustAudioPlatform extends JustAudioPlatform {
  final FakeAudioConfig config;
  final Map<String, FakeAudioPlayerPlatform> players = {};

  FakeJustAudioPlatform({FakeAudioConfig? config})
      : config = config ?? FakeAudioConfig();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakeAudioPlayerPlatform(request.id, config);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(String id, this.config) : super(id) {
    _events = StreamController<PlaybackEventMessage>.broadcast();
  }

  final FakeAudioConfig config;
  late final StreamController<PlaybackEventMessage> _events;

  final Stopwatch _clock = Stopwatch();
  Duration _base = Duration.zero;
  double _speed = 1.0;
  bool _playing = false;
  int _loads = 0;
  ProcessingStateMessage _state = ProcessingStateMessage.idle;

  /// Set by the chaos driver to make exactly one load fail.
  bool failNextLoad = false;
  int injectedFailures = 0;

  Duration? _duration;

  Duration get position {
    var p = _base;
    if (_playing && _clock.isRunning) {
      p += Duration(
          microseconds: (_clock.elapsedMicroseconds * _speed).round());
    }
    final d = _duration;
    if (d != null && p > d) p = d;
    if (p < Duration.zero) p = Duration.zero;
    return p;
  }

  void _emit() {
    if (_events.isClosed) return;
    _events.add(PlaybackEventMessage(
      processingState: _state,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition: _duration ?? Duration.zero,
      duration: _duration,
      icyMetadata: null,
      currentIndex: _duration == null ? null : 0,
      androidAudioSessionId: null,
    ));
  }

  Future<void> _delay() => Future<void>.delayed(config.latency);

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    await _delay();
    if (failNextLoad) {
      failNextLoad = false;
      injectedFailures++;
      _state = ProcessingStateMessage.idle;
      _playing = false;
      _clock.stop();
      _emit();
      throw PlatformException(code: 'chaos_injected_load_failure');
    }
    _loads++;
    _duration = config.defaultDuration + Duration(seconds: 7 * _loads);
    _base = request.initialPosition ?? Duration.zero;
    _clock
      ..reset()
      ..start();
    if (!_playing) _clock.stop();
    _state = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _delay();
    _playing = true;
    if (!_clock.isRunning) _clock.start();
    _state = ProcessingStateMessage.ready;
    _emit();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    await _delay();
    _base = position;
    _playing = false;
    _clock.stop();
    _emit();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    await _delay();
    _base = request.position ?? Duration.zero;
    _clock
      ..reset()
      ..start();
    if (!_playing) _clock.stop();
    _emit();
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    await _delay();
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _delay();
    _speed = request.speed;
    _emit();
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    await _delay();
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
      SetSkipSilenceRequest request) async {
    await _delay();
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _delay();
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    await _delay();
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
      SetShuffleOrderRequest request) async {
    await _delay();
    return SetShuffleOrderResponse();
  }

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
      SetPreferredPeakBitRateRequest request) async {
    return SetPreferredPeakBitRateResponse();
  }

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
      SetAllowsExternalPlaybackRequest request) async {
    return SetAllowsExternalPlaybackResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _state = ProcessingStateMessage.idle;
    _playing = false;
    _clock.stop();
    _emit();
    await _events.close();
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    throw UnimplementedError('chaos fake: concatenating API not used by Shuro');
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    throw UnimplementedError('chaos fake: concatenating API not used by Shuro');
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    throw UnimplementedError('chaos fake: concatenating API not used by Shuro');
  }

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(
      AudioEffectSetEnabledRequest request) async {
    return AudioEffectSetEnabledResponse();
  }

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
      AndroidEqualizerGetParametersRequest request) async {
    throw UnimplementedError('chaos fake: equalizer not used by Shuro');
  }

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
      AndroidEqualizerBandSetGainRequest request) async {
    throw UnimplementedError('chaos fake: equalizer not used by Shuro');
  }

  @override
  Future<SetWebCrossOriginResponse> setWebCrossOrigin(
      SetWebCrossOriginRequest request) async {
    return SetWebCrossOriginResponse();
  }

  @override
  Future<SetWebSinkIdResponse> setWebSinkId(SetWebSinkIdRequest request) async {
    return SetWebSinkIdResponse();
  }
}

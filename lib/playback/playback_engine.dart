import '../models/download_state.dart';
import '../models/song.dart';
import 'audio_diagnostics.dart';

/// The app-owned playback contract.
///
/// This is §6 of the playback plan made real: widgets and state talk to this
/// interface, and **no** widget imports `just_audio`/`ExoPlayer` types. Today
/// `PlayerController` is the implementation (backed by just_audio); a native
/// Media3 engine can replace it without a screen changing, which is the whole
/// point of having the seam before the spike rather than after it.
///
/// Deliberately **not** on this interface: anything that promises output
/// fidelity. Source quality is a request ([SourcePolicy]); what the device
/// does with the samples is reported separately and honestly
/// ([AudioDiagnostics]) — see §1 and §10 of the plan.
abstract class PlaybackEngine {
  /// Replaces the queue and starts at [startIndex] (optionally at [startAt]).
  Future<void> setQueue(List<Song> items, {required int startIndex, Duration? startAt});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();

  /// What to ask the server for. Not an approximation via a high bitrate cap:
  /// see [SourcePolicy] and [streamParametersFor].
  void setSourcePolicy(SourcePolicy policy);

  /// ReplayGain/EQ/crossfade state, kept separate from source quality because
  /// processing changes PCM without making the *source* any less original
  /// (§4.2).
  void setProcessingOptions(ProcessingOptions options);

  /// Typed snapshot — never a raw player object.
  PlaybackStateSnapshot getPlaybackState();

  /// What is being played and where it came from.
  SourceInfo getSourceInfo();

  /// Everything known about source, decoder, route and capability — with
  /// `unknown` wherever it isn't known (§6, §10). Null when no track is loaded:
  /// there is no honest diagnostics object for "nothing is playing" that
  /// wouldn't have to claim a source kind.
  AudioDiagnostics? getOutputDiagnostics();
}

/// What Shuro asks Navidrome for when it resolves a track.
///
/// [quality] maps onto the server's own transcode parameters; [original] means
/// "the file's own bytes" and is sent as `format=raw` **alone**. The plan is
/// explicit that Original must not be approximated by a very high
/// `maxBitRate` — and Navidrome's own `ResolveRequest`
/// (`core/stream/legacy_client.go`) returns immediately on `format=raw`,
/// before any bitrate/format decision, which is why that one signal is enough.
class SourcePolicy {
  final StreamingQuality quality;

  /// If the server cannot serve what was asked for, may it hand back a
  /// transcode instead? Off by default: §3.3 and §7/Phase 1 both require that
  /// a silent downgrade never happens, only an explicitly permitted one.
  final bool allowServerFallback;

  const SourcePolicy({this.quality = StreamingQuality.original, this.allowServerFallback = false});

  bool get isOriginal => quality == StreamingQuality.original;

  @override
  String toString() => 'SourcePolicy(${quality.name}, fallback: $allowServerFallback)';
}

/// Processing that changes PCM *after* the source was fetched. Kept as its own
/// axis so the UI can say "source is original, but ReplayGain is applied"
/// rather than conflating the two (§4.2).
class ProcessingOptions {
  final bool replayGainEnabled;
  final bool equalizerEnabled;
  final bool crossfadeEnabled;

  const ProcessingOptions({
    this.replayGainEnabled = false,
    this.equalizerEnabled = false,
    this.crossfadeEnabled = false,
  });

  static const ProcessingOptions none = ProcessingOptions();

  bool get anyEnabled => replayGainEnabled || equalizerEnabled || crossfadeEnabled;
}

/// A typed view of playback state.
class PlaybackStateSnapshot {
  final Song? currentSong;
  final int queueIndex;
  final int queueLength;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;

  /// The engine's own decoded duration when it has one, otherwise the tagged
  /// duration.
  final Duration duration;

  /// True when [duration] came from the engine rather than the song's tags.
  final bool hasEngineDuration;
  final bool shuffle;
  final PlayerRepeatMode repeatMode;

  const PlaybackStateSnapshot({
    this.currentSong,
    this.queueIndex = 0,
    this.queueLength = 0,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.hasEngineDuration = false,
    this.shuffle = false,
    this.repeatMode = PlayerRepeatMode.off,
  });
}

/// What is being played, and where the bytes came from — the "source" half of
/// the diagnostics split. Container/format facts come from the server's own
/// tag scan; whether the *stream* was transcoded is a separate question that
/// only a response can answer ([StreamMode.unknown] until one does).
class SourceInfo {
  /// Null when nothing is loaded — "unknown" is the only honest answer there.
  final SourceKind? kind;
  final String? codec;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  final StreamMode streamMode;
  final SourcePolicy policy;

  const SourceInfo({
    this.kind,
    this.codec,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
    this.streamMode = StreamMode.unknown,
    this.policy = const SourcePolicy(),
  });
}

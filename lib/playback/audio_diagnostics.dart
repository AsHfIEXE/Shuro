import '../models/song.dart';
import '../models/download_state.dart';
import 'audio_capability.dart';
import 'playback_engine.dart';

/// The diagnostics model from §6 of the playback plan, plus the request-policy
/// check from §3.1.
///
/// One rule runs through this whole file, and it is the rule the plan is most
/// insistent about (§1, §4.3, §10): **a source file's metadata is never
/// presented as a fact about the output path.** Every field that can't be
/// established is `null` or `unknown`, and the UI is expected to render it that
/// way rather than filling the gap with something plausible.

enum SourceKind { local, navidrome }

/// Assembles diagnostics for a song from everything the app knows: the song's
/// own reported metadata, the last capability answer, the request check and (if
/// one has been run) a stream probe result.
///
/// Wired from app.dart, the same way the audio-source and metadata resolvers
/// are — so [PlayerController] can answer [PlaybackEngine.getOutputDiagnostics]
/// without ever importing AppState (playback plan §6).
typedef AudioDiagnosticsResolver = AudioDiagnostics Function(Song song, SourcePolicy policy, ProcessingOptions processing);

/// Whether the bytes that arrived are the file's own, or the server's
/// re-encode. `unknown` is the honest default until a response proves it.
enum StreamMode { original, transcoded, unknown }

enum RouteKind { builtIn, wired, bluetooth, usb, other, unknown }

/// A three-state capability answer. `unsupported` and `unknown` are different
/// claims and must stay distinguishable: "the platform said no" is evidence,
/// "we couldn't ask" is not (§4.3).
enum CapabilityState { supported, unsupported, unknown }

class SourceDiagnostics {
  final SourceKind sourceKind;
  final String? codec;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  final StreamMode streamMode;
  final SourcePolicy policy;

  /// Whether the app's own request matched [policy] — e.g. that Original really
  /// did ask for `format=raw` and didn't sneak in a bitrate cap. Null when there
  /// was no request to check (a local file).
  final SourceRequestCheck? requestCheck;

  const SourceDiagnostics({
    required this.sourceKind,
    this.codec,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
    this.streamMode = StreamMode.unknown,
    this.policy = const SourcePolicy(),
    this.requestCheck,
  });
}

class DecoderDiagnostics {
  final String? name;
  final String? outputEncoding;

  const DecoderDiagnostics({this.name, this.outputEncoding});

  static const DecoderDiagnostics unknown = DecoderDiagnostics();
}

class RouteDiagnostics {
  final RouteKind kind;
  final String? deviceLabel;

  const RouteDiagnostics({this.kind = RouteKind.unknown, this.deviceLabel});

  static const RouteDiagnostics unknown = RouteDiagnostics();
}

/// Capability is a *request/answer* pair, never a guarantee (§5.1, §10):
/// [highResolutionPcmRequested] and [bitPerfectUsbRequested] record what was
/// attempted, while [directPlayback] records what the platform reported.
class CapabilityDiagnostics {
  final CapabilityState directPlayback;
  final bool highResolutionPcmRequested;
  final bool bitPerfectUsbRequested;

  /// How the platform said it would play it, when it distinguished: offload and
  /// bitstream passthrough are the modes that bypass the framework's mixer.
  final DirectPlaybackMode directPlaybackMode;

  /// Whether the platform accepted the requested configuration, when it says.
  final bool? highResolutionPcmAccepted;
  final bool? bitPerfectUsbAccepted;

  /// Why the answer is what it is, when the platform explains itself (e.g. "no
  /// direct-playback query before API 33"). An `unknown` that explains itself
  /// reads as an honest gap rather than a bug.
  final String? reason;

  const CapabilityDiagnostics({
    this.directPlayback = CapabilityState.unknown,
    this.directPlaybackMode = DirectPlaybackMode.unknown,
    this.highResolutionPcmRequested = false,
    this.bitPerfectUsbRequested = false,
    this.highResolutionPcmAccepted,
    this.bitPerfectUsbAccepted,
    this.reason,
  });

  static const CapabilityDiagnostics unknown = CapabilityDiagnostics();
}

class ProcessingDiagnostics {
  final bool replayGainEnabled;
  final bool equalizerEnabled;
  final bool crossfadeEnabled;

  const ProcessingDiagnostics({
    this.replayGainEnabled = false,
    this.equalizerEnabled = false,
    this.crossfadeEnabled = false,
  });

  bool get anyEnabled => replayGainEnabled || equalizerEnabled || crossfadeEnabled;

  factory ProcessingDiagnostics.from(ProcessingOptions options) => ProcessingDiagnostics(
        replayGainEnabled: options.replayGainEnabled,
        equalizerEnabled: options.equalizerEnabled,
        crossfadeEnabled: options.crossfadeEnabled,
      );
}

class AudioDiagnostics {
  final SourceDiagnostics source;
  final DecoderDiagnostics decoder;
  final RouteDiagnostics route;
  final CapabilityDiagnostics capability;
  final ProcessingDiagnostics processing;

  const AudioDiagnostics({
    required this.source,
    this.decoder = const DecoderDiagnostics(),
    this.route = const RouteDiagnostics(),
    this.capability = const CapabilityDiagnostics(),
    this.processing = const ProcessingDiagnostics(),
  });

  /// Builds diagnostics for [song] from the facts the app actually has.
  ///
  /// [capability] is whatever the platform reported (or left unknown);
  /// [probeStreamMode] is set only once a response has been inspected. Nothing
  /// in here is inferred from the source's tags, so a 24/96 FLAC that the phone
  /// resamples still shows `24-bit / 96000 Hz` under *source* and `unknown`
  /// under capability — which is the whole point of the split.
  static AudioDiagnostics forSong({
    required Song song,
    required SourcePolicy policy,
    required ProcessingOptions processing,
    SourceRequestCheck? requestCheck,
    CapabilityDiagnostics capability = const CapabilityDiagnostics(),
    DecoderDiagnostics decoder = const DecoderDiagnostics(),
    RouteDiagnostics route = const RouteDiagnostics(),
    StreamMode probeStreamMode = StreamMode.unknown,
  }) {
    final info = song.audioInfo;
    return AudioDiagnostics(
      source: SourceDiagnostics(
        sourceKind: song.isLocal ? SourceKind.local : SourceKind.navidrome,
        codec: info.hasFormat ? info.format : null,
        sampleRateHz: info.sampleRateHz,
        bitDepth: info.bitDepth,
        channels: _channelsFromLabel(info.channels),
        streamMode: policy.isOriginal == false ? StreamMode.transcoded : probeStreamMode,
        policy: policy,
        requestCheck: requestCheck,
      ),
      decoder: decoder,
      route: route,
      capability: capability,
      processing: ProcessingDiagnostics.from(processing),
    );
  }

  /// `AudioInfo.channels` is a display label ("Stereo", "Mono", "6 ch"); this
  /// turns the ones we can be sure about back into a count, and leaves the rest
  /// null rather than guessing.
  static int? _channelsFromLabel(String label) {
    final lower = label.toLowerCase().trim();
    if (lower == 'mono') return 1;
    if (lower == 'stereo') return 2;
    final match = RegExp(r'^(\d+)\s*ch').firstMatch(lower);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }}

/// Result of checking the request we actually sent against the policy we meant
/// to apply (§7, Phase 1 exit gate: "the original-source option does not
/// accidentally request a bitrate-limited stream").
class SourceRequestCheck {
  final bool matchesPolicy;
  final String detail;

  const SourceRequestCheck({required this.matchesPolicy, required this.detail});

  static const SourceRequestCheck notApplicable = SourceRequestCheck(matchesPolicy: true, detail: 'No server request to check.');
}

/// The query parameters [policy] requires. This is the mapping the plan asks
/// for in §3.1: explicit, in one place, and testable without a server.
Map<String, String> streamParametersFor(SourcePolicy policy) {
  switch (policy.quality) {
    case StreamingQuality.original:
      // `format=raw` and nothing else. Navidrome (core/stream/legacy_client.go)
      // returns `Format: "raw"` immediately for this value, before any
      // transcode decision — so one explicit signal is sufficient, and adding a
      // bitrate parameter here would be exactly the approximation §3.1 forbids.
      return const {'format': 'raw'};
    case StreamingQuality.high:
      return const {'maxBitRate': '320'};
    case StreamingQuality.medium:
      return const {'maxBitRate': '160'};
    case StreamingQuality.low:
      return const {'maxBitRate': '96'};
  }
}

/// Inspects a stream URL the app built and reports whether it actually asks for
/// what [policy] intends.
///
/// This exists because "Original" is only as good as the request behind it: a
/// URL that carries both `format=raw` and a `maxBitRate` cap, or a capped mode
/// that forgot its parameter, silently changes what you hear. Checking the real
/// URL — not the intent — is what makes that visible.
SourceRequestCheck verifyStreamUrl(String? url, SourcePolicy policy) {
  if (url == null || url.isEmpty) {
    return const SourceRequestCheck(matchesPolicy: false, detail: 'No stream URL was produced for this track.');
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return const SourceRequestCheck(matchesPolicy: true, detail: 'Local file — no server request is involved.');
  }

  Map<String, String> params;
  try {
    params = Uri.parse(url).queryParameters;
  } catch (_) {
    return const SourceRequestCheck(matchesPolicy: false, detail: 'The stream URL could not be parsed.');
  }

  final format = params['format'];
  final maxBitRate = params['maxBitRate'];

  if (policy.isOriginal) {
    if (format != 'raw') {
      return SourceRequestCheck(
        matchesPolicy: false,
        detail: 'Original was requested but the URL does not carry format=raw — the server may transcode this stream.',
      );
    }
    if (maxBitRate != null && maxBitRate != '0') {
      return SourceRequestCheck(
        matchesPolicy: false,
        detail: 'Original was requested but the URL also caps the bitrate at $maxBitRate kbps, which can force a transcode.',
      );
    }
    return const SourceRequestCheck(matchesPolicy: true, detail: 'Original requested as format=raw with no bitrate cap.');
  }

  final expected = streamParametersFor(policy)['maxBitRate'];
  if (format == 'raw') {
    return SourceRequestCheck(
      matchesPolicy: false,
      detail: 'A capped quality was requested but the URL asks for format=raw, so the cap will have no effect.',
    );
  }
  if (expected != null && maxBitRate != expected) {
    return SourceRequestCheck(
      matchesPolicy: false,
      detail: 'Expected a $expected kbps cap for ${policy.quality.label}, but the URL carries ${maxBitRate ?? "no cap"}.',
    );
  }
  return SourceRequestCheck(matchesPolicy: true, detail: 'Capped request matches the ${policy.quality.label} policy ($expected kbps).');
}

/// A source of the audio attributes Shuro plays music with — used by the native
/// capability bridge (see audio_capability.dart) so the query matches the real
/// playback configuration rather than an arbitrary one (§5.1 rule 1).
Map<String, dynamic> musicAudioAttributes() => const {
      'usage': 'media',
      'contentType': 'music',
    };

/// Convenience for logs/diagnostics: a compact description of the diagnostics
/// state, with `unknown` where the app genuinely doesn't know. Credentials are
/// never included — stream URLs are deliberately not rendered here (§6: "do not
/// put credentials in stream URLs or diagnostics logs").
String describeDiagnostics(AudioDiagnostics diagnostics) {
  final source = diagnostics.source;
  return [
    'source=${source.sourceKind.name}',
    'mode=${source.streamMode.name}',
    'codec=${source.codec ?? "unknown"}',
    'rate=${source.sampleRateHz ?? "unknown"}',
    'depth=${source.bitDepth ?? "unknown"}',
    'channels=${source.channels ?? "unknown"}',
    'route=${diagnostics.route.kind.name}',
    'directPlayback=${diagnostics.capability.directPlayback.name}',
  ].join(' ');
}

import 'package:flutter/services.dart';

import 'audio_diagnostics.dart';

/// The decoded PCM format to ask the platform about.
///
/// Direct-playback support on Android is per-format, so a query without a format
/// can only ever answer "unknown" — which is exactly what the native half
/// returns when this is omitted.
///
/// [forCurrentEngine] builds the format the *current* engine actually outputs:
/// 16-bit PCM at the source's own sample rate and channel count, because
/// just_audio/ExoPlayer decodes to 16-bit PCM by default. When Phase 4 configures
/// Media3's high-resolution PCM output, this is the one place that changes to
/// ask about 24-bit — and the answer will then describe the format the app
/// genuinely intends to play.
class AudioQueryFormat {
  final int sampleRateHz;
  final int channelCount;
  final PcmEncoding encoding;

  const AudioQueryFormat({
    required this.sampleRateHz,
    required this.channelCount,
    this.encoding = PcmEncoding.pcm16,
  });

  /// The format to query for, given what the server reported about a track.
  /// Falls back to 48 kHz stereo — a default worth *asking* about, never a
  /// default worth reporting as fact.
  factory AudioQueryFormat.forCurrentEngine({int? sampleRateHz, int? channelCount, PcmEncoding encoding = PcmEncoding.pcm16}) {
    final rate = (sampleRateHz != null && sampleRateHz > 0) ? sampleRateHz : 48000;
    final channels = (channelCount != null && channelCount > 0) ? channelCount.clamp(1, 2) : 2;
    return AudioQueryFormat(sampleRateHz: rate, channelCount: channels, encoding: encoding);
  }

  Map<String, dynamic> toChannelArguments() => {
        'sampleRateHz': sampleRateHz,
        'channelCount': channelCount,
        'pcmEncoding': encoding.wireName,
      };
}

enum PcmEncoding {
  pcm16,
  pcm24,
  pcm32float;

  String get wireName => switch (this) {
        PcmEncoding.pcm16 => 'pcm16',
        PcmEncoding.pcm24 => 'pcm24',
        PcmEncoding.pcm32float => 'pcm32float',
      };
}

/// How the platform says it would play a stream, when it says anything.
///
/// This is the signal that actually matters for fidelity, and it is why a bare
/// "direct playback: supported" is not enough: [offload] bypasses the
/// framework's mixing/resampling stage, and [bitstream] hands the compressed
/// stream to the output device undecoded. [none] means the framework would
/// resample or mix. Either way it is a capability answer, not a measurement
/// (plan §5.1 rule 5, §10).
enum DirectPlaybackMode {
  none,
  offload,
  offloadGapless,
  bitstream,
  unknown;

  static DirectPlaybackMode parse(String? value) => switch (value) {
        'none' => DirectPlaybackMode.none,
        'offload' => DirectPlaybackMode.offload,
        'offloadGapless' => DirectPlaybackMode.offloadGapless,
        'bitstream' => DirectPlaybackMode.bitstream,
        _ => DirectPlaybackMode.unknown,
      };

  String get label => switch (this) {
        DirectPlaybackMode.none => 'no direct path',
        DirectPlaybackMode.offload => 'offload',
        DirectPlaybackMode.offloadGapless => 'offload (gapless)',
        DirectPlaybackMode.bitstream => 'bitstream passthrough',
        DirectPlaybackMode.unknown => 'mode unknown',
      };
}

/// A point-in-time answer about the audio **output path**: which route is
/// active, and what the platform says about direct playback for a given format
/// (playback plan §5.1).
///
/// This is deliberately a separate object from the source metadata. §10 of the
/// plan is emphatic that a capability query is *evidence*, not proof: the app
/// may select a configuration because of it, but it must never present it as
/// verified end-to-end output.
class AudioCapabilityReport {
  final RouteKind routeKind;
  final String? routeLabel;
  final CapabilityState directPlayback;

  /// How the platform would play it (offload / bitstream / no direct path),
  /// when the platform distinguished.
  final DirectPlaybackMode directPlaybackMode;

  /// Why the answer is what it is — e.g. "Android 9 has no direct-playback query
  /// (needs API 33+)". Shown in the UI so an `unknown` explains itself instead of
  /// looking like a bug.
  final String? reason;

  /// Whether the platform accepted a requested configuration — null when it
  /// wasn't asked or didn't say.
  final bool? highResolutionPcmAccepted;
  final bool? bitPerfectUsbAccepted;

  /// Where this answer came from, for display ("Android AudioManager", or
  /// "not queried"). Diagnostics should never look more authoritative than the
  /// thing that produced them.
  final String source;

  const AudioCapabilityReport({
    this.routeKind = RouteKind.unknown,
    this.routeLabel,
    this.directPlayback = CapabilityState.unknown,
    this.directPlaybackMode = DirectPlaybackMode.unknown,
    this.reason,
    this.highResolutionPcmAccepted,
    this.bitPerfectUsbAccepted,
    this.source = 'not queried',
  });

  static const AudioCapabilityReport unknown = AudioCapabilityReport();

  CapabilityDiagnostics toDiagnostics({
    bool highResolutionPcmRequested = false,
    bool bitPerfectUsbRequested = false,
  }) =>
      CapabilityDiagnostics(
        directPlayback: directPlayback,
        directPlaybackMode: directPlaybackMode,
        highResolutionPcmRequested: highResolutionPcmRequested,
        bitPerfectUsbRequested: bitPerfectUsbRequested,
        highResolutionPcmAccepted: highResolutionPcmAccepted,
        bitPerfectUsbAccepted: bitPerfectUsbAccepted,
        reason: reason,
      );

  RouteDiagnostics toRouteDiagnostics() => RouteDiagnostics(kind: routeKind, deviceLabel: routeLabel);
}

/// Where output-route and capability facts come from.
///
/// Every platform that can't answer returns `unknown` rather than a default —
/// on web/desktop, and on Android below API 33, "we couldn't ask" is the truth
/// (§4.3).
abstract class AudioCapabilitySource {
  Future<AudioCapabilityReport> read({AudioQueryFormat? format});
}

/// The default: knows nothing, and says so.
class UnknownAudioCapabilitySource implements AudioCapabilitySource {
  const UnknownAudioCapabilitySource();

  @override
  Future<AudioCapabilityReport> read({AudioQueryFormat? format}) async => AudioCapabilityReport.unknown;
}

/// The Dart half of the native bridge described in §5.1 / Phase 3. The Kotlin
/// half is `AudioCapabilityBridge.kt`; the contract is documented on both sides.
///
/// The channel is optional by design. In a build with no Android platform project
/// (or on an OS/API level without those APIs) the call throws
/// `MissingPluginException`, and this returns `unknown` — playback is never
/// blocked by diagnostics, which is rule 4 of §5.1.
class MethodChannelAudioCapabilitySource implements AudioCapabilitySource {
  static const MethodChannel channel = MethodChannel('shuro/audio_capability');

  const MethodChannelAudioCapabilitySource();

  @override
  Future<AudioCapabilityReport> read({AudioQueryFormat? format}) async {
    try {
      final arguments = <String, dynamic>{
        ...musicAudioAttributes(),
        if (format != null) ...format.toChannelArguments(),
      };
      final response = await channel.invokeMapMethod<String, dynamic>('getCapability', arguments);
      if (response == null) return AudioCapabilityReport.unknown;
      return AudioCapabilityReport(
        routeKind: _routeKind(response['routeKind'] as String?),
        routeLabel: response['routeLabel'] as String?,
        directPlayback: _capabilityState(response['directPlayback'] as String?),
        directPlaybackMode: DirectPlaybackMode.parse(response['directPlaybackMode'] as String?),
        reason: response['directPlaybackReason'] as String?,
        highResolutionPcmAccepted: response['highResolutionPcmAccepted'] as bool?,
        bitPerfectUsbAccepted: response['bitPerfectUsbAccepted'] as bool?,
        source: (response['source'] as String?) ?? 'Android AudioManager',
      );
    } on MissingPluginException {
      // No native half in this build — expected, not an error.
      return AudioCapabilityReport.unknown;
    } on PlatformException {
      // A bridge that failed is still an unknown answer, never a false one.
      return AudioCapabilityReport.unknown;
    }
  }

  static RouteKind _routeKind(String? value) => switch (value) {
        'builtIn' => RouteKind.builtIn,
        'wired' => RouteKind.wired,
        'bluetooth' => RouteKind.bluetooth,
        'usb' => RouteKind.usb,
        'other' => RouteKind.other,
        _ => RouteKind.unknown,
      };

  static CapabilityState _capabilityState(String? value) => switch (value) {
        'supported' => CapabilityState.supported,
        'unsupported' => CapabilityState.unsupported,
        _ => CapabilityState.unknown,
      };
}

/// Holds the last known capability answer and refreshes it only when asked.
///
/// Caching is a requirement, not an optimisation (§5.1 rule 3 and §8): these
/// queries must never be made from a widget `build()` or a position listener.
/// [refresh] answers from cache; [recheck] forces a fresh read; [invalidate] is
/// what a route change calls. Changing [queryFormat] also invalidates, because
/// the answer is format-specific.
class AudioCapabilityMonitor {
  final AudioCapabilitySource source;

  AudioCapabilityReport? _last;
  Future<AudioCapabilityReport>? _inFlight;
  int _generation = 0;
  int _readCount = 0;
  AudioQueryFormat? _queryFormat;

  AudioCapabilityMonitor({AudioCapabilitySource? source}) : source = source ?? const UnknownAudioCapabilitySource();

  AudioCapabilityReport? get last => _last;

  AudioQueryFormat? get queryFormat => _queryFormat;

  /// Sets the format to query about. A change discards the cached answer: the
  /// platform's answer for 16-bit/44.1 kHz says nothing about 24-bit/96 kHz.
  void setQueryFormat(AudioQueryFormat? format) {
    final changed = _queryFormat?.sampleRateHz != format?.sampleRateHz ||
        _queryFormat?.channelCount != format?.channelCount ||
        _queryFormat?.encoding != format?.encoding;
    if (!changed) return;
    _queryFormat = format;
    invalidate();
  }

  /// Number of times the underlying source actually answered — used by tests to
  /// prove the caching behaviour rather than assert it in prose.
  int get readCount => _readCount;

  /// Answers from the cached report when there is one, so a screen can ask for
  /// diagnostics as often as it likes without touching the platform (§5.1 rule
  /// 3). Call [invalidate] first — or use [recheck] — to force a fresh read;
  /// that is what a route change and the panel's re-check action do.
  Future<AudioCapabilityReport> refresh() {
    final cached = _last;
    if (cached != null) return Future<AudioCapabilityReport>.value(cached);

    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final generation = _generation;
    final format = _queryFormat;
    final future = source.read(format: format).then((report) {
      // A route change during the read means this answer is already stale.
      if (generation == _generation) {
        _last = report;
        _readCount++;
      }
      return report;
    }).whenComplete(() {
      if (generation == _generation) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  /// Drops the cached answer and reads again — the explicit "re-check" path.
  Future<AudioCapabilityReport> recheck() {
    invalidate();
    return refresh();
  }

  AudioCapabilityReport reportOrUnknown() => _last ?? AudioCapabilityReport.unknown;

  /// Called when the output route changes.
  void invalidate() {
    _generation++;
    _last = null;
    _inFlight = null;
  }
}

/// The app's shared capability monitor.
///
/// One instance per process: the bridge talks to a single audio system, and the
/// caching above only helps if every reader shares one cache. Constructed with
/// the method-channel source, which degrades to `unknown` wherever there is no
/// native half — web, desktop, or an Android build without the platform project.
final AudioCapabilityMonitor sharedAudioCapabilityMonitor =
    AudioCapabilityMonitor(source: const MethodChannelAudioCapabilitySource());

/// Routes the native `routeChanged` callback into [monitor] (§5.1 rule 2).
///
/// A headset or DAC being plugged in makes the cached answer wrong, and Android
/// tells us through `AudioDeviceCallback` — so the cache is dropped and re-read
/// instead of being trusted until the next app resume. Where there is no native
/// half the callback simply never fires; nothing else is needed.
void attachNativeRouteListener([AudioCapabilityMonitor? monitor]) {
  final target = monitor ?? sharedAudioCapabilityMonitor;
  MethodChannelAudioCapabilitySource.channel.setMethodCallHandler((call) async {
    if (call.method == 'routeChanged') {
      await target.recheck();
    }
    return null;
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/models/audio_info.dart';
import 'package:shuro/models/download_state.dart';
import 'package:shuro/models/song.dart';
import 'package:shuro/playback/audio_capability.dart';
import 'package:shuro/playback/audio_diagnostics.dart';
import 'package:shuro/playback/playback_engine.dart';

/// Tests for the playback architecture: the source policy, the request check,
/// and the rule from §10 of the plan that keeps source metadata from being
/// presented as a fact about the output path.
void main() {
  Song songWith({
    AudioInfo? audioInfo,
    String? localFilePath,
  }) =>
      Song(
        id: 'song-1',
        title: 'Test Song',
        artist: 'Test Artist',
        artistId: 'artist-1',
        albumId: 'album-1',
        duration: const Duration(seconds: 200),
        gradientColors: const [Colors.red, Colors.blue],
        audioInfo: audioInfo ?? const AudioInfo(),
        localFilePath: localFilePath,
      );

  group('streamParametersFor', () {
    test('Original asks for format=raw and nothing else', () {
      final params = streamParametersFor(const SourcePolicy());
      expect(params, {'format': 'raw'});
      // §3.1 and the Phase 1 exit gate: Original must never be approximated by
      // a bitrate cap, because a cap is a transcode request.
      expect(params.containsKey('maxBitRate'), isFalse);
    });

    test('capped qualities ask for a bitrate cap and no format=raw', () {
      expect(streamParametersFor(const SourcePolicy(quality: StreamingQuality.high)), {'maxBitRate': '320'});
      expect(streamParametersFor(const SourcePolicy(quality: StreamingQuality.medium)), {'maxBitRate': '160'});
      expect(streamParametersFor(const SourcePolicy(quality: StreamingQuality.low)), {'maxBitRate': '96'});
    });
  });

  group('verifyStreamUrl', () {
    const original = SourcePolicy();
    const high = SourcePolicy(quality: StreamingQuality.high);

    test('accepts a URL that really asks for the raw file', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&format=raw', original);
      expect(check.matchesPolicy, isTrue);
    });

    test('flags a URL that also carries a bitrate cap under Original', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&format=raw&maxBitRate=320', original);
      expect(check.matchesPolicy, isFalse);
      expect(check.detail, contains('320'));
    });

    test('flags an Original request that forgot format=raw', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&maxBitRate=320', original);
      expect(check.matchesPolicy, isFalse);
      expect(check.detail.toLowerCase(), contains('transcode'));
    });

    test('treats maxBitRate=0 as "no limit", which is compatible with Original', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&format=raw&maxBitRate=0', original);
      expect(check.matchesPolicy, isTrue);
    });

    test('accepts a capped request that matches its policy', () {
      expect(verifyStreamUrl('https://music.example/rest/stream.view?id=1&maxBitRate=320', high).matchesPolicy, isTrue);
    });

    test('flags a capped request whose cap is wrong', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&maxBitRate=160', high);
      expect(check.matchesPolicy, isFalse);
    });

    test('flags a capped policy whose URL asks for raw, which would ignore the cap', () {
      final check = verifyStreamUrl('https://music.example/rest/stream.view?id=1&format=raw', high);
      expect(check.matchesPolicy, isFalse);
    });

    test('treats a local file as nothing to check', () {
      final check = verifyStreamUrl('/storage/emulated/0/Music/track.flac', original);
      expect(check.matchesPolicy, isTrue);
      expect(check.detail.toLowerCase(), contains('local'));
    });

    test('reports a missing URL instead of pretending it is fine', () {
      expect(verifyStreamUrl(null, original).matchesPolicy, isFalse);
      expect(verifyStreamUrl('', original).matchesPolicy, isFalse);
    });
  });

  group('AudioDiagnostics.forSong', () {
    test('reports nothing rather than plausible defaults when the server said nothing', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(),
        policy: const SourcePolicy(),
        processing: ProcessingOptions.none,
      );
      expect(diagnostics.source.codec, isNull);
      expect(diagnostics.source.bitDepth, isNull);
      expect(diagnostics.source.sampleRateHz, isNull);
      expect(diagnostics.source.channels, isNull);
      expect(diagnostics.source.sourceKind, SourceKind.navidrome);
    });

    test('carries high-resolution source facts without claiming them as output', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(audioInfo: const AudioInfo(format: 'FLAC', bitDepth: 24, sampleRateHz: 96000, bitrateKbps: 2847, channels: 'Stereo')),
        policy: const SourcePolicy(),
        processing: ProcessingOptions.none,
      );
      expect(diagnostics.source.bitDepth, 24);
      expect(diagnostics.source.sampleRateHz, 96000);
      expect(diagnostics.source.channels, 2);
      // The whole point of §10: the output path is *not* inferred from this.
      expect(diagnostics.capability.directPlayback, CapabilityState.unknown);
      expect(diagnostics.route.kind, RouteKind.unknown);
      expect(diagnostics.capability.highResolutionPcmRequested, isFalse);
    });

    test('leaves the stream mode unknown for Original until a response is seen', () {
      final pending = AudioDiagnostics.forSong(song: songWith(), policy: const SourcePolicy(), processing: ProcessingOptions.none);
      expect(pending.source.streamMode, StreamMode.unknown);

      final probed = AudioDiagnostics.forSong(
        song: songWith(),
        policy: const SourcePolicy(),
        processing: ProcessingOptions.none,
        probeStreamMode: StreamMode.original,
      );
      expect(probed.source.streamMode, StreamMode.original);
    });

    test('knows a capped policy is a transcode request even before probing', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(),
        policy: const SourcePolicy(quality: StreamingQuality.low),
        processing: ProcessingOptions.none,
      );
      expect(diagnostics.source.streamMode, StreamMode.transcoded);
    });

    test('marks a local file as local and leaves the request check not applicable', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(localFilePath: 'C:/Music/a.flac'),
        policy: const SourcePolicy(),
        processing: ProcessingOptions.none,
      );
      expect(diagnostics.source.sourceKind, SourceKind.local);
      expect(diagnostics.source.requestCheck, isNull);
    });

    test('maps channel labels it can be sure about and leaves the rest null', () {
      int? channelsFor(String label) => AudioDiagnostics.forSong(
            song: songWith(audioInfo: AudioInfo(channels: label)),
            policy: const SourcePolicy(),
            processing: ProcessingOptions.none,
          ).source.channels;

      expect(channelsFor('Mono'), 1);
      expect(channelsFor('Stereo'), 2);
      expect(channelsFor('6 ch'), 6);
      expect(channelsFor(AudioInfo.notReported), isNull);
    });

    test('reports processing separately from source quality', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(),
        policy: const SourcePolicy(),
        processing: const ProcessingOptions(replayGainEnabled: true),
      );
      expect(diagnostics.processing.replayGainEnabled, isTrue);
      expect(diagnostics.processing.anyEnabled, isTrue);
      expect(diagnostics.source.policy.isOriginal, isTrue, reason: 'processing must not change the source policy');
    });
  });

  group('AudioInfo labels', () {
    test('says "Not reported" instead of inventing values', () {
      const info = AudioInfo();
      expect(info.formatLabel, AudioInfo.notReported);
      expect(info.bitDepthLabel, AudioInfo.notReported);
      expect(info.sampleRateLabel, AudioInfo.notReported);
      expect(info.bitrateLabel, AudioInfo.notReported);
      expect(info.channelsLabel, AudioInfo.notReported);
      expect(info.nothingReported, isTrue);
    });

    test('formats a real 24/96 measurement', () {
      const info = AudioInfo(format: 'FLAC', bitDepth: 24, sampleRateHz: 96000);
      expect(info.formatLabel, 'FLAC');
      expect(info.bitDepthLabel, '24-bit');
      expect(info.sampleRateLabel, '96 kHz');
      expect(info.nothingReported, isFalse);
    });

    test('marks a lossless bitrate as an average rather than an exact figure', () {
      expect(const AudioInfo(format: 'FLAC', bitrateKbps: 2847).bitrateLabel, '2847 kbps (average)');
      expect(const AudioInfo(format: 'MP3', bitrateKbps: 320).bitrateLabel, '320 kbps');
    });

    test('handles a non-integer sample rate', () {
      expect(const AudioInfo(sampleRateHz: 44100).sampleRateLabel, '44.1 kHz');
    });
  });

  group('AudioCapabilityMonitor', () {
    test('caches, and only re-queries after a route change', () async {
      final source = _FakeCapabilitySource();
      final monitor = AudioCapabilityMonitor(source: source);

      await monitor.refresh();
      await monitor.refresh();
      expect(source.calls, 1, reason: 'a second read must come from the cache, not the platform');
      expect(monitor.readCount, 1);

      monitor.invalidate();
      await monitor.refresh();
      expect(source.calls, 2, reason: 'invalidate() is what a route change calls');
    });

    test('de-duplicates concurrent reads', () async {
      final source = _FakeCapabilitySource(delay: const Duration(milliseconds: 20));
      final monitor = AudioCapabilityMonitor(source: source);
      await Future.wait([monitor.refresh(), monitor.refresh(), monitor.refresh()]);
      expect(source.calls, 1);
    });

    test('answers unknown, never a default, when there is no platform answer', () async {
      final monitor = AudioCapabilityMonitor();
      final report = await monitor.refresh();
      expect(report.routeKind, RouteKind.unknown);
      expect(report.directPlayback, CapabilityState.unknown);
      expect(report.source, 'not queried');
      expect(monitor.reportOrUnknown().directPlayback, CapabilityState.unknown);
    });

    test('maps a platform answer onto the diagnostics model', () async {
      final source = _FakeCapabilitySource();
      final monitor = AudioCapabilityMonitor(source: source);
      final report = await monitor.refresh();
      final capability = report.toDiagnostics(highResolutionPcmRequested: true);
      expect(capability.directPlayback, CapabilityState.supported);
      expect(capability.highResolutionPcmRequested, isTrue);
      expect(capability.highResolutionPcmAccepted, isNull, reason: 'asked, not answered');
      expect(report.toRouteDiagnostics().kind, RouteKind.bluetooth);
      expect(report.source, 'fake platform');
    });
  });

  group('AudioQueryFormat', () {
    test('asks about the format the current engine outputs, with sane defaults', () {
      final format = AudioQueryFormat.forCurrentEngine(sampleRateHz: 96000, channelCount: 2);
      expect(format.sampleRateHz, 96000);
      expect(format.channelCount, 2);
      expect(format.encoding, PcmEncoding.pcm16, reason: 'the current engine decodes to 16-bit PCM');
    });

    test('falls back to 48 kHz stereo rather than refusing to ask', () {
      final format = AudioQueryFormat.forCurrentEngine();
      expect(format.sampleRateHz, 48000);
      expect(format.channelCount, 2);
    });

    test('ignores zeros and clamps the channel count', () {
      expect(AudioQueryFormat.forCurrentEngine(sampleRateHz: 0).sampleRateHz, 48000);
      expect(AudioQueryFormat.forCurrentEngine(channelCount: 0).channelCount, 2);
      expect(AudioQueryFormat.forCurrentEngine(channelCount: 6).channelCount, 2);
    });

    test('serialises to the channel argument names the Kotlin half reads', () {
      final arguments = const AudioQueryFormat(sampleRateHz: 44100, channelCount: 2, encoding: PcmEncoding.pcm24).toChannelArguments();
      expect(arguments['sampleRateHz'], 44100);
      expect(arguments['channelCount'], 2);
      expect(arguments['pcmEncoding'], 'pcm24');
    });
  });

  group('AudioCapabilityMonitor query format', () {
    test('passes the format to the source and re-reads only when it changes', () async {
      final source = _FakeCapabilitySource();
      final monitor = AudioCapabilityMonitor(source: source);

      monitor.setQueryFormat(AudioQueryFormat.forCurrentEngine(sampleRateHz: 44100));
      await monitor.refresh();
      expect(source.lastFormat?.sampleRateHz, 44100);
      expect(source.calls, 1);

      // Same format again: cached, no new platform read.
      monitor.setQueryFormat(AudioQueryFormat.forCurrentEngine(sampleRateHz: 44100));
      await monitor.refresh();
      expect(source.calls, 1);

      // A different format makes the previous answer meaningless.
      monitor.setQueryFormat(AudioQueryFormat.forCurrentEngine(sampleRateHz: 96000));
      await monitor.refresh();
      expect(source.calls, 2);
      expect(source.lastFormat?.sampleRateHz, 96000);
    });
  });

  group('capability reason', () {
    test('carries the platform explanation into diagnostics so "unknown" explains itself', () {
      const report = AudioCapabilityReport(
        directPlayback: CapabilityState.unknown,
        reason: 'Android 9 has no direct-playback query (needs API 33+).',
        source: 'Android AudioManager',
      );
      final capability = report.toDiagnostics();
      expect(capability.directPlayback, CapabilityState.unknown);
      expect(capability.reason, contains('API 33'));
      expect(capability.highResolutionPcmAccepted, isNull);
      expect(capability.bitPerfectUsbAccepted, isNull);
    });
  });

  group('describeDiagnostics', () {
    test('names what is unknown and never renders a stream URL', () {
      final diagnostics = AudioDiagnostics.forSong(
        song: songWith(),
        policy: const SourcePolicy(),
        processing: ProcessingOptions.none,
      );
      final described = describeDiagnostics(diagnostics);
      expect(described, contains('codec=unknown'));
      expect(described, contains('directPlayback=unknown'));
      expect(described, isNot(contains('http')));
    });
  });
}

class _FakeCapabilitySource implements AudioCapabilitySource {
  final Duration delay;
  int calls = 0;
  AudioQueryFormat? lastFormat;

  _FakeCapabilitySource({this.delay = Duration.zero});

  @override
  Future<AudioCapabilityReport> read({AudioQueryFormat? format}) async {
    calls++;
    lastFormat = format;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return const AudioCapabilityReport(
      routeKind: RouteKind.bluetooth,
      routeLabel: 'Test Buds',
      directPlayback: CapabilityState.supported,
      source: 'fake platform',
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shuro/playback/audio_diagnostics.dart';
import 'package:shuro/playback/playback_engine.dart';

/// The signal-path summary is a claim surface. These tests pin the wording so
/// it can never drift into saying more than the app knows.
void main() {
  group('signalPathSummary', () {
    test('reports source format, unknown route, and an unknown direct path', () {
      const d = AudioDiagnostics(
        source: SourceDiagnostics(
          sourceKind: SourceKind.local,
          codec: 'flac',
          sampleRateHz: 96000,
          bitDepth: 24,
          channels: 2,
          streamMode: StreamMode.unknown,
          policy: SourcePolicy(),
        ),
      );

      final s = d.signalPathSummary;

      expect(s, contains('FLAC 24-bit 96 kHz'));
      expect(s, contains('Route not reported'));
      expect(s, contains('direct path not reported'));
      expect(s.toLowerCase(), isNot(contains('bit-perfect')));
      expect(s.toLowerCase(), isNot(contains('bit perfect')));
    });

    test('marks a capped quality setting as server transcoded', () {
      const d = AudioDiagnostics(
        source: SourceDiagnostics(
          sourceKind: SourceKind.navidrome,
          codec: 'mp3',
          sampleRateHz: 44100,
          bitDepth: 16,
          channels: 2,
          streamMode: StreamMode.transcoded,
          policy: SourcePolicy(),
        ),
      );

      expect(d.signalPathSummary, contains('server transcoded'));
    });

    test('names the device and its reported ceiling when available', () {
      const d = AudioDiagnostics(
        source: SourceDiagnostics(
          sourceKind: SourceKind.local,
          codec: 'flac',
          sampleRateHz: 44100,
          bitDepth: 16,
          channels: 2,
          streamMode: StreamMode.unknown,
          policy: SourcePolicy(),
        ),
        route: RouteDiagnostics(kind: RouteKind.usb, deviceLabel: 'USB DAC'),
        capability: CapabilityDiagnostics(sampleRatesLabel: '384000'),
      );

      final s = d.signalPathSummary;
      expect(s, contains('USB DAC'));
      expect(s, contains('384000'));
    });

    test('wins with processing when this engine edits the audio', () {
      const d = AudioDiagnostics(
        source: SourceDiagnostics(
          sourceKind: SourceKind.local,
          codec: 'flac',
          sampleRateHz: 44100,
          bitDepth: 16,
          channels: 2,
          streamMode: StreamMode.unknown,
          policy: SourcePolicy(),
        ),
        processing: ProcessingDiagnostics(
          equalizerEnabled: true,
          replayGainEnabled: true,
        ),
      );

      final s = d.signalPathSummary;
      expect(s, contains('processed here'));
      expect(s, contains('EQ'));
      expect(s, contains('ReplayGain'));
    });

    test('says direct only when the platform answered yes', () {
      const base = SourceDiagnostics(
        sourceKind: SourceKind.local,
        codec: 'flac',
        sampleRateHz: 44100,
        bitDepth: 16,
        channels: 2,
        streamMode: StreamMode.unknown,
        policy: SourcePolicy(),
      );

      const supported = AudioDiagnostics(
        source: base,
        capability: CapabilityDiagnostics(directPlayback: CapabilityState.supported),
      );
      const unsupported = AudioDiagnostics(
        source: base,
        capability: CapabilityDiagnostics(directPlayback: CapabilityState.unsupported),
      );

      expect(supported.signalPathSummary, contains('direct path reported'));
      expect(unsupported.signalPathSummary, contains('cannot take it direct'));
    });

    test('never invents a format when tags are missing', () {
      const d = AudioDiagnostics(
        source: SourceDiagnostics(
          sourceKind: SourceKind.navidrome,
          streamMode: StreamMode.unknown,
          policy: SourcePolicy(),
        ),
      );
      expect(d.signalPathSummary, contains('Format not reported'));
    });
  });
}

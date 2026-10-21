import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/download_state.dart';
import '../../models/song.dart';
import '../../playback/audio_capability.dart';
import '../../playback/audio_diagnostics.dart';
import '../../playback/playback_engine.dart';
import '../../services/stream_probe.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';

/// "7. Audio information panel" — the diagnostics screen from §4.3 of the
/// playback plan.
///
/// Its whole reason for existing is the split the plan insists on: **source**,
/// **playback request** and **output capability** are three different things,
/// and conflating them is how an app ends up claiming "24-bit/96 kHz output"
/// because a file's tags say so. So:
///
///  * every value says where it came from, and says "not reported" rather than
///    filling a gap with something plausible;
///  * the request is checked against the URL the app actually built, not
///    against what it meant to build;
///  * output-capability rows are only ever populated from a platform answer, and
///    the panel states plainly that Shuro does not verify the output format.
void showAudioInfoSheet(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _AudioInfoSheet(song: song),
  );
}

class _AudioInfoSheet extends StatefulWidget {
  final Song song;
  const _AudioInfoSheet({required this.song});

  @override
  State<_AudioInfoSheet> createState() => _AudioInfoSheetState();
}

class _AudioInfoSheetState extends State<_AudioInfoSheet> {
  bool _probing = false;
  StreamProbe? _probe;
  String? _probeError;

  @override
  void initState() {
    super.initState();
    // A deliberate, user-initiated read (opening the panel), not a per-frame
    // query: §5.1 rule 3 allows exactly this and forbids the latter.
    unawaited(_refreshCapability());
  }

  Future<void> _refreshCapability() async {
    // Ask about the format this engine actually outputs for this track, so the
    // answer describes a real configuration rather than a hypothetical one.
    final info = widget.song.audioInfo;
    sharedAudioCapabilityMonitor
        .setQueryFormat(AudioQueryFormat.forCurrentEngine(
      sampleRateHz: info.hasSampleRate ? info.sampleRateHz : null,
      channelCount: info.channelCount,
    ));
    await sharedAudioCapabilityMonitor.recheck();
    if (mounted) setState(() {});
  }

  /// Diagnostics for *this* sheet's song, using the same resolver the app wires
  /// into the player (so the panel and `PlayerController.getOutputDiagnostics`
  /// can never disagree about the same track).
  AudioDiagnostics _diagnostics() {
    final player = context.read<PlayerController>();
    final resolver = player.diagnosticsResolver;
    if (resolver != null)
      return resolver(
          widget.song, player.sourcePolicy, player.processingOptions);
    return AudioDiagnostics.forSong(
        song: widget.song,
        policy: player.sourcePolicy,
        processing: player.processingOptions);
  }

  Future<void> _runProbe() async {
    final appState = context.read<AppState>();
    final url = appState.audioSourceFor(widget.song);
    if (url == null || !url.startsWith('http')) {
      setState(() {
        _probe = null;
        _probeError = url == null
            ? 'No stream is available for this track right now.'
            : 'This track plays from a local file, so there is no server stream to check.';
      });
      return;
    }
    setState(() {
      _probing = true;
      _probe = null;
      _probeError = null;
    });
    final probe = await StreamProbeService.probe(url);
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probe = probe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final diagnostics = _diagnostics();
    final source = diagnostics.source;
    final info = widget.song.audioInfo;
    final probe = _probe;
    final requestCheck = source.requestCheck;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2)))),
              Text('Audio Information',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${widget.song.title} · ${widget.song.artist}',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 20),
              const _SectionLabel('SOURCE'),
              Text(
                source.sourceKind == SourceKind.local
                    ? 'This device (local file)'
                    : 'Your Navidrome server',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _InfoRow('Codec', info.formatLabel,
                  provenance: 'server file scan'),
              _InfoRow('Bit depth', info.bitDepthLabel,
                  provenance: 'server file scan'),
              _InfoRow('Sample rate', info.sampleRateLabel,
                  provenance: 'server file scan'),
              _InfoRow('Channels', info.channelsLabel,
                  provenance: 'server file scan'),
              _InfoRow('Bitrate', info.bitrateLabel,
                  provenance: 'server file scan'),
              if (info.nothingReported)
                const _Note(
                    'Your server did not report technical details for this file, so these read "not reported" rather than a guess.')
              else
                const _Note(
                    'These describe the file itself, as your server indexed it — not what your device outputs.'),
              const SizedBox(height: 20),
              const _SectionLabel('PLAYBACK'),
              _InfoRow('Quality requested', source.policy.quality.label,
                  provenance: _policySummary(source.policy)),
              if (requestCheck != null) _RequestCheckRow(check: requestCheck),
              _InfoRow(
                'Stream mode',
                switch (source.streamMode) {
                  StreamMode.original => 'Original file',
                  StreamMode.transcoded => 'Transcoded by the server',
                  StreamMode.unknown => 'Original requested — not yet verified',
                },
                provenance: 'from the request, until a response is inspected',
              ),
              _InfoRow('Resolved for', _resolvedFor(appState),
                  provenance: 'current connection'),
              _InfoRow(
                  'Effects applied',
                  diagnostics.processing.anyEnabled
                      ? _effectsLabel(diagnostics.processing)
                      : 'None',
                  provenance: 'this engine applies none'),
              if (!source.policy.isOriginal)
                const _Note(
                    'A capped quality setting means the server re-encodes this stream. Choose "Original" to stream the file untouched — see the stream check below for what actually arrives.'),
              const SizedBox(height: 20),
              const _SectionLabel('OUTPUT CAPABILITY'),
              _InfoRow('Route', _routeLabel(diagnostics.route),
                  provenance: _routeProvenance()),
              _InfoRow(
                  'Direct playback', _capabilityLabel(diagnostics.capability),
                  provenance: _capabilityProvenance()),
              if (diagnostics.capability.sampleRatesLabel != null)
                _InfoRow('Device sample rates',
                    diagnostics.capability.sampleRatesLabel!,
                    provenance: 'reported by the output device'),
              if (diagnostics.capability.channelCountsLabel != null)
                _InfoRow('Device channels',
                    diagnostics.capability.channelCountsLabel!,
                    provenance: 'reported by the output device'),
              if (diagnostics.capability.encodingsLabel != null)
                _InfoRow(
                    'Device encodings', diagnostics.capability.encodingsLabel!,
                    provenance: 'reported by the output device'),
              if (diagnostics.capability.reason != null &&
                  diagnostics.capability.directPlayback ==
                      CapabilityState.unknown)
                _Note(diagnostics.capability.reason!),
              if (diagnostics.capability.highResolutionPcmRequested)
                _InfoRow(
                    'High-res PCM',
                    diagnostics.capability.highResolutionPcmAccepted == null
                        ? 'Requested (no answer)'
                        : (diagnostics.capability.highResolutionPcmAccepted!
                            ? 'Accepted'
                            : 'Rejected'),
                    provenance: 'requested configuration'),
              const _Note(
                'Android decides how these samples reach your speaker, headphones or USB device, and Shuro cannot measure that last stage. Nothing here is a claim of verified hardware output.',
              ),
              const SizedBox(height: 20),
              const _SectionLabel('STREAM CHECK'),
              Text(
                'Asks your server for this track\'s stream and reports what it actually sends back — the difference between the quality you asked for and the audio you get.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white60, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _probing ? null : _runProbe,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: kDividerColor)),
                    icon: _probing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white70))
                        : const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: Text(
                        _probing ? 'Checking…' : 'Check what the server sends'),
                  ),
                  IconButton(
                    onPressed: _refreshCapability,
                    tooltip: 'Re-check the output route',
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ],
              ),
              if (_probeError != null) ...[
                const SizedBox(height: 12),
                Text(_probeError!,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.amber.shade100,
                        fontSize: 12,
                        height: 1.4)),
              ],
              if (probe != null && _probeError == null) ...[
                const SizedBox(height: 14),
                if (probe.statusCode == 0)
                  Text(
                    'No response from the server (${probe.elapsed.inMilliseconds} ms). It may be unreachable right now.',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.amber.shade100,
                        fontSize: 12,
                        height: 1.4),
                  )
                else ...[
                  _InfoRow('HTTP status',
                      '${probe.statusCode}${probe.supportsRange ? ' (range supported)' : ''}',
                      provenance: 'response headers'),
                  _InfoRow(
                      'Server sent',
                      probe.servedFormat ??
                          (probe.contentType.isEmpty
                              ? 'undeclared type'
                              : probe.contentType),
                      provenance: 'Content-Type'),
                  _InfoRow('Track size', probe.sizeLabel,
                      provenance: 'Content-Length / Content-Range'),
                  const SizedBox(height: 8),
                  _Verdict(
                      probe: probe,
                      taggedFormat: info.format,
                      isOriginal: source.policy.isOriginal),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _policySummary(SourcePolicy policy) => policy.isOriginal
      ? 'sent as format=raw'
      : 'sent as a ${streamParametersFor(policy)['maxBitRate']} kbps cap';

  static String _effectsLabel(ProcessingDiagnostics processing) {
    final active = <String>[
      if (processing.replayGainEnabled) 'ReplayGain',
      if (processing.equalizerEnabled) 'Equalizer',
      if (processing.crossfadeEnabled) 'Crossfade',
    ];
    return active.isEmpty ? 'None' : active.join(' · ');
  }

  static String _routeLabel(RouteDiagnostics route) => switch (route.kind) {
        RouteKind.builtIn => 'Built-in output',
        RouteKind.wired => 'Wired / USB-C adapter',
        RouteKind.bluetooth => 'Bluetooth (codec negotiated by the device)',
        RouteKind.usb => route.deviceLabel ?? 'USB audio device',
        RouteKind.other => route.deviceLabel ?? 'Other route',
        RouteKind.unknown => 'Not reported',
      };

  /// Names the mode when the platform distinguished it: "supported (offload)"
  /// or "supported (bitstream passthrough)" says far more about fidelity than
  /// a bare "supported" — and an unsupported answer names why.
  static String _capabilityLabel(CapabilityDiagnostics capability) =>
      switch (capability.directPlayback) {
        CapabilityState.supported =>
          'Supported for this format · ${capability.directPlaybackMode.label}',
        CapabilityState.unsupported =>
          'No direct path for this format · ${capability.directPlaybackMode.label}',
        CapabilityState.unknown => 'Not reported',
      };

  String _routeProvenance() {
    final report = sharedAudioCapabilityMonitor.reportOrUnknown();
    return report.source == 'not queried'
        ? 'no platform answer available here'
        : report.source;
  }

  String _capabilityProvenance() {
    final report = sharedAudioCapabilityMonitor.reportOrUnknown();
    return report.directPlayback == CapabilityState.unknown
        ? 'no platform answer available here'
        : '${report.source}, for music audio attributes';
  }

  /// Which quality setting governs this stream. Derived from the two settings
  /// themselves rather than the connection type, which is private to AppState:
  /// if the effective value matches one and not the other, that's which applied.
  /// When both hold the same value nothing here can tell them apart, and saying
  /// so beats guessing.
  String _resolvedFor(AppState appState) {
    final effective = appState.effectiveStreamingQuality;
    final matchesWifi = effective == appState.wifiQuality;
    final matchesMobile = effective == appState.mobileQuality;
    if (matchesWifi && !matchesMobile) return 'Wi-Fi';
    if (matchesMobile && !matchesWifi) return 'Mobile data';
    return 'either (both quality settings match)';
  }
}

/// Shows whether the request the app actually built matches the policy it meant
/// to apply — §7's Phase 1 exit gate ("the original-source option does not
/// accidentally request a bitrate-limited stream"), made visible.
class _RequestCheckRow extends StatelessWidget {
  final SourceRequestCheck check;
  const _RequestCheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final ok = check.matchesPolicy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              size: 16,
              color: ok
                  ? Colors.lightGreenAccent.shade100
                  : Colors.orangeAccent.shade100),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    ok
                        ? 'Request matches the policy'
                        : 'Request does not match the policy',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: ok
                            ? Colors.lightGreenAccent.shade100
                            : Colors.orangeAccent.shade100,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(check.detail,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white60, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line answer to "am I actually getting the original?".
class _Verdict extends StatelessWidget {
  final StreamProbe probe;
  final String? taggedFormat;
  final bool isOriginal;

  const _Verdict(
      {required this.probe,
      required this.taggedFormat,
      required this.isOriginal});

  @override
  Widget build(BuildContext context) {
    final served = probe.servedFormat;
    final known = taggedFormat != null && taggedFormat!.trim().isNotEmpty;
    final String message;
    final Color colour;
    final IconData icon;

    if (served == null) {
      message =
          'The server answered but did not declare a format, so the stream could not be verified.';
      colour = Colors.white70;
      icon = Icons.help_outline_rounded;
    } else if (!known) {
      message =
          'Server sent $served (${probe.sizeLabel}). Your server does not report a library format for this track, so there is nothing to compare it against.';
      colour = Colors.white70;
      icon = Icons.info_outline_rounded;
    } else if (probe.matchesFormat(taggedFormat!)) {
      message = isOriginal
          ? 'Original file served — $served, ${probe.sizeLabel}, no transcode.'
          : 'Server sent $served, matching the library format. A capped quality was requested, so treat this as a re-encode of the original.';
      colour =
          isOriginal ? Colors.lightGreenAccent.shade100 : Colors.amber.shade100;
      icon =
          isOriginal ? Icons.check_circle_rounded : Icons.info_outline_rounded;
    } else {
      message =
          'Server sent $served for a ${taggedFormat!} track — it is transcoding this stream, so you are not hearing the original file.';
      colour = Colors.orangeAccent.shade100;
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: kCardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDividerColor)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: colour, fontSize: 12, height: 1.45))),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.white54, size: 14),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white60, fontSize: 11, height: 1.45))),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white60,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600)),
      );
}

/// A label/value row with a quiet provenance note, so no number in this panel
/// can be mistaken for something it isn't.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? provenance;

  const _InfoRow(this.label, this.value, {this.provenance});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white70, fontSize: 13)),
                if (provenance != null)
                  Text(provenance!,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

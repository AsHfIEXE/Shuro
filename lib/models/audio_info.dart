/// Technical playback info shown in the "Audio Information" sheet and the
/// album header.
///
/// Every field here describes the **source** file as the server's own scan
/// reports it — never the output path, and never a guess. That's why the
/// numeric fields are nullable: a server that doesn't send `bitDepth` (a plain
/// Subsonic server, an older Navidrome, an untagged file) gets `null` and the
/// UI says "not reported", instead of this class inventing "16-bit / 44.1 kHz"
/// and the app presenting that invention as a property of your music.
///
/// See the playback plan §4.3 ("Source sample rate, bit depth and channel count
/// when reliable metadata is available") and §9 ("Source data is correct or
/// unknown; never fabricated").
class AudioInfo {
  final String? format;
  final int? bitDepth;
  final int? sampleRateHz;
  final int? bitrateKbps;

  /// Kept non-nullable as a display label: "Not reported" when the server
  /// didn't supply a channel count.
  final String channels;

  static const String notReported = 'Not reported';

  const AudioInfo({
    this.format,
    this.bitDepth,
    this.sampleRateHz,
    this.bitrateKbps,
    this.channels = notReported,
  });

  bool get hasFormat => format != null && format!.trim().isNotEmpty;
  bool get hasBitDepth => bitDepth != null && bitDepth! > 0;
  bool get hasSampleRate => sampleRateHz != null && sampleRateHz! > 0;
  bool get hasBitrate => bitrateKbps != null && bitrateKbps! > 0;
  bool get hasChannels => channels.trim().isNotEmpty && channels != notReported;

  /// True when the server told us nothing about this file's technical shape —
  /// useful so the UI can say "the server didn't report this" once rather than
  /// five times.
  bool get nothingReported => !hasFormat && !hasBitDepth && !hasSampleRate && !hasBitrate && !hasChannels;

  String get formatLabel => hasFormat ? format! : notReported;

  String get sampleRateLabel {
    if (!hasSampleRate) return notReported;
    final khz = sampleRateHz! / 1000;
    final rounded = khz == khz.roundToDouble() ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1);
    return '$rounded kHz';
  }

  String get bitDepthLabel => hasBitDepth ? '$bitDepth-bit' : notReported;

  /// Lossless formats have no meaningful single bitrate, so saying "1000 kbps"
  /// for a FLAC is misleading even when the server does report it — the label
  /// says what the number actually is (§4.3: "for variable-bitrate/lossless
  /// formats, make clear that this is an estimate or measured value if not
  /// exact").
  String get bitrateLabel {
    if (!hasBitrate) return notReported;
    final lossless = hasFormat && const {'FLAC', 'ALAC', 'WAV', 'AIFF', 'APE', 'WV'}.contains(format!.toUpperCase());
    return '$bitrateKbps kbps${lossless ? ' (average)' : ''}';
  }

  String get channelsLabel => hasChannels ? channels : notReported;

  /// The channel *count*, when the label names one we can be sure about.
  /// "Stereo" → 2, "Mono" → 1, "6 ch" → 6, "Not reported" → null. Used by the
  /// capability query, which has to state a real channel count to be meaningful.
  int? get channelCount {
    if (!hasChannels) return null;
    final lower = channels.toLowerCase().trim();
    if (lower == 'mono') return 1;
    if (lower == 'stereo') return 2;
    final match = RegExp(r'^(\d+)\s*ch').firstMatch(lower);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

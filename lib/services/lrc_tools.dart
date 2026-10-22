import '../models/lyrics.dart';

/// Pure helpers around raw lyric text (roadmap #21): format detection, LRC
/// parsing into the app's own track model, and whole-file timestamp shifting.
///
/// Nothing here touches the network or the disk, so every rule is unit-testable
/// against exact strings.
class LrcTools {
  const LrcTools._();

  /// `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` — also `[h:mm:ss.xx]`.
  static final RegExp _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// True when [text] carries at least one LRC timestamp.
  static bool isLrc(String text) => _stamp.allMatches(text).isNotEmpty;

  /// Parses LRC text into a line-synced track, or a static one when no
  /// timestamps are present. Metadata tags (`[ar:…]`, `[ti:…]`, `[offset:…]`)
  /// are skipped — the app keeps timing adjustment in the editor, not in
  /// hidden file metadata, so nothing here is silently applied twice.
  static LyricsTrack parse(String text) {
    if (!isLrc(text)) return staticTrack(text);

    final lines = <LyricsLine>[];
    for (final raw in text.split('\n')) {
      final stamps = _stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final content = raw.replaceFirst(_stamp, '').trim();
      if (content.isEmpty) continue;
      final start = _stampToDuration(stamps.first);
      lines.add(LyricsLine(
        syllables: [
          LyricsSyllable(text: content, start: start, end: start),
        ],
        start: start,
        end: start,
      ));
    }
    if (lines.isEmpty) return staticTrack(text);
    return LyricsTrack(type: LyricsSyncType.line, source: LyricsSource.edited, lines: lines);
  }

  /// Builds a no-timing track from plain text.
  static LyricsTrack staticTrack(String text) {
    final lines = <LyricsLine>[];
    var cursor = Duration.zero;
    for (final raw in text.split('\n')) {
      final content = raw.replaceFirst(_stamp, '').trim();
      lines.add(LyricsLine(
        syllables: [
          LyricsSyllable(text: content, start: cursor, end: cursor),
        ],
        start: cursor,
        end: cursor,
      ));
    }
    return LyricsTrack(type: LyricsSyncType.static_, source: LyricsSource.edited, lines: lines);
  }

  /// Shifts every timestamp in LRC [text] by [delta] (positive = later).
  ///
  /// Timestamps never go below zero: a stamp that would land before the start
  /// clamps to `[00:00.00]` rather than wrapping into a nonsense value.
  static String shiftTimestamps(String text, Duration delta) {
    return text.replaceAllMapped(_stamp, (match) {
      final shifted = _stampToDuration(match as RegExpMatch) + delta;
      final clamped = shifted < Duration.zero ? Duration.zero : shifted;
      final centis = (clamped.inMilliseconds % 1000) ~/ 10;
      final minutes = clamped.inMinutes;
      final seconds = clamped.inSeconds % 60;
      final mm = minutes.toString().padLeft(2, '0');
      final ss = seconds.toString().padLeft(2, '0');
      final xx = centis.toString().padLeft(2, '0');
      return '[$mm:$ss.$xx]';
    });
  }

  static Duration _stampToDuration(RegExpMatch match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = match.group(3);
    final ms = fraction == null
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
  }
}

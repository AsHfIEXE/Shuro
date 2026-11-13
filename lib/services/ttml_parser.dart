import 'package:xml/xml.dart';

import '../models/lyrics.dart';
import 'lyrics_parser.dart' show estimateSyllables;

/// Parses a TTML document (lrc.red's primary format) into a [LyricsTrack],
/// keeping every real timestamp.
///
/// Rules:
///  - `<p>` is a lyric line, each timed `<span>` inside it a karaoke segment.
///  - Adjacent spans with no whitespace between them are fragments of one word
///    (`spe`+`cial`): they join visually (`isPartOfWord`) but keep their own
///    timing, which makes the track [LyricsSyncType.syllable].
///  - Translation / romanisation spans are skipped; background vocals are kept
///    inline as ordinary timed segments.
///  - Timing is never manufactured: a line without timed spans only gets
///    estimated words when the whole document has too few timed lines to count
///    as word-synced, and then the track says so (`wordTimingIsEstimated`).
///  - Anything unusable returns null so the caller falls through to the next
///    source.
LyricsTrack? parseTtml(
  String source, {
  Duration? duration,
  String? sourceUrl,
  LyricsSource provider = LyricsSource.lrcRed,
}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source);
  } catch (_) {
    return null;
  }

  final lines = <LyricsLine>[];
  var timedLines = 0;
  var anyFragment = false;

  for (final p in doc.findAllElements('p')) {
    final lineBegin = parseTtmlTime(p.getAttribute('begin'));
    final lineEnd = parseTtmlTime(p.getAttribute('end'));

    final pieces = <_Piece>[];
    _walk(p, pieces);

    if (pieces.isNotEmpty) {
      final built = _buildSyllables(pieces);
      if (built.isEmpty) continue;
      anyFragment = anyFragment || built.any((s) => s.isPartOfWord);
      timedLines++;
      final start = built.first.start;
      final end = lineEnd != null && lineEnd > built.last.end ? lineEnd : built.last.end;
      lines.add(LyricsLine(syllables: built, start: start, end: end));
    } else {
      // No timed spans: line-level only.
      final text = p.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || lineBegin == null) continue;
      final end = lineEnd != null && lineEnd > lineBegin ? lineEnd : lineBegin + const Duration(seconds: 3);
      lines.add(LyricsLine(syllables: estimateSyllables(text, lineBegin, end), start: lineBegin, end: end));
    }
  }

  if (lines.isEmpty) return null;
  lines.sort((a, b) => a.start.compareTo(b.start));

  // Timing outside the recording: the document is for another cut of the song.
  if (duration != null && duration > Duration.zero) {
    if (lines.first.start > duration + const Duration(seconds: 5)) return null;
  }

  // Word-synced only when (nearly) every line really carries span timing.
  final wordSynced = timedLines > 0 && timedLines >= (lines.length * 0.8).ceil();
  final type = !wordSynced
      ? LyricsSyncType.line
      : (anyFragment ? LyricsSyncType.syllable : LyricsSyncType.word);

  return LyricsTrack(
    type: type,
    source: provider,
    lines: lines,
    wordTimingIsEstimated: !wordSynced,
    sourceUrl: sourceUrl,
  );
}

class _Piece {
  final String text;
  final Duration start;
  final Duration end;
  final bool spaceBefore;
  final bool spaceAfter;
  const _Piece(this.text, this.start, this.end, {this.spaceBefore = false, this.spaceAfter = false});
}

void _walk(XmlElement parent, List<_Piece> out) {
  var gap = false;
  for (final node in parent.children) {
    if (node is XmlText) {
      if (RegExp(r'\s').hasMatch(node.value)) gap = true;
      continue;
    }
    if (node is! XmlElement || node.name.local != 'span') continue;
    final role = node.attributes
        .where((a) => a.name.local == 'role')
        .map((a) => a.value)
        .join(' ');
    if (role.contains('x-translation') || role.contains('x-roman')) continue;

    final begin = parseTtmlTime(node.getAttribute('begin'));
    final end = parseTtmlTime(node.getAttribute('end'));
    final hasChildSpans = node.children.any((c) => c is XmlElement && c.name.local == 'span');

    if (hasChildSpans) {
      final before = out.length;
      _walk(node, out);
      if (gap && out.length > before) {
        out[before] = _copy(out[before], spaceBefore: true);
      }
      gap = false;
      continue;
    }

    final raw = node.innerText;
    final text = raw.replaceAll(RegExp(r'\s+'), ' ');
    final trimmed = text.trim();
    if (trimmed.isEmpty || begin == null || end == null || end < begin) {
      if (RegExp(r'\s').hasMatch(raw)) gap = true;
      continue;
    }
    out.add(_Piece(
      trimmed,
      begin,
      end,
      spaceBefore: gap || text.startsWith(' '),
      spaceAfter: text.endsWith(' '),
    ));
    gap = text.endsWith(' ');
  }
}

_Piece _copy(_Piece p, {bool? spaceBefore}) => _Piece(p.text, p.start, p.end,
    spaceBefore: spaceBefore ?? p.spaceBefore,
    spaceAfter: p.spaceAfter);

List<LyricsSyllable> _buildSyllables(List<_Piece> pieces) {
  final out = <LyricsSyllable>[];
  for (var i = 0; i < pieces.length; i++) {
    final cur = pieces[i];
    final next = i + 1 < pieces.length ? pieces[i + 1] : null;
    // A space follows when this piece ends one, or the next one starts one.
    final spaced = next != null && (cur.spaceAfter || next.spaceBefore);
    var end = cur.end;
    if (end < cur.start) end = cur.start;
    out.add(LyricsSyllable(
      text: spaced ? '${cur.text} ' : cur.text,
      start: cur.start,
      end: end,
      isPartOfWord: i > 0 && !(pieces[i - 1].spaceAfter || cur.spaceBefore),
    ));
  }
  return out;
}

/// TTML clock values: `19.764`, `1:00.998`, `3:58.640`, `00:03:12.450`, plus
/// offset forms `12.5s` / `1500ms`. Returns null for anything else.
Duration? parseTtmlTime(String? value) {
  if (value == null) return null;
  final v = value.trim();
  if (v.isEmpty) return null;

  final ms = RegExp(r'^(\d+(?:\.\d+)?)ms$').firstMatch(v);
  if (ms != null) return Duration(microseconds: (double.parse(ms.group(1)!) * 1000).round());
  final s = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(v);
  if (s != null) return Duration(microseconds: (double.parse(s.group(1)!) * 1e6).round());

  final parts = v.split(':');
  if (parts.length > 3) return null;
  final secs = double.tryParse(parts.last);
  if (secs == null || secs < 0) return null;
  var total = secs;
  if (parts.length >= 2) {
    final m = int.tryParse(parts[parts.length - 2]);
    if (m == null || m < 0) return null;
    total += m * 60;
  }
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]);
    if (h == null || h < 0) return null;
    total += h * 3600;
  }
  return Duration(microseconds: (total * 1e6).round());
}

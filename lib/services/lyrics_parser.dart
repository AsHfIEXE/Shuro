import 'dart:math' as math;

import '../models/lyrics.dart';

/// Pure lyrics parsing and matching — no HTTP, no Flutter, no state.
///
/// Everything the lyrics stack decides that isn't network I/O lives here, so
/// the rules are unit-testable without a device or a server (see
/// test/lyrics_parser_test.dart). [LyricsService] owns the fetching;
/// [LyricsScreen] owns the pixels; this file owns what the data *is*.
///
/// Formats handled, with the precision each one actually carries:
///  - `.lrc` (`[mm:ss.xx]text`) — line-level timing.
///  - enhanced `.lrc` (`[mm:ss.xx]<mm:ss.xx>word<...>word`) — real word-level
///    timing, so karaoke highlighting is not a guess.
///  - the LRCLIB word-synced Lyricsfile (`lines[].words[].start_ms`), whose
///    schema is verified against LRCLIB's own server source and fixtures —
///    all timestamps are integer **milliseconds**.
///  - OpenSubsonic `structuredLyrics` (embedded tags), whose `line.start` is
///    milliseconds and is *omitted* when the entry isn't synced (so a missing
///    start must never be read as "0").

/// `[mm:ss]`, `[mm:ss.x]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, `[hh:mm:ss.xx]` —
/// leading line timestamps. `[ar:Artist]`-style metadata tags can't match
/// (the first group must be digits), so they're skipped for free.
final RegExp _timestampRe = RegExp(r'\[(?:(\d{1,3}):)?(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// `<mm:ss.xx>` inline word timestamps (enhanced LRC).
final RegExp _wordTimestampRe = RegExp(r'<(?:(\d{1,3}):)?(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');

final RegExp _whitespaceRe = RegExp(r'\s+');

/// How far a candidate recording's duration may differ before its *timings*
/// stop being safe to trust. LRCLIB's own exact lookup matches within ±2s;
/// this is looser to absorb tag-vs-decode duration differences, and still far
/// tighter than "any result the search returned".
const Duration kSyncedDurationTolerance = Duration(seconds: 5);

/// Upper bound used when a format gives no duration to close the last line
/// with (LRC files have no end marker for the final line).
const Duration _trailingLineLength = Duration(seconds: 6);

// --- small helpers ---------------------------------------------------------

Duration? _durationFromMatch(Match match) {
  final hours = match.group(1);
  final minutes = match.group(2);
  final seconds = match.group(3);
  if (minutes == null || seconds == null) return null;
  final fraction = match.group(4);
  final millis = fraction == null ? 0 : int.parse(fraction.padRight(3, '0').substring(0, 3));
  return Duration(
    hours: hours == null ? 0 : int.parse(hours),
    minutes: int.parse(minutes),
    seconds: int.parse(seconds),
    milliseconds: millis,
  );
}

/// Closes the final line of a format that has no explicit end: a fixed
/// trailing window, trimmed to the song's own length when that's known.
Duration _closeLastLine(Duration start, Duration fallbackDuration) {
  final candidate = start + _trailingLineLength;
  if (fallbackDuration > Duration.zero && candidate > fallbackDuration) return fallbackDuration;
  return candidate;
}

bool _endsWithSpace(String text) => text.isNotEmpty && text.endsWith(' ');

/// The joined syllable text is what the UI renders, so leading/trailing
/// whitespace from a tagging format must not leak into it.
List<LyricsSyllable> _trimEdges(List<LyricsSyllable> syllables) {
  if (syllables.isEmpty) return syllables;
  final first = syllables.first;
  final last = syllables.last;
  final firstText = first.text.replaceFirst(RegExp(r'^\s+'), '');
  final lastText = last.text.replaceFirst(RegExp(r'\s+$'), '');
  return [
    for (var i = 0; i < syllables.length; i++)
      if (i == 0)
        LyricsSyllable(text: firstText, start: first.start, end: first.end, isPartOfWord: false)
      else if (i == syllables.length - 1)
        LyricsSyllable(text: lastText, start: last.start, end: last.end, isPartOfWord: syllables[i].isPartOfWord)
      else
        syllables[i],
  ];
}

// --- estimating only when there is no better data -------------------------

/// Interpolates per-word timing inside a line that only has line-level
/// timing. This is an *estimate* — callers must keep reporting the track as
/// [LyricsSyncType.line] so the UI can label it as one.
///
/// Two things make it as close to real as estimation can be:
///
///  * **Syllables, not letters.** A word's sung duration tracks how many
///    syllables it has, so weights come from vowel groups (the standard cheap
///    syllable heuristic) with a small bonus for long words. "I" (1) and
///    "extraordinary" (7) no longer get equal time, which is what made the
///    earlier even split visibly trail or lead on real lyrics.
///  * **Punctuation pauses.** A word ending a clause is usually held and
///    followed by a breath, so the *next* word starts a little later: 70 ms after
///    a comma/semicolon/colon, 160 ms after a full stop or question/exclamation
///    mark. Without this, the highlight ran straight through the gap a singer
///    actually leaves.
///
/// What this cannot do is know the real word boundaries — that needs audio
/// analysis (forced alignment), which is exactly why a source that *has* word
/// timings is preferred and why the UI labels this case as an estimate.
List<LyricsSyllable> estimateSyllables(String text, Duration start, Duration end) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  final words = trimmed.split(_whitespaceRe).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  if (words.length == 1) {
    return [LyricsSyllable(text: words.first, start: start, end: end > start ? end : start)];
  }

  final weights = [for (final word in words) _sungWeight(word)];
  final totalWeight = weights.fold<int>(0, (sum, w) => sum + w);
  final spanMs = math.max(1, (end - start).inMilliseconds);

  // Sung time is bounded by an estimate of the actual singing, never by the
  // whole span: a line followed by an instrumental break must not keep its last
  // word lit for the length of the break. Never exceed the span either — that
  // would bleed into the next line.
  final sungMs = math.min(spanMs, totalWeight * kSyllableRateMs);

  // Word starts, proportional to sung weight, inside the sung window.
  final offsets = <int>[];
  var consumed = 0;
  for (var i = 0; i < words.length; i++) {
    offsets.add((sungMs * consumed / totalWeight).round());
    consumed += weights[i];
  }

  final syllables = <LyricsSyllable>[];
  for (var i = 0; i < words.length; i++) {
    final isLast = i == words.length - 1;
    final wordStart = start + Duration(milliseconds: offsets[i]);
    // The next word starts at its own offset, minus the pause this word's
    // punctuation earns — so the gap appears *after* the word, not as a jump.
    final rawEnd = isLast ? sungMs : offsets[i + 1] - _pauseAfterMs(words[i]);
    final endOffset = rawEnd > offsets[i] ? rawEnd : offsets[i] + 60;
    final wordEnd = start + Duration(milliseconds: endOffset);
    syllables.add(LyricsSyllable(
      text: isLast ? words[i] : '${words[i]} ',
      start: wordStart,
      end: wordEnd > wordStart ? wordEnd : wordStart + const Duration(milliseconds: 60),
    ));
  }
  return syllables;
}

/// Estimated singing rate: roughly how long one syllable takes at a typical
/// tempo. Used to bound a line's *sung* time independently of the line's full
/// span, because for LRC the span runs to the next line's timestamp and
/// therefore swallows the instrumental gap.
///
/// Without this, the last word of every line kept its highlight right up to the
/// next line — most visible on a line that ends before a break, where the
/// highlight visibly sat on the final word through several seconds of silence.
/// A wrong rate drifts words one way rather than randomly, which is what the
/// manual ±0.5 s sync control on the lyrics screen is for.
const int kSyllableRateMs = 300;

final RegExp _vowelGroupRe = RegExp(r'[aeiouyAEIOUY]+');

/// A word's approximate sung length: one unit per vowel group, with a small
/// bonus for long words (consonant clusters take time too).
int _sungWeight(String word) {
  final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return 1;
  final groups = _vowelGroupRe.allMatches(letters).length;
  final base = groups == 0 ? 1 : groups;
  return letters.length >= 7 ? base + 1 : base;
}

/// Milliseconds of breath after a word, based on the punctuation it ends with.
int _pauseAfterMs(String word) {
  final last = word.trimRight();
  if (last.isEmpty) return 0;
  final tail = last[last.length - 1];
  if ('.!?…'.contains(tail)) return 160;
  if (',;:—-'.contains(tail)) return 70;
  return 0;
}

/// Lines for lyrics with no timing at all. Every line carries a zero-length
/// window at 0:00 on purpose — [LyricsSyncType.static_] tells the UI not to
/// highlight or auto-scroll it, and inventing evenly-spaced timings here is
/// exactly what used to make unsynced lyrics "highlight" along a track they
/// had no relationship with.
List<LyricsLine> staticLines(String plain) {
  final texts = plain.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty);
  return [
    for (final text in texts)
      LyricsLine(syllables: [LyricsSyllable(text: text, start: Duration.zero, end: Duration.zero)], start: Duration.zero, end: Duration.zero),
  ];
}

// --- LRC ------------------------------------------------------------------

/// Parses `.lrc` text. [hasWordSync] is true only when at least one line
/// carried real inline word timestamps, so the caller can mark the result
/// [LyricsSyncType.syllable] instead of [LyricsSyncType.line].
({List<LyricsLine> lines, bool hasWordSync}) parseLrc(String lrc, {Duration fallbackDuration = Duration.zero}) {
  final timed = <({Duration start, String content})>[];

  for (final rawLine in lrc.split('\n')) {
    var rest = rawLine.trim();
    if (rest.isEmpty) continue;
    final starts = <Duration>[];
    // One or more leading timestamps; `[00:10.00][01:20.00]same text` means
    // the same lyric happens twice.
    while (true) {
      final match = _timestampRe.matchAsPrefix(rest);
      if (match == null) break;
      final start = _durationFromMatch(match);
      if (start == null) break;
      starts.add(start);
      rest = rest.substring(match.end);
      if (rest.trim().isEmpty) break;
    }
    if (starts.isEmpty) continue; // metadata tag / comment line
    final content = rest.trim();
    if (content.isEmpty) continue; // gap marker — nothing to show
    for (final start in starts) {
      timed.add((start: start, content: content));
    }
  }

  if (timed.isEmpty) return (lines: const <LyricsLine>[], hasWordSync: false);
  timed.sort((a, b) => a.start.compareTo(b.start));

  var hasWordSync = false;
  final lines = <LyricsLine>[];
  for (var i = 0; i < timed.length; i++) {
    final entry = timed[i];
    final end = i + 1 < timed.length ? timed[i + 1].start : _closeLastLine(entry.start, fallbackDuration);
    final List<LyricsSyllable> syllables;
    if (_wordTimestampRe.hasMatch(entry.content)) {
      syllables = _trimEdges(_syllablesFromWordTags(entry.content, entry.start, end));
      if (syllables.length > 1) hasWordSync = true;
    } else {
      syllables = estimateSyllables(entry.content, entry.start, end);
    }
    if (syllables.isEmpty) continue;
    lines.add(LyricsLine(syllables: syllables, start: entry.start, end: end));
  }
  return (lines: lines, hasWordSync: hasWordSync);
}

List<LyricsSyllable> _syllablesFromWordTags(String content, Duration lineStart, Duration lineEnd) {
  final matches = _wordTimestampRe.allMatches(content).toList();
  if (matches.isEmpty) return estimateSyllables(content, lineStart, lineEnd);

  final pieces = <({Duration start, String text})>[];
  final lead = content.substring(0, matches.first.start);
  if (lead.trim().isNotEmpty) pieces.add((start: lineStart, text: lead));
  for (var i = 0; i < matches.length; i++) {
    final start = _durationFromMatch(matches[i]);
    final text = content.substring(matches[i].end, i + 1 < matches.length ? matches[i + 1].start : content.length);
    if (start == null) continue;
    pieces.add((start: start, text: text));
  }
  if (pieces.isEmpty) return estimateSyllables(content, lineStart, lineEnd);

  final syllables = <LyricsSyllable>[];
  for (var i = 0; i < pieces.length; i++) {
    final text = pieces[i].text;
    if (text.isEmpty) continue;
    var end = i + 1 < pieces.length ? pieces[i + 1].start : lineEnd;
    if (end <= pieces[i].start) end = pieces[i].start + const Duration(milliseconds: 120);
    // "no space before this" — how a tagging format expresses that a syllable
    // continues the previous word instead of starting a new one.
    final isPartOfWord = syllables.isNotEmpty && !_endsWithSpace(syllables.last.text);
    syllables.add(LyricsSyllable(text: text, start: pieces[i].start, end: end, isPartOfWord: isPartOfWord));
  }
  return syllables;
}

/// True when an LRC's only content is the instrumental marker LRCLIB itself
/// recognises (`[AU: instrumental]`) — so a track with no lead vocals reads
/// as "instrumental", not as "no lyrics found".
bool isInstrumentalLrc(String lrc) {
  // Two passes on purpose: a file can carry the marker *and* real lyric lines
  // (some taggers write it as a placeholder before the text is filled in), and
  // reading that as "instrumental" would hide lyrics that are actually there.
  // Real content anywhere means this is not an instrumental file.
  var marker = false;
  for (final rawLine in lrc.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = RegExp(r'^\[([a-zA-Z#]+):(.*)\]$').firstMatch(line);
    if (match == null) return false; // real lyric content
    final key = match.group(1)!.toLowerCase();
    final value = match.group(2)!.trim().toLowerCase();
    if (key == 'au' && value.contains('instrumental')) marker = true;
  }
  return marker;
}

// --- LRCLIB word-synced Lyricsfile ---------------------------------------

class LyricsfileData {
  final List<LyricsLine> lines;
  final bool hasWordSync;
  final bool instrumental;
  final Duration offset;
  const LyricsfileData({required this.lines, required this.hasWordSync, required this.instrumental, required this.offset});
}

class _RawWord {
  String? text;
  int? startMs;
  int? endMs;
}

class _RawLine {
  String? text;
  int? startMs;
  int? endMs;
  final List<_RawWord> words = [];
}

/// Parses LRCLIB's Lyricsfile (the `lyricsfile` field of a `/api/get`
/// response) — a small, known subset of YAML, read with a tolerant
/// indentation-aware scanner rather than a YAML dependency. Field names and
/// units are taken from LRCLIB's own server implementation and test fixtures:
/// `metadata.instrumental`, `metadata.offset_ms` (may be negative),
/// `lines[].text`, `lines[].start_ms`, `lines[].end_ms`, and
/// `lines[].words[].{text,start_ms}` — every timestamp an integer in
/// milliseconds.
///
/// Returns null when the document has no timed lines at all, so callers can
/// fall back to `plainLyrics`/`syncedLyrics` from the same record.
LyricsfileData? parseLyricsfile(String yaml, {Duration fallbackDuration = Duration.zero}) {
  var instrumental = false;
  var offsetMs = 0;

  final rawLines = <_RawLine>[];
  _RawLine? current;
  var inMetadata = false;
  var inLines = false;
  var inWords = false;
  var linesIndent = -1;
  var wordsIndent = -1;
  var skipUntilIndent = -1;

  for (final rawLine in yaml.split('\n')) {
    final trimmedRight = rawLine.replaceFirst(RegExp(r'\s+$'), '');
    if (trimmedRight.trim().isEmpty) continue;
    final indent = trimmedRight.length - trimmedRight.trimLeft().length;
    final content = trimmedRight.trim();

    if (skipUntilIndent >= 0) {
      if (indent >= skipUntilIndent) continue; // body of a block scalar we don't need
      skipUntilIndent = -1;
    }
    if (content.startsWith('#')) continue;

    final isItem = content.startsWith('-');
    final body = isItem ? content.substring(1).trim() : content;
    final key = _yamlKey(body);
    final value = _yamlValue(body);

    if (!isItem && indent == 0) {
      switch (key) {
        case 'metadata':
          inMetadata = true;
          inLines = false;
          inWords = false;
          continue;
        case 'lines':
          inLines = true;
          inMetadata = false;
          inWords = false;
          continue;
        default:
          // `plain:`/`notes:`/`version:` and anything else at the root — skip
          // a block scalar's body when the value opens one.
          inMetadata = false;
          inLines = false;
          inWords = false;
          skipUntilIndent = _opensBlockScalar(value) ? indent + 2 : -1;
          continue;
      }
    }

    if (inMetadata) {
      switch (key) {
        case 'instrumental':
          instrumental = value.toLowerCase() == 'true';
        case 'offset_ms':
        case 'offset':
          offsetMs = _intValue(value) ?? offsetMs;
        default:
          break;
      }
      continue;
    }

    if (!inLines) continue;

    if (isItem && (linesIndent < 0 || indent <= linesIndent)) {
      linesIndent = indent;
      inWords = false;
      wordsIndent = -1;
      current = _RawLine();
      rawLines.add(current);
      _applyLineField(current, key, value);
      continue;
    }

    if (isItem) {
      // Deeper than a line item: a word inside the line's `words:` list.
      if (current == null) continue;
      if (key == 'words' && _isInlineEmpty(value)) continue;
      inWords = true;
      wordsIndent = indent;
      final word = _RawWord();
      current.words.add(word);
      _applyWordField(word, key, value);
      continue;
    }

    if (key == 'words') {
      inWords = true;
      wordsIndent = indent + 1;
      if (_isInlineEmpty(value)) inWords = false;
      continue;
    }

    if (current == null) continue;
    if (inWords && current.words.isNotEmpty && indent >= wordsIndent) {
      _applyWordField(current.words.last, key, value);
    } else {
      _applyLineField(current, key, value);
    }
  }

  final offset = Duration(milliseconds: offsetMs);
  final timed = <({Duration start, Duration? end, String text, List<_RawWord> words})>[];
  for (final raw in rawLines) {
    final explicit = raw.text?.trim() ?? '';
    final fromWords = raw.words.map((w) => w.text ?? '').join().trim();
    final text = explicit.isNotEmpty ? explicit : fromWords;
    if (text.isEmpty || raw.startMs == null) continue;
    timed.add((
      start: Duration(milliseconds: raw.startMs!) + offset,
      end: raw.endMs == null ? null : Duration(milliseconds: raw.endMs!) + offset,
      text: text,
      words: raw.words,
    ));
  }
  if (timed.isEmpty) return instrumental ? const LyricsfileData(lines: [], hasWordSync: false, instrumental: true, offset: Duration.zero) : null;
  timed.sort((a, b) => a.start.compareTo(b.start));

  var hasWordSync = false;
  final lines = <LyricsLine>[];
  for (var i = 0; i < timed.length; i++) {
    final entry = timed[i];
    final end = entry.end ?? (i + 1 < timed.length ? timed[i + 1].start : _closeLastLine(entry.start, fallbackDuration));
    final realWords = entry.words.where((w) => w.startMs != null && (w.text ?? '').trim().isNotEmpty).toList();
    final List<LyricsSyllable> syllables;
    if (realWords.length >= 2) {
      syllables = _trimEdges(_syllablesFromRawWords(entry.words, entry.start, end, offset));
      hasWordSync = true;
    } else {
      syllables = estimateSyllables(entry.text, entry.start, end);
    }
    if (syllables.isEmpty) continue;
    lines.add(LyricsLine(syllables: syllables, start: entry.start, end: end));
  }
  return LyricsfileData(lines: lines, hasWordSync: hasWordSync, instrumental: instrumental, offset: offset);
}

List<LyricsSyllable> _syllablesFromRawWords(List<_RawWord> words, Duration lineStart, Duration lineEnd, Duration offset) {
  final usable = [for (final w in words) if ((w.text ?? '').isNotEmpty) w];
  if (usable.isEmpty) return const [];
  final syllables = <LyricsSyllable>[];

  // Words without their own start times still need a slot: distribute the
  // untimed ones across the gap between their timed neighbours.
  final timedStarts = <int, Duration>{};
  for (var i = 0; i < usable.length; i++) {
    if (usable[i].startMs != null) timedStarts[i] = Duration(milliseconds: usable[i].startMs!) + offset;
  }
  if (timedStarts.isEmpty) return estimateSyllables(usable.map((w) => w.text ?? '').join(), lineStart, lineEnd);

  Duration startFor(int index) {
    final known = timedStarts[index];
    if (known != null) return known;
    var previousIndex = index - 1;
    while (previousIndex >= 0 && !timedStarts.containsKey(previousIndex)) {
      previousIndex--;
    }
    var nextIndex = index + 1;
    while (nextIndex < usable.length && !timedStarts.containsKey(nextIndex)) {
      nextIndex++;
    }
    final previousTime = previousIndex >= 0 ? timedStarts[previousIndex]! : lineStart;
    final nextTime = nextIndex < usable.length ? timedStarts[nextIndex]! : lineEnd;
    if (nextTime <= previousTime) return previousTime;
    final gapCount = nextIndex - previousIndex;
    final step = (nextTime - previousTime).inMilliseconds / (gapCount <= 0 ? 1 : gapCount);
    return previousTime + Duration(milliseconds: (step * (index - previousIndex)).round());
  }

  for (var i = 0; i < usable.length; i++) {
    final raw = usable[i];
    final start = startFor(i);
    final rawText = raw.text ?? '';
    final isLast = i == usable.length - 1;
    final text = isLast ? rawText.replaceFirst(RegExp(r'\s+$'), '') : (rawText.endsWith(' ') ? rawText : '$rawText ');
    var end = raw.endMs != null ? Duration(milliseconds: raw.endMs!) + offset : startFor(i + 1 < usable.length ? i + 1 : i);
    if (i == usable.length - 1 || end <= start) end = lineEnd > start ? lineEnd : start + const Duration(milliseconds: 120);
    final isPartOfWord = syllables.isNotEmpty && !_endsWithSpace(syllables.last.text);
    syllables.add(LyricsSyllable(text: text, start: start, end: end, isPartOfWord: isPartOfWord));
  }
  return syllables;
}

String _yamlKey(String body) {
  final index = body.indexOf(':');
  if (index < 0) return body.trim();
  return body.substring(0, index).trim();
}

String _yamlValue(String body) {
  final index = body.indexOf(':');
  if (index < 0) return '';
  return body.substring(index + 1).trim();
}

bool _opensBlockScalar(String value) => value == '|' || value == '>' || value == '|-' || value == '>-' || value == '|+' || value == '>+';

bool _isInlineEmpty(String value) => value.replaceAll(' ', '') == '[]';

int? _intValue(String value) {
  final cleaned = value.replaceAll('_', '').replaceAll('"', '').replaceAll("'", '').trim();
  if (cleaned.isEmpty) return null;
  final direct = int.tryParse(cleaned);
  if (direct != null) return direct;
  final asDouble = double.tryParse(cleaned);
  if (asDouble != null) return asDouble.round();
  return null; // "mm:ss.xx" style values aren't used for *_ms fields in this schema
}

void _applyLineField(_RawLine line, String key, String value) {
  switch (key) {
    case 'text':
    case 'value':
    case 'line':
      line.text = _unquote(value);
    case 'start_ms':
    case 'startMs':
    case 'start':
      line.startMs = _intValue(value) ?? line.startMs;
    case 'end_ms':
    case 'endMs':
    case 'end':
      line.endMs = _intValue(value) ?? line.endMs;
    default:
      break;
  }
}

void _applyWordField(_RawWord word, String key, String value) {
  switch (key) {
    case 'text':
    case 'value':
    case 'word':
      word.text = _unquote(value);
    case 'start_ms':
    case 'startMs':
    case 'start':
      word.startMs = _intValue(value) ?? word.startMs;
    case 'end_ms':
    case 'endMs':
    case 'end':
      word.endMs = _intValue(value) ?? word.endMs;
    default:
      break;
  }
}

String _unquote(String value) {
  var text = value.trim();
  if (text.length >= 2 && ((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("'") && text.endsWith("'")))) {
    return text.substring(1, text.length - 1);
  }
  final commentIndex = text.indexOf(' #');
  if (commentIndex >= 0) text = text.substring(0, commentIndex);
  return text.trim();
}

// --- OpenSubsonic embedded lyrics ----------------------------------------

/// Parses an OpenSubsonic `getLyricsBySongId` `lyricsList` object into a
/// [LyricsTrack]. A server can offer several `structuredLyrics` entries
/// (different languages); a synced one wins, and an unsynced one becomes
/// [LyricsSyncType.static_] rather than being given invented timings.
LyricsTrack? parseEmbeddedStructured(Map<String, dynamic> lyricsList, {required Duration songDuration}) {
  final entries = lyricsList['structuredLyrics'] as List<dynamic>?;
  if (entries == null || entries.isEmpty) return null;

  Map<String, dynamic>? synced;
  Map<String, dynamic>? unsynced;
  for (final raw in entries) {
    if (raw is! Map<String, dynamic>) continue;
    final hasTimedLines = (raw['line'] as List<dynamic>? ?? const []).any((line) => line is Map<String, dynamic> && line['start'] is num);
    if (raw['synced'] == true && hasTimedLines) {
      synced ??= raw;
    } else {
      unsynced ??= raw;
    }
  }

  final chosen = synced ?? unsynced;
  if (chosen == null) return null;
  final rawLines = chosen['line'] as List<dynamic>? ?? const [];
  final offset = Duration(milliseconds: (chosen['offset'] as num?)?.toInt() ?? 0);

  if (synced != null) {
    final timed = <({Duration start, String text})>[];
    for (final raw in rawLines) {
      if (raw is! Map<String, dynamic>) continue;
      final text = (raw['value'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      final startMs = (raw['start'] as num?)?.toInt();
      if (startMs == null) continue; // spec: start is omitted on unsynced lines
      timed.add((start: Duration(milliseconds: startMs) + offset, text: text));
    }
    if (timed.isEmpty) return null;
    timed.sort((a, b) => a.start.compareTo(b.start));

    var hasWordSync = false;
    final lines = <LyricsLine>[];
    for (var i = 0; i < timed.length; i++) {
      final entry = timed[i];
      final end = i + 1 < timed.length ? timed[i + 1].start : _closeLastLine(entry.start, songDuration);
      final List<LyricsSyllable> syllables;
      if (_wordTimestampRe.hasMatch(entry.text)) {
        syllables = _trimEdges(_syllablesFromWordTags(entry.text, entry.start, end));
        if (syllables.length > 1) hasWordSync = true;
      } else {
        syllables = estimateSyllables(entry.text, entry.start, end);
      }
      if (syllables.isEmpty) continue;
      lines.add(LyricsLine(syllables: syllables, start: entry.start, end: end));
    }
    if (lines.isEmpty) return null;
    return LyricsTrack(
      type: hasWordSync ? LyricsSyncType.syllable : LyricsSyncType.line,
      source: LyricsSource.embedded,
      lines: lines,
      wordTimingIsEstimated: !hasWordSync,
    );
  }

  final texts = rawLines
      .whereType<Map<String, dynamic>>()
      .map((line) => (line['value'] as String?)?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .toList();
  if (texts.isEmpty) return null;
  return LyricsTrack(type: LyricsSyncType.static_, source: LyricsSource.embedded, lines: staticLines(texts.join('\n')));
}

// --- candidate matching ---------------------------------------------------

/// One candidate record from an LRCLIB search, scored against what's playing.
class LyricsCandidate {
  final Map<String, dynamic> record;

  /// |candidate duration − song duration|.
  final Duration delta;
  final bool hasSyncedLyrics;

  /// 0 = title and artist match cleanly, 1 = loose (prefix/contains, or a
  /// featured-artist difference), 2 = the record doesn't really look like
  /// this track.
  final int textPenalty;

  const LyricsCandidate({required this.record, required this.delta, required this.hasSyncedLyrics, required this.textPenalty});

  /// Whether this candidate's timings are safe to sync against: it must have
  /// synced data *and* be close enough in duration. A line-synced record
  /// whose duration is wildly different is a different recording/version —
  /// syncing to it is what produces "lyrics drift more and more" reports.
  bool get timingsTrustworthy => hasSyncedLyrics && delta <= kSyncedDurationTolerance;

  String get label {
    final title = record['trackName'] as String? ?? '?';
    final artist = record['artistName'] as String? ?? '?';
    return '$title — $artist';
  }
}

/// Picks the best of an LRCLIB `/api/search` result set for the track that's
/// actually playing, instead of blindly taking the first row (which is what
/// used to attach a different recording's lyrics to a song).
LyricsCandidate? pickBestCandidate(
  Iterable<Map<String, dynamic>> records, {
  required String title,
  required String artist,
  String? album,
  required Duration duration,
}) {
  LyricsCandidate? best;
  for (final record in records) {
    if (record['instrumental'] == true) continue;
    final syncedText = (record['syncedLyrics'] as String?)?.trim() ?? '';
    final plainText = (record['plainLyrics'] as String?)?.trim() ?? '';
    final lyricsfileText = (record['lyricsfile'] as String?)?.trim() ?? '';
    if (syncedText.isEmpty && plainText.isEmpty && lyricsfileText.isEmpty) continue;

    final recordSeconds = (record['duration'] as num?)?.toDouble();
    if (recordSeconds == null) continue;
    final delta = (Duration(milliseconds: (recordSeconds * 1000).round()) - duration).abs();
    final candidate = LyricsCandidate(
      record: record,
      delta: delta,
      hasSyncedLyrics: syncedText.isNotEmpty,
      textPenalty: _textPenalty(title: title, artist: artist, album: album, record: record),
    );

    if (best == null) {
      best = candidate;
      continue;
    }
    if (_isBetter(candidate, best)) best = candidate;
  }
  return best;
}

bool _isBetter(LyricsCandidate candidate, LyricsCandidate current) {
  if (candidate.textPenalty != current.textPenalty) return candidate.textPenalty < current.textPenalty;

  // Within the same text-match tier, a trustworthy sync wins outright...
  final candidateTrust = candidate.timingsTrustworthy;
  final currentTrust = current.timingsTrustworthy;
  if (candidateTrust != currentTrust) return candidateTrust;

  // ...then closeness of duration decides, with a small preference for a
  // record that has synced text at all (its text is still worth showing, even
  // unsynced). Ranking by delta *first* matters: a synced record that is a
  // minute off is a different recording, and must lose to a plain record that
  // matches the track — otherwise the app picks lyrics for another version and
  // the highlight drifts against the audio.
  final candidateScore = candidate.delta.inMilliseconds - (candidate.hasSyncedLyrics ? 500 : 0);
  final currentScore = current.delta.inMilliseconds - (current.hasSyncedLyrics ? 500 : 0);
  return candidateScore < currentScore;
}

int _textPenalty({required String title, required String artist, String? album, required Map<String, dynamic> record}) {
  final wantedTitle = _normalizeMatchText(title);
  final wantedArtist = _normalizeMatchText(artist);
  final gotTitle = _normalizeMatchText(record['trackName'] as String? ?? record['name'] as String? ?? '');
  final gotArtist = _normalizeMatchText(record['artistName'] as String? ?? '');
  if (wantedTitle.isEmpty) return 2;

  var penalty = 0;
  if (gotTitle == wantedTitle) {
    penalty = 0;
  } else if (gotTitle.contains(wantedTitle) || wantedTitle.contains(gotTitle)) {
    penalty = 1;
  } else {
    penalty = 2;
  }
  if (penalty == 0 && wantedArtist.isNotEmpty && gotArtist.isNotEmpty && gotArtist != wantedArtist) {
    // Same title, different artist: could be a feature credit or a cover.
    // Only a loose mismatch — a strict one would reject legitimate
    // "Artist feat. X" records.
    final loose = gotArtist.contains(wantedArtist) || wantedArtist.contains(gotArtist);
    penalty = loose ? 1 : 2;
  }

  if (penalty > 0 && album != null && album.isNotEmpty) {
    final wantedAlbum = _normalizeMatchText(album);
    final gotAlbum = _normalizeMatchText(record['albumName'] as String? ?? '');
    if (wantedAlbum.isNotEmpty && gotAlbum == wantedAlbum && gotTitle == wantedTitle) {
      penalty = math.max(0, penalty - 1); // matching album rescues a loose artist match
    }
  }
  return penalty;
}

/// Recognises the qualifiers that name a *version* of a track rather than a
/// different track: "(Remastered 2011)", "- Live", "(Deluxe Edition)".
final RegExp _versionKeywordRe = RegExp(
  r'\b(?:remaster|remastered|deluxe|live|mono|stereo|explicit|clean|anniversary|edition|version|edit|mix|remix|instrumental|karaoke|\d{4})\b',
  caseSensitive: false,
);

/// Lower-cased, punctuation-free, with bracketed qualifiers removed — so
/// "Song (Remastered 2011)" and "Song (feat. X)" both compare equal to
/// "Song", which is the comparison a user expects when picking lyrics.
///
/// Version qualifiers matter more than they look: treating a remaster as a
/// "loose" title match let an unrelated record's exact title outrank the right
/// song, and the result was lyrics for a different track.
String _normalizeMatchText(String input) {
  var text = input.toLowerCase();

  // Bracketed groups that are purely a version qualifier ("(Remastered 2011)",
  // "[Live]"). A bracketed group without such a keyword is kept — it may be
  // part of the actual title.
  text = text.replaceAllMapped(RegExp(r'[([][^)\]]*[)\]]'), (match) {
    return _versionKeywordRe.hasMatch(match.group(0)!) ? ' ' : match.group(0)!;
  });

  // Bare " - Remastered 2011" / " - Live" tails.
  final dashIndex = text.indexOf(' - ');
  if (dashIndex > 0 && _versionKeywordRe.hasMatch(text.substring(dashIndex + 3))) {
    text = text.substring(0, dashIndex);
  }

  // Featured-artist credits (bracketed or bare) don't change which recording
  // this is.
  text = text.replaceAll(RegExp(r'\((?:feat|ft|with)\.?[^)]*\)'), ' ');
  text = text.replaceAll(RegExp(r'\[(?:feat|ft|with)\.?[^\]]*\]'), ' ');
  text = text.replaceAll(RegExp(r'\b(?:feat|ft)\.?\s+\S+'), ' ');
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Turns a record's `syncedLyrics`/`lyricsfile`/`plainLyrics` fields into a
/// [LyricsTrack], preferring real word timing, then line timing, then plain
/// text — and never inventing timing for text that has none.
///
/// [duration] is the duration of the track *playing* (used to close the last
/// line and to sanity-check the match), while the record's own duration is
/// reported back on [LyricsTrack.matchedDuration] so the UI can be honest
/// about a near-miss.
LyricsTrack? trackFromRecord(
  Map<String, dynamic> record, {
  required Duration duration,
  required LyricsSource source,
  Duration? matchDelta,
}) {
  if (record['instrumental'] == true) return null;

  final matchedTitle = record['trackName'] as String? ?? record['name'] as String?;
  final matchedArtist = record['artistName'] as String?;
  final recordSeconds = (record['duration'] as num?)?.toDouble();
  final matchedDuration = recordSeconds == null ? null : Duration(milliseconds: (recordSeconds * 1000).round());

  final synced = (record['syncedLyrics'] as String?) ?? '';
  final plain = (record['plainLyrics'] as String?) ?? '';
  final lyricsfile = (record['lyricsfile'] as String?) ?? '';

  if (lyricsfile.trim().isNotEmpty) {
    final parsed = parseLyricsfile(lyricsfile, fallbackDuration: duration);
    if (parsed != null && parsed.instrumental) return null;
    if (parsed != null && parsed.lines.isNotEmpty) {
      // A word-synced Lyricsfile is the most precise thing LRCLIB can hand
      // over, so it wins over the line-level `syncedLyrics` rendition of the
      // same record.
      final trustworthy = matchDelta == null || matchDelta <= kSyncedDurationTolerance;
      if (parsed.hasWordSync && trustworthy) {
        return LyricsTrack(
          type: LyricsSyncType.syllable,
          source: source,
          lines: parsed.lines,
          matchedTitle: matchedTitle,
          matchedArtist: matchedArtist,
          matchedDuration: matchedDuration,
          providerOffset: parsed.offset == Duration.zero ? null : parsed.offset,
        );
      }
      if (!parsed.hasWordSync && trustworthy) {
        return LyricsTrack(
          type: LyricsSyncType.line,
          source: source,
          lines: parsed.lines,
          matchedTitle: matchedTitle,
          matchedArtist: matchedArtist,
          matchedDuration: matchedDuration,
          providerOffset: parsed.offset == Duration.zero ? null : parsed.offset,
          wordTimingIsEstimated: true,
        );
      }
    }
  }

  if (synced.trim().isNotEmpty) {
    if (isInstrumentalLrc(synced)) return null;
    final parsed = parseLrc(synced, fallbackDuration: duration);
    final trustworthy = matchDelta == null || matchDelta <= kSyncedDurationTolerance;
    if (parsed.lines.isNotEmpty && trustworthy) {
      if (parsed.hasWordSync) {
        return LyricsTrack(
          type: LyricsSyncType.syllable,
          source: source,
          lines: parsed.lines,
          matchedTitle: matchedTitle,
          matchedArtist: matchedArtist,
          matchedDuration: matchedDuration,
        );
      }
      // Line-level only, and the record is close enough in duration to trust
      // its timings — safe to render as a synced track.
      return LyricsTrack(
        type: LyricsSyncType.line,
        source: source,
        lines: parsed.lines,
        matchedTitle: matchedTitle,
        matchedArtist: matchedArtist,
        matchedDuration: matchedDuration,
        wordTimingIsEstimated: true,
      );
    }
    if (parsed.lines.isNotEmpty && !trustworthy && plain.trim().isEmpty) {
      // Timings exist but belong to a different-length recording: show the
      // text unsynced rather than highlighting words against the wrong clock.
      return LyricsTrack(
        type: LyricsSyncType.static_,
        source: source,
        lines: staticLines(plain.isNotEmpty ? plain : synced.replaceAll(_timestampRe, '')),
        matchedTitle: matchedTitle,
        matchedArtist: matchedArtist,
        matchedDuration: matchedDuration,
      );
    }
  }

  if (plain.trim().isNotEmpty) {
    return LyricsTrack(
      type: LyricsSyncType.static_,
      source: source,
      lines: staticLines(plain),
      matchedTitle: matchedTitle,
      matchedArtist: matchedArtist,
      matchedDuration: matchedDuration,
    );
  }

  return null;
}

/// The lyrics model. Shapes are ours, not any one provider's: everything in
/// here can be produced by a real source (LRCLIB, or a Navidrome server's own
/// embedded tags) and consumed by the lyrics screen without either side
/// needing to know where the data came from.

/// A single syllable, or a whole word when the source only has word-level
/// timing, with its own timing — this is what makes progressive karaoke
/// highlighting possible. [isPartOfWord] means "no space before this", i.e.
/// this piece continues the previous word rather than starting a new one.
class LyricsSyllable {
  final String text;
  final Duration start;
  final Duration end;
  final bool isPartOfWord;

  const LyricsSyllable({required this.text, required this.start, required this.end, this.isPartOfWord = false});
}

/// One line of lyrics. [plainText] is the line's rendered text, reconstructed
/// from its syllables so the two can never disagree.
class LyricsLine {
  final List<LyricsSyllable> syllables;
  final Duration start;
  final Duration end;

  const LyricsLine({required this.syllables, required this.start, required this.end});

  String get plainText => syllables.map((s) => s.text).join();
}

/// How precise the timing actually is — this describes the *data*, not the
/// preferred look, and the screen must not render a precision the data
/// doesn't have:
///  - [syllable]: real per-word timings (an enhanced `.lrc` with inline
///    `<mm:ss.xx>` tags, or a word-synced LRCLIB Lyricsfile). Safe to render
///    as true karaoke.
///  - [line]: real per-*line* timings only. Per-word movement on top of this
///    is an estimate — see [LyricsTrack.wordTimingIsEstimated].
///  - [static_]: no timing at all. Must not be highlighted or auto-scrolled
///    as if it were synced.
enum LyricsSyncType { syllable, line, static_ }

/// Which source actually answered — shown to the user as attribution.
enum LyricsSource {
  /// LRCLIB (lrclib.net), matched by title/artist/album/duration.
  lrclib,

  /// Lyrics the Navidrome/OpenSubsonic server extracted from the file's own
  /// tags (`getLyricsBySongId`).
  embedded,

  /// Lyrics the user typed or imported on this device and chose to keep
  /// (roadmap #21). Stored per song id, consulted before every other source.
  edited,

  /// Nothing found.
  none,
}

class LyricsAttributionPerson {
  final String username;
  final String? url;
  const LyricsAttributionPerson({required this.username, this.url});
}

class LyricsTrack {
  final LyricsSyncType type;
  final LyricsSource source;
  final List<LyricsLine> lines;

  /// Writers/uploaders, when the source reports them.
  final LyricsAttributionPerson? uploader;
  final LyricsAttributionPerson? maker;

  /// What the provider actually matched, when it reports it (LRCLIB does) —
  /// shown in the UI so a near-miss ("same song, different master") is
  /// visible instead of silently drifting against the audio.
  final String? matchedTitle;
  final String? matchedArtist;
  final Duration? matchedDuration;

  /// The provider's own offset for this record, already applied to [lines] —
  /// kept so the UI can explain where a constant shift comes from.
  final Duration? providerOffset;

  /// True when the per-word timings on [lines] were interpolated from line
  /// timings rather than supplied by the provider. The screen uses this to
  /// label estimated karaoke honestly.
  final bool wordTimingIsEstimated;

  const LyricsTrack({
    required this.type,
    required this.source,
    required this.lines,
    this.uploader,
    this.maker,
    this.matchedTitle,
    this.matchedArtist,
    this.matchedDuration,
    this.providerOffset,
    this.wordTimingIsEstimated = false,
  });

  bool get hasTiming => type != LyricsSyncType.static_ && lines.isNotEmpty;

  /// Real per-word data — the only case that may be presented as true
  /// karaoke rather than an estimate.
  bool get hasRealWordSync => type == LyricsSyncType.syllable;
}

extension LyricsSourceLabel on LyricsSource {
  String get label {
    switch (this) {
      case LyricsSource.lrclib:
        return 'LRCLIB';
      case LyricsSource.embedded:
        return 'the file\'s own tags';
      case LyricsSource.edited:
        return 'your edit';
      case LyricsSource.none:
        return 'Unavailable';
    }
  }
}

/// Vestigial: LRCLIB is the only lyrics source.
///
/// "Spicy Lyrics" used to be selectable here. It was removed because there is
/// no honest way to integrate it: its API needs an application key, and every
/// request is addressed by a Spotify track ID (`/v1/lyrics/{trackId}`), which a
/// self-hosted Navidrome/OpenSubsonic library does not carry — so the setting
/// could never have done anything. Word-by-word karaoke still exists as a
/// *rendering*, driven by real word timings whenever the data has them (see
/// [LyricsTrack.hasRealWordSync]).
///
/// This enum survives only because a persisted settings payload and an AppState
/// field still reference it; the picker itself is gone.
enum LyricsProviderType { lrclib }

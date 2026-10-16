import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/lyrics.dart';
import '../../models/song.dart';
import '../../services/lyrics_service.dart';
import '../../state/app_state.dart';
import '../../state/appearance_settings.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/artwork_thumb.dart';
import '../../widgets/blurred_artwork_backdrop.dart';
import '../../widgets/immersive_scope.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/shuro_icons.dart';

/// Opens the lyrics view for whatever is playing. [song] is only the starting
/// point: the screen follows [PlayerController.currentSong] from then on, so
/// skipping a track (or letting one end) while it's open swaps the lyrics
/// instead of leaving the previous track's words on screen.
void openLyricsScreen(BuildContext context, Song song) {
  // Wrapped at the route level so the immersive mode (when the setting is on)
  // lasts exactly as long as this screen exists and is always undone on pop.
  // pushRisingOnce: a fast double-tap used to stack two copies (audit F4-5).
  pushRisingOnce(context, ImmersiveScope(child: LyricsScreen(initialSong: song)));
}

/// One track's lyrics, or the reason there are none. The screen renders the
/// *track*, never a spinner forever and never a lie.
class _LyricsView {
  final LyricsTrack? track;
  final LyricsFailureKind? failure;
  final String? detail;

  const _LyricsView.found(LyricsTrack this.track) : failure = null, detail = null;
  const _LyricsView.miss(this.failure, {this.detail}) : track = null;

  bool get hasTrack => track != null;
}

/// "11. Lyrics" — a fullscreen view of the current track's lyrics.
///
/// Correctness rules this screen follows deliberately:
///  - **It shows the live track.** The song it renders comes from
///    [PlayerController.currentSong], not from the widget it was opened with;
///    a track change re-fetches and re-renders.
///  - **Lines never reflow.** The active line is not bigger than the others
///    (the old 18→24 px jump changed every line's height, so the list shifted
///    under the scroll animation on each line change). Emphasis is colour and
///    the accent bar instead.
///  - **Scrolling is measured, not guessed.** The active line is positioned
///    with [Scrollable.ensureVisible] against its own rendered box, replacing
///    the `line * 78 px - 260` arithmetic that drifted from the real layout.
///  - **Only real timing drives the highlight.** [LyricsSyncType.static_]
///    lyrics are shown as plain text with no highlight and no auto-scroll,
///    rather than being given evenly-spaced fake timings.
///  - **One line animates per frame.** The karaoke fill repaints only the
///    active line; highlighting state changes rebuild the list a handful of
///    times per song instead of 60 times a second.
class LyricsScreen extends StatefulWidget {
  final Song? initialSong;

  /// When true the screen renders as a plain stack (no Scaffold, no header,
  /// no mini transport) so Now Playing can host it inline — the landscape
  /// right pane and the portrait "next lines" preview are the same widget.
  final bool embedded;

  /// When non-null and this is an embedded (in-Now-Playing) instance with
  /// NOTHING to show — no lyrics found, lookup failed, or the track has none
  /// — this widget replaces the small centered message. On the wide layout's
  /// half-screen pane a tiny message read as an empty/broken area; the
  /// fallback keeps the pane useful (the Up Next list).
  final Widget? embeddedFallback;

  /// When true the attribution footer and sync bar are hidden too — the
  /// portrait preview is a few lines, not a full controls surface.
  final bool compact;

  /// How the lines align. Centred on the full screen and the portrait
  /// preview; the landscape side pane passes [TextAlign.left] so the lyrics
  /// read as a proper column next to the player instead of hugging the right
  /// edge of the screen.
  final TextAlign textAlign;

  const LyricsScreen({
    super.key,
    this.initialSong,
    this.embedded = false,
    this.compact = false,
    this.embeddedFallback,
    this.textAlign = TextAlign.center,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final ScrollController _scroll = ScrollController();

  /// Index of the line being sung, or -1 before the first line starts.
  final ValueNotifier<int> _currentLine = ValueNotifier<int>(-1);

  /// The playback clock within the current line — drives the karaoke fill.
  /// Updated ~30x/sec from [PlayerController.smoothPositionStream], while the
  /// rest of the list only rebuilds when the *line* changes.
  final ValueNotifier<Duration> _position = ValueNotifier<Duration>(Duration.zero);

  final Map<int, GlobalKey> _lineKeys = {};

  late final AppState _appState;
  late final PlayerController _player;
  StreamSubscription<Duration>? _positionSub;

  /// The song whose lyrics are currently loaded ([_future] belongs to it).
  Song? _song;
  Future<_LyricsView>? _future;

  Duration _offset = Duration.zero;
  bool _autoScrollEnabled = true;

  /// Set while the user is scrolling by hand: auto-scroll stands down so the
  /// two aren't fighting over the same scroll position, and a "Resume" chip
  /// appears instead of the view silently snapping back mid-read.
  bool _manualScrolling = false;
  Timer? _manualScrollTimer;

  int _lastAutoScrolledLine = -1;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _player = context.read<PlayerController>();
    _song = widget.initialSong;
    _positionSub = _player.smoothPositionStream.listen(_onClockTick);
    if (_song != null) _startLoad(_song!);
  }

  /// Starts (or restarts) the fetch for [song]. The result is stored only if
  /// the song is still the one on screen when it lands, so a slow lookup can
  /// never overwrite a newer track's lyrics.
  void _startLoad(Song song) {
    final future = _load(song);
    _future = future;
    future.then((view) {
      if (!mounted || _song?.id != song.id) return;
      setState(() {
        _loadedView = view;
      });
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _manualScrollTimer?.cancel();
    _scroll.dispose();
    _currentLine.dispose();
    _position.dispose();
    super.dispose();
  }

  /// Embedded lyrics (the server extracted them from the file's own tags) are
  /// tried first: they're as real as any online lookup, need no fuzzy match
  /// against a title, and are usually the version the tagger synced by hand.
  /// LRCLIB runs whenever that comes back empty — including when the server
  /// answers with a structured-but-empty result ("looked, found nothing"):
  /// only REAL lines short-circuit the online lookup. Local files go through
  /// the same path: their tags (filled by the local tag enrichment) are real
  /// metadata, so a tagged import gets LRCLIB too, and an untagged one simply
  /// ends at the not-found state.
  Future<_LyricsView> _load(Song song) async {
    try {
      final embedded = await _appState.fetchEmbeddedLyrics(song);
      if (embedded != null && embedded.lines.isNotEmpty) {
        return _LyricsView.found(embedded);
      }
    } catch (_) {
      // A server that doesn't implement the extension (or hiccupped) must not
      // stop the LRCLIB fallback — AppState already swallows this, belt and
      // braces here too.
    }

    final album = _appState.albumById(song.albumId)?.title;
    final result = await LyricsService.lookup(
      title: song.title,
      artist: song.artist,
      album: album,
      duration: song.duration,
    );
    if (result.isFound) return _LyricsView.found(result.track!);
    return _LyricsView.miss(result.failure, detail: result.detail);
  }

  void _retry() {
    final song = _song;
    if (song == null) return;
    _startLoad(song);
    setState(() {});
  }

  /// The playback clock. Runs ~30x/sec while something is playing; the work
  /// here is O(1) plus, at most, one line-switch notification.
  void _onClockTick(Duration rawPosition) {
    final track = _track;
    if (track == null || !track.hasTiming) return;
    final loaded = _song;
    if (loaded == null || _player.currentSong?.id != loaded.id) {
      // Something else is playing — clear the highlight rather than pointing
      // at a line of a track that isn't the one you're hearing.
      if (_currentLine.value != -1) _currentLine.value = -1;
      return;
    }
    final position = rawPosition + _offset;
    _position.value = position;
    final index = _lineIndexAt(track, position);
    if (index != _currentLine.value) {
      _currentLine.value = index;
      _autoScrollTo(index);
    }
  }

  /// The view whose lyrics are currently on screen. The clock callback and
  /// the footer read the *loaded* track, never a half-applied switch.
  _LyricsView? _loadedView;
  LyricsTrack? get _track => _loadedView?.track;

  /// Index of the line that should be highlighted at [position] — the last
  /// line whose start has passed. Binary search rather than the old linear
  /// scan, which ran over every line on every frame.
  int _lineIndexAt(LyricsTrack track, Duration position) {
    final lines = track.lines;
    if (lines.isEmpty) return -1;
    if (position < lines.first.start) return -1;
    var low = 0;
    var high = lines.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].start <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  void _autoScrollTo(int index) {
    if (index < 0 || index == _lastAutoScrolledLine || !_autoScrollEnabled || _manualScrolling) return;
    _lastAutoScrolledLine = index;
    // After the frame that built this line, so its rendered box exists to
    // measure against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _lineKeys[index]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        // Roughly a third down the viewport: enough context above to read
        // ahead, and the target never jumps to the very edge.
        alignment: 0.34,
        duration: reduceMotionEnabled ? Duration.zero : const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onUserScroll() {
    _manualScrollTimer?.cancel();
    if (!_manualScrolling) setState(() => _manualScrolling = true);
    // Give up the override a few seconds after the user stops, so the view
    // follows the song again by itself.
    _manualScrollTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _manualScrolling = false);
      _lastAutoScrolledLine = -1;
      _autoScrollTo(_currentLine.value);
    });
  }

  void _resumeAutoScroll() {
    _manualScrollTimer?.cancel();
    setState(() => _manualScrolling = false);
    _lastAutoScrolledLine = -1;
    _autoScrollTo(_currentLine.value);
  }

  void _resetFor(Song song) {
    _song = song;
    _loadedView = null;
    _lineKeys.clear();
    _position.value = Duration.zero;
    _currentLine.value = -1;
    _lastAutoScrolledLine = -1;
    _manualScrolling = false;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    _offset = Duration(milliseconds: appState.lyricsOffsetMs);
    _autoScrollEnabled = appState.lyricsAutoScroll;

    // The live track wins over whatever this screen was opened with.
    final live = player.currentSong ?? _song ?? widget.initialSong;

    if (live == null) {
      return _shell(accent: kBrandColor, child: const _Message(icon: Icons.music_off_rounded, message: 'Nothing is playing right now.'));
    }

    if (_song?.id != live.id) {
      // A different track took over: swap the whole view (title, fetch and
      // lyrics) rather than showing this song's title over the last song's
      // words for a frame.
      _resetFor(live);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _song?.id != live.id) return;
        _startLoad(live);
        setState(() {});
      });
      return _shell(
        accent: live.gradientColors.last,
        song: live,
        child: const _Message(icon: null, loading: true, message: 'Loading lyrics…'),
      );
    }

    return ArtworkPaletteBuilder(
      artwork: live.artwork,
      fallback: live.gradientColors,
      cacheKey: live.id,
      builder: (context, colors) => _shell(
        accent: colors.last,
        song: live,
        colors: colors,
        child: FutureBuilder<_LyricsView>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _Message(icon: null, loading: true, message: 'Loading lyrics…');
            }
            final result = snapshot.data;
            if (result == null || !result.hasTrack) {
              final fallback = widget.embedded && widget.embeddedFallback != null ? widget.embeddedFallback : null;
              if (fallback != null) return fallback;
              return _failureView(result);
            }
            final track = result.track!;
            if (track.lines.isEmpty) {
              final fallback = widget.embedded && widget.embeddedFallback != null ? widget.embeddedFallback : null;
              if (fallback != null) return fallback;
              return const _Message(icon: Icons.music_off_rounded, message: 'This track has no lyrics to show.');
            }
            return _buildLyrics(track, colors.last);
          },
        ),
      ),
    );
  }

  Widget _failureView(_LyricsView? result) {
    final failure = result?.failure;
    final detail = result?.detail;
    switch (failure) {
      case LyricsFailureKind.instrumental:
        return _Message(
          icon: Icons.piano_rounded,
          message: detail ?? 'This track is instrumental.',
          caption: 'Nothing to display for a track with no lead vocals.',
        );
      case LyricsFailureKind.rateLimited:
        return _Message(
          icon: Icons.hourglass_bottom_rounded,
          message: 'Lyrics lookup is temporarily rate-limited.',
          caption: detail ?? 'LRCLIB asked this app to slow down — try again in a minute.',
          onRetry: _retry,
        );
      case LyricsFailureKind.rejected:
        return _Message(
          icon: Icons.report_gmailerrorred_rounded,
          message: "Couldn't look up lyrics.",
          caption: detail ?? 'LRCLIB refused the request.',
          onRetry: _retry,
        );
      case LyricsFailureKind.network:
        return _Message(
          icon: Icons.cloud_off_rounded,
          message: "Couldn't reach the lyrics service.",
          caption: detail ?? 'Check your connection and try again.',
          onRetry: _retry,
        );
      case LyricsFailureKind.notFound:
        return _Message(
          icon: Icons.search_off_rounded,
          message: 'No lyrics found for this track.',
          caption: detail ?? 'LRCLIB has no match for this title and artist.',
          onRetry: _retry,
        );
      case null:
        // Local import, or no track at all: [detail] explains which.
        return _Message(
          icon: Icons.info_outline_rounded,
          message: detail ?? 'Lyrics are not available for this track.',
        );
    }
  }

  /// Renders the track at exactly the precision its data supports: word-by-word
  /// karaoke only when the source supplied word timings, whole-line highlighting
  /// when it supplied line timings, and plain text when it supplied none. There
  /// is no style switch, because a style cannot create timing that isn't there.
  Widget _buildLyrics(LyricsTrack track, Color accent) {
    final isSynced = track.type != LyricsSyncType.static_;
    // Word-by-word fill whenever there is *any* timing to drive it — that is the
    // karaoke feel that was asked for. When the source only has line timings, the
    // per-word motion is an estimate, and the footer says so rather than implying
    // a precision the data doesn't have (see LyricsTrack.wordTimingIsEstimated).
    // Line-by-line mode (Settings → Appearance → Lyrics highlight): no
    // within-line fill at all — the whole current line takes the white + glow
    // treatment, everything else stays on the opacity ladder. The fill only
    // runs in word mode.
    final highlightWords = context.watch<AppearanceSettings>().lyricsHighlight == LyricsHighlight.word;
    final karaoke = isSynced && highlightWords;

    return Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) _onUserScroll();
            return false;
          },
          child: SingleChildScrollView(
            controller: _scroll,
            // Every line is laid out (lyric counts are small and text-only):
            // that is what lets the active line be scrolled to by measurement
            // instead of by estimated pixel offsets.
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < track.lines.length; i++)
                  ValueListenableBuilder<int>(
                    valueListenable: _currentLine,
                    builder: (context, currentIndex, _) {
                      final isCurrent = currentIndex == i;
                      _lineKeys.putIfAbsent(i, () => GlobalKey());
                      return _LyricsLineView(
                        key: _lineKeys[i],
                        line: track.lines[i],
                        isCurrent: isCurrent,
                        karaoke: karaoke && isCurrent,
                        position: _position,
                        accent: accent,
                        dimmed: !isSynced,
                        textAlign: widget.textAlign,
                        onTap: () => _seekToLine(track.lines[i], isCurrent),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        if (_manualScrolling)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: _ResumeChip(onTap: _resumeAutoScroll, accent: accent),
            ),
          ),
      ],
    );
  }

  /// Tapping a line jumps playback there. Uses the player's own
  /// [PlayerController.playSong] `startAt`, which works whether this track is
  /// already loaded or still starting — the previous code fired `playSong`
  /// (async!) and then seeked immediately, so the seek landed on whatever was
  /// loaded at that instant (usually the previous track, or nothing).
  void _seekToLine(LyricsLine line, bool isCurrent) {
    final song = _song;
    if (song == null) return;
    if (isCurrent) {
      _player.seekTo(line.start);
    } else {
      _player.playSong(song, startAt: line.start);
    }
  }

  Widget _shell({required Color accent, required Widget child, Song? song, List<Color>? colors}) {
    final content = Column(
      children: [
        if (!widget.embedded) _Header(song: song, accent: accent),
        Expanded(child: child),
        if (!widget.compact && !widget.embedded && _loadedView?.track != null) _AttributionFooter(track: _loadedView!.track!, detail: _loadedView!.detail),
        if (!widget.compact) _SyncBar(accent: accent, offsetMs: _offset.inMilliseconds, enabled: _track?.hasTiming ?? false),
        if (!widget.embedded && song != null) MiniTransportBar(song: song, accentColor: accent),
      ],
    );
    final stack = Stack(
      children: [
        // The same backdrop as Now Playing, pushed much further back: heavier
        // blur and a heavier scrim, because lyrics are long passages of small
        // text. Embedded mode skips it — the host surface already paints one.
        if (!widget.embedded)
          Positioned.fill(
            child: BlurredArtworkBackdrop(
              artwork: song?.artwork,
              palette: colors ?? song?.gradientColors ?? kBrandGradient,
              cacheKey: song?.id ?? 'no-track',
              style: BlurBackdropStyle.lyrics,
            ),
          ),
        SafeArea(child: content),
      ],
    );
    return widget.embedded ? stack : Scaffold(backgroundColor: Colors.black, body: stack);
  }
}

// --- line rendering -------------------------------------------------------

/// One lyric line. [isCurrent] adds the accent bar and colour; the karaoke
/// fill is only built for the current line, so a frame's repaint cost is one
/// line rather than the whole list.
class _LyricsLineView extends StatelessWidget {
  final LyricsLine line;
  final bool isCurrent;
  final bool karaoke;
  final bool dimmed;
  final ValueNotifier<Duration> position;
  final Color accent;
  final TextAlign textAlign;
  final VoidCallback onTap;

  const _LyricsLineView({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.karaoke,
    required this.position,
    required this.accent,
    required this.dimmed,
    required this.textAlign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = GoogleFonts.getFont(
      currentFontFamily,
      fontSize: 21,
      height: 1.5,
      // Constant size and weight for every line: emphasis comes from colour and a
      // paint-time scale, so switching lines never re-measures the list. Changing
      // the font size per line (the original approach) reflowed every line's
      // height and made the scroll animation judder.
      fontWeight: FontWeight.w600,
    );

    final Widget content = karaoke
        ? _KaraokeFill(line: line, position: position, accent: accent, baseStyle: baseStyle, textAlign: textAlign)
        : AnimatedDefaultTextStyle(
            // Line-by-line mode: the colour/glow change between states fades
            // over 200 ms instead of snapping — the line-level counterpart of
            // the continuous word fill.
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            style: baseStyle.copyWith(
              // Opacity ladder: current white, upcoming 66%, past 46% — one
              // system instead of assorted greys.
              color: isCurrent ? Colors.white : (dimmed ? const Color(0x75FFFFFF) : const Color(0xA8FFFFFF)),
              shadows: isCurrent ? [Shadow(color: accent.withValues(alpha: 0.35), blurRadius: 24)] : null,
            ),
            child: Text(
              line.plainText,
              // Centred on the full screen; the landscape pane passes left so
              // the column reads as one block of text.
              textAlign: textAlign,
            ),
          );

    // The owner's spec: the line being sung stays crisp; every other line
    // BLURS. The extra inner padding gives the blur room to fade inside the
    // filtered bounds — without it the filter clips at the line box and every
    // blurred line gets sharp edges above and below (seen in landscape).
    // On web the per-line ImageFiltered renders as black-box/smear artifacts
    // on CanvasKit (and stacks one layer per line) — lines dim via opacity
    // there instead, which reads almost identically.
    final Widget painted = (!isCurrent && !dimmed)
        ? (kIsWeb
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                child: Opacity(opacity: 0.42, child: content),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ImageFiltered(
                  // Subtle: 0.3 keeps surrounding lines readable while the
                  // sung line stays clearly the focus (owner tune-down from
                  // 0.8 — still reads as "defocused", not "blurred").
                  imageFilter: ImageFilter.blur(sigmaX: 0.3, sigmaY: 0.3, tileMode: TileMode.decal),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    child: content,
                  ),
                ),
              ))
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: content,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedScale(
        // ×1.06 reads as focus; the old ×1.10 bounced.
        scale: isCurrent ? 1.06 : 1.0,
        alignment: Alignment.center,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: painted,
      ),
    );
  }
}

/// Progressive word-by-word fill. Rebuilds on every clock tick, but only ever
/// for the line currently being sung.
///
/// **One continuous quantity drives it.** The colour of each syllable is a
/// function of how many of its characters have been reached, measured
/// line-wide ([_sungCharsAt]) — the same quantity the (removed) sweep used.
/// Coverage therefore crosses syllable boundaries smoothly and the fill has
/// nothing to jump at: the old per-syllable time lerp snapped grey → tint →
/// white → grey at every word boundary, which is what read as stepped.
class _KaraokeFill extends StatelessWidget {
  final LyricsLine line;
  final ValueNotifier<Duration> position;
  final Color accent;
  final TextStyle baseStyle;
  final TextAlign textAlign;

  const _KaraokeFill({required this.line, required this.position, required this.accent, required this.baseStyle, required this.textAlign});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, current, _) {
        final sungChars = _sungCharsAt(current);
        final spans = <TextSpan>[];
        var consumed = 0.0;
        for (final syllable in line.syllables) {
          final length = syllable.text.length.clamp(1, 1 << 20).toDouble();
          final coverage = ((sungChars - consumed) / length).clamp(0.0, 1.0);
          spans.add(TextSpan(text: syllable.text, style: _styleForCoverage(coverage)));
          consumed += length;
        }
        return RichText(textAlign: textAlign, text: TextSpan(children: spans));
      },
    );
  }

  /// Characters sung so far, fractional — completed syllables count in full,
  /// the syllable being sung contributes its elapsed fraction. This is the
  /// line-wide measure that makes the fill continuous.
  double _sungCharsAt(Duration current) {
    var sung = 0.0;
    for (final syllable in line.syllables) {
      final length = syllable.text.length.clamp(1, 1 << 20).toDouble();
      if (current >= syllable.end) {
        sung += length;
      } else if (current > syllable.start) {
        final total = (syllable.end - syllable.start).inMilliseconds;
        final within = total <= 0 ? 1.0 : ((current - syllable.start).inMilliseconds / total).clamp(0.0, 1.0);
        sung += length * within;
      }
    }
    return sung;
  }

  TextStyle _styleForCoverage(double coverage) {
    const upcoming = Color(0xFF999DA3); // cool grey, ≈4.5:1 against the sung white
    // easeOut on coverage: quick to leave the grey, gentle settling into
    // white — reads as motion rather than as a switch.
    final color = Color.lerp(upcoming, Colors.white, Curves.easeOut.transform(coverage)) ?? Colors.white;
    // The glow peaks mid-syllable and fades to nothing at both ends, so the
    // highlight travels as one continuous wave instead of flashing per word.
    final glow = coverage <= 0 || coverage >= 1 ? 0.0 : (1 - (2 * coverage - 1).abs());
    return baseStyle.copyWith(
      color: color,
      shadows: glow > 0.03 ? [Shadow(color: accent.withValues(alpha: 0.45 * glow), blurRadius: 18)] : null,
    );
  }
}

// --- chrome ---------------------------------------------------------------

class _Header extends StatelessWidget {
  final Song? song;
  final Color accent;
  const _Header({required this.song, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close lyrics',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
              tooltip: 'Close',
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('LYRICS', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11, letterSpacing: 1.4)),
                const SizedBox(height: 2),
                Text(
                  song?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ResumeChip extends StatelessWidget {
  final VoidCallback onTap;
  final Color accent;
  const _ResumeChip({required this.onTap, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: kCardColor.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: 0.5))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vertical_align_center_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text('Follow lyrics', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-context sync correction: the same value Settings → Sync adjustment
/// edits, but reachable while looking at the lyric that's out of step. The
/// Settings dialog's ± never accumulated (it re-read the stored value inside
/// its own builder, so "Done" saved the original), which is why nudging the
/// sync appeared to do nothing at all.
class _SyncBar extends StatelessWidget {
  final Color accent;
  final int offsetMs;
  final bool enabled;
  const _SyncBar({required this.accent, required this.offsetMs, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final label = offsetMs == 0 ? 'Lyrics in sync' : '${offsetMs > 0 ? '+' : ''}${(offsetMs / 1000).toStringAsFixed(1)}s';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: enabled ? () => appState.updateLyricsOffset(offsetMs - 500) : null,
            icon: const Icon(Icons.replay_10_rounded, size: 20),
            color: Colors.white70,
            tooltip: 'Shift lyrics 0.5s earlier',
          ),
          SizedBox(
            width: 128,
            child: Text(
              enabled ? label : 'No timing to adjust',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: enabled ? () => appState.updateLyricsOffset(offsetMs + 500) : null,
            icon: const Icon(Icons.forward_10_rounded, size: 20),
            color: Colors.white70,
            tooltip: 'Shift lyrics 0.5s later',
          ),
          if (offsetMs != 0)
            TextButton(
              onPressed: () => appState.updateLyricsOffset(0),
              child: Text('Reset', style: GoogleFonts.getFont(currentFontFamily, color: accent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _AttributionFooter extends StatelessWidget {
  final LyricsTrack track;
  final String? detail;
  const _AttributionFooter({required this.track, this.detail});

  @override
  Widget build(BuildContext context) {
    final parts = <String>['Lyrics via ${track.source.label}'];
    if (track.maker != null) parts.add('written by ${track.maker!.username}');
    if (track.uploader != null) parts.add('added by ${track.uploader!.username}');
    final precision = switch (track.type) {
      LyricsSyncType.syllable => 'word-synced',
      LyricsSyncType.line => 'line-synced · word timing estimated',
      LyricsSyncType.static_ => 'not synced',
    };
    parts.add(precision);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        children: [
          Text(
            parts.join(' · '),
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white38, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading / empty / error presentation for the lyrics body, on its black
/// backdrop rather than the app's surface colour.
class _Message extends StatelessWidget {
  final IconData? icon;
  final String message;
  final String? caption;
  final bool loading;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.message, this.caption, this.loading = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70))
            else if (icon != null)
              Icon(icon, color: Colors.white54, size: 32),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w600)),
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(caption!, textAlign: TextAlign.center, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 12, height: 1.5)),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kDividerColor)),
                child: Text('Try again', style: GoogleFonts.getFont(currentFontFamily, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slim transport bar pinned to the bottom of lyrics — play/pause and skip
/// without leaving the screen. Driven by the live player, so it stays honest
/// when the track changes underneath it.
class MiniTransportBar extends StatelessWidget {
  final Song song;
  final Color? accentColor;

  const MiniTransportBar({super.key, required this.song, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final isActive = player.currentSong?.id == song.id;
    final accent = accentColor ?? song.gradientColors.last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        children: [
          Hero(
            tag: 'artwork_${song.id}',
            child: ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 40, radius: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Previous track',
            child: IconButton(
              icon: const ShuroIcon(ShuroGlyph.previous, size: 22, color: Colors.white70),
              onPressed: player.previous,
              tooltip: 'Previous',
            ),
          ),
          Semantics(
            button: true,
            label: isActive && player.isPlaying ? 'Pause' : 'Play',
            child: GestureDetector(
              onTap: () => (isActive && player.currentSong?.id == song.id) ? player.togglePlayPause() : player.playSong(song),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                child: player.isBuffering && isActive
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                        child: ShuroIcon(
                          isActive && player.isPlaying ? ShuroGlyph.pause : ShuroGlyph.play,
                          key: ValueKey(isActive && player.isPlaying),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Next track',
            child: IconButton(
              icon: const ShuroIcon(ShuroGlyph.next, size: 22, color: Colors.white70),
              onPressed: player.next,
              tooltip: 'Next',
            ),
          ),
        ],
      ),
    );
  }
}

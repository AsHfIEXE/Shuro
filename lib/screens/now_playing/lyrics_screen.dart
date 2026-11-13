import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/lyrics.dart';
import '../../models/song.dart';
import '../../playback/event_log.dart';
import '../settings/settings_prefs.dart';
import '../../services/lyrics_service.dart';
import '../../state/app_state.dart';
import '../../state/appearance_settings.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../theme/dynamic_theme.dart';
import '../../widgets/artwork_ring.dart';
import '../../widgets/blurred_artwork_backdrop.dart';
import '../../widgets/window_caption_buttons.dart';
import '../../widgets/immersive_scope.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/shuro_icons.dart';
import '../../widgets/smooth_position_builder.dart';
import 'lyrics_edit_sheet.dart';
import 'lyrics_appearance_sheet.dart';
import 'lyrics_sync_card.dart';
import '../../services/lrc_tools.dart';
import '../../services/lyrics_prefetch.dart';
import '../../services/lyrics_resolver.dart';
import '../../widgets/click_region.dart';
import '../../widgets/desktop_context_menu.dart';
import '../../widgets/state_views.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the lyrics view for whatever is playing. [song] is only the starting
/// point: the screen follows [PlayerController.currentSong] from then on, so
/// skipping a track (or letting one end) while it's open swaps the lyrics
/// instead of leaving the previous track's words on screen.
void openLyricsScreen(BuildContext context, Song song) {
  // Wrapped at the route level so the immersive mode (when the setting is on)
  // lasts exactly as long as this screen exists and is always undone on pop.
  // pushRisingOnce: a fast double-tap used to stack two copies (audit F4-5).
  pushRisingOnce(
      context, ImmersiveScope(child: LyricsScreen(initialSong: song)));
}

/// One track's lyrics, or the reason there are none. The screen renders the
/// *track*, never a spinner forever and never a lie.
class _LyricsView {
  final LyricsTrack? track;
  final LyricsFailureKind? failure;
  final String? detail;

  const _LyricsView.found(LyricsTrack this.track)
      : failure = null,
        detail = null;
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
  final TextAlign? textAlign;

  const LyricsScreen({
    super.key,
    this.initialSong,
    this.embedded = false,
    this.compact = false,
    this.embeddedFallback,
    this.textAlign,
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
  final ValueNotifier<Duration> _position =
      ValueNotifier<Duration>(Duration.zero);

  final Map<int, GlobalKey> _lineKeys = {};

  late final AppState _appState;
  late final PlayerController _player;
  StreamSubscription<Duration>? _positionSub;

  /// The song whose lyrics are currently loaded ([_future] belongs to it).
  Song? _song;
  Future<_LyricsView>? _future;

  Duration _offset = Duration.zero;
  bool _autoScrollEnabled = true;

  /// True while the reader has scrolled UP into earlier lines. Auto-scroll
  /// stays completely off in that state — the old 6-second timer jumped the
  /// view back to the sung line and stole the reader's position repeatedly.
  bool _readingUp = false;
  double? _scrollStart;

  /// Set while the user is scrolling by hand: auto-scroll stands down so the
  /// two aren't fighting over the same scroll position, and a "Resume" chip
  /// appears instead of the view silently snapping back mid-read.
  bool _manualScrolling = false;
  Timer? _manualScrollTimer;

  int _lastAutoScrolledLine = -1;

  /// Desktop pane only: whether the tools pill's "Sync" button has expanded
  /// the inline offset bar (the bar is hidden until asked for).
  bool _showSyncPane = false;

  /// Last appearance values seen, so a change to text size or alignment can
  /// re-centre the sung line: wrapping changes every line's height, and the
  /// old scroll offset would otherwise leave the current line off screen.
  double? _seenScale;
  bool? _seenCentre;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = Provider.of<AppearanceSettings>(context);
    final changed = _seenScale != null &&
        (_seenScale != a.lyricsFontScale || _seenCentre != a.lyricsAlignCenter);
    _seenScale = a.lyricsFontScale;
    _seenCentre = a.lyricsAlignCenter;
    if (changed) {
      _lastAutoScrolledLine = -1;
      _autoScrollTo(_currentLine.value);
    }
  }

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
  /// Roadmap #21: open the editor seeded with the stored edit when one exists,
  /// otherwise with the currently shown lyrics, so fixing one wrong line never
  /// means retyping the song.
  Future<void> _openLyricsEditor() async {
    final song = _song;
    if (song == null) return;
    final store = await _appState.lyricsEditStore();
    final stored = await store.load(song.id);
    final seed = stored ?? _seedFromTrack(_loadedView?.track);
    if (!mounted) return;
    await showLyricsEditSheet(
      context,
      song: song,
      store: store,
      currentText: seed,
      onSaved: () {
        if (mounted && _song?.id == song.id) _startLoad(song);
      },
    );
  }

  /// Serializes a track back to plain/LRC text for the editor. Only real
  /// line timing is written out; estimated or absent timing stays text-only.
  String _seedFromTrack(LyricsTrack? track) {
    if (track == null) return '';
    final buffer = StringBuffer();
    for (final line in track.lines) {
      if (track.hasTiming && line.start > Duration.zero) {
        final m = line.start.inMinutes.toString().padLeft(2, '0');
        final s = (line.start.inSeconds % 60).toString().padLeft(2, '0');
        final cs = ((line.start.inMilliseconds % 1000) ~/ 10)
            .toString()
            .padLeft(2, '0');
        buffer.writeln('[$m:$s.$cs] ${line.plainText}');
      } else {
        buffer.writeln(line.plainText);
      }
    }
    return buffer.toString();
  }

  /// What the warm caches already know about [song], or null. Lets the first
  /// frame show real lyrics (the prefetcher warms current + next) rather than
  /// the skeleton, then the full lookup (which also honours saved edits)
  /// settles on top.
  _LyricsView? _peek(Song song) {
    final album = _appState.albumById(song.albumId)?.title;
    final hit = LyricsResolver.peek(
        title: song.title,
        artist: song.artist,
        album: album,
        duration: song.duration);
    if (hit == null) return null;
    return hit.isFound
        ? _LyricsView.found(hit.track!)
        : _LyricsView.miss(hit.failure, detail: hit.detail);
  }

  void _startLoad(Song song) {
    // Progressive: lyrics show as soon as ANY source answers (e.g. LRCLIB's
    // line-synced text) and upgrade in place if lrc.red's word timing lands
    // a moment later.
    final ex = SettingsExtras.instance;
    PlaybackEventLog.instance.add('lyrics.view', {
      'stage': 'load',
      'song': song.id,
      'red': ex.lyricsUseLrcRed ? 1 : 0,
      'lib': ex.lyricsUseLrclib ? 1 : 0,
      'emb': ex.lyricsUseEmbedded ? 1 : 0,
    });
    final future = _load(song, onProgress: (view) {
      if (!mounted || _song?.id != song.id) return;
      setState(() => _loadedView = view);
    });
    _future = future;
    future.then((view) {
      if (!mounted || _song?.id != song.id) return;
      PlaybackEventLog.instance.add('lyrics.view', {
        'stage': view.hasTrack ? 'shown' : 'miss',
        'song': song.id,
        if (view.hasTrack) 'src': view.track!.source.name,
        if (view.hasTrack) 'type': view.track!.type.name,
        if (!view.hasTrack) 'why': view.failure?.name,
      });
      setState(() {
        _loadedView = view;
      });
    }).catchError((Object e) {
      // A lookup must never leave the skeleton spinning forever: any
      // unexpected error becomes an explained, retryable miss.
      if (!mounted || _song?.id != song.id) return;
      PlaybackEventLog.instance.add('lyrics.view', {'stage': 'error', 'song': song.id, 'err': e.runtimeType.toString()});
      setState(() {
        _loadedView = _LyricsView.miss(LyricsFailureKind.network,
            detail: 'The lyrics lookup failed unexpectedly ($e).');
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
  Future<_LyricsView> _load(Song song, {void Function(_LyricsView)? onProgress}) {
    // Never let the skeleton spin forever: a stalled server call or storage
    // read turns into the "couldn't reach" state with a Retry button.
    return _loadInner(song, onProgress: onProgress).timeout(
      const Duration(seconds: 25),
      onTimeout: () => _LyricsView.miss(LyricsFailureKind.network,
          detail: 'The lyrics lookup timed out. Try again.'),
    );
  }

  Future<_LyricsView> _loadInner(Song song, {void Function(_LyricsView)? onProgress}) async {
    // A saved on-device edit always wins (roadmap #21): the user chose these
    // words, so neither the server's tags nor LRCLIB may override them.
    try {
      final store = await _appState
          .lyricsEditStore()
          .timeout(const Duration(seconds: 4));
      final edited =
          await store.load(song.id).timeout(const Duration(seconds: 4));
      if (edited != null && edited.trim().isNotEmpty) {
        return _LyricsView.found(LrcTools.parse(edited));
      }
    } catch (_) {
      // Storage problems degrade to the normal lookup, never to an error.
    }

    // One resolver for the whole app (also used by the prefetcher):
    // lrc.red -> LRCLIB -> embedded tags. Embedded goes through the shared
    // cache, so a prefetched track renders without waiting on the network.
    final album = _appState.albumById(song.albumId)?.title;
    final result = await LyricsResolver.resolve(
      title: song.title,
      artist: song.artist,
      album: album,
      duration: song.duration,
      onUpdate: onProgress == null
          ? null
          : (r) {
              if (r.isFound) onProgress(_LyricsView.found(r.track!));
            },
      embedded: () => EmbeddedLyricsCache.fetch(
              song.id, () => _appState.fetchEmbeddedLyrics(song))
          .timeout(const Duration(seconds: 8), onTimeout: () => null),
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
    if (index < 0 ||
        index == _lastAutoScrolledLine ||
        !_autoScrollEnabled ||
        _manualScrolling) return;
    if (_readingUp) return; // the reader owns the position while reading up
    _lastAutoScrolledLine = index;
    // After the frame that built this line, so its rendered box exists to
    // measure against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _lineKeys[index]?.currentContext;
      if (target == null) return;
      final renderObject = target.findRenderObject();
      if (renderObject == null || !renderObject.attached) return;
      // Reveal ONLY inside this lyrics view's own scrollable. The old
      // `Scrollable.ensureVisible` walked up the tree and, in the embedded
      // Now-Playing preview, could resolve to the PAGE scroll view — which
      // dragged the artwork, header and transport up and down on every lyric
      // change. If the nearest scrollable is not ours, we do nothing.
      final scrollable = Scrollable.maybeOf(target);
      if (scrollable == null) return;
      if (!_scroll.hasClients || scrollable.position != _scroll.position)
        return;
      final position = scrollable.position;
      final viewport = RenderAbstractViewport.of(renderObject);
      final reveal = viewport.getOffsetToReveal(renderObject, 0.34).offset;
      final targetOffset =
          reveal.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((targetOffset - position.pixels).abs() < 1.0) return;
      if (reduceMotionEnabled) {
        position.jumpTo(targetOffset);
      } else {
        position.animateTo(
          targetOffset,
          duration: ShuroMotion.autoscroll,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onUserScrollStart() {
    _manualScrollTimer?.cancel();
    _scrollStart = _scroll.hasClients ? _scroll.offset : 0;
    if (!_manualScrolling) setState(() => _manualScrolling = true);
  }

  void _onUserScrollUpdate(double offset) {
    final start = _scrollStart;
    if (start != null) {
      if (offset < start - 8) {
        _readingUp = true; // reading earlier lines: never yank the view
      } else if (offset > start + 24) {
        _readingUp = false; // moved back down: following may resume
      }
    }
    _manualScrollTimer?.cancel();
    _manualScrollTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _manualScrolling = false);
      _lastAutoScrolledLine = -1;
      // No forced jump on resume: it only re-enables following, so the view
      // moves on the NEXT line change. Jumping here was the "it keeps
      // auto-scrolling me away" bug.
      if (!_readingUp) _autoScrollTo(_currentLine.value);
    });
  }

  void _resumeAutoScroll() {
    _manualScrollTimer?.cancel();
    _readingUp = false;
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
    _offset = Duration(
        milliseconds: appState
            .lyricsOffsetFor(player.currentSong?.id ?? _song?.id));
    _autoScrollEnabled = appState.lyricsAutoScroll;

    // The live track wins over whatever this screen was opened with.
    final live = player.currentSong ?? _song ?? widget.initialSong;

    if (live == null) {
      return _shell(
          accent: kBrandColor,
          child: const _Message(
              icon: Icons.music_off_rounded,
              message: 'Nothing is playing right now.'));
    }

    if (_song?.id != live.id) {
      // A different track took over: swap the whole view (title, fetch and
      // lyrics) rather than showing this song's title over the last song's
      // words for a frame.
      _resetFor(live);
      // Start the lookup right now (it only assigns _future; the setState
      // happens when it lands) so a warmed cache paints on this very frame
      // instead of after a skeleton round-trip.
      _startLoad(live);
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
            final done = snapshot.connectionState == ConnectionState.done;
            // Until the full lookup settles, show whatever the warm caches
            // already hold (never the previous song's data).
            // Progressive updates (first source to answer) land in _loadedView
            // before the future completes; show them immediately.
            final result = done
                ? snapshot.data
                : (_loadedView ?? _peek(live));
            if (!done && result == null) {
              return const _LoadingSkeleton();
            }
            if (result == null || !result.hasTrack) {
              final fallback =
                  widget.embedded && widget.embeddedFallback != null
                      ? widget.embeddedFallback
                      : null;
              if (fallback != null) return fallback;
              return _failureView(result);
            }
            final track = result.track!;
            if (track.lines.isEmpty) {
              final fallback =
                  widget.embedded && widget.embeddedFallback != null
                      ? widget.embeddedFallback
                      : null;
              if (fallback != null) return fallback;
              return const _Message(
                  icon: Icons.music_off_rounded,
                  message: 'This track has no lyrics to show.');
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
          message: 'Instrumental',
          caption: 'This track has no words. Enjoy the music.',
        );
      case LyricsFailureKind.rateLimited:
        return _Message(
          icon: Icons.hourglass_bottom_rounded,
          message: 'Lyrics lookup is paused',
          caption: 'Too many requests. Showing saved lyrics where we have them.',
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
          message: 'No lyrics for this song',
          caption: detail ?? 'Search again, import an .lrc file, or write your own.',
          onRetry: _retry,
          retryLabel: 'Search again',
          secondaryLabel: 'Add lyrics',
          onSecondary: _openLyricsEditor,
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
    final highlightWords =
        context.watch<AppearanceSettings>().lyricsHighlight ==
            LyricsHighlight.word;
    final karaoke = isSynced && highlightWords;

    return Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) _onUserScrollStart();
            return false;
          },
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (_manualScrolling)
                _onUserScrollUpdate(notification.metrics.pixels);
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
                        // Distance from the sung line drives the fade ladder
                        // in the line view; before the first line the index
                        // is -1, which simply reads as "further away".
                        final distance = (i - currentIndex).abs();
                        _lineKeys.putIfAbsent(i, () => GlobalKey());
                        final appearance = context.watch<AppearanceSettings>();
                        return _LyricsLineView(
                          key: _lineKeys[i],
                          line: track.lines[i],
                          isCurrent: isCurrent,
                          distance: distance,
                          karaoke: karaoke && isCurrent,
                          position: _position,
                          accent: accent,
                          dimmed: !isSynced,
                          // A side pane keeps its own alignment; the full
                          // screen follows the user's centre/left choice.
                          wide: _wideFull,
                          textAlign: widget.textAlign ??
                              (_wideFull
                                  ? TextAlign.left
                                  : appearance.lyricsAlignCenter
                                  ? TextAlign.center
                                  : TextAlign.left),
                          fontScale: appearance.lyricsFontScale,
                          glow: appearance.lyricsGlow,
                          onTap: () => _seekToLine(track.lines[i], isCurrent),
                          onContextMenu: (pos) =>
                              _showLineMenu(pos, track.lines[i]),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_manualScrolling || _readingUp)
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

  /// Right-click on a lyric line: copy the line, or the line with the song's
  /// title and artist. Clipboard only; nothing is shared off-device.
  void _showLineMenu(Offset globalPosition, LyricsLine line) {
    final text = line.plainText.trim();
    if (text.isEmpty) return;
    final song = context.read<PlayerController>().currentSong ?? _song;
    Future<void> copy(String value, String message) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) showSuccessSnackBar(context, message);
    }

    showContextMenuAt(context, globalPosition, [
      ContextMenuItem(
        label: 'Copy line',
        icon: Icons.copy_rounded,
        onTap: () => copy(text, 'Lyric line copied'),
      ),
      ContextMenuItem(
        label: 'Copy with title and artist',
        icon: Icons.format_quote_rounded,
        onTap: () => copy(
            song == null ? text : '"$text"\n${song.title} - ${song.artist}',
            'Line copied with title and artist'),
      ),
    ]);
  }

  /// Tapping a line jumps playback there. Uses the player's own
  /// [PlayerController.playSong] `startAt`, which works whether this track is
  /// already loaded or still starting — the previous code fired `playSong`
  /// (async!) and then seeked immediately, so the seek landed on whatever was
  /// loaded at that instant (usually the previous track, or nothing).
  void _seekToLine(LyricsLine line, bool isCurrent) {
    // Tapping a line is an explicit "follow the song" action: leave reading
    // mode and re-arm auto-scroll.
    _readingUp = false;
    _manualScrollTimer?.cancel();
    _manualScrolling = false;
    final song = _song;
    if (song == null) return;
    // Lyrics time -> player time: the display clock compares rawPosition +
    // user offset against line starts, so the seek target subtracts the
    // offset again - without this a tap lands a whole offset off.
    var target = line.start - _offset;
    if (target < Duration.zero) target = Duration.zero;
    // Never reload for a tap: replaying via playSong restarted the track
    // from zero and stomped the queue entry (also the source of the
    // "playback struggles" whenever lyrics were clicked). Seek the loaded
    // track instead.
    if (_player.currentSong?.id == song.id) {
      _player.seekTo(target);
    } else {
      _player.playSong(song, startAt: target);
    }
  }

  /// Wide full-screen lyrics (desktop board): left-aligned column, big type,
  /// floating transport pill. Phones and the embedded pane keep their layouts.
  bool get _wideFull =>
      !widget.embedded &&
      !widget.compact &&
      MediaQuery.sizeOf(context).width >= 700;

  Widget _shell(
      {required Color accent,
      required Widget child,
      Song? song,
      List<Color>? colors}) {
    final wide = _wideFull;
    final content = Column(
      children: [
        if (!widget.embedded)
          Padding(
            // The immersive screens cover the shell's title bar; the window
            // caption buttons sit in the top-right corner, so the header's
            // own right-side tools keep their distance.
            padding: EdgeInsets.only(
                right: WindowCaptionButtons.supported && !widget.compact
                    ? kWindowCaptionWidth
                    : 0),
            child: _Header(
                song: song,
                accent: accent,
                wide: wide,
                onEditLyrics: _openLyricsEditor,
                onAppearance: () => showLyricsAppearanceSheet(context)),
          ),
        // Desktop pane chrome (the redesign right column): LYRICS label,
        // word-sync chip and a compact tools pill. The portrait preview
        // (compact) stays chrome-less.
        if (widget.embedded && !widget.compact)
          _EmbeddedPaneHeader(
              track: _track,
              offsetMs: _offset.inMilliseconds,
              onAppearance: () => showLyricsAppearanceSheet(context),
              onToggleSync: () =>
                  setState(() => _showSyncPane = !_showSyncPane),
              onEdit: _song == null ? null : _openLyricsEditor,
              onExpand: song == null
                  ? null
                  : () => openLyricsScreen(context, song)),
        if (widget.embedded && !widget.compact && _showSyncPane)
          _SyncBar(
              accent: accent,
              offsetMs: _offset.inMilliseconds,
              songId: song?.id ?? _song?.id,
              enabled: _track?.hasTiming ?? false),
        Expanded(
            child: wide
                ? Padding(
                    // Board: the column starts at x~210 of a 1190 canvas.
                    padding: EdgeInsets.only(
                        left: MediaQuery.sizeOf(context).width * 0.176 + 64,
                        right: 96),
                    child: child)
                : child),
        // Attribution shows in the embedded pane too: the desktop lyrics
        // column is a full lyrics surface, and "where did these words come
        // from" is not a phone-only question.
        if (!widget.compact  && _loadedView?.track != null)
          _AttributionFooter(
              track: _loadedView!.track!, detail: _loadedView!.detail),
        if (!widget.compact && !widget.embedded)
          _SyncBar(
              accent: accent,
              offsetMs: _offset.inMilliseconds,
              songId: song?.id ?? _song?.id,
              enabled: _track?.hasTiming ?? false),
        if (!widget.embedded && !wide && song != null)
          MiniTransportBar(song: song, accentColor: accent),
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
        // Board scrub rail: the ticked scroll/position indicator on the
        // right edge of the full-screen lyrics.
        if (!widget.embedded)
          Positioned(
            right: 10,
            top: 140,
            bottom: 150,
            width: 24,
            child: _LyricsScrubRail(controller: _scroll),
          ),
        SafeArea(child: content),
        // Window controls travel with the immersive screen on desktop.
        if (!widget.embedded && !widget.compact && WindowCaptionButtons.supported)
          const Positioned(top: 0, right: 0, child: WindowCaptionButtons()),
        // (No floating transport pill on the full-screen lyrics: the
        // standard sync bar and attribution stay, per review.)
      ],
    );
    return widget.embedded
        ? stack
        : Scaffold(backgroundColor: Colors.black, body: stack);
  }
}

// --- line rendering -------------------------------------------------------

/// One lyric line. [isCurrent] adds the violet cue, the w800 weight and the
/// white/glow treatment; the karaoke fill is only built for the current
/// line, so a frame's repaint cost is one line rather than the whole list.
///
/// Everything else fades by [distance] from the sung line - the redesign
/// ladder (0.55 / 0.4 / 0.3) that replaced the old per-line blur, which
/// cost a filter layer per line and read as smudge next to real text.
class _LyricsLineView extends StatefulWidget {
  final LyricsLine line;
  final bool isCurrent;

  /// |line index - sung index|, from the owner's line builder. A sung index
  /// of -1 (before the first line) simply counts as distance.
  final int distance;
  final bool karaoke;
  final bool dimmed;
  final ValueNotifier<Duration> position;
  final Color accent;
  final TextAlign textAlign;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onContextMenu;

  /// Appearance from Settings (roadmap #27): the same three knobs on every
  /// platform - text size, whether the glow renders, and (via [textAlign],
  /// resolved by the owner) centre vs left.
  final double fontScale;
  final bool glow;

  /// Desktop full-screen board layout: 32 px type (34 on the sung line via
  /// the 1.06 scale), pink cue bar outside the text, hover row with a play
  /// glyph at the right and the timestamp in the left gutter.
  final bool wide;

  const _LyricsLineView({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.karaoke,
    required this.position,
    required this.accent,
    required this.dimmed,
    required this.textAlign,
    required this.onTap,
    this.onContextMenu,
    this.fontScale = 1.0,
    this.wide = false,
    this.glow = true,
  });

  @override
  State<_LyricsLineView> createState() => _LyricsLineViewState();
}

class _LyricsLineViewState extends State<_LyricsLineView> {
  /// Desktop hover affordance (row highlight + timestamp). Touch platforms
  /// never set it; see the guard at the end of [build].
  bool _hovered = false;

  /// Redesign fade ladder: sung line 1.0, +/-1 0.55, +/-2 0.4, further 0.3.
  static double _ladderOpacity(int distance) {
    if (distance <= 0) return 1.0;
    if (distance == 1) return 0.55;
    if (distance == 2) return 0.40;
    return 0.30;
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final isCurrent = widget.isCurrent;
    final textAlign = widget.textAlign;
    final baseStyle = GoogleFonts.getFont(
      currentFontFamily,
      fontSize: (widget.wide ? 32 : 21) * widget.fontScale,
      height: 1.5,
      // Constant size for every line: emphasis comes from colour, weight and
      // a paint-time scale, so switching lines never re-measures the list.
      // The fixed line `height` is what lets the sung line go w800 without
      // reflowing the column (weight widens a line, it does not grow one).
      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
    );

    final Widget content = widget.karaoke
        ? _KaraokeFill(
            line: line,
            position: widget.position,
            accent: widget.accent,
            baseStyle: baseStyle,
            textAlign: textAlign)
        : AnimatedDefaultTextStyle(
            // Line-by-line mode: the colour/weight/glow change between
            // states fades over 200 ms instead of snapping - the
            // line-level counterpart of the continuous word fill.
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            style: baseStyle.copyWith(
              // Fade ladder by distance from the sung line (1.0 sung,
              // 0.55 / 0.4 / 0.3 away); untimed lyrics stay at the old
              // single dim tone.
              color: isCurrent
                  ? Colors.white
                  : (widget.dimmed
                      ? const Color(0x9CFFFFFF)
                      : Colors.white
                          .withValues(alpha: _ladderOpacity(widget.distance))),
              shadows: (isCurrent && widget.glow)
                  ? [
                      Shadow(
                          color: widget.accent.withValues(alpha: 0.35),
                          blurRadius: 24)
                    ]
                  : null,
            ),
            child: Text(
              line.plainText,
              // Centred on the full screen; the landscape pane passes left so
              // the column reads as one block of text.
              textAlign: textAlign,
            ),
          );

    final Widget painted = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: content,
    );

    // The sung line carries the redesign cue: a 3 px brand-violet bar at the
    // left edge when the column is left-aligned, a 22x3 violet underline
    // under the centred text otherwise.
    final Widget cued = !isCurrent
        ? painted
        : widget.wide
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  painted,
                  // 3 px pink cue bar hanging in the gutter, left of the text.
                  Positioned(
                    left: -18,
                    top: 12,
                    bottom: 12,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _kLyricsPink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              )
        : textAlign == TextAlign.left
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, right: 8),
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: kBrandColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(child: painted),
                ],
              )
            : Column(
                children: [
                  painted,
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: kBrandColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              );

    final Widget tappable = InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedScale(
        // A 1.06 read as focus; the old 1.10 bounced.
        scale: isCurrent ? 1.06 : 1.0,
        alignment: widget.wide ? Alignment.centerLeft : Alignment.center,
        duration: ShuroMotion.lineChange,
        curve: ShuroMotion.std,
        child: cued,
      ),
    );

    // Hover is a pointer affordance: there is no hover to answer on touch,
    // so those platforms keep the plain tappable line.
    if (!isDesktopPlatform) return tappable;
    final menuCallback = widget.onContextMenu;
    final showHover = _hovered && !widget.dimmed;
    final row = AnimatedContainer(
      // Board hover row: white 8% wash, r14. The timestamp says when the
      // line is sung (right edge in the pane, left gutter full screen) and
      // a play glyph says "click to seek". The InkWell below still seeks.
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: _hovered
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: ClickRegion(
              onSecondaryTapUp: menuCallback == null
                  ? null
                  : (d) => menuCallback(d.globalPosition),
              child: tappable,
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: showHover ? 1.0 : 0.0,
            child: ExcludeSemantics(
              excluding: !showHover,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 14),
                child: widget.wide
                    ? const Icon(Icons.play_arrow_rounded,
                        size: 22, color: Colors.white70)
                    : Text(
                        _formatClock(line.start),
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kStatusText, fontSize: 11),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: !widget.wide
          ? row
          : Stack(
              clipBehavior: Clip.none,
              children: [
                row,
                Positioned(
                  left: -76,
                  top: 0,
                  bottom: 0,
                  width: 52,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: showHover ? 1.0 : 0.0,
                        child: Text(
                          _formatClock(line.start),
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kStatusText, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

  const _KaraokeFill(
      {required this.line,
      required this.position,
      required this.accent,
      required this.baseStyle,
      required this.textAlign});

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
          spans.add(TextSpan(
              text: syllable.text, style: _styleForCoverage(coverage)));
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
        final within = total <= 0
            ? 1.0
            : ((current - syllable.start).inMilliseconds / total)
                .clamp(0.0, 1.0);
        sung += length * within;
      }
    }
    return sung;
  }

  TextStyle _styleForCoverage(double coverage) {
    // Redesign: sung words white, upcoming words white at 55% - the same
    // tone the +/-1 fade-ladder step uses, so the fill hands off cleanly
    // to the next line.
    // easeOut on coverage: quick to leave the dim tone, gentle settling
    // into white - reads as motion rather than as a switch.
    final upcoming = Colors.white.withValues(alpha: 0.55);
    final color = Color.lerp(
            upcoming, Colors.white, Curves.easeOut.transform(coverage)) ??
        Colors.white;
    // The glow peaks mid-syllable and fades to nothing at both ends, so the
    // highlight travels as one continuous wave instead of flashing per word.
    final glow =
        coverage <= 0 || coverage >= 1 ? 0.0 : (1 - (2 * coverage - 1).abs());
    return baseStyle.copyWith(
      color: color,
      shadows: glow > 0.03
          ? [
              Shadow(
                  color: accent.withValues(alpha: 0.45 * glow), blurRadius: 18)
            ]
          : null,
    );
  }
}

// --- chrome ---------------------------------------------------------------

class _Header extends StatelessWidget {
  final Song? song;
  final Color accent;
  final bool wide;
  final VoidCallback? onEditLyrics;
  final VoidCallback? onAppearance;
  const _Header(
      {required this.song,
      required this.accent,
      this.wide = false,
      this.onEditLyrics,
      this.onAppearance});

  @override
  Widget build(BuildContext context) {
    if (wide) return _buildWide(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close lyrics',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white, size: 28),
              tooltip: 'Close',
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('LYRICS',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white60,
                        fontSize: 11,
                        letterSpacing: 1.4)),
                const SizedBox(height: 2),
                Text(
                  song?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Lyrics appearance',
            child: IconButton(
              icon: const Icon(Icons.tune_rounded,
                  size: 20, color: Colors.white70),
              tooltip: 'Lyrics appearance',
              onPressed: onAppearance,
            ),
          ),
          Semantics(
            button: true,
            label: 'Edit lyrics',
            child: IconButton(
              icon: const Icon(Icons.edit_rounded,
                  size: 20, color: Colors.white70),
              tooltip: 'Edit lyrics',
              onPressed: song == null ? null : onEditLyrics,
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop board header: 32 px chevron circle at the left, centred
  /// "LYRICS" over "Title · Artist", and translate / edit / Aa circles at the
  /// right.
  Widget _buildWide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          _LyricsCircleButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text('LYRICS',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.8)),
                const SizedBox(height: 2),
                Text(
                  song == null
                      ? 'Nothing playing'
                      : '${song!.title} \u00b7 ${song!.artist}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _LyricsCircleButton(
            icon: Icons.translate_rounded,
            tooltip: 'Translate (not available yet)',
            onTap: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                    content: Text('Lyrics translation is not available yet'))),
          ),
          const SizedBox(width: 8),
          _LyricsCircleButton(
            icon: Icons.edit_rounded,
            tooltip: 'Edit lyrics',
            onTap: song == null ? null : onEditLyrics,
          ),
          const SizedBox(width: 8),
          _LyricsCircleButton(
            label: 'Aa',
            tooltip: 'Lyrics appearance',
            onTap: onAppearance,
          ),
        ],
      ),
    );
  }
}

/// 32 px glass circle used by the full-screen lyrics header (icon or text).
class _LyricsCircleButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  const _LyricsCircleButton(
      {this.icon, this.label, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: ClickRegion(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: icon != null
                ? Icon(icon, size: 18, color: Colors.white70)
                : Text(label ?? '',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

const Color _kLyricsPink = Color(0xFFEC4899);

/// Chrome for the embedded desktop pane (Now Playing's right column):
/// "LYRICS" label, a "Word-synced" chip when the track really carries word
/// timing, and a compact tools pill - appearance, sync offset, edit. Built
/// only when hosted as a pane (embedded and not compact); the portrait
/// preview and the fullscreen lyrics screen keep their own chrome.
class _EmbeddedPaneHeader extends StatelessWidget {
  final LyricsTrack? track;
  final int offsetMs;
  final VoidCallback onAppearance;

  /// Expands/collapses the inline [_SyncBar] under this header.
  final VoidCallback onToggleSync;
  final VoidCallback? onEdit;
  final VoidCallback? onExpand;

  const _EmbeddedPaneHeader({
    this.onExpand,
    required this.track,
    required this.offsetMs,
    required this.onAppearance,
    required this.onToggleSync,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final offsetLabel = offsetMs == 0
        ? '0.0'
        : '${offsetMs > 0 ? '+' : ''}${(offsetMs / 1000).toStringAsFixed(1)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 4),
      // The label group scales down when the pane is narrow; the tools pill
      // stays pinned right with a real gap. (The old single FittedBox around
      // the whole row made the Spacer collapse, so the pill sat on top of the
      // "LYRICS" label.)
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('LYRICS',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kMuted2,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4)),
                    if (track?.hasRealWordSync ?? false) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kGreen.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: kGreen, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Word-synced',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: kGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Tools pill: the redesign's compact controls for this column. No
          // translate control - the feature does not exist, and a dead
          // button is worse than no button.
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kHairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Lyrics appearance',
                  onPressed: onAppearance,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: const EdgeInsets.all(6),
                  icon: Text('Aa',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Translate (not available yet)',
                  onPressed: () => ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(
                          content: Text(
                              'Lyrics translation is not available yet'))),
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.translate_rounded,
                      size: 16, color: Colors.white70),
                ),
                TextButton(
                  onPressed: onToggleSync,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: GoogleFonts.getFont(currentFontFamily,
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: Text('Sync ${offsetLabel}s'),
                ),
                IconButton(
                  tooltip: 'Edit lyrics',
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.edit_rounded,
                      size: 16, color: Colors.white70),
                ),
                if (onExpand != null)
                  IconButton(
                    tooltip: 'Full-screen lyrics',
                    onPressed: onExpand,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    icon: const Icon(Icons.open_in_full_rounded,
                        size: 15, color: Colors.white70),
                  ),
              ],
            ),
          ),
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
          decoration: BoxDecoration(
              color: kCardColor.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.5))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vertical_align_center_rounded,
                  size: 16, color: accent),
              const SizedBox(width: 8),
              Text('Follow lyrics',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
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
  final String? songId;
  const _SyncBar(
      {required this.accent,
      required this.offsetMs,
      required this.enabled,
      this.songId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final label = offsetMs == 0
        ? 'Lyrics in sync'
        : '${offsetMs > 0 ? '+' : ''}${(offsetMs / 1000).toStringAsFixed(1)} s';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      // Wrap: the controls total ~290 dp and overflowed in a narrow lyrics pane.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            onPressed: enabled
                ? () => appState.nudgeLyricsOffset(songId, offsetMs - 100)
                : null,
            icon: const Icon(Icons.remove_rounded, size: 20),
            color: Colors.white70,
            tooltip: 'Shift lyrics 0.1 s earlier (saved for this song)',
          ),
          SizedBox(
            width: 128,
            child: ClickRegion(
              onTap: enabled
                  ? () => showLyricsSyncCard(context, songId: songId)
                  : null,
              child: Text(
                enabled ? label : 'No timing to adjust',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
          IconButton(
            onPressed: enabled
                ? () => appState.nudgeLyricsOffset(songId, offsetMs + 100)
                : null,
            icon: const Icon(Icons.add_rounded, size: 20),
            color: Colors.white70,
            tooltip: 'Shift lyrics 0.1 s later (saved for this song)',
          ),
          if (offsetMs != 0)
            TextButton(
              onPressed: () =>
                  appState.nudgeLyricsOffset(songId, 0, reset: true),
              child: Text('Reset',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: accent, fontSize: 12)),
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
    // Redesign footer copy: "Lyrics via <source>, Synced by <user>,
    // Per-word timing" - only the fields the track actually has.
    final parts = <String>['Lyrics via ${track.source.label}'];
    if (track.uploader != null)
      parts.add('Synced by ${track.uploader!.username}');
    if (track.maker != null) parts.add('Written by ${track.maker!.username}');
    final precision = switch (track.type) {
      LyricsSyncType.syllable => 'Syllable timing',
      LyricsSyncType.word => 'Word timing',
      LyricsSyncType.line => 'Line timing',
      LyricsSyncType.static_ => 'Not synced',
    };
    parts.add(precision);

    // lrc.red's terms ask for a visible attribution linking to the track
    // page; with no URL launcher in the app, tapping copies that link.
    final link = track.sourceUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        children: [
          ClickRegion(
            onTap: link == null
                ? null
                : () async {
                    // lrc.red's terms: credit AND link back wherever its data
                    // is shown. Open the track page; copy it if that fails.
                    var opened = false;
                    try {
                      opened = await launchUrl(Uri.parse(link),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                    if (!opened && context.mounted) {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('Copied $link')));
                    }
                  },
            child: Text(
              parts.join(' · '),
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kStatusText,
                  fontSize: 11,
                  decoration: link == null ? null : TextDecoration.underline,
                  decorationColor: Colors.white24),
            ),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white38, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading state per the redesign: shimmer skeleton lines standing in for
/// the lyric column that is about to fill in. A private mini shimmer - a
/// highlight band sweeping across rounded bars every 1.4 s - rather than a
/// spinner, so the shape of the wait matches the shape of the content.
class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton();

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: no decorative loops. The bars stay - they still say
    // "lyrics are coming" - but they hold still.
    if (reduceMotionEnabled) return const _SkeletonBars(sweepX: null);
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) => _SkeletonBars(sweepX: _sweep.value),
    );
  }
}

/// The bars themselves. [sweepX] is the sweep's 0..1 phase, or null for the
/// static reduced-motion version.
class _SkeletonBars extends StatelessWidget {
  final double? sweepX;
  const _SkeletonBars({required this.sweepX});

  // Varying widths (40-90%) so the column reads as lines of text, not a
  // grid of blocks.
  static const _widths = [0.9, 0.58, 0.82, 0.44, 0.72, 0.5, 0.86];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading lyrics',
      child: LayoutBuilder(builder: (context, constraints) {
        // Short hosts (compact landscape panes) get fewer, thinner bars so
        // the skeleton never overflows its viewport.
        final maxH = constraints.maxHeight;
        final compact = maxH.isFinite && maxH < 320;
        final tight = maxH.isFinite && maxH < 240;
        final widths =
            tight ? _widths.take(3).toList() : (compact ? _widths.take(5).toList() : _widths);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 16 : 32, 24, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final width in widths)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    child: FractionallySizedBox(
                      widthFactor: width,
                      child: _bar(compact ? 12 : 18),
                    ),
                  ),
                ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Looking for synced lyrics…',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _bar(double height) {
    final bar = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: kCardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    final x = sweepX;
    if (x == null) return bar;
    // The sweep: a translucent white band translated across the bar over
    // the 1.4 s cycle (fully off the left edge at 0, off the right at 1).
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [Colors.transparent, Colors.white24, Colors.transparent],
        stops: const [0.3, 0.5, 0.7],
        transform: _SweepShift(-1.0 + 3.0 * x),
      ).createShader(bounds),
      child: bar,
    );
  }
}

/// Shifts a gradient horizontally by [dx] bar-widths (see [_SkeletonBars]).
class _SweepShift extends GradientTransform {
  final double dx;
  const _SweepShift(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx * bounds.width, 0, 0);
}

/// Loading / empty / error presentation for the lyrics body, on its black
/// backdrop rather than the app's surface colour.
class _Message extends StatelessWidget {
  final IconData? icon;
  final String message;
  final String? caption;
  final VoidCallback? onRetry;
  final String retryLabel;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  const _Message({
    required this.icon,
    required this.message,
    this.caption,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    // Board "Lyrics - tools and states": an 80 px disc with a 36 px icon, a
    // 16/700 title, 12 px copy and 220 x 40 pills. Paused lookups are amber.
    final paused = icon == Icons.hourglass_bottom_rounded;
    final tint = paused ? const Color(0xFFF59E0B) : Colors.white;
    Widget pill(String label, VoidCallback onTap, {required bool primary}) =>
        ClickRegion(
          onTap: onTap,
          child: Container(
            width: 220,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary
                  ? const Color(0xFF7C3AED)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: GoogleFonts.getFont(currentFontFamily,
                    fontSize: primary ? 13 : 12,
                    fontWeight: FontWeight.w600,
                    color: primary ? Colors.white : const Color(0xFFE8E8F0))),
          ),
        );
    final both = onRetry != null && onSecondary != null && secondaryLabel != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: paused ? 0.12 : 0.06),
                ),
                child: Icon(icon,
                    color: paused ? tint : Colors.white54, size: 36),
              ),
            const SizedBox(height: 24),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: const Color(0xFFE8E8F0),
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            if (caption != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Text(caption!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: const Color(0xFF9AA3B5),
                        fontSize: 12,
                        height: 1.6)),
              ),
            ],
            if (onRetry != null || onSecondary != null) ...[
              const SizedBox(height: 32),
              if (onRetry != null)
                pill(retryLabel, onRetry!, primary: both),
              if (both) const SizedBox(height: 10),
              if (onSecondary != null && secondaryLabel != null)
                pill(secondaryLabel!, onSecondary!, primary: false),
            ],
          ],
        ),
      ),
    );
  }
}

class MiniTransportBar extends StatelessWidget {
  final Song song;
  final Color? accentColor;

  const MiniTransportBar({super.key, required this.song, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final isActive = player.currentSong?.id == song.id;
    final accent = accentColor ?? song.gradientColors.last;
    // The clock reads the live player when this is the track playing, and
    // the song's own tag otherwise ("1:26 / 3:24" next to the ring).
    final elapsed = isActive ? player.position : Duration.zero;
    final total = isActive ? player.duration : song.duration;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        children: [
          // Redesign: the same 52 px ring-scrub artwork language as Now
          // Playing (3 px stroke, 9 px knob - NpvMetrics), driven by the
          // smooth position builder so the arc glides like the big ring.
          // No hero: this screen sits above surfaces that already own an
          // 'artwork_' hero tag, and a shared tag in one route throws.
          SizedBox(
            width: 52,
            height: 52,
            child: SmoothPositionBuilder(
              builder: (context, player, position, progress) => ArtworkRing(
                song: song,
                progress: player.currentSong?.id == song.id ? progress : 0,
                colors: song.gradientColors,
                size: 52,
                strokeWidth: NpvMetrics.ringStrokeMini,
                knobSize: NpvMetrics.knobMini,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white60, fontSize: 11)),
                Text('${_formatClock(elapsed)} / ${_formatClock(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMuted2, fontSize: 11)),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Previous track',
            child: IconButton(
              icon: const ShuroIcon(ShuroGlyph.previous,
                  size: 22, color: Colors.white70),
              onPressed: player.previous,
              tooltip: 'Previous',
            ),
          ),
          Semantics(
            button: true,
            label: isActive && player.isPlaying ? 'Pause' : 'Play',
            child: ClickRegion(
              onTap: () => (isActive && player.currentSong?.id == song.id)
                  ? player.togglePlayPause()
                  : player.playSong(song),
              child: Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: accent),
                child: player.isBuffering && isActive
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: ShuroIcon(
                          isActive && player.isPlaying
                              ? ShuroGlyph.pause
                              : ShuroGlyph.play,
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
              icon: const ShuroIcon(ShuroGlyph.next,
                  size: 22, color: Colors.white70),
              onPressed: player.next,
              tooltip: 'Next',
            ),
          ),
        ],
      ),
    );
  }
}

/// Board transport for the wide full-screen lyrics: a 560 x 56 glass pill
/// with the ring-art, title/artist, prev / play / next, the nested sync
/// control (Sync - 0.0 s + Reset) and a 2 px pink-to-violet progress line.
class _FloatingTransportPill extends StatelessWidget {
  final Song song;
  final int offsetMs;
  final bool syncEnabled;
  const _FloatingTransportPill(
      {required this.song, required this.offsetMs, required this.syncEnabled});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final isActive = player.currentSong?.id == song.id;
    final playing = isActive && player.isPlaying;
    final label = '${offsetMs > 0 ? '+' : ''}${(offsetMs / 1000).toStringAsFixed(1)} s';
    final maxW = MediaQuery.sizeOf(context).width - 160;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW.clamp(420.0, 600.0)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xCC0B0F14),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: SmoothPositionBuilder(
                          builder: (context, p, position, progress) =>
                              ArtworkRing(
                            song: song,
                            progress: isActive ? progress : 0,
                            colors: song.gradientColors,
                            size: 40,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white60, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        padding: const EdgeInsets.all(10),
                        icon: const ShuroIcon(ShuroGlyph.previous,
                            size: 22, color: Colors.white70),
                        onPressed: player.previous,
                        tooltip: 'Previous',
                      ),
                      ClickRegion(
                        onTap: () => isActive
                            ? player.togglePlayPause()
                            : player.playSong(song),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.white),
                          child: Center(
                            child: ShuroIcon(
                              playing ? ShuroGlyph.pause : ShuroGlyph.play,
                              color: const Color(0xFF0B0F14),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        padding: const EdgeInsets.all(10),
                        icon: const ShuroIcon(ShuroGlyph.next,
                            size: 22, color: Colors.white70),
                        onPressed: player.next,
                        tooltip: 'Next',
                      ),
                      const SizedBox(width: 10),
                      // Nested sync control.
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Sync',
                                style: GoogleFonts.getFont(currentFontFamily,
                                    color: Colors.white54, fontSize: 12)),
                            const SizedBox(width: 10),
                            _SyncNudge(
                              icon: Icons.remove_rounded,
                              tooltip: 'Shift lyrics 0.1 s earlier',
                              onTap: syncEnabled
                                  ? () => appState.nudgeLyricsOffset(
                                      song.id, offsetMs - 100)
                                  : null,
                            ),
                            ClickRegion(
                              onTap: syncEnabled
                                  ? () => showLyricsSyncCard(context,
                                      songId: song.id)
                                  : null,
                              child: SizedBox(
                                width: 48,
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            _SyncNudge(
                              icon: Icons.add_rounded,
                              tooltip: 'Shift lyrics 0.1 s later',
                              onTap: syncEnabled
                                  ? () => appState.nudgeLyricsOffset(
                                      song.id, offsetMs + 100)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            ClickRegion(
                              onTap: offsetMs == 0
                                  ? null
                                  : () => appState.nudgeLyricsOffset(
                                      song.id, 0,
                                      reset: true),
                              child: Text('Reset',
                                  style: GoogleFonts.getFont(
                                      currentFontFamily,
                                      color: offsetMs == 0
                                          ? const Color(0x66A78BFA)
                                          : const Color(0xFFA78BFA),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 2 px pink -> violet progress line along the bottom edge.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: SmoothPositionBuilder(
                    builder: (context, p, position, progress) =>
                        Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor:
                            isActive ? progress.clamp(0.0, 1.0) : 0.0,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [_kLyricsPink, kBrandColor]),
                          ),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 18 px circular -/+ button inside the transport pill's sync control.
class _SyncNudge extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _SyncNudge({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: ClickRegion(
          onTap: onTap,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white
                  .withValues(alpha: onTap == null ? 0.05 : 0.12),
            ),
            child: Icon(icon,
                size: 12,
                color: onTap == null ? Colors.white30 : Colors.white),
          ),
        ),
      ),
    );
  }
}

/// m:ss clock ("1:12") for the mini transport time and the desktop hover
/// timestamps on lyric lines.
String _formatClock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Board scrub rail: tick marks down the right edge (every ~12 px, 14 px
/// long, white 35%) with a lighter thumb block showing where the viewport
/// sits. Dragging jumps the scroll; a short list shows a full-height thumb
/// and ignores drags.
class _LyricsScrubRail extends StatelessWidget {
  final ScrollController controller;

  const _LyricsScrubRail({required this.controller});

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder: the controller is a Listenable, so the thumb tracks
    // autoscroll too, not just user drags.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(builder: (context, box) {
          final h = box.maxHeight;
          final hasClients = controller.hasClients;
          final max =
              hasClients ? controller.position.maxScrollExtent : 0.0;
          final extent = hasClients
              ? controller.position.viewportDimension
              : h;
          final ratio =
              max > 0 ? (controller.offset / max).clamp(0.0, 1.0) : 0.0;
          final thumbH = max > 0
              ? (extent / (max + extent) * h).clamp(48.0, h)
              : h;
          final thumbTop = (h - thumbH) * ratio;
          final ticks = (h / 12).floor();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: max > 0
                ? (d) {
                    final local =
                        d.localPosition.dy.clamp(0.0, h);
                    controller.jumpTo((local / h) * max);
                  }
                : null,
            child: Stack(
              children: [
                for (var i = 0; i < ticks; i++)
                  Positioned(
                    right: 6,
                    top: i * 12.0 + 2,
                    child: Container(
                      width: 14,
                      height: 2,
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                Positioned(
                  right: 4,
                  top: thumbTop,
                  child: Container(
                    width: 18,
                    height: thumbH,
                    decoration: BoxDecoration(
                      color:
                          Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

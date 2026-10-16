# Playback / UI state audit — Shuro Flutter app

**Branch:** `perf/phase-1-playback-stability` (verified with `git branch --show-current`)
**Date:** 2026-10-16 · **Scope:** UI layer only (screens + widgets + the lyrics/palette providers they call)
**Method:** Read-only line-by-line review of the audited files plus the `PlayerController` contract they consume. Every finding cites `file:line` with the quoted code. `lib/` was not modified.

**Audited files**

- `lib/screens/now_playing/now_playing_screen.dart` (incl. volume sheet, sleep sheet, audio-info sheet host, scrubbing ring)
- `lib/screens/now_playing/lyrics_screen.dart` (incl. `openLyricsScreen`, the lyrics/palette providers it calls)
- `lib/screens/now_playing/queue_screen.dart`
- `lib/screens/now_playing/audio_info_sheet.dart`
- `lib/widgets/mini_player.dart`
- `lib/widgets/up_next_list.dart`, `lib/widgets/artwork_ring.dart`, `lib/widgets/blurred_artwork_backdrop.dart`, `lib/widgets/playback_controls.dart`, `lib/widgets/smooth_position_builder.dart`, `lib/widgets/page_transitions.dart`
- Providers/helpers: `lib/theme/dynamic_theme.dart` (`ArtworkPalette` / `ArtworkPaletteBuilder`), `lib/services/lyrics_service.dart`, `lib/state/player_controller.dart` (contract reference only — not an audit target)

**Severity scale**

- **HIGH** — corrupts state or crashes in ordinary use. (None found.)
- **MED** — user-visible wrong behavior in common flows; no state corruption.
- **LOW** — edge-case or cosmetic; requires a narrow timing window.

---

## Findings by bug class

### Class 1 — Stale async completions (lyrics fetch, palette extraction, route lookups, metadata enrichment)

**0 findings — all four async paths in the UI layer are correctly generation-guarded.**

- **OK — lyrics fetch is keyed per song id and guarded.** `lyrics_screen.dart:148-152`:
  ```dart
  void _startLoad(Song song) {
    ...
    if (!mounted || _song?.id != song.id) return;   // stale-fetch guard
  ```
  The same guard is repeated on the post-frame kickoff (`lyrics_screen.dart:327`: `if (!mounted || _song?.id != live.id) return;`), so a track change that lands between the build-frame reset and the load kickoff cannot start a fetch for a superseded song. Confidence: HIGH — guard checked on all entry points (`initState`, `_retry`, build-triggered change).
- **OK — `LyricsService.lookup` cannot throw past its boundary.** All exceptions are converted to `LyricsLookupResult.miss` at the boundary (`lyrics_service.dart:207-213`, catch-all `} catch (e) { return LyricsLookupResult.miss(LyricsFailureKind.network, ...); }`), so the un-guarded `.then` in `_startLoad` cannot leak an unhandled async error. Confidence: HIGH.
- **OK — `ArtworkPaletteBuilder` keys its async work per artwork/song id (the specific item this audit was asked to verify).** Re-resolve is triggered by a cacheKey change (`dynamic_theme.dart:113`: `if (oldWidget.cacheKey != widget.cacheKey) _resolve();`), the completion callback refuses stale results (`dynamic_theme.dart:119`: `if (!mounted || widget.cacheKey != key) return;`), and `build` re-checks the key before using the cached colors (`dynamic_theme.dart:131`). Extraction results are cached per id (`dynamic_theme.dart:48-77`). A palette finished *after* the track changed cannot color the new track's UI. Confidence: HIGH.
- **OK — backdrop blur-bake is generation-guarded.** `blurred_artwork_backdrop.dart:241` (`_generation++;` on every re-resolve) and `:266` (`if (!mounted || generation != _generation) { blurred.dispose(); return; }`) prevent a slow blur of the old cover from being written under the new one. Confidence: HIGH.
- **OK — route/capability recheck in `_PlayingFromLine`** is mounted-guarded (`now_playing_screen.dart:1436-1437`: `unawaited(sharedAudioCapabilityMonitor.recheck().then((r) { if (mounted) setState(() => _report = r); }));`). It writes route state, not song state, so no song-id key is needed. Confidence: HIGH.
- **OK — Audio Information sheet is a snapshot by design.** It renders `widget.song` fixed at open time with a mounted-guarded probe (`audio_info_sheet.dart:57` `if (mounted) setState(() {});` and `:85` `if (!mounted) return;` after `await StreamProbeService.probe(url)`). It labels itself with the song it describes, so a track change under it is not a stale write. Confidence: HIGH.

### Class 2 — Subscription leaks (StreamSubscription/listeners without cancel; duplicates after re-navigation)

**0 findings.**

- **OK — lyrics position stream.** `lyrics_screen.dart:141` `_positionSub = _player.smoothPositionStream.listen(_onClockTick);` is canceled in `dispose` (`lyrics_screen.dart:160-162`, alongside `_manualScrollTimer?.cancel()`). Each navigation creates a fresh screen state, so no duplicate subscriptions accumulate. Confidence: HIGH.
- **OK — volume sheet listener.** `now_playing_screen.dart:1132` registers via `VolumeController.instance.addListener(...)`, stored in `_sub`, and `dispose` removes it (`now_playing_screen.dart:1156-1159`). Confidence: HIGH.
- **OK — backdrop image stream listener.** Removed before every re-resolve (`blurred_artwork_backdrop.dart:250`) and on dispose (`:213`). Confidence: HIGH.
- **OK — no `didChangeDependencies`-based subscriptions** exist in any audited screen, so the classic "re-subscribe on every dependency change" leak cannot occur here. Confidence: HIGH.

Adjacent observation (not counted): the volume controller plugin API is global — `unawaited(VolumeController.instance.removeListener());` (`now_playing_screen.dart:1159`) detaches *the* plugin listener, not this sheet's. Today the sheet is the only subscriber in the app, so nothing breaks; if a second subscriber ever appears, this dispose will silently detach theirs. Prefer scoping it when the plugin allows.

### Class 3 — setState after dispose / async-gap dereferences

**1 finding.**

- **F3-1 · LOW — null assertion on `player.currentSong!` evaluated at tap time.** `queue_screen.dart:80`:
  ```dart
  onPressed: () => showSongActionsSheet(context, player.currentSong!),
  ```
  The row is only built while `player.currentSong != null`, but the closure re-reads the getter when tapped. If the queue is emptied in the sub-frame between build and tap (e.g. `removeFromQueue` on the last row sets `_currentSong = null` and stops the engine, `player_controller.dart:1048-1055`), the `!` throws before the rebuild repaints. Same pattern at `queue_screen.dart:56-59/73` (display-only, safe there since the row is rebuilt off the same notify). This is the async-gap family of class 3 — no `setState` is involved, but the dereference crosses the same gap. **Fix:** capture at build (`final song = player.currentSong!;` used inside the closure) or guard at tap (`final s = player.currentSong; if (s != null) showSongActionsSheet(context, s);`).

- **OK — every async `setState` in the audited surface carries a mounted/generation guard.** Verified sites: lyrics load callback `lyrics_screen.dart:152`, auto-scroll post-frame `:262`, manual-scroll timer `:282`, track-change post-frame `:327`; volume sheet system-volume read `now_playing_screen.dart:1136-1141`, delayed re-read `:1150`; sleep timer sheet `:984` (`if (!context.mounted) return;`) and `:1053` (`if (sheetContext.mounted)`); save-queue-as-playlist `queue_screen.dart:34` (`... || !context.mounted) return;`); audio-info probe `audio_info_sheet.dart:57/85`. Confidence: HIGH — every `await`/`.then`/`Timer`/post-frame callback in these files was checked.

### Class 4 — Duplicate navigation (repeated taps pushing NPV / Lyrics / Queue twice)

**5 findings — all MED. No push site in the audited surface has any duplicate guard** (`risingRoute` is a plain `PageRouteBuilder`, `page_transitions.dart:11-30`; buttons stay tappable during the 320 ms transition).

- **F4-1 · MED — mini player tap pushes Now Playing.** `mini_player.dart:67`:
  `onTap: () => Navigator.of(context).push(risingRoute(NowPlayingScreen(initialSong: song))),` — a double-tap stacks two NPV routes (each kicks off its own backdrop blur-bake and palette work).
- **F4-2 · MED — mini player swipe-up pushes Now Playing.** `mini_player.dart:83-87` (`onVerticalDragEnd` → same push). Combined with F4-1, a tap immediately followed by a flick can push twice.
- **F4-3 · MED — mini player wide-layout Queue button.** `mini_player.dart:151`: `onPressed: () => Navigator.of(context).push(risingRoute(const QueueScreen())),`
- **F4-4 · MED — Queue pushed from both NPV layouts.** `now_playing_screen.dart:339` (portrait quick actions) and `:394` (wide header): identical unguarded `push(risingRoute(const QueueScreen()))`.
- **F4-5 · MED — Lyrics pushed from three call sites.** `openLyricsScreen` (`lyrics_screen.dart:27-31`) is an unguarded `push(risingRoute(LyricsScreen(...)))`, called from `now_playing_screen.dart:346`, `:508`, and `widgets/song_actions_sheet.dart:158`.

**Fix (one helper, applied at every site):** route pushes through a shared guard, e.g.

```dart
void pushRisingOnce(BuildContext context, Widget page) {
  final nav = Navigator.of(context);
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return;   // something is already covering us
  final r = risingRoute(page);
  if (nav.canPop() && _inFlight) return;           // same-destination push already animating
  _inFlight = true;
  r.completed.whenComplete(() => _inFlight = false);
  nav.push(r);
}
```

(a static per-destination in-flight flag cleared when the route settles; `isCurrent` alone already kills the worst cases). Also applies to the modal sheets (`showModalBottomSheet` at `now_playing_screen.dart:985/1099`) which can double-open on a fast double-tap.

### Class 5 — Mini player / NPV disagreeing on current track or play state

**1 finding.**

- **F5-1 · LOW — NPV keeps rendering a "ghost" track after the controller has nothing.** `now_playing_screen.dart:97`:
  ```dart
  final song = player.currentSong ?? initialSong;
  ```
  When the queue is emptied (`PlayerController` sets `_currentSong = null`), the mini player hides itself (`mini_player.dart:46`: `song == null ? const SizedBox(...) : _MiniPlayerBar(...)`) while NPV — still open — falls back to `initialSong` and shows title/artwork/transport at a paused, zero-progress state for a song that no longer exists in any queue. **Fix:** show NPV's empty state when `player.currentSong == null` and use `initialSong` only as the pre-first-notify placeholder (e.g. keep it just for the first frame's Hero content).

- **OK — play state is derived from `PlayerController` everywhere; no screen keeps its own copy of the current song.** Mini player: `mini_player.dart:41` (`context.select((p) => p.currentSong)`) plus per-bar `isActive = player.currentSong?.id == song.id` with `isPlaying/isBuffering = isActive && player.*` (`:60-62`, again `:192`, `:241`). NPV: `now_playing_screen.dart:97-112` derives everything from the watched controller. Queue screen: `queue_screen.dart:16-21`, play/pause icon straight off `player.isPlaying`/`player.isBuffering` (`:66-77`). Up Next list: `up_next_list.dart:22`. Lyrics screen: `lyrics_screen.dart:315` (`player.currentSong ?? _song ?? widget.initialSong` — same fallback family as F5-1, so it agrees with NPV, not with the mini player; counting them as one finding). Confidence: HIGH.

### Class 6 — Seek during loading/buffering, position > duration displays, progress ring jumping on track change

**2 findings.**

- **F6-1 · MED — stale position/duration/progress rendered under the new track's title during the load window.** `_jumpTo` publishes the new song *before* any audio exists (`player_controller.dart:551-560` — `final generation = ++_loadGeneration; ... _currentSong = song; ... notifyListeners();` with the `await setAudioSource` only at `:701-709`), but the position/duration getters read the engine raw (`player_controller.dart:306`: `Duration get position => _audioPlayer.position;` and the duration getter at `:314-318` returns the engine's duration whenever it is non-null — during the window that is either the *outgoing* source's values, or, if the engine nulls duration mid-swap, the getter falls back to the new song's *tagged* duration while `position` still reports the outgoing source). The UI consumes these unconditionally once `isCurrent` is true — and `isCurrent` (`now_playing_screen.dart:108`: `final isCurrent = player.currentSong?.id == song.id;`) is trivially true for the just-published song. So `_TimesRow` (`now_playing_screen.dart:263`, `:433`) and the ring (`:174/:189`) show the old track's elapsed/total under the new title, and the mini player's bar/total do the same (`mini_player.dart:192-193`, `:242-243`). It self-corrects when the load lands — or persists up to the 20 s load timeout on a stalled network. This is the brief's "progress ring jumping on track change" symptom.
  **Fix:** expose the load-keyed state that already exists — `String? get loadedSongId => _loadedSongId;` — and gate the UI's time reads on it (`final live = player.loadedSongId == song.id;` → position/progress `live ? player.position : Duration.zero`, total `live ? player.duration : song.duration`) in both NPV (`now_playing_screen.dart:108-112`) and the mini bar (`mini_player.dart:192-193, 242-243`).

- **F6-2 · LOW — pending seek computed against the outgoing track's duration and applied unclamped after the new load.** `seekTo` clamps the target with `duration` (`player_controller.dart:939-947`), which during `_isLoading` is the *old* source's length, then defers via `_pendingSeek = t` (`:952`); after the new source lands, `_jumpTo` applies it verbatim (`:725-728`: `await _audioPlayer.seek(pending);`) with no re-clamp. A drag on the scrubbing ring (`now_playing_screen.dart:594-595`) or mini bar (`mini_player.dart:198-207`) while the next track is buffering can therefore aim past the end of a *shorter* new track — just_audio clamps to the end, which reads as an instant `completed` and an unwanted auto-advance (a thrown seek is swallowed at `:729-731`).
  **Fix:** one line where the pending seek is applied — `final max = _audioPlayer.duration; if (max != null && pending > max) pending = max;`.

- **OK — position > duration can never render.** Controller-level clamp (`player_controller.dart:327-334`, `value > 1 → 1`), NPV `_ProgressLine` clamp (`now_playing_screen.dart:752`: `value: progress.clamp(0.0, 1.0)`), ring input pre-clamped (`:88/:594`), mini bar clamp (`mini_player.dart:243`), volume rows clamp (`now_playing_screen.dart:1182/1210/1283`). Confidence: HIGH.
- **OK — the UI never seeks the engine directly.** Both seek surfaces route through `seekToProgress → seekTo` and its pending-seek machinery (`now_playing_screen.dart:89`, `:595`; `mini_player.dart:201`), so a seek during a load is deferred and applied to the right track, not to whatever is loaded. Confidence: HIGH.
- **OK — lyric-line tap seek is race-free.** `lyrics_screen.dart:496-498` uses `seekTo(line.start)` / `playSong(song, startAt: line.start)`; `playSong` folds the position into the load itself (`player_controller.dart:874`, `initialPosition: startAt` at `:576`) instead of the old play-then-seek race described in the code comment. Confidence: HIGH.
- **OK — `previous()` no longer trusts stale engine position.** It restarts the current track only when that track is actually loaded (`player_controller.dart:993-1000`: `final loadedForCurrent = song != null && !_isLoading && _loadedSongId == song.id;` before checking `position.inSeconds > 3`). Confidence: HIGH.

### Class 7 — Listener leaks on PlayerController / ChangeNotifier

**0 findings.**

- **OK — the audited UI never calls `player.addListener`.** All screens subscribe through provider `watch`/`select` (auto-managed with the element): `mini_player.dart:41/58`, `queue_screen.dart:16`, `up_next_list.dart:22`, lyrics screen build. Confidence: HIGH.
- **OK — the app's only manual `addListener` pair is balanced.** `app.dart:437-440` adds four listeners (`AppState` + `PlayerController`) and `app.dart:587-590` removes the same four on rebind/dispose. Confidence: HIGH.

---

## Adjacent observations (outside the 7 classes — noted, not counted)

1. **`SmoothPositionBuilder` is dead code.** Nothing instantiates it (`grep` across `lib/` finds only its own file); the doc comments on `PlayerController.smoothPositionStream` still claim the progress ring uses it. Consequence: the NPV ring and mini bar step at the ~1 Hz `notifyListeners` rate instead of per-frame. Perf polish, not a state bug. (`smooth_position_builder.dart:9-35`.)
2. **`ArtworkPalette.extract` has no in-flight dedup** (`dynamic_theme.dart:48-56`): two concurrent extractions for the same uncached key both decode the image; the second write to `_cache` is an equal-valued no-op. Perf-only.
3. **`_LyricsScreenState.build` mutates state during build** (`_resetFor` + `jumpTo`, `lyrics_screen.dart:315-325`) — legal but delicate; currently safe because `jumpTo` is `hasClients`-guarded and the heavy work is deferred to a mounted-guarded post-frame callback.
4. **Queue list rows capture `player.queue` snapshots at build time** (`queue_screen.dart:20-21`, `up_next_list.dart:26-37`): a tap processed in the same frame as a queue mutation acts on the stale snapshot; `playSong` re-establishes a queue containing the tapped song, so the worst case is a benign rollback of autoplay appends.

---

## Summary table

| # | Bug class | Findings | Highest severity |
|---|-----------|----------|------------------|
| 1 | Stale async completions | 0 (5 paths checked, all OK) | — |
| 2 | Subscription leaks | 0 (3 checked OK) | — |
| 3 | setState after dispose / async-gap deref | 1 (F3-1) | LOW |
| 4 | Duplicate navigation | 5 (F4-1 … F4-5) | MED |
| 5 | Mini player / NPV state disagreement | 1 (F5-1) | LOW |
| 6 | Seek during loading / progress correctness | 2 (F6-1, F6-2) | MED |
| 7 | ChangeNotifier listener leaks | 0 (2 checked OK) | — |
| | **Total** | **9** | **MED** |

**Headline:** the async-lifecycle core of this UI layer is in genuinely good shape — every await/then/timer path that writes song-dependent state carries a song-id generation guard and a mounted check (classes 1, 2, 7 are clean, including the `ArtworkPaletteBuilder` keying this audit specifically asked to verify). The two classes worth fixing before the perf phase lands are **duplicate navigation** (one shared push guard fixes all five sites) and the **load-window progress/seek staleness** (gate position reads on the existing `_loadedSongId`; re-clamp `_pendingSeek` at apply time).

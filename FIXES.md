# Shuro — playback, streaming quality and lyrics fixes

**Date:** 2026-10-13 · **Scope:** the Flutter app in this folder (`lib/`)
**Diff:** 25 files changed · 3 added · 2 removed · 53 unchanged
**Rollback:** `_backup_lib/` is a byte-identical copy of `lib/` taken before the first edit
(+ `_baseline_analyze.txt` holds the pre-change analyzer output).

## Verify it yourself

```powershell
cd shuro
flutter analyze --no-pub     # 24 issues, 0 errors   (before: 37 issues, 0 errors)
flutter test  --no-pub       # 45 tests, all passing
```

> `flutter test` needs `PUB_CACHE` when run from a bare shell:
> `$env:PUB_CACHE="$env:LOCALAPPDATA\Pub\Cache"`

There is no device, emulator, Navidrome server or LRCLIB access in the environment
this was written in, so **nothing below was verified by playing audio**. Evidence is:
static analysis, 45 unit tests over the extracted logic, and the specs of the APIs
involved (quoted where it matters). Section 8 lists what remains unverified.

---

## 1. Playback

| Symptom you reported | Root cause in the code | Fix |
| --- | --- | --- |
| UI doesn't update when you play a new song | `NowPlayingScreen` kept the song it was constructed with and fell back to it whenever the player's current song differed (`now_playing_screen.dart:48-50`) | It now renders `player.currentSong ?? initialSong` — the constructor argument is only the starting point |
| …and the lyrics screen was worse | `LyricsScreen` held `widget.song` for its header, its fetch **and** its transport bar, so a track change left the previous track's words on screen and never re-fetched (`lyrics_screen.dart:57,77-90`) | Follows `PlayerController.currentSong`, re-fetches on change, and discards a slow result that no longer matches the song on screen |
| Going back/forward misbehaves | `previous()` read `_audioPlayer.position`, which still reports the **outgoing** track's position right after a switch — so "previous" restarted the track you had just moved to instead of going back (`player_controller.dart:308-310`) | `previous()` only trusts the engine's position when it is reporting the current song; otherwise it steps back in the queue |
| A new song sometimes got skipped instantly | `_onPlayerStateChanged` advanced the queue on **any** `completed` event, including one from the source being replaced (`:139-146`) | Only the track the engine actually finished (`_loadedSongId == currentSong.id`, no load in flight) may advance |
| Random failures when tapping tracks quickly | Overlapping load requests (see §2) | Loads are serialised through `_loadChain`; a superseded load is ignored by a generation counter and can neither publish state nor start audio |
| Play button dead after a failed load | A failed load set the song but left nothing loaded | `_needsReload`: pressing play re-attempts the load instead of flipping an icon over silence |
| Progress/time drifting against the audio | Everything used the server's *tagged* duration (`player_controller.dart:196-206`) | `duration` prefers the engine's own decoded duration, falling back to the tag before load |
| Tapping a lyric line did nothing (or seeked the wrong track) | `playSong()` (async) was followed immediately by `seekTo()` (`lyrics_screen.dart:100-102`), so the seek landed on whatever was loaded at that instant | `playSong(..., startAt:)` plus `_pendingSeek`, applied when that load lands |
| Tapping the card of the song already playing restarted it from 0:00 | Cards called `playSong` unconditionally | New `PlayerController.playOrToggle` — cards, tiles and lists pause what's playing instead |
| No sign anything was loading | — | `isBuffering` drives a spinner in the transport button, mini player and queue row |

**Bonus fix found while reading:** `AppShell` wraps the mini player and nav bar in a
`SafeArea`, and Home/Library rails were 200 px fixed-height with 150 px cards — both
fine for now, but neither accounts for large text scale (see §8).

## 2. Your debug log — the `AbortError`

```
RethrownDartError: AbortError: The play() request was interrupted by a new load request.
```

That is the browser's HTML5 media element refusing a `play()` whose source was replaced
before it started — i.e. a second `setUrl` racing a `play()` that hadn't settled. It is
the same race the generation counter addresses, seen from the platform side.

Two changes:

1. **Loads are serialised.** `_jumpTo` chains onto `_loadChain`, so the next load starts
   only after the previous one has settled — the interruption is never created.
2. **Interruption is not an error.** `_startPlayback()` treats `PlayerInterruptedException`
   and abort-style messages (`aborterror`, `interrupted by a new load request`,
   `interrupted by a call to pause`) as expected outcomes, so they can't surface as a
   spurious "Couldn't play…" snackbar over the track you actually chose.

I could not reproduce this locally (no Chrome run here), so the fix is matched to the
exact error string rather than observed. If it recurs, the only remaining route would be
a load started from two places at once — there is no such path left in this code.

## 3. Lyrics

### LRCLIB ("won't work now, for some reason")

Verified against LRCLIB's own docs (lrclib.net/docs):

* they **require** clients to identify themselves — `User-Agent`, or `X-User-Agent` /
  `Lrclib-Client` as alternatives. The old client sent none of them, which is one way
  this quietly stops working;
* a `429` must be obeyed using the server's `Retry-After` header ("Your client **must**
  honor this header. Ignoring it and continuing to send requests may result in a
  temporary ban") — the old client treated `429` as a plain error and retried on the
  next screen open;
* malformed parameters are rejected **before** the API layer and return **plain text**,
  not JSON — the old client `json.decode`d the body unconditionally, so an error page
  was a crash rather than a "no lyrics" result.

Now: identifying headers on every request; `429`/`503` honoured with `Retry-After` (and a
client-side cooldown so a rate-limited app stops hammering); ≥300 ms spacing between
requests; per-track result cache plus in-flight dedupe (the screen previously re-issued
up to three requests every single time it was opened); content-type check before decode;
typed failures (`notFound`, `instrumental`, `rateLimited`, `rejected`, `network`) each with
their own honest message and a working **Try again**.

### Matching the *right* recording

The search fallback used to take `results.first` — which is how a different recording's
lyrics (and timings) get attached to your song. Now:

* the album is sent with the exact lookup as well (it was dropped);
* search results are **ranked** by duration proximity with a ±5 s tolerance plus
  title/artist matching that ignores `feat.` credits and version qualifiers
  (`(Remastered 2011)`, `- Live`, `(Deluxe Edition)`);
* timings from a recording whose length differs by more than 5 s are **never** used to
  drive the highlight — the text still shows, explicitly marked unsynced. This was the
  main cause of "lyrics sync so badly": the words were fine, the clock belonged to a
  different version;
* instrumental records produce "This track is instrumental", not "No lyrics found".

### Real word-level sync (not an estimate)

Word-by-word movement is now driven by real timings where they exist:

* enhanced `.lrc` with inline `<mm:ss.xx>` tags;
* LRCLIB's word-synced Lyricsfile — `lines[].words[].start_ms`, **integer milliseconds**.
  The schema and units were read from LRCLIB's own server implementation and test
  fixtures (`server/src/lyricsfile.rs`), not guessed. `metadata.offset_ms` is applied.

Everything else renders at the precision it actually has: line-level data gets whole-line
highlighting, unsynced text is plain with **no highlight and no auto-scroll** (it used to
be given evenly-spaced fake timings, which is why unsynced lyrics scrolled along like a
wrong karaoke track).

### The screen itself

* **Lines are centred** (your note) — the sung line is the focal point instead of a
  left-aligned list item with a rail pushing it off-centre.
* **No reflow.** The active line no longer switches 18 px → 24 px, which used to change
  every line's height and shift the list under the scroll animation on each line change.
  Emphasis is colour, shadow and opacity; geometry stays put.
* **Measured scrolling.** The active line is positioned with `Scrollable.ensureVisible`
  against its own rendered box, replacing `line * 78 px − 260` arithmetic that drifted
  from the real layout.
* **Smooth karaoke.** Within the current line each word interpolates from "upcoming" to
  the accent colour with easing, instead of switching state — and only that one line
  repaints per frame (the old version rebuilt the whole list ~30×/second).
* **Scroll vs. auto-scroll.** Dragging the lyrics pauses follow-along and shows a
  "Follow lyrics" chip; it resumes on its own a few seconds after you stop.
* **Sync adjustment that works.** The Settings ± dialog never accumulated (it re-read the
  stored value inside its own builder, so "Done" saved the original number) — fixed, and
  the same ±0.5 s controls now sit on the lyrics screen where you need them.

### Spicy Lyrics: removed

You said to remove it if it can't work, so it's gone. It genuinely can't be called from
this app: the real endpoint is `api.spicylyrics.org/v1/lyrics/{trackId}`, it needs an
application key, and every request is addressed by a **Spotify** track ID — which a
self-hosted Navidrome/OpenSubsonic library doesn't carry. Removed: the provider option,
its picker sheet, the dead `data/mock_lyrics.dart` fixture, and the model fields only
that fixture used. A documented single-value stub keeps the persisted setting and
`AppState` field compiling (see §7).

## 4. Streaming quality

* **Original** still requests `format=raw` (spec: "use the special value `raw` to disable
  transcoding"). It now *also* sends `maxBitRate=0` ("If set to zero, no limit is
  imposed") so servers that honour only one of the two signals still serve the untouched
  file — **this half is currently blocked, see §7.**
* **A real check, not a claim.** Audio Information → *"Check what the server sends"* asks
  the server for the track's actual stream URL and reads the response headers (a 1-byte
  range request; the body is dropped immediately), then reports media type, size, range
  support and a verdict: *original file served* / *server is transcoding* / *could not be
  verified*. This is the first time the app can distinguish "I asked for original" from
  "I got original".
* **Non-Wi-Fi is transcoded by design** in the old defaults: `mobileQuality` is `High`,
  i.e. `maxBitRate=320`, so on mobile data every stream is re-encoded. The sheet now says
  which setting applied and how to get the untouched file.
* **Honest settings.** ReplayGain, Gapless playback, Crossfade and Volume normalization
  only ever wrote values nothing read; the switches are gone, replaced by one line saying
  so. (just_audio 0.9.46 exposes no playlist/offload API on this code path, so making them
  real would mean a different playback architecture — see §8.)

## 5. Home tab and general UX

* **Cards are obviously interactive.** Every card now has an ink ripple, a semantics
  label, and the card for the track that's playing shows a pause control (tap it to
  pause; tap elsewhere on the card to toggle) instead of silently restarting it.
* **Rails are no longer dead ends.** "Recently Played", "Recently Added", "Recommended
  for you" and "Recently Played Albums" all have a working **See all**, backed by two new
  screens (`SongListScreen`, `AlbumGridScreen`) with play-all and shuffle actions. Rail
  headers show ~2.5 of up to 10 cards, so the rest was previously unreachable.
* **No more fake loading.** Home always showed a 650 ms skeleton, even with a library
  already in memory. It now appears only while the first fetch is genuinely in flight.
* **Search isn't a dead end.** The search bar is a real control (button semantics, ripple)
  and the pushed search screen has a back button — it had no AppBar, so on desktop/web the
  only way out was a system gesture that doesn't exist there.
* **Queue**: the play/pause affordance is a working control (it used to show a *pause*
  icon exactly when playback was already paused) and shows a spinner while buffering.
* **Destructive actions ask first**: removing a local folder and swipe-deleting a local
  file both confirm, and both say the files on disk are untouched.
* **Downloads no longer lie**: the storage bar was computed from a made-up 45 MB/song;
  it's replaced by real counts plus a note that downloads are simulated in this build.
* **Smart playlists show real counts** (they claimed "4 songs" forever, because only a
  4-song collage preview is stored).
* **Contrast**: the shared muted-text token was `white38` (~3.0–3.6:1 — below the 4.5:1
  AA bar) and used for nearly every subtitle; it's now `white54` (~5.9:1).
* **Accessibility**: transport controls and icon-only buttons have semantics labels and
  tooltips; "See all" and the profile avatar are ~44 px targets.
* **Snackbars**: cleared before showing (they used to queue up and arrive late), shared
  styling, and "Not interested" no longer records the same negative feedback twice.
* **Reduce animations** is honoured by the shimmer placeholders too.

## 6. Tests added

`test/lyrics_parser_test.dart` (39 tests) and `test/stream_probe_test.dart` (6 tests) cover
the rules that were getting this wrong: LRC/enhanced-LRC/lyricsfile/embedded parsing and
their units, real-vs-estimated word sync, unsynced text never getting fake timings,
candidate ranking and duration tolerance, version-qualifier normalisation, and the
probe's verdict logic.

Two of them failed on first run and **the tests were right** — both were bugs in my new
code, fixed before delivery:

1. `isInstrumentalLrc` reported an instrumental file when the marker appeared *alongside*
   real lyric lines, which would have hidden real lyrics;
2. version qualifiers like `(Remastered 2011)` were scored as a *loose* title match, so an
   unrelated record with an exact title could outrank the correct song.

## 7. Blocked by the workspace write guard — needs your call

The write guard refuses to save any file containing a credential-shaped literal. Two files
have lines that trip it, and both are **false positives** — plain variable references:

| File | Flagged line |
| --- | --- |
| `lib/state/app_state.dart:172` | `password: m['password'] as String` (reading persisted server config) |
| `lib/backend/navidrome_api_client.dart:33` | `token: token,` (constructor field assignment) |

`lib/backend/navidrome_music_repository.dart` is very likely in the same state (it passes
`password:` into the client). I have not worked around the guard — that's its rule — so
three items are **not done**:

1. **`maxBitRate=0` alongside `format=raw`** for Original quality (§4) — the remaining half
   of "make sure Original really is original" for servers that ignore `format=raw`;
2. removing the now-vestigial `lyricsProvider` field, its persisted settings key and the
   single-value enum stub (§3);
3. **persisting your avatar and recent searches** across restarts (both are in-memory only
   today; `_persistSettings` never writes them).

Tell me which way you want to go and I'll finish accordingly — or, if you'd rather not
touch those files at all, items 1–3 are small self-contained patches I can hand you as
text to apply yourself.

## 8. Not verified, or still true as-is

* **Nothing was played.** No device/emulator/server here: playback behaviour, real LRCLIB
  responses and real Navidrome response headers were not exercised end to end.
* **Gapless playback and crossfade remain unimplemented** (just_audio 0.9.46 has no
  playlist/offload API on this path). They're now labelled honestly rather than switched
  on and ignored.
* **Downloads are simulated end to end** — no bytes are written. The UI now says so.
* **Saved server passwords are stored unencrypted** (`shared_preferences`, not secure
  storage — the pubspec comment already admitted this). Worth moving to
  `flutter_secure_storage`; that's a config + migration change, not a bug fix.
* **Multi-language embedded lyrics**: a synced entry is preferred, but there's no language
  picker when a server offers several translations.
* **Text-scale overflow** on fixed-height rails and the mini player is reduced but not
  eliminated; a proper pass would use `MediaQuery.textScalerOf`-aware heights throughout.
* A few rows of the README still describe the old model (the lyrics-provider paragraph is
  updated; the quality/limitations sections are not).

## Round 7 — visual pass (shuffle/repeat clarity, backgrounds, karaoke, notification, nav, grids)

- **Library grids fixed**: Albums/Artists/Genres used *fixed* column counts (2/3/2) — at 1920 px that meant one ~950 px cell per item, the giant circles in the screenshots. All three grids now use `maxCrossAxisExtent` (albums 200, artists 170, genres 240), so columns grow with width and cells keep their designed size on every device.
- **Shuffle/repeat now state-explicit**: new `PlayerModeButton` — muted when off, accent-coloured with a dot when on, repeat-one swaps icon and shows a "1" badge; tooltips and screen-reader labels state the mode in words ("Repeat one, on"). The old pair was two icons with two opacities, which read as disabled.
- **Third Now Playing background**: Settings → Now Playing background now offers **Animated blur** (Apple-style), **Animated gradient** (new — the artwork palette as a slowly rotating sweep, no image processing), and **Static artwork colours**.
- **Smoother karaoke**: the active line renders as a continuous *sweep* — a dim base with a masked bright copy, feathered edge, sub-word motion computed from the syllable timings (per-frame cost is one small shader, no text re-layout). The old word-by-word colour fill remains selectable in Settings → Lyrics highlight.
- **Notification**: app label capitalised to "Shuro" (the media notification header shows the app label), notification channel named/described properly, badge enabled. The layout itself is Android's system media template — its colours come from the artwork; a fully custom notification layout would mean replacing audio_service's media-notification integration.
- **Open-source attribution**: Settings → About gained "Open source licenses" (Flutter's auto-collected licence page covering every linked package) and "Services & data sources" (LRCLIB, Last.fm, MusicBrainz, Cover Art Archive, Navidrome/OpenSubsonic).
- **New navigation**: Shuro's own design on all form factors — floating capsule bottom bar on phones, matching slim rail with the app mark on wide screens; active destination gets a brand-tinted pill + filled icon (shape + colour, so it reads for colour-blind users too).

## Round 8 — Subsonic API features, reference navbar, NPV/Lyrics redesign (ui-ux-pro-max)

- **Server feature layer** (`lib/backend/subsonic_api.dart`, new): the interactive half of the Subsonic API the catalogue client never covered — search3, star/unstar, setRating/getSong, scrobble (submission + now-playing), getRandomSongs, getSongsByGenre, getSimilarSongs2, getTopSongs, playlist CRUD, savePlayQueue/getPlayQueue, getScanStatus/startScan. Own auth (same md5-salt scheme), typed failures, honest Child→Song mapping (no fabricated format/bitrate). 7 unit tests.
- **Play counting** (P0): Shuro never told the server about plays. Now: `scrobble` submission=false on track start (shows in Navidrome's "now playing"), submission=true at the listen threshold (≥50% or 4 min) — Navidrome play counts work. Wired via `PlayerController.onTrackStarted/onListenThresholdReached` + `ServerLink` (app.dart), fire-and-forget.
- **Favourites sync** (P0): favourites were device-local only. All 4 heart call sites now go through `Favorites.toggle` → star/unstar to the server; on connect `ServerLink` merges both ways (server stars appear locally, local-only hearts get pushed).
- **Ratings**: the song action sheet shows the server's own userRating (fetched live via getSong) with 5-tap star setting (setRating), only when a server is connected.
- **Rescan**: Settings → Server → "Rescan server library" calls startScan and reports the file count.
- **Navbar**: rebuilt to the owner's reference — compact floating rounded-rectangle (16 px corners, not a capsule), icon-only, centred, active tab white + small brand dot; wide screens keep a slim labelled rail in the same language (`lib/widgets/shuro_nav.dart`).
- **Queue/song sheet overflow fixed**: the 192 px bottom overflow in the action sheet (small landscape windows) — the sheet is now height-bounded (85%) and scrollable.
- **NPV/Lyrics redesign per `_refs/uidesign_npv_lyrics.md`** (written against ui-ux-pro-max rules): backdrop σ 46→20 so the artwork reads as *blurred artwork* (was grey mush), flat scrim 0.34→0.16, lyrics scrim 0.58→0.40, artwork decoded ≤512 px (ResizeImage), crossfade 720→480 ms, breathe 30 s / amplitude 0.03; lyrics: 21/1.5 w600 ladder (current white + accent glow 0.35/24, upcoming 66%, past 46%), emphasis ×1.10→×1.06/260 ms, sweep feather clamp(0.08×width, 24–44) with accent glow on the sung copy; NPV: title 22/28 w700, artist 14 white60, eyebrow 11 w600 ls 2.0, track-change 360 ms rise-in/fade-out.
- **Deferred from the spec** (next round): static grain layer (needs a noise asset), staggered entry choreography, merged bottom action row, ring glow retune, progress-snap on track change.
- **For later**: Last.fm-based recommendations — the seam exists (`getSimilarSongs2`/`getTopSongs` + Last.fm client + scrobble history); server playlist CRUD UI and play-queue sync are client-ready but not yet surfaced.

## Round 9 — karaoke wrap fix, landscape NPV, customizable backdrop, full-width nav

- **Karaoke wrap bug fixed**: a logical lyric line that wrapped onto two visual rows lit up both rows at once — the sweep was one left-to-right mask across the whole box, so row 2's start revealed together with row 1's. The sweep is now a CustomPainter that reads the text's own line metrics and clips row by row: full rows above the sung edge, a partial character-accurate rect on the edge's row, nothing below. Sub-word smoothness kept.
- **Landscape Now Playing, reference-style**: at ≥1024 px the screen is now player-left / lyrics-right — artwork ring (up to 560 dp) with a thin progress line + split times under it, title, transport; the right pane is the live lyrics view (own lyrics-weight backdrop for legibility, expand button to open full screen). Portrait fills its empty space with the live "current + next lines" lyric preview between transport and the bottom actions (fade-masked, tap-to-seek; the LYRICS bar still opens the full screen).
- **Backdrop customization**: Settings → Appearance → **Background blur** (slider, 0.4×–2.0× the designed sigma, live) and **Background motion** (Still / Subtle / Normal — period 50 s & amplitude 1.2% on subtle, off on still). Both persist.
- **Navbar full width**: edge-to-edge bottom bar, rounded top corners, 74 dp tall + labelled items (the small floating capsule left the bottom edge bare).
- **Bigger artwork**: Library albums 200→230 dp cells, artists 170→200; NPV ring caps raised (phone 320→360, wide 460→560).
- **Original quality everywhere**: mobile data silently defaulted to High (320 kbps). A one-time migration flips the stored default to Original (format=raw) — later explicit user choices in Settings are respected.

## Round 10 — karaoke/NPV regression fix, smooth adaptive backdrop, server playlists, real downloads, app icon

- **Lyrics/NPV regression fixed**: the shader-sweep karaoke renderer mislaid its painted copy on device (overlapping lines). It is removed; the karaoke is now one proven per-syllable colour fill (white sung, accent-glow on the syllable being sung, grey upcoming) that cannot desync from its layout. The NPV lyric preview is a fixed 150 dp strip again — not the whole lower screen.
- **Smooth adaptive backdrop (the lag fix)**: the old breathe re-filtered a blurred subtree every frame — a full ImageFiltered re-raster at 60 fps, which is what read as "sloppy lagging". The backdrop is now: **mesh gradient** (4–5 palette-coloured nodes drifting on slow orbits, painted as cheap radial fills) + the artwork **blurred once per track** into a small cached `ui.Image`, then *drawn* per frame (a texture blit) with the breathe applied to the draw. Same look, a fraction of the per-frame cost — motion is smooth now, and the blur/motion settings still apply (blur strength re-renders the cached plate, motion level sets the shared clock).
- **Server playlists**: the Playlists tab now shows an "On your server" section — every playlist Navidrome reports, with create, rename, delete and "add the playing song" for the ones the logged-in user owns (ownership read from the server's `owner` field), and a detail screen with Play all / Shuffle / tap-to-play. Changes hit the server immediately.
- **Real downloads**: downloads used to be a 1.2-second fake progress animation — no file, no location, nothing survived anything. Now: the track streams at original quality (format=raw) to disk (default: the app's documents folder, which **survives app updates**; or a folder you pick — Downloads → Change location), real byte progress, a persisted registry (songId → file + metadata) rebuilt on restart, and offline playback prefers the downloaded file automatically.
- **Play all / Shuffle all** in Library → Songs: the sort defines the order, shuffle randomises it; both queue the whole list.
- **App icon**: the owner's artwork (two gradient pills on #0B0F14) rendered to every launcher density plus an Android adaptive icon (dark background layer + scaled foreground).
- **Honest notes**: Navidrome's Subsonic API does not expose tag/metadata editing, so "manage my library" means what the API allows — playlists, favourites, ratings, and the scan trigger (Settings → Server → Rescan), all live. Artwork caching uses Flutter's ImageCache (in-memory); persistent artwork caching is a documented follow-up.

## Round 11 — corner seam fixed, notification media controls (native queue)

- **Playbar/navbar corner mismatch fixed**: the mini player and the nav bar were two stacked shapes with their own corners — a rounded bottom against a rounded top with a seam. The mini player is now merged INTO the nav bar's rounded block (`ShuroNavBar.header`), one surface, one set of corners; the mini player's own border is gone.
- **Notification media controls (the missing features)**: the notification only ever showed pause + stop because playback loaded ONE song at a time — the system template shows previous/next only when the native playlist actually has them. Playback now loads the whole queue as one native playlist (`ConcatenatingAudioSource`, original-quality URLs per item, per-item MediaItems): **previous / pause / next** appear in the notification, notification skips move the app (index listener follows the engine and fires play-reporting), and Android 13+ can render its seek bar. In-app next/previous/shuffle/repeat/autoplay logic is unchanged; native moves ride a plain engine seek with a full-reload fallback.
- Honest limits: the yellow/coloured background, the layout, and the stop button are Android's system media template (from just_audio_background) — not customizable without replacing the notification stack. A seek bar inside the notification itself only exists on Android 13+; on Android 9 (BlueStacks) the system template can't render one.

## Round 12 — red-screen fix, wrong-song fix (PACT handoff)

Contract: (1) the red error text over the NPV backdrop must go; (2) picking a song must play THAT song — app display, Navidrome scrobble, and audio must agree; (3) LYRICS affordance redesigned. Non-goals: notification stack, no player rewrite.

- **Red error screen fixed**: `createLocalImageConfiguration` (reads MediaQuery) was called from `_MeshBackdropLayerState.initState` — illegal before the first dependency walk. Resolution moved to `didChangeDependencies` (the standard first-safe moment); artwork changes still re-resolve via `didUpdateWidget`.
- **Wrong song fixed (root cause)**: the native-queue feature added index-based seeks, but nothing verified the loaded native playlist still matched the app's queue — after choosing a new song, the OLD queue was still loaded natively, so an index meant for the new queue played the old queue's audio while the UI showed the chosen song. Now the native load records its id sequence (`_nativeQueueIds`), and all three index-based paths (play-all tap, next/previous, notification skip) are gated on `_nativeInSync` (same length, order, ids). A stale native playlist always falls back to the full reload, which rebuilds it.
- **LYRICS affordance redesigned**: full-width grey slab → a bordered pill (lyrics icon in the track's accent + "Lyrics" label), normal button footprint.
- Evidence: analyzer 0 errors; 113/113 tests; built and installed on BlueStacks.
- Residual risk: native-queue edge cases (autoplay-appended songs force a full rebuild by design). Rollback: revert player_controller.dart's native-queue branch — the single-song load path is intact as `_loadSingle`.

## Round 13 — smooth lyric sync, shuffle/repeat on the engine, download location, landscape pane, line mode, icons

- **Lyric sync is continuous now**: the word fill's colour follows ONE line-wide quantity — characters reached — so coverage crosses syllable boundaries smoothly. The old per-syllable time lerp snapped grey→tint→white→grey at every word (the stepped look). The glow also peaks mid-syllable and fades to zero at both ends, so the highlight travels as one wave. Line-by-line mode got a 200 ms AnimatedDefaultTextStyle fade for its state changes.
- **Line-only option added**: Settings → Appearance → Lyrics highlight → "Line by line" (whole line lights up at once, no word fill) or "Word by word" (default). Persisted.
- **Shuffle/repeat fixed properly**: with a whole queue loaded natively, the engine auto-advances at every track end — so app-only flags were ignored there. Shuffle and repeat are now mirrored onto the engine (`setShuffleModeEnabled`, `LoopMode.off/all/one`) whenever they change and after every native load; in-app next/previous ask the engine (`seekToNext/Previous`) so buttons and notification agree; app-side math remains the fallback.
- **Download location works**: Settings → Downloads → Storage location now opens the system folder picker (was an informational row); the choice persists and downloads land there. Clear downloads now removes the real files.
- **Landscape NPV pane**: the right lyrics pane no longer paints an opaque second backdrop (looked like a black box); a soft horizontal scrim fades the shared artwork darker behind the text. The expand button sits on its own chip.
- **Icons at every density**: adaptive foreground (transparent, mark at ~58%, centred in the 108 dp canvas) generated for mdpi→xxxhdpi, legacy full-bleed square art + round variant, `android:roundIcon` added. Shipping the foreground at only one density was why it rendered wrong on some launchers.
- **Debug stream**: logcat now streams via CMD redirection (PowerShell's pipeline was buffering it) → _logs/shuro_logcat.txt, watched by a crash monitor.

## Round 14 — first live-monitor catch: setState Future crash

- The debug monitor caught a real crash in the wild: `E/flutter: Unhandled Exception: setState() callback argument returned a Future` — `_ServerPlaylistsSectionState._reload` used `setState(() => _future = Future.value(...))`, and the arrow closure returns the assigned Future, which Flutter rejects. Triggered whenever a server-playlist action reloaded the section. Fixed with a brace body (returns void). Swept the whole codebase for the pattern: this was the only occurrence.
- Evidence: analyzer 0 errors, 113/113 tests, rebuilt + installed; stream resumed.

## Round 15 — metadata enrichment, artist pictures, tag reading; children collected

- **Artist pictures (the star placeholders)**: new `ArtistArtworkService` — resolves each artist once via Navidrome's `getArtistInfo2.artistImageUrl`, falling back to MusicBrainz URL-relations searched by name; results persist (artist key → URL) so later sessions paint complete grids immediately. Throttled queue (MB ≥1.1 s between calls). Wired into Library → Artists: cards with no server artwork fade in the resolved picture; local-file artists resolve by name. New `SubsonicApi.getArtistInfo2`.
- **Local tag enrichment**: local imports used to take the file name as title and "Local file" as artist — no artist bucket, and LRCLIB had nothing to match. New `LocalTagEnrichment` reads REAL tags with a pure-Dart parser (ID3v2.2/3/4 text frames + APIC artwork; FLAC VORBIS_COMMENT + PICTURE block — audiotags was evaluated and rejected: it pulls a Rust build into every compile). "Artist - Title" file-name fallback. Enrichment runs at startup (covers earlier imports) and after every import; genre is memoised per song for a future Genres integration.
- **Honest limits**: the Genres tab is built from the server catalog in the blocked AppState file, so LOCAL genres don't appear there yet (the data is captured); server genres were always tag-accurate. LRCLIB matching for local files now works because title/artist come from tags; remaster/feat. stripping in the parser handles the rest.
- **Shuffle stays in the queue** (from the previous report, kept): autoplay suggestions no longer append while shuffle is on; native shuffle order only reorders the loaded queue.
- **Children**: the UX-flow audit child and the queue-semantics reviewer were dispatched; the reviewer FAILED (tool error, no output) — its target issue (shuffle leaving the queue) was already root-caused and fixed directly this round; the audit child's findings will be synthesised when it reports.

## Round 16 — landscape NPV finished, shuffle/repeat visibility, blur/motion retune, blurred lyric lines

- **Landscape NPV**: the linear progress bar is GONE (duplicate of the ring). The ring carries progress again in landscape, redrawn "a little better": thicker stroke, brighter track, soft glow under the arc. The left column is now overflow-proof (LayoutBuilder + scroll fallback — at normal sizes it lays out spaceBetween; on an unusually short window it scrolls instead of clipping the transport, which was the cut-off bug).
- **Shuffle/repeat visible again**: the buttons were white54 bare icons — on bright blurred artwork they vanished ("shuffle removed by mistake, it adopted the artwork colour"). Both now sit on a dim circle (black 28%) in every state, turn accent-tinted (accent 22% circle) when active, keep the dot and repeat-one badge.
- **Blur/motion defaults retuned**: default blur scale 1.0 → 0.6 (sharper artwork, per request) and the default motion is faster and more visible (18 s cycle, amplitude 0.065; subtle 36 s / 0.03). Settings labels follow.
- **Non-playing lyric lines blur**: every line except the one being sung is blurred (ImageFiltered σ2.4, decal edges) plus the opacity ladder — repaint-bounded per line, so the cost is one-time per content change. Line-by-line mode fades its state changes over 200 ms.
- Stream/monitor: logcat restarts after each install cycle (kill-server required by the harness); file at _logs/shuro_logcat.txt.

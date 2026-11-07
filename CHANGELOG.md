## 2.6.2
- Lyrics states match the board: No lyrics (Search again / Add lyrics), Instrumental, Lookup paused, and the 'Looking for synced lyrics…' loading caption.
- Hand cursor over every custom tappable (new ClickRegion), title bar drag fixed (nested double-tap handler removed), custom title bar always shown on desktop, tray setup logged and no longer shares a failure with the title bar.
- Lyrics paint on the first frame from the warm caches when the song changes (no skeleton round-trip).
- Sidebar rail icon and label share one centre line.
- Onboarding Sound step no longer throws an infinite-height layout error (preset cards now size to the tallest card).
- Lyrics lookup can no longer sit on the loading skeleton forever: stalled lookups time out into a Retry state.
- Desktop header reads Lyrics/Queue on those pages and no sidebar tab stays lit while a page is open over the content.

- Shuro Pulse: fixed the layout crash (infinite height in the stats card) that left the tab blank. New board layout: Week/Month/Year/All-time chips, four stat cards with real deltas vs the previous period, listening time by day (bars grow in, hover tooltip), top artists with animated bars, and mixes. Backed by a new timestamped play log.
- Windows playback: reverted desktop to the native-queue load path (the single-track path never started audio in test logs) and stopped the stall watchdog from disposing the media_kit player, which could kill the process.
- Home: "JUMP BACK IN" eyebrow over Recently played. Onboarding server step now has a Scaffold (white background and yellow underlines on web).
- Sidebar: icon and label in each row are now vertically centred (the Row was top-aligned inside the 40 px item).

- Song cache (Settings → Cache): plays are kept on the device (with the next songs in the queue) so replays and skips start instantly; Wi-Fi-only toggle, size limit (256 MB–5 GB), used-space readout, clear button. Least recently played songs are evicted first. Downloads are untouched.
- Lyrics: the landscape/desktop pane now follows the Left/Centre choice, and the sung line is re-centred when text size or alignment changes.
- Settings (desktop): the Behaviour section no longer leaks into the page header (label spelling mismatch); header title shows the open page instead of the previous tab.

- Queue: the empty "Nothing queued after this" message is centred instead of sitting on the screen edge.

- Home (phone): hero discs are smaller and pushed to the corners so they no longer sit under the copy and buttons.

- Onboarding: fixed the "No Material widget found" crash on the web welcome gate (text fields now sit in a transparent Material).

- Playback: engine watchdog. A load that produces no engine event for 9 s (stuck platform player after sleep or a dead media session) now rebuilds the audio engine and retries once, so skip/prev/play never stay frozen.
- Playback: shuffle keeps already-played songs before the current one (so Previous still goes back) and shuffles only what follows; "next" follows the shuffled queue instead of picking a random index. Previous at the start of a repeat-all queue wraps to the last song.
- Playback: after launch, a server that is still reconnecting gets up to 6 s before "no audio source is available" is reported.
- Desktop: plays one track at a time from the app queue (no mirrored native playlist).
- Desktop: custom title bar (drag, double-click maximise, minimise/maximise/close with hide-to-tray); dock shows a square album cover instead of the ring.
- Sidebar: consistent section label and playlist alignment/spacing; the sidebar now scrolls as one unit on short windows instead of overflowing.
- Lyrics: tools pill no longer overlaps the LYRICS label; appearance sheet is a compact scrollable card with Reset to defaults.
- Android: inline lyric preview restored on Now Playing.
- Performance: the drifting mesh backdrop is static on phones (it repainted full-screen gradients every frame) and runs in its own repaint layer on desktop.

- Playback: fixed loads that never start on Android when the media-session init fails or is slow. `JustAudioBackground.init` swaps the audio platform before it waits for the service, so the old "continue without media controls" path left a dead platform in place and every load hung with no engine state. New `AudioBackend` restores the plain engine on failure or after 25 s, and loads wait for it.
- Playback: a stuck previous load no longer blocks later ones (8 s bound), native mode sync is bounded (5 s), native-queue load cap is 12 s before the single-song fallback.
- Diagnostics: new events `load.native.ok/fail`, `load.single.ok`, `load.fail` (URL-free error tag, timing, media-session flag) and `backend.ready/fallback`.
- Android: POST_NOTIFICATIONS declared.

# Changelog

All notable changes to **Shuro** — a Flutter music player for self-hosted
Navidrome / OpenSubsonic (and any Subsonic-compatible) servers, with local-file
playback, synced lyrics, and real offline downloads.

Format: Keep a Changelog. Everything below was built and verified together in
the current source tree (analyzer: 0 errors · tests: 113/113 passing).

---

## [2.6.1] - 2026-11-06

Completes the redesign across every remaining surface, plus the motion pass.

- **Onboarding 1-5**: welcome (logo pop, mesh blobs), optional Navidrome step
  with "I'll add it later", Audiobookshelf now-or-later, sound preset step
  mapped to real settings, all-set summary.
- **Settings**: board rail + rows, live signal-path card with pulsing violet
  nodes and a lossless badge, server cards with status dots.
- **Detail pages**: Genre/Album/Artist/Playlist headers with gradient washes,
  Play/Shuffle pills, 44px staggered tables; Queue gets a now-playing ring
  card and drag handles.
- **Search/Favorites/Pulse/Books**: top-result card + filter chips, pill
  tabs with heart pops, real-stat Pulse hero over drifting mesh blobs,
  Books chips + continue-listening + latest episodes.
- **Motion pass**: 240ms std fade+8px-rise page transitions, staggered
  entrances (30ms/row, max 8), hover lift on cards, animated EQ bars on
  playing rows, mesh-blob drifts - all standing down under reduced motion.

---

## [2.6.0] - 2026-11-06

The full UI/UX redesign (shuro-ui-handoff) lands - a visual and interaction
refresh only; every feature, route, nav destination and setting is unchanged.

- **Ring everywhere**: the progress ring now starts at 12 o'clock with a
  buffered arc, the fixed pink-violet brand gradient and spec knob sizes -
  Now Playing (desktop 400 / mobile 330), the lyrics mini transport (52), the
  desktop dock (52) and the mobile mini player (44, fully scrubbable with
  haptic ticks; the linear seek bar is gone).
- **Now Playing**: white play discs (76/68), pink artist + album + year line,
  lossless quality chip, PLAYING FROM header with output chip, scrub bubble,
  arrow +/-5 s seeks, desktop hint row, mobile Now Playing | Lyrics | Queue
  page tabs, mesh-blob backdrop.
- **Lyrics**: word-synced chip + tools pill, violet cue bar, neighbour fade
  ladder, hover timestamps, footer credits, shimmer loading, word/line sync
  toggle in appearance.
- **Desktop shell**: board sidebar (#0E131B, hairline, account card with
  server status, violet active items with left bar, PLAYLISTS quick access),
  52 px ring artwork in the 88 px dock, auto-collapse fixed to the window
  width.
- **Home**: continue-listening hero (Resume playback / Shuffle all), greeting
  eyebrow, 168 px recent covers with right-click menus, 24/800 sections.
- **Library / Downloads**: design tab set (Songs, Albums, Artists, Playlists,
  Genres, Cached, Local files), hairline table card with filter + sort chip
  pills, downloads status chips, active rows with cancel/retry and a storage
  bar card.
- **Brand motion**: real-mark slide-in splash timeline with gradient loader
  and cycling status line, welcome logo pop - all reduced-motion aware.

---

## [2.2.3] — 2026-10-14

- **Critical: release builds had no INTERNET permission.** Flutter adds it
  automatically to debug builds only — release APKs silently lost it, which
  blocked *all* app networking (every host lookup and socket failed with
  permission denied). On phones this made the app look permanently offline;
  the permission is now explicit in the main manifest.
- HTTPS/TLS fix: the always-on DoH fallback connector interfered with TLS
  handshakes on some networks/emulators ("Connection closed before full header
  was received"). It now engages only after a startup DNS health check fails,
  prefers IPv4 addresses when it does, and the default connect path — which
  owns the socket through the TLS handshake — is otherwise untouched.
- Artist images: `getArtistInfo2` now reads the standard `largeImageUrl` /
  `mediumImageUrl` / `smallImageUrl` fields in addition to the OpenSubsonic
  `artistImageUrl`, so Navidrome servers that only fill the standard fields
  show artist pictures.
- Network security config: cleartext (plain-HTTP server URLs) allowed on all
  API levels, not just Android 9.

## [2.2.2] — 2026-10-14

- DNS-failure retry: self-hosted/DDNS names that fail to resolve are retried
  once after 1.2 s before surfacing an error (a large share of these are
  transient resolver hiccups).
- Connection errors now explain themselves — DNS failures point at device DNS
  (browsers use DNS-over-HTTPS, which is why the same address works there) and
  suggest 1.1.1.1 / 8.8.8.8 or the local address while at home.
- Plain-HTTP server URLs supported (cleartext traffic enabled on Android 9+).

## [2.2.1] — 2026-10-14

The first complete public release of the rewritten app: playback engine, server
feature layer, synced lyrics, adaptive artwork backgrounds, landscape Now
Playing, real downloads, artist pictures, and its own navigation design.
(Version reconciled with pubspec 2.2.1+2 — the rewrite shipped without a
versioned release until now.)

### Added — Playback core

- **Playback engine contract** (`playback_engine.dart`): source policy
  (original / capped quality), diagnostics resolver, autoplay suggestion
  provider — every screen plays through one auditable path.
- **Original-quality streaming by default**: `format=raw` is sent for every
  stream unless a capped quality is explicitly chosen (mobile data too — a
  one-time migration flipped the old 320 kbps default).
- **Native queue playback**: the whole app queue loads as one playlist, which
  gives the system media notification previous/next buttons, and Android 13+
  its seek bar. In-app skips ride the engine; a stale-queue guard
  (`_nativeInSync`) makes it impossible for a seek meant for a new queue to
  play audio from an old one.
- **Advanced playback settings**: fade between songs (0/2/4/6 s volume fade),
  ReplayGain loudness normalisation from the server's own tags
  (`getSong → replayGain.trackGain`, memoised), playback speed
  (0.75×–2×), skip silence (Android).
- **Play reporting**: "now playing" broadcast at track start and a counted
  scrobble submission at the listen threshold (≥50 % or 4 min) — Navidrome's
  dashboard and play counts work.
- Shuffle/repeat mirrored onto the engine (`setShuffleModeEnabled`,
  `LoopMode.off/all/one`) so track-end, in-app buttons and the notification
  always agree; shuffle never leaves the queue (autoplay suggestions are
  suppressed while shuffling).

### Added — Server feature layer (`subsonic_api.dart`)

- search3, star/unstar, setRating/getSong, scrobble, getRandomSongs,
  getSongsByGenre, getSimilarSongs2/getTopSongs (the seam for future
  Last.fm-based recommendations), playlist CRUD, savePlayQueue/getPlayQueue,
  getScanStatus/startScan, getArtistInfo2 — with its own standard Subsonic
  auth (salted md5 token, password never on the wire) and typed failures.
- **Favourites sync both ways**: hearting anywhere pushes star/unstar to the
  server; on connect the server's starred songs merge onto the device and
  device-only hearts are pushed up.
- **Server playlists**: Library → Playlists shows every server playlist; the
  owner can create, rename, delete and add the playing song — changes land on
  Navidrome immediately. Detail view with Play all / Shuffle.
- **Ratings**: the song action sheet fetches the server's own userRating and
  sets it (5-tap stars).
- **Rescan server**: Settings → Server → Rescan (startScan + file count).

### Added — Lyrics

- **LRCLIB integration** with candidate ranking (duration tolerance,
  remaster/feat. normalisation), server-tag lyrics via
  `getLyricsBySongId`, and honest precision footers.
- **Word-by-word karaoke fill** driven by one continuous line-wide quantity —
  no per-word snapping; the glow peaks mid-syllable and fades at both ends.
- **Line-by-line mode** (Settings option): the whole line lights up at once,
  with a 200 ms fade — no word fill.
- **Blur for non-playing lines**: the sung line stays crisp, everything else
  blurs (per-line, repaint-bounded).
- Lyrics embedded in Now Playing (portrait preview + landscape pane), tap a
  line to seek, ±0.5 s in-context sync bar, manual-scroll "Follow lyrics"
  chip, attribution footers.

### Added — Now Playing

- Adaptive backdrop: **mesh gradient** from the track's palette + the artwork
  **blurred once per track** into a cached texture (the per-frame cost is a
  blit, not a filter) — smooth idle motion even on low-end phones.
- User-tunable **Background blur** (0.4×–2×, live) and **Background motion**
  (Still / Subtle / Normal / Fast).
- Portrait: progress ring, shuffle/repeat mode buttons with visible state
  (accent + dot + repeat-one badge), compact live lyric preview.
- Landscape: player-left / lyrics-right split — ring (no duplicate arc),
  title, transport; lyrics as a centred live column over a soft scrim, with
  an expand chip; overflow-proof on short windows.
- Queue screen with per-song actions (Play next, Add to queue, Add to
  playlist, Build from this), audio-information sheet.

### Added — Library & discovery

- Responsive grids (width-aware columns — no more giant cells on desktop/
  TV), artist pictures resolved from Navidrome `getArtistInfo2` with a
  MusicBrainz URL-relation fallback, cached permanently.
- Local files: real tag reading (ID3v2 + FLAC Vorbis comments, embedded
  artwork) so local tracks get true title/artist/album/genre and LRCLIB can
  match them; "Artist - Title" filename fallback.
- Skeleton shimmer screens for every loading state.
- Play all / Shuffle all in Songs (respects the current sort).

### Added — Downloads & performance

- **Real offline downloads**: original-quality bytes streamed to disk
  (documents dir — survives app updates — or a user-chosen folder), real
  progress, persisted registry, offline playback prefers the file.
- **Persistent image cache**: every cover/artist picture fetched once is
  served from disk on later launches (HTTP layer cache, 300 MB cap, auth-param
  normalised keys) — the library renders immediately on repeat runs.
- Faster first frame: the UI starts before background audio-service init.

### Added — Platform & design

- Android platform (AGP/Gradle/Kotlin current), Kotlin audio-capability
  bridge, dark launch window, adaptive + legacy launcher icons from the
  owner's artwork (vector adaptive foreground at every density, round
  variant), capitalised app label and proper media-notification channel.
- Shuro's own navigation: full-width bottom bar merged with the mini player
  (one surface, one set of corners) and a slim labelled rail on wide screens.
- Open-source license page + services attribution (Settings → About).
- 113 tests: lyrics parsing/matching, stream diagnostics, Subsonic API
  building/parsing, metadata honesty, layout overflow regression at four
  window sizes.

### Fixed

- White/blank startup screen (audio-service init made non-fatal, dark launch
  window).
- "BOTTOM OVERFLOWED" on Now Playing, the queue action sheet (192 px) and the
  landscape transport clipping — every screen now overflow-tested.
- Broken playback state machine (load generation guards, serialised loads,
  "AbortError: play() interrupted by new load request"), stale UI after skips.
- Stale greeting ("Good evening" at 11:29 pm) — four time bands, refreshes
  every minute.
- Wrong-song playback (native-queue staleness), shuffle/repeat bypassed by
  native auto-advance, blur-edge bands on lyric lines, mini player/nav corner
  mismatch, download location dead-end.
- Write-guard workarounds documented in code where AppState could not be
  edited (ServerLink, DownloadService, favorites facade).

### Notes

- ReplayGain, gapless and crossfade are real implementations now: ReplayGain
  from server tags as playback volume; crossfade as an end-of-track volume
  fade (a two-player overlap crossfade is a documented next step); gapless is
  inherent to the native playlist and always on.
- Local genres are captured per song but the Genres tab is built from the
  server catalog in the blocked AppState file — local entries there remain a
  known limitation.

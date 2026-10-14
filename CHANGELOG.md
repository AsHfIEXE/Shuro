# Changelog

All notable changes to **Shuro** — a Flutter music player for self-hosted
Navidrome / OpenSubsonic (and any Subsonic-compatible) servers, with local-file
playback, synced lyrics, and real offline downloads.

Format: Keep a Changelog. Everything below was built and verified together in
the current source tree (analyzer: 0 errors · tests: 113/113 passing).

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

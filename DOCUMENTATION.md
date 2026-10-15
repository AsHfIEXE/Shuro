# Shuro — Documentation

Complete reference for the Shuro codebase: what the app does, how it is
structured, how every subsystem works, how to build and test it, and the
platform quirks worth knowing. For a short marketing-style overview see
[README.md](README.md).

---

## 1. What Shuro is

A fast, dark, feature-complete music player for Android for people who run
their own music server. It speaks the **Subsonic / OpenSubsonic API**
(Navidrome and friends) and plays **local files** with real tag support.

Core promises:

- **Original quality, always.** Streams request `format=raw` — the server
  sends the file's own bytes, never a transcode. Downloads are original too.
- **Your server, fully controllable.** Favourites, ratings, playlists,
  play reporting/scrobbling, rescan — everything writes back.
- **Honest by design.** Audio Info separates what the *source* is, what the
  *decoder* reports, and what the *output path* supports. A field without
  evidence says "Not reported" — never a guess dressed up as fact.

---

## 2. Feature inventory

| Area | Features |
|---|---|
| Playback | Original-quality streaming (`format=raw`), explicit High/Medium/Low transcode tiers, windowed native queue with gapless hand-off, fade-between-songs, playback speed 0.75–2×, skip silence, ReplayGain from server tags, download-preferred playback |
| Queue | Full queue management: play next, add to queue, remove, reorder, clear, shuffle the queue itself, autoplay suggestions past the end, persistent queue + position across launches |
| Lyrics | Embedded server-side tags → LRCLIB fallback (tag-less tracks included), word-by-word karaoke fill or line highlight, ±0.5 s sync adjuster, tap-a-line-to-seek, auto-scroll with manual-scroll pause, embedded preview (portrait), full pane (landscape), fullscreen page |
| Now Playing | Artwork palette theming (real colors extracted per track), mesh-gradient + blurred-artwork backdrop with 4 motion levels and tunable blur, draggable progress ring with scrub feedback, immersive mode, idle behavior consistent across orientations |
| Server | Multi-server support with per-server library cache, favourites two-way sync, star ratings, playlist CRUD (owner-gated), rescan trigger, play reporting + Last.fm scrobble client, artist pictures (server → MusicBrainz fallback) |
| Offline | Original-quality downloads to app storage or a user folder, real progress, persisted registry, automatic download-preferred playback |
| Local files | Folder import with recursive scan, ID3v2/FLAC Vorbis tag enrichment (no native deps), artwork palette from tags, same player pipeline as server tracks |
| Platform | System media notification with full controls, lock-screen art, Bluetooth/headset route handling, adaptive launcher icons, dark launch screen with animated splash |
| Web (Chrome) | Runs for fast testing: same UI, browser-owned DNS/caching; media playback via the browser stack |

---

## 3. Architecture

```
lib/
├── main.dart              # composition root: overrides, proxy, secure prefs, boot
├── app.dart               # MaterialApp, AuthGate (boot/reconnect/welcome), AppShell
├── app_info.dart          # version constants
├── backend/               # server + repository layer
│   ├── subsonic_api.dart          # Subsonic/OpenSubsonic REST client (23 endpoints)
│   ├── navidrome_api_client.dart  # low-level auth (salt+token), typed calls
│   ├── navidrome_music_repository.dart  # snapshot fetcher + stream/cover URLs
│   ├── music_repository.dart      # MusicRepository interface + snapshot model
│   └── mock_music_repository.dart # demo backend (first-run preview)
├── models/                # Song, Album, Artist, AudioInfo, DownloadState...
├── playback/              # PlaybackEngine contract, AudioDiagnostics, capability
├── screens/               # home, library, discover, search, settings, now_playing,
│                          # playlist, artist, album, downloads, lyrics...
├── services/              # stream proxy, image/library caches, downloads,
│                          # lyrics (LRCLIB), scrobbles, artist artwork, tag
│                          # enrichment, persistence, secure secret store
├── state/                 # AppState (session/catalog), PlayerController (engine
│                          # + queue), AppearanceSettings, PlaybackPrefs
├── theme/                 # dark theme, typography, brand tokens
└── widgets/               # shared UI: ring, mini player, nav, skeletons, sheets
```

**Data flow:** screens watch `AppState` (session, catalog, settings) and
`PlayerController` (playback state). Player never imports AppState — the
composition root wires resolvers (stream URL, metadata, ReplayGain, lyrics)
into it as callbacks. This keeps the engine swappable (see §4).

---

## 4. Playback engine

`PlayerController` implements the `PlaybackEngine` contract
(`lib/playback/playback_engine.dart`): `setQueue / play / pause / seek / next /
previous`, `setSourcePolicy` (Original/High/Medium/Low), and
`getOutputDiagnostics()`. Underneath it wraps a single `just_audio`
`AudioPlayer` with `just_audio_background` for the system media session.

Key mechanics:

- **Windowed native queue.** The app queue is loaded into the native playlist
  as a *window* around the playhead (±12/15 songs; whole queue when ≤60).
  This is why tapping a song starts instantly even in a 5,000-track queue —
  the old whole-queue load was the multi-second delay. A jump outside the
  window rebuilds it; native↔app index translation always goes through the
  loaded id list, which prevents the wrong-song class of bugs.
- **Serialized loads.** All source loads chain through one guard (`_loadChain`)
  with generation counters: a newer tap always wins, interrupted loads never
  surface errors, and every load has a 20 s timeout that degrades to a
  retryable error instead of hanging.
- **Smooth position.** `smoothPositionStream` interpolates at up to ~60 fps
  (period clamped 16–24 ms for normal tracks) for the ring and karaoke fill;
  everything else listens at ~1 Hz.
- **Crossfade / ReplayGain / speed / skip-silence** are applied per track as
  playback tweaks, mirrored onto the native engine.
- **Original quality.** The source resolver builds `format=raw` URLs for
  Original (never a transcode) and `maxBitRate`-capped URLs only for the
  explicit paid tiers. Downloads use the `download` endpoint.

Diagnostics live in `lib/playback/audio_diagnostics.dart`: source (codec,
rate, depth, channels, stream mode, request check) vs decoder (what the
decoder reported) vs route (kind + label) vs capability (direct playback,
hi-res requested/accepted) vs processing. The Audio Info sheet renders these
as three separate groups with per-field provenance.

---

## 5. Server integration

- **`subsonic_api.dart`** — 23 verified endpoints: ping, search3, star/unstar,
  setRating, getSong, getStarred2, scrobble, getArtistInfo2 (all image
  fields), getRandomSongs, getSongsByGenre, getSimilarSongs2, getTopSongs,
  playlist CRUD, savePlayQueue, getScanStatus/startScan, download, cover art,
  stream. Salt+token auth, JSON mode.
- **`navidrome_music_repository.dart`** — full-library snapshot fetch
  (artists → albums → songs, bounded concurrency) and derives the
  genre→song-ids map client-side so every screen works off one snapshot.
- **`server_link.dart`** — on connect, binds favourites/ratings/playlist/
  scrobble features to the live server; on disconnect, unbinds.
- **Play reporting** — now-playing broadcast on track start, scrobble at the
  real-listen threshold (half the track or 4 minutes).

### Library cache + boot flow

`lib/services/library_cache.dart` stores the whole snapshot per server as
JSON (encoded/decoded in a background isolate — never on the UI thread) with
the server's `lastScan` stamp:

- **Returning launch:** the library paints instantly from cache; the fresh
  fetch runs in the background and swaps in.
- **Scan-change detection:** if the server's last scan is unchanged, the full
  per-album re-fetch is skipped entirely.
- **Server down + cache exists:** the library stays browsable (offline mode);
  only server streaming is unavailable.
- **Local-folder rescans** run in parallel, off the connect critical path.

---

## 6. Lyrics

`lib/screens/now_playing/lyrics_screen.dart` + `lib/services/lyrics_service.dart`.

Lookup order: **server-embedded tags** (getLyricsBySongId) → **LRCLIB**
(tag-less tracks included; tagged local imports too) → designed failure
states (not found / instrumental / rate-limited / network, with retry).
Only real embedded *lines* short-circuit the online lookup.

Rendering: word-by-word karaoke fill driven by the interpolated position
stream (line index changes only at boundaries), auto-scroll that retargets
rather than restarts, manual scroll pauses, tap-to-seek, ±0.5 s adjuster.
Inactive lines are subtly defocused on Android and opacity-dimmed on web
(CanvasKit-safe). The portrait preview fades via a bounded alpha mask —
no darkening overlays over artwork, ever.

---

## 7. Downloads & offline

`lib/services/download_service.dart` — original-quality bytes via the
`download` endpoint to app-storage (survives updates) or a user folder, with
a persisted registry, real progress, and cancellation. Playback resolves
sources in order: downloaded file → stream. Downloads survive server outages.

---

## 8. Services

| Service | Purpose |
|---|---|
| `stream_proxy.dart` | Loopback reverse proxy audio streams can be rewritten through; own DoH-capable resolution. Gated behind a startup DNS health check (a healthy resolver keeps the default path, which is required for clean TLS). |
| `image_disk_cache.dart` | HTTP-level disk cache for image responses (auth params stripped from keys), 300 MB cap with prune. Covers paint instantly on every launch. |
| `library_cache.dart` | Whole-library snapshot per server (§5), isolate-encoded. |
| `server_secret_store.dart` | Server passwords in OS-backed secure storage (Android Keystore). Prefs hold only non-secret fields; legacy installs migrate on first load; Reset wipes it. |
| `download_service.dart` | Real offline downloads (above). |
| `lyrics_service.dart` | LRCLIB client. |
| `artist_artwork_service.dart` | Artist pictures: server metadata → MusicBrainz fallback, disk-cached, throttled. |
| `local_tag_enrichment.dart` | Pure-Dart ID3v2/FLAC Vorbis reader for imported files (no native deps). |
| `scrobble_service.dart` | Last.fm scrobble client. |
| `app_persistence.dart` | Typed SharedPreferences wrapper (settings, favorites, history, playlists, queue, servers-minus-secrets). |
| `audio_capability.dart` | Kotlin bridge client: direct-playback capability + route changes (API 33+ queries, route-change requery, never a measurement). |

---

## 9. State

- **`AppState`** — session (connection status machine, servers, multi-server),
  catalog snapshot + derived views, favourites/ratings/playlists/history,
  settings, downloads registry, library sync/offline flags.
- **`PlayerController`** — the engine + queue + transport state; exposes
  `smoothPositionStream`; persists queue state on background.
- **`AppearanceSettings` / `PlaybackPrefs`** — view prefs and real audio
  effects, pushed into the player by the shell.

---

## 10. Persistence & security

- Non-secret data: `shared_preferences` (typed via `AppPersistence`).
- **Server passwords: Android Keystore-encrypted secure storage**
  (`server_secret_store.dart`) — never plain prefs. Legacy installs migrate
  on first load and are scrubbed from prefs immediately.
- **Settings → Reset app data** stops playback, clears prefs + secure store +
  all caches, and closes the app; the next launch is a fresh Welcome. The
  music server itself is never touched.
- Queue/favourites/history survive restarts (toggleable).

---

## 11. Android platform

- `minSdk 24`, `targetSdk 36`, AGP 9.1.
- Manifest: `INTERNET` (explicit — release builds don't get it implicitly),
  foreground-service + media permissions, cleartext allowed for self-hosted
  HTTP servers via network security config, `AudioServiceActivity` host.
- `AudioCapabilityBridge.kt` — capability queries + route callbacks.
- Adaptive vector launcher icon, dark launch theme, animated splash that
  holds while the server reconnects.
- Release signing: keystore at `android/app/shuro-release.jks` +
  `android/key.properties`; the Gradle wiring reads them for release builds.

## 12. Web (Chrome)

Runs the same UI for fast iteration (`flutter run -d chrome`). The browser
owns DNS and caching (proxy/DoH machinery disabled there); lyrics dim by
opacity instead of per-line filters; the backdrop is mesh-only. Known web
limits: Cloudflare-proxied DDNS domains may refuse localhost-origin requests
(use the LAN URL), and downloads/local-import are IO features.

---

## 13. Build & run

```powershell
# Android release APK (what CI publishes as Shuro_v<version>.apk)
flutter build apk --release

# Install on a running BlueStacks (adb 5555) or device
adb install -r build\app\outputs\flutter-apk\app-release.apk

# Web (Chrome) for fast UI iteration
flutter run -d chrome --web-port=8420
```

Environment (Windows): `JAVA_HOME` = Android Studio JBR,
`ANDROID_HOME/ANDROID_SDK_ROOT` = Android SDK, `PUB_CACHE` =
`%LOCALAPPDATA%\Pub\Cache`.

CI: `.github/workflows/android-release.yml` — analyze (non-gating on infos) →
test → release build → SHA-256 → prerelease `Shuro_v<version>.apk` on every
push to `main`.

## 14. Testing

```powershell
flutter analyze   # 0 errors baseline (~37 infos)
flutter test      # 113 tests across 6 files
```

Suites: lyrics parser, metadata, NPV layout (portrait + landscape +
large-screen), playback architecture (engine contract, queue/window rules),
stream probe, Subsonic API.

---

## 15. Known limitations & platform notes

- **BlueStacks**: its window manager force-restarts apps on per-app
  orientation changes (looks like a freeze); `run-as` is unavailable.
- **Web**: CORS applies — Cloudflare-proxied DDNS domains may refuse
  localhost origins (LAN URL works); no notification/downloads on web.
- **Exotic codecs** (DSD/APE/…): not decoded by the Android platform — the
  app shows a clear "can't play this format" state rather than transcoding.
- **Hi-res PCM / USB bit-perfect**: future, measurement-gated phases (plan
  §8.2/8.3) — never claimed without verified output.

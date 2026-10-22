# Shuro — Engineering Roadmap

All requested features, organised by priority and dependency.
Each item is a focused session's work, not a bullet to rush.

---

## Tier 1 — Ship-blocking (do before 1.0)

| # | Feature | Scope | Est. effort |
|---|---|---|---|
| 1 | **Signed releases** | CI signing via GitHub Secrets, SHA256SUMS, auto-tag on `v*` | 1 session |
| 2 | **Windows installer** (InnoSetup) | `Shuro-Setup-x64.exe` from CI | 1 session |
| 3 | **Linux .deb package** | `dpkg-deb` from CI with proper Depends | 1 session |
| 4 | **Home-screen widget** (Android) | 4×1 + 4×2 via `home_widget` + native `AppWidgetProvider` | 1–2 sessions |
| 5 | **ListenBrainz polish** | Retry-After backoff, secure token migration, per-device output memory | ½ session |
| 6 | **Playlist "Add songs"** | Song picker with search + multi-select from playlist detail | ½ session |
| 7 | **Right-click context menus** (all surfaces) | Songs, albums, artists, playlists — desktop convention | ½ session |

## Tier 2 — Audiophile (differentiation)

| # | Feature | Scope | Effort |
|---|---|---|---|
| 8 | **Preamp / loudness enhancer** | `AndroidLoudnessEnhancer` in AudioPipeline, persisted | ½ session |
| 9 | **Per-output-device profiles** | Remember volume + EQ per output device ID | 1 session |
| 10 | **Signal-path summary** in Audio Info | One-line: "44.1/16 → USB DAC (up to 96 kHz), direct" | ½ session |
| 11 | **Crossfade 0–12 s** | Shared-output overlap, disabled for spoken/radio/repeat-one | 1 session |
| 12 | **Music disk cache** | Bounded LRU audio segment cache (256 MB–4 GB per profile) | 1–2 sessions |

## Tier 3 — Content expansion (Audiobookshelf)

| # | Feature | Scope | Effort |
|---|---|---|---|
| 13 | **ABS progress sync** | Checkpoint 5s / sync 15s / pause/seek/exit, failed syncs visible | 1 session |
| 14 | **Chapters** | ABS chapter model + just_audio chapter mapping | 1 session |
| 15 | **Per-item speed** | Spoken speed per book/episode, music resets to 1.0 on switch | ½ session |
| 16 | **Listening stats** | Wall-clock accumulation, today/week/all-time, per-item breakdown | 1 session |
| 17 | **Books & Podcasts UI** | SpokenLibraryScreen, item detail, chapter nav | 1–2 sessions |
| 18 | **Series** | ABS series identity, next-unfinished, completed counts | 1 session |
| 19 | **Podcast subscriptions** | ABS server search, RSS preview, OPML import/export | 1 session |
| 20 | **Offline spoken checkpoints** | Separate checkpoint + preview/commit for downloaded spoken audio | 1 session |

## Tier 4 — UX polish

| # | Feature | Scope | Effort |
|---|---|---|---|
| 21 | **Lyric editing** | LRC/TXT picker, per-song editor, timing tool | 1 session |
| 22 | **Playlist covers** | Collage/PNG import, title/colour controls | ½ session |
| 23 | **Library health** | Missing artwork/tags/duplicates report | ½ session |
| 24 | **Rediscovery** | Forgotten favourites, older artists, unfinished albums | ½ session |
| 25 | **Settings search** | Index labels + section topics, reveal + focus | ½ session |
| 26 | **Context menus** (all surfaces) | Right-click on tracks/albums/artists/playlists | ½ session |
| 27 | **Immersive lyrics** | Appearance popup, typography/colour/layout, word glow | 1 session |
| 28 | **Command palette** | Ctrl+Shift+P, filter all commands | 1 session |
| 29 | **Undo system** | Last 20 queue/playlist/favourite edits | 1 session |
| 30 | **Listening profiles** | 30 named snapshots of settings | 1 session |
| 31 | **Recap** (listening stats visualisation) | 12 designs, year in review | 2 sessions |
| 32 | **Font manager** | 14 presets + Windows installed-font query | ½ session |
| 33 | **What's New** | Per-version changelog, feature links | ½ session |
| 34 | **Accessibility pass** | Focus indicators, zoom checks, screen reader audit | 1 session |

## Tier 5 — Advanced (post-1.0)

| # | Feature | Scope | Effort |
|---|---|---|---|
| 35 | **Application styles** | 9 visual styles (Original, Soft, Precision, Outline, Bold, Retro, Editorial, Neon, Ribbon) | 2–3 sessions |
| 36 | **Custom CSS** | Bounded import, preview, mini-player sync | 1 session |
| 37 | **Desktop window manager** | Remember size/position, frameless title bar, fullscreen | 1 session |
| 38 | **Tray full controls** | Play/pause/next/prev in tray menu (already partially done) | ½ session |
| 39 | **MPV telemetry coalescing** | 250ms coalesced + trailing snapshot | N/A (mobile uses ExoPlayer, not MPV) |

---

## Deferred indefinitely

| Feature | Reason |
|---|---|
| Chromecast / Cast | Requires Google Play Services, conflicts with privacy promise |
| Spotify integration | External account + OAuth, separate product |
| Shazam song recognition | Requires audio fingerprinting, heavy native dependency |
| YouTube/Innertube | Copyright risk, against privacy promise |
| Social features | Against privacy promise |
| Cloud sync | Against privacy promise (device-local only) |

---

## Implementation rules

1. Each item is **one focused session** — analyse, implement, test, chaos-verify, commit
2. Never rush a feature into the last 10 minutes of a session
3. Every UI change must be **verified visually** on the device
4. Every backend change must pass the **chaos harness** (seed 1 minimum, full 20-seed gate before release)
5. **Analyzer must stay at zero** — no new errors, warnings, or infos
6. The Android app must **never regress** — all desktop code is behind platform guards
7. **Report a problem** is the acceptance test for any backend change

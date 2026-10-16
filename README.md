<p align="center">
  <img src="docs/brand/shuro-banner.svg" alt="Shuro — Your music. Your server. Your sound." width="540" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Android%20%C2%B7%20desktop%20%C2%B7%20web-8A5CF6" alt="platform" />
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B" alt="Flutter" />
  <img src="https://img.shields.io/badge/tests-146%20passing%20%C2%B7%2040k%20chaos%20actions-2EA043" alt="tests" />
  <img src="https://img.shields.io/badge/telemetry-none-2EA043" alt="no telemetry" />
  <img src="https://img.shields.io/badge/quality-format%3Draw%20bitperfect-F5A623" alt="original quality" />
</p>

> **Own your music. Stream it at full quality. Let it surprise you.**

**Shuro** is a fast, dark, cinematic music player for people who run their own
server. It speaks the **Subsonic / OpenSubsonic API** — built for
**Navidrome** and every compatible server — and plays your **local files**
with real tag support. One library, every source, bit-perfect.

No accounts. No telemetry. No transcoding unless you ask for it.

---

## ✨ The showcase

### 🖤 A Now Playing screen that feels alive

- **Adaptive artwork backdrop** — a slow-breathing mesh gradient generated
  from each track's own color palette, with the cover blurred into it.
  Tune the blur, pick the motion speed (Normal · Subtle · Lively), or turn
  it off entirely — your battery, your call.
- **Karaoke lyrics** — word-by-word fill or line-by-line highlight, from
  LRCLIB or your files' embedded tags. Tap any line to seek. Nudge sync
  ±0.5 s without leaving the view.
- **Scrubbing artwork ring** — the progress bar *is* the artwork: grab it
  anywhere and drag.
- **Split-screen landscape** — player on the left, live lyrics on the right,
  the sung line always in view.
- **Audio info sheet** — the truth about what's playing: codec, bitrate,
  output route, original vs transcoded. Never a lie about your audio path.
- **Sleep timer suite** — presets, a custom clock picker, *End of track*,
  *End of queue* (plays everything you queued, then pauses), a real
  fade-out, +10 minutes, live countdown on the chip, cancel-safe.

### 🖥️ Multi-server, one library

Run more than one music server? Shuro **merges them into a single unified
library** — songs, albums, artists and playlists side by side, deduplicated,
with per-server switches in Settings. Your home server and your backup
server become one collection. Switching servers mid-queue even keeps
playing, routed per-song.

### 🧠 Shuro Pulse — recommendations that rotate, not repeat

Most players give you the same "similar songs" forever. Shuro Pulse is a
**session-rotating, on-device recommendation engine**:

| Signal | What it does |
|---|---|
| 🕐 Session rotation | Every app launch re-seeds every list — a fresh mix each time, stable while you listen |
| 📈 Recency decay | What you heard an hour ago sinks; what you haven't heard in weeks rises |
| 🎨 Genre-affinity graph | Genres score by the taste of the songs living in them — your favorites pull up their unknown neighbors |
| 🌙 Time-of-day | Late-night mixes lean mellow; evening mixes lean energy |
| 🎭 Diversity cap | No artist floods your feed — max 2 tracks each until everyone's had a turn |
| 🧭 Anti-echo | Because-You-Like deliberately recommends under-listened artists adjacent to your taste |

**Discover rows:** For You · Tonight's Flow · Because You Like <artist> ·
Rediscover · Deep Cuts · Fresh From Your Library.

### 🪄 Ask for a mood, get a mix

- **Build with Shuro** — type *"something calm for studying"* or *"high
  energy for the gym"* and get a ranked queue.
- **Build from this** — every song is a seed: Similar · Same era ·
  Deeper cuts · Surprise me · Smooth continuation.
- **10 Smart Playlists** — Rediscover, Deep Cuts, Late Night, Favorites Mix,
  Recently Added, Forgotten Favorites, High Energy, Chill, Focus, Long
  Drive. Re-evaluated live, never a stale stored list.

### 📥 Real offline. Real quality.

- **Original-quality downloads** to storage that survives app updates — or
  any folder you pick. Playback prefers them automatically.
- **Offline mode** with a cache-first library: airplane mode doesn't lock
  you out of what you own.
- **Original quality everywhere** — streams use `format=raw`: the server
  sends the file's own bytes, never a transcode, unless you pick a capped
  quality yourself.

### 🔊 Serious playback engineering

- Windowed native queue — instant track starts even in a 10,000-song queue,
  gapless hand-off, full lock-screen / Bluetooth / **Android Auto** controls.
- Fade between songs, playback speed 0.75×–2×, skip silence, ReplayGain from
  your server's tags.
- **Wrong-song self-heal** — if the engine and the UI ever disagree about
  what's playing, Shuro detects and resyncs itself in the background.
- **Scrobbles that count** — now-playing broadcast and proper submissions,
  so your server's play counts and Last.fm are accurate.

### 🔒 Privacy that isn't a promise, it's a design

- The app **asks before anything** — a first-launch consent screen explains
  exactly what leaves the device (lyrics queries, artist art, your own
  server traffic — that's all).
- **Zero telemetry.** No analytics SDK, no crash uploader, no ads.
- Credentials live in **encrypted secure storage**, never in plain prefs.
- **Report a problem** exports a *redacted* on-device event log — the last
  300 playback events with credentials and URLs scrubbed. You choose where
  it goes.

---

## 🖼️ The UI tour

| Screen | What you'll see |
|---|---|
| **Home** | Pulse-powered rows that change every session, your recent queues, quick jumps into every library section |
| **Library** | Songs · Albums · Artists · Genres · Playlists · Local — responsive from phones to TVs, with sort and Play/Shuffle on every list |
| **Now Playing** | The palette-lit centerpiece: breathing backdrop, karaoke lyrics, scrubbing ring, quick actions (Queue · Sleep · Volume · Audio info) |
| **Lyrics** | Full-screen word-fill karaoke with a sync nudge, or a live preview under the ring |
| **Queue** | Reorder, remove, jump — with up-next intelligence from Pulse |
| **Discover** | Six Pulse rows + Smart Playlists + Build with Shuro |
| **Search** | Instant, across songs, albums, artists, genres and playlists |
| **Settings** | Servers, quality, playback, appearance (fonts, artwork styles, motion, blur), downloads, About with device facts and licenses |

Dark-only by design — because a music player should disappear into the
music. Reduce-animations honoured everywhere; every loading state is a real
skeleton, never a spinner stuck in the void.

---

## ⚡ Built the hard way

Shuro is developed with the tooling most apps never build:

- 🧪 **146 tests**, including a **seeded chaos harness** that fires
  **40,000 random playback actions** (skips, seeks, queue edits, injected
  failures) against the real player and asserts the invariants after every
  single action — any failure reproduces from its seed.
- 🩺 A redacted **event log** you can export, so a bug report is evidence,
  not vibes.
- ⏱️ Startup that **cannot hang**: every boot-time dependency has a hard
  timeout — the worst case is a retryable error, never a splash screen
  forever.
- 📐 Layout verified at 320×568 phones, tablets, TVs and landscape.

Targets Android API 24+ on 3 GB RAM devices and up. The same code runs as
desktop and web builds.

---

## 🚀 Getting started

1. **Connect** — your Navidrome / Subsonic URL + account (or local files
   only). Multiple servers welcome; credentials are stored encrypted.
2. **Listen** — tap any song. Portrait gives you the ring and lyric preview;
   landscape splits player + lyrics.
3. **Make it yours** — streaming quality (original by default), fade,
   ReplayGain, speed, skip silence, backdrop motion, fonts, artwork styles,
   downloads location, sleep timer defaults.

### Build from source

```bash
flutter pub get
flutter test                # 146 tests, chaos suite included
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

Or just push to `main` — GitHub Actions (`.github/workflows/android-release.yml`)
builds, tests and publishes a release APK automatically.

---

## 🌐 Services Shuro talks to

- **Your Navidrome / Subsonic server** — your music, your credentials, your
  machine.
- **LRCLIB (lrclib.net)** — synced lyrics, only when you open the lyrics view.
- **MusicBrainz / Cover Art Archive** — artist pictures and metadata
  fallback, rate-limited and cached.
- **Last.fm** — optional scrobbling client built in (bring your own account).

No account data leaves your server except the queries that power the feature
you triggered. Everything recommendation-related is computed on-device.

## 🗂️ Project structure

```
lib/
├── backend/          # Subsonic REST clients + catalog mapping
├── models/           # Song, Album, Artist, lyrics, download state…
├── playback/         # Engine contract, source policy, diagnostics, event log
├── screens/          # Home, Library, Search, Discover, Favorites,
│                     # Now Playing, Lyrics, Queue, Downloads, Settings…
├── services/         # Shuro Pulse, downloads, lyrics, artwork, caching…
├── state/            # AppState (catalog/session), PlayerController,
│                     # AppearanceSettings
├── theme/            # Dark theme, brand tokens, dynamic palette
└── widgets/          # Shared UI (player, nav, cards, sheets, skeletons)
```

## 📄 License & author

© **AsHfIEXE**. All rights reserved.

Open-source packages are listed inside the app: **Settings → About → Open
source licenses**. External services are credited under **Settings → About →
Services & data sources**.

See [CHANGELOG.md](CHANGELOG.md) for the release history and
[docs/playback-audit.md](docs/playback-audit.md) for how the playback core
is audited.

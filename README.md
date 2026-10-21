<p align="center">
  <img src="docs/brand/shuro-banner.svg" alt="Shuro — Your music. Your server. Your sound." width="540" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Android%20%C2%B7%20desktop%20%C2%B7%20web-8A5CF6" alt="platform" />
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B" alt="Flutter" />
  <img src="https://img.shields.io/badge/tests-160%2B%20%C2%B7%2040k%20chaos%20actions-2EA043" alt="tests" />
  <img src="https://img.shields.io/badge/telemetry-none-2EA043" alt="no telemetry" />
  <img src="https://img.shields.io/badge/streams-format%3Draw%20%26%23x2014%3B%20no%20hidden%20transcode-F5A623" alt="original quality" />
</p>

> **Own your music. Stream it at full quality. Let it surprise you.**

**Shuro** is a fast, dark, cinematic music player for people who run their own
server. It speaks the **Subsonic / OpenSubsonic API** — built for
**Navidrome** and every compatible server — and plays your **local files**
with real tag support. One library, every source.

No accounts. No telemetry. No transcoding unless you ask for it.

---

## ✨ The showcase

### 🖤 A Now Playing screen that feels alive

- **Adaptive artwork backdrop** — a slow-breathing mesh gradient generated
  from each track's own palette, with the cover blurred into it. Tune the
  blur, pick the motion speed (Normal · Subtle · Lively), or switch it off.
- **Karaoke lyrics** — word-by-word fill or line-by-line highlight, from
  LRCLIB or your files' embedded tags. Tap a line to seek, nudge sync
  ±0.5 s, and read without being dragged: auto-follow can only move the
  lyric list itself, never the page.
- **A positional cue, not just bold** — the sung line carries an accent
  caret (left-aligned) or underline (centred), with a 78 % / 60 % contrast
  ladder for upcoming and past lines — repeated lines ("oh oh oh") are
  unambiguous.
- **Scrubbing artwork ring** — the progress bar *is* the artwork: a white
  knob with a glow marks the position, grows while you drag, and previews
  the target before a single seek is issued on release.
- **Split-screen landscape** — player left, live lyrics right, the sung
  line always in view; a bottom transport stays in the full lyrics view.
- **Sleep timer suite** — presets, a custom clock picker (*"pause at 12:17"*
  means exactly that, tomorrow if it already passed), *End of track*,
  *End of queue*, fade-out, +10 minutes, live countdown, cancel-safe.
- **Immersive mode** that re-asserts itself after rotation.

### 🎚️ Audiophile controls — real DSP, honest reporting

- **System equalizer (Android)** — the player is built with an
  `AudioPipeline` carrying Android's `AndroidEqualizer`, so EQ is a
  multi-band system effect applied before the mixer, not a volume trick.
  Bands persist across restarts, flat-reset included; unsupported
  platforms say so instead of showing dead sliders.
- **While EQ is on**, the sheet states plainly that Android is processing
  the audio, so direct/bit-perfect USB output is not in use.
- **Audio Info that tells the truth** — file codec/bitrate/channels, the
  request actually made (original vs capped), the classified output route,
  the platform's direct-playback answer, and the **output device's accepted
  sample rates, channel counts and PCM encodings**. Unknowns read
  "not reported" — never a guess, and never a "bit-perfect" claim.
- **Original quality by default** — streams request the file's own bytes
  (`format=raw`); High/Medium/Low caps exist for metered connections.

### 🧠 Shuro Pulse — recommendations that rotate, not repeat

| Signal | What it does |
|---|---|
| 🕐 Session rotation | Every launch re-seeds every list — fresh mix, stable while you listen |
| 📈 Recency decay | Recently heard tracks sink; unheard ones rise |
| 🎨 Genre-affinity graph | Genres score by the taste of the songs living in them |
| 🌙 Time-of-day | Late night leans mellow, evening leans energy |
| 🎭 Diversity cap | Max 2 tracks per artist until everyone had a turn |
| 🧭 Anti-echo | Because-You-Like favours under-listened artists near your taste |

Rows **never come back thin**: For You and Tonight's Flow guarantee their
length, Rediscover tops up, and Because-You-Like / Deep Cuts have honest
local-library fallbacks instead of empty sections. Results are memoized per
library signature + hour, so Pulse never janks a frame.

**Discover rows:** For You · Tonight's Flow · Because You Like <artist> ·
Rediscover · Deep Cuts · Fresh From Your Library.

### 🪄 Ask for a mood, get a mix

- **Build with Shuro** — *"something calm for studying"*, *"high energy for
  the gym"* → a ranked queue.
- **Build from this** — every song is a seed: Similar · Same era · Deeper
  cuts · Surprise me · Smooth continuation.
- **10 Smart Playlists** — Rediscover, Deep Cuts, Late Night, Favorites Mix,
  Recently Added, Forgotten Favorites, High Energy, Chill, Focus, Long
  Drive. Re-evaluated live, never a stale stored list.

### 🖥️ Multi-server, one library

Several servers **merge into one collection** — songs, albums, artists and
playlists side by side, deduplicated, per-server switches in Settings, and
per-song routing that keeps playing across a server switch.

### 🔀 Shuffle that means what it says

Turning shuffle **on** shuffles what's ahead while the playing track stays
put; the native queue is re-laid in that order so **"Up next" is exactly
what plays**; turning it **off restores the saved queue order**. Queue
integrity is enforced by the chaos harness — the playing track can never
leave the queue.

### 📥 Real offline. Real quality.

Original-quality downloads that survive app updates (or any folder you
pick), automatic download-preferred playback, and a cache-first library
that works in airplane mode.

### 🔊 Serious playback engineering

- Windowed native queue — instant starts even in huge queues, gapless
  hand-off, full lock-screen / Bluetooth / **Android Auto** controls.
- Fade between songs, speed 0.75×–2×, skip silence, ReplayGain from your
  server's tags.
- **Direct streaming** — the loopback proxy only engages when the DNS
  health check fails; a healthy network streams straight to the engine, and
  `Range` requests are honoured so seeking doesn't re-download.
- **Scrobbles that count** — now-playing ping, Last.fm's documented rule
  (submit at 50 % or 4 min, skip ≤30 s), ordered persistent queue with
  retry, plus Navidrome play reporting.
- **Wrong-song self-heal** — if engine and UI ever disagree, Shuro detects
  and resyncs in the background.

### 📐 Adaptive to every window

- **Navigation rail in every landscape window** (from 400 dp wide) and on
  portrait tablets/foldables from 720 dp; bottom bar only on portrait
  phones, where it costs nothing.
- Rail width scales **86 / 104 / 116 dp**; below **420 dp tall** it goes
  icon-only, hides the logo and scrolls — no overflow stripes at any size.
- Tab state survives the rail↔bar switch (shared key), sheets are
  height-bounded and scroll, and rows that can't fit wrap instead of
  overflowing.
- Song rails measure the user's **text scale**, so large system fonts don't
  clip cards.

### 🔒 Privacy that isn't a promise, it's a design

- First-launch **consent screen** listing exactly what leaves the device.
- **Zero telemetry**: no analytics SDK, no crash uploader, no ads.
- Credentials in **encrypted secure storage**.
- **Report a problem** exports a *redacted* event log (last 300 playback
  events, URLs and credentials scrubbed) — you choose where it goes.

---

## 🖼️ The UI tour

| Screen | What you'll see |
|---|---|
| **Splash → Onboarding** | Animated dark launch on the brand mark, welcome, consent, guided server setup |
| **Home** | Pulse rows that change every session, recent queues, quick jumps |
| **Library** | Songs · Albums · Artists · Genres · Playlists · Local — sort and Play/Shuffle everywhere |
| **Album & Artist detail** | Full discographies, artist pages, server artwork |
| **Collections** | Curated server groupings, browsed like native playlists |
| **Now Playing** | Breathing backdrop, karaoke lyrics with caret cue, scrubbing ring, quick actions (Queue · Sleep · Volume · Audio info) |
| **Lyrics** | Full-screen word-fill karaoke, sync nudge, tap-to-seek, reading mode that never yanks you back |
| **Queue** | Reorder, remove, play-next, clear, shuffle — resumes exactly where you left off after a reboot |
| **Discover** | Six Pulse rows + Smart Playlists + Build with Shuro |
| **Favorites & Downloads** | Two-way favourites with your server; downloads hub with real progress and storage control |
| **Playlists** | Create locally, edit server playlists (owner-gated), save your queue as a playlist |
| **Search** | Instant, across songs, albums, artists, genres and playlists |
| **Settings** | Servers, quality tiers, playback, **Equalizer**, appearance (fonts, artwork styles, motion, blur), downloads, About with device facts, licences and Report a problem |

Dark-only by design. Skeletons for every loading state. Reduce-animations
honoured everywhere — and the Performance profile disables motion, blur and
the per-frame ring ticker for low-RAM devices.

**Personalization:** font family picker, artwork styles, backdrop blur and
motion, profile avatar editor, adaptive launcher icon and animated splash.

**Local files are first-class:** recursive folder import with ID3v2 / FLAC
Vorbis tag enrichment — artwork, palettes and the same player pipeline.

---

## ⚡ Built the hard way

- 🧪 **160+ tests**, including a **seeded chaos harness** firing **40,000
  random playback actions** (skips, seeks, queue edits, injected failures)
  with invariants asserted after every action — any failure reproduces from
  its seed.
- 🩺 A **redacted event log** + Report a problem, so bug reports are
  evidence rather than vibes.
- ⏱️ Startup that **cannot hang**: every boot dependency has a hard timeout.
- 📐 Layouts verified from 320×568 phones to tablets, TVs and landscape,
  plus large-font and narrow-split-screen cases.
- 📄 Engineering notes in the repo: `docs/playback-audit.md`,
  `docs/audio-feature-review.md`, `docs/perf-report.md`.

Targets Android API 24+ on 3 GB RAM devices and up. The same code runs as
desktop and web builds.

### Windows desktop

Windows and Linux playback uses the **libmpv** backend through
Media Kit. Shuro keeps its tested queue/controller API while both desktop
platforms share the same decoder for server streams and local files.
Building Windows needs two machine-level prerequisites, both one-time:

1. **Developer Mode** (Windows Settings → Privacy & security → For developers)
   — Flutter needs symlink support for plugin links.
2. **Visual Studio 2022** with the *Desktop development with C++* workload
   (the Flutter Windows toolchain).

Then:

`ash
flutter config --enable-windows-desktop
flutter build windows --release   # build/windows/x64/runner/Release/
`

What works on Windows: library browsing, streaming from your server, local
files, Pulse, lyrics, equalizer UI (system EQ is Android-only — the sheet says
so), offline downloads. System media keys / lock-screen controls are a mobile
media-session feature and are simply absent, not broken.

---

## 🚀 Getting started

1. **Connect** — your Navidrome / Subsonic URL + account (or local files
   only). Multiple servers welcome; credentials are stored encrypted.
2. **Listen** — tap any song. Portrait gives the ring and lyric preview;
   landscape splits player + lyrics.
3. **Make it yours** — quality tiers, fade, ReplayGain, speed, skip silence,
   **equalizer bands**, backdrop motion, fonts, downloads location, sleep
   defaults.

### Build from source

```bash
flutter pub get
flutter test                # includes the seeded chaos suite
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # Play upload artifact
```

Pull requests and pushes to `main` run analysis, the full test suite, and
release builds for Android, Windows, and Linux. A GitHub Release is created
only from a `v<pubspec-version>` tag or a manual run with **Publish** enabled,
after every platform artifact succeeds and Android signing is configured.

For signed Android releases, add these GitHub Actions secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
and `ANDROID_KEY_PASSWORD`. The workflow publishes a `SHA256SUMS.txt` file
alongside the APK, AAB, Windows installer, and Debian/Ubuntu package.

---

## 🌐 Services Shuro talks to

- **Your Navidrome / Subsonic server** — your music, your credentials.
- **LRCLIB (lrclib.net)** — synced lyrics, only when you open the lyrics view.
- **MusicBrainz / Cover Art Archive** — artist pictures and metadata
  fallback, rate-limited and cached.
- **Last.fm** — optional scrobbling with your own account.

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
├── services/         # Shuro Pulse, equalizer, downloads, lyrics, caching…
├── state/            # AppState (catalog/session), PlayerController,
│                     # AppearanceSettings, DeviceProfile…
├── theme/            # Dark theme, brand tokens, dynamic palette
└── widgets/          # Shared UI (player, nav, cards, sheets, skeletons)
```

## 📄 License & author

© **AsHfIEXE**. All rights reserved.

Open-source packages are listed in-app: **Settings → About → Open source
licenses**. External services are credited under **Settings → About →
Services & data sources**.

See [CHANGELOG.md](CHANGELOG.md) for release history.

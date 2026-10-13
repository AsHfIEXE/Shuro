# Shuro

**Shuro** is a fast, dark, feature-complete music player for Android, built for
people who run their own music server. It speaks the **Subsonic / OpenSubsonic
API** — so it works with **Navidrome** and any other compatible server — and it
also plays your **local files** with real tag support.

Own your music. Stream it at full quality. Take it offline.

---

## Highlights

- **Original-quality playback** — streams use `format=raw` by default: the
  server sends the file's own bytes, never a transcode. Downloads are original
  too.
- **Synced lyrics** — word-by-word karaoke fill (continuous, smooth) or
  line-by-line highlighting, from LRCLIB and from your files' own embedded
  tags, with an in-context ±sync adjuster.
- **Adaptive artwork backdrop** — a mesh gradient built from each track's
  palette with the cover blurred into it, animating in slow motion. Blur
  strength and motion speed are yours to tune (or switch off entirely).
- **Landscape Now Playing** — player and live lyrics side by side, with a
  draggable seek bar and the sung line always in view.
- **Real offline downloads** — songs are saved at original quality to storage
  that survives app updates (or to any folder you pick), and playback prefers
  them automatically.
- **Full server control** — favourites, star ratings, playlist
  create/rename/delete (owner-gated), rescan: everything writes straight to
  your Navidrome.
- **Play reporting** — now-playing broadcast and proper scrobbles, so your
  server's play counts and dashboard are accurate. Last.fm scrobbling client
  included.
- **Advanced playback** — fade between songs, playback speed (0.75×–2×),
  skip silence (Android), ReplayGain from your server's tags.
- **Artist pictures** — from your server's metadata, with a MusicBrainz
  fallback; cached on disk after the first fetch.
- **Shuffle that shuffles your queue**, gapless native-queue playback, full
  system media controls (lock screen, Bluetooth, Android Auto), and a
  persistent image cache so the library paints instantly on every launch.
- **Tablet / desktop / TV ready** — a width-aware layout with a navigation
  rail, and landscape split-screen Now Playing.
- Dark-only design, skeletons for every loading state, reduce-animations
  honoured everywhere.

## Requirements

- A **Navidrome** (or any Subsonic-compatible) server with an account, for
  streaming — or just import local audio files.
- Android (API 24+) for installation. The UI also runs on desktop and web
  builds of the same code.

## Build

```bash
flutter pub get
flutter test                # 113 tests
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

Or simply push to `main` — the included GitHub Actions workflow
(`.github/workflows/release.yml`) builds a release APK and publishes it as a
GitHub Release tagged with the current `pubspec` version.

### Lock-screen / notification controls

Handled by `just_audio_background`. The manifest already declares the audio
service and media-button receiver, so nothing extra is needed — playback
controls appear on the lock screen, notification shade, Bluetooth and Android
Auto out of the box.

## Using Shuro

1. **Connect** — enter your server URL, username and password (or continue
   with local files only). Servers are remembered; startup reconnects
   automatically.
2. **Library** — Songs, Albums, Artists, Genres, Playlists and Local tabs,
   all responsive from phones to TVs. Sort songs and Play all / Shuffle any
   list.
3. **Now Playing** — tap any song. Portrait shows the progress ring and a
   live lyric preview; landscape splits into player + full lyrics. Long-press
   artwork or use the ⋮ menu for per-track actions (download, rating,
   playlist, lyrics, audio info).
4. **Lyrics** — full-screen or inline; word-by-word or line-by-line
   highlighting (Settings → Appearance → Lyrics highlight); tap a line to
   seek; nudge sync ±0.5 s without leaving the lyrics.
5. **Downloads** — mark songs from their ⋮ menu; pick your storage folder in
   Settings → Downloads → Storage location.
6. **Settings** — server management, streaming quality (original by default),
   playback (fade, replay gain, speed, skip silence), appearance (background
   style, blur, motion, lyrics highlight, fonts, reduce animations), and
   open-source licenses.

## Services Shuro talks to

- **Your Navidrome / Subsonic server** — your music, your credentials, your
  machine.
- **LRCLIB (lrclib.net)** — synced lyrics, only when you open the lyrics view.
- **MusicBrainz / Cover Art Archive** — artist pictures and metadata fallback,
  rate-limited and cached.
- **Last.fm** — optional scrobbling client built in (bring your own account).

No account data leaves your server except the queries that power the feature
you triggered.

## Project structure

```
lib/
├── backend/          # Subsonic REST clients + catalog mapping
├── models/           # Song, Album, Artist, lyrics, download state…
├── playback/         # Engine contract, source policy, diagnostics
├── screens/          # Home, Library, Search, Discover, Favorites,
│                     # Now Playing, Lyrics, Queue, Downloads, Settings…
├── services/         # Downloads, lyrics, artist artwork, tag enrichment,
│                     # caching, server link, playback prefs…
├── state/            # AppState (catalog/session), PlayerController,
│                     # AppearanceSettings
├── theme/            # Dark theme, brand tokens, dynamic palette
└── widgets/          # Shared UI (player, nav, cards, sheets, skeletons)
```

## License & author

© **AsHfIEXE**. All rights reserved.

Open-source packages used by Shuro are listed with their licenses inside the
app: **Settings → About → Open source licenses**. External services are
credited under **Settings → About → Services & data sources**.

See [CHANGELOG.md](CHANGELOG.md) for the release history.

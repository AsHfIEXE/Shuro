# Play Store listing — Shuro

Everything Play Console asks for, drafted from what the app actually does.

## App name (≤30 chars)

```
Shuro — self-hosted player
```
(26 chars)

## Short description (≤80 chars)

```
Your music, your server, your sound. Bit-perfect streaming, zero telemetry.
```
(77 chars)

## Full description (≤4000 chars)

```
Shuro is a fast, dark, cinematic music player for people who run their own
music server. Connect Navidrome or any Subsonic/OpenSubsonic server and hear
your library at its original quality — or play local files with real tag
support. Own your music. Stream it at full quality.

ORIGINAL QUALITY
Streams request the file's own bytes (format=raw) — no hidden transcode.
Prefer a lighter stream? Explicit High/Medium/Low tiers are one tap away.

MULTI-SERVER, ONE LIBRARY
Run more than one server? Shuro merges them into a single collection —
songs, albums, artists, playlists — deduplicated, with per-server switches.
Your home server and your backup become one library.

SHURO PULSE
A recommendation engine that rotates, not repeats. Every session brings a
fresh mix built from your favorites, your listening history, the time of
day and a genre-affinity graph — on your device, with no profile uploaded.

• For You, Tonight's Flow, Because You Like, Rediscover, Deep Cuts
• 10 live Smart Playlists
• Ask for a mood: "something calm for studying" builds a queue
• Every song is a seed: Similar, Same era, Deeper cuts, Surprise me

A NOW PLAYING SCREEN THAT FEELS ALIVE
An artwork backdrop that breathes with each track's own palette. Karaoke
lyrics with word-by-word fill, tap-a-line to seek and ±0.5s sync nudge.
Scrub the progress ring itself. Landscape splits player and lyrics.

REAL OFFLINE
Original-quality downloads that survive app updates, automatic
download-preferred playback, and a cache-first library that works in
airplane mode.

SERIOUS PLAYBACK
Gapless windowed queue, fade between songs, 0.75–2× speed, skip silence,
ReplayGain, full lock-screen / Bluetooth / Android Auto controls, accurate
scrobbles to your server and Last.fm.

PERFORMANCE PROFILES
Auto, Performance, Balanced, Quality — pick how much motion, blur and image
cache your phone should spend. Auto reads your device's RAM and chooses.

PRIVACY BY DESIGN
No analytics. No crash uploader. No ads. A one-time consent screen lists
exactly what leaves the device (lyrics lookups, artist art, your own server
traffic). Credentials stay in encrypted storage. "Report a problem" exports
a redacted event log you choose to share.

DARK-ONLY. PHONE TO TABLET TO TV.
Responsive layouts, skeletons instead of spinners, reduce-animations
honoured everywhere.

Requires a Navidrome / Subsonic-compatible server for streaming, or import
local audio files. Android 7.0+.
```

## Category & tags

- Category: **Music & Audio**
- Tags: music player, self-hosted, Subsonic, Navidrome, offline

## Content rating questionnaire — answers

- Violence / sexuality / language / controlled substances: **No**
- User-generated content sharing: **No** (no social features)
- Ads: **No**
- In-app purchases: **No**

## Data safety form — answers (derived from the manifest + code)

| Question | Answer |
|---|---|
| Does the app collect or share data? | **No** data collected, **no** data shared |
| Data types collected | None |
| Data types shared | None |
| Is data encrypted in transit? | Yes — all traffic is HTTPS to the user's own server or public metadata services |
| Can users request deletion? | N/A — nothing is stored off-device; local data clears with app data |
| Permissions declared | `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK` — all for playback of the user's own library |

Third-party services the app contacts **only when the feature is used**:
LRCLIB (lyrics), MusicBrainz/Cover Art Archive (artist art), Last.fm
(optional scrobbling with the user's own account). No identifiers are sent.

## Screenshots — capture checklist (phone, ≥2 required, up to 8)

Capture on the device, no debug banner (release build), 1080×2400-ish:

1. Home — Pulse rows
2. Now Playing — backdrop + ring
3. Lyrics — karaoke line
4. Discover — Smart Playlists
5. Queue
6. Settings → Performance profile sheet

Store at `docs/store/screenshots/01-home.png` … and upload in that order.

## Graphics

- Feature graphic: `docs/store/feature-graphic-1024x500.png` ✓ generated
- App icon: 512×512 `docs/brand/icon-512.png` ✓ generated

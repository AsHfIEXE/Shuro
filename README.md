# Shuro

A complete Flutter/Dart UI for Shuro, a self-hosted Navidrome/OpenSubsonic
music player — every screen from onboarding through settings, built on
Shuro's own identity (see `## Brand` below).

## Setup

1. Create a new Flutter app (skip if you already have one):
   ```bash
   flutter create shuro_app
   cd shuro_app
   ```
2. Copy this project's `pubspec.yaml` dependencies block into yours (or
   replace the file outright if this is a fresh project).
3. Copy the `lib/` folder here into your project, replacing the default
   `lib/main.dart`.
4. Install dependencies and run:
   ```bash
   flutter pub get
   flutter run
   ```
5. **Required for lock-screen/notification playback controls to work** —
   see `## Lock-screen & notification controls` right below. Without this
   one-time manual step, playback still works fine in-app, but nothing
   shows up (or responds to taps) on the lock screen, in a Bluetooth
   headset's display, or in Android Auto.

## Lock-screen & notification controls

Real playback controls outside the app (lock screen, notification shade,
Bluetooth/car head units, Android Auto) are wired up via
[`just_audio_background`](https://pub.dev/packages/just_audio_background)
(`lib/main.dart` calls `JustAudioBackground.init(...)` before `runApp`;
`PlayerController` tags every track it loads with a `MediaItem` built from
real title/artist/album/artwork — see `AppState.nowPlayingMetadataFor`).

That package needs one manual addition this sandbox can't make for you
(there's no `android/` folder here — only `lib/`, since this environment
has no Flutter SDK to generate one). Add this to
**`android/app/src/main/AndroidManifest.xml`**, inside the `<application>`
tag, alongside your existing `<activity>`:

```xml
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true"
    tools:ignore="Instantiatable">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>

<receiver
    android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</receiver>
```

And these two permissions as direct children of the top-level `<manifest>`
tag (same level as any existing `<uses-permission>`):

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

If the manifest doesn't already declare the `tools:` XML namespace on its
root `<manifest>` tag, add `xmlns:tools="http://schemas.android.com/tools"`
there too (`flutter create`'s default manifest usually already has it).

Without this, the app doesn't crash and in-app playback is unaffected —
`just_audio` just never gets a real Android `MediaSession` to publish, so
there's nothing for the OS to show controls for outside the app itself.

## Brand

- **Mark**: `lib/widgets/app_logo.dart` — two rounded diagonal bars offset
  into an "S", violet fading to cyan. Pure vector (`CustomPainter`), so
  it's crisp at any size with no image asset to ship, and it's the single
  source of truth: Splash and Welcome both render this same widget.
- **Colors** (`lib/theme/app_theme.dart`): Primary `#7C3AED`, Secondary
  `#00D4FF`, Accent `#FF6B9D` (`kAccentColor`, not yet used anywhere —
  reserved for a future highlight moment), Dark `#0B0F14`, Surface
  `#1A1F2B`, Text `#E8E8F0` (`kTextColor` — used for headings; ordinary
  body text still uses plain white/opacity grays, which read close enough
  to `kTextColor` that swapping every instance wasn't worth the churn —
  easy to do later with a find-and-replace if you want it exact).
- **Type**: Sora for headings (`headingFont()` in `app_theme.dart` — used
  by `SectionHeader`, screen titles, the wordmark), Inter for everything
  else by default. Body face is user-selectable (Settings → Appearance →
  Font); heading face is fixed, since that pairing is the brand identity,
  not an accident of the font picker.

## App icon / Play Store assets

`AppLogo(showBackground: true)` draws the mark on a rounded-square dark
backdrop, matching an app-icon composition — but this environment has no
Flutter runtime to rasterize it into the PNGs Android/Play Store actually
need. To get real launcher icon files: run the app, screenshot
`AppLogo(size: 1024, showBackground: true)` rendered on its own (or
recreate the shape in a design tool — it's two rounded rectangles), then
feed that PNG to the `flutter_launcher_icons` package to generate every
required size.

## Navigation

Bottom nav: Home / Library / Search / Favorites. Settings lives behind the
profile avatar on Home (tap it) rather than taking a nav slot — Downloads
is reached from Home's header icon or Library's app bar.

## Structure

```
lib/
  main.dart                 – entry point, providers, font-driven remount
  app.dart                  – AuthGate (onboarding vs main app) + AppShell (bottom nav + mini player)
  models/                   – Song, Album, Artist, Playlist, AudioInfo, ServerConfig, DownloadStatus
  data/mock_library.dart    – static sample catalog, used only by MockMusicRepository
  backend/                  – the swappable backend layer (see "Backend architecture" below)
    music_repository.dart         – MusicRepository interface + MusicLibrarySnapshot/exceptions
    mock_music_repository.dart    – wraps data/mock_library.dart behind the interface
    navidrome_api_client.dart     – real Subsonic/OpenSubsonic HTTP client (auth, endpoints, URLs)
    navidrome_music_repository.dart – maps the real API client's responses onto app models
  state/
    player_controller.dart  – playback, queue, shuffle/repeat — real audio via just_audio
    app_state.dart           – servers/repository, favorites, downloads, local files, playlists, settings
  theme/app_theme.dart      – brand colors, heading/body font system
  widgets/                  – AppLogo, BrandLoadingIndicator, ShimmerBox, SongTile, cards,
                               action sheets, page transitions, state views
  screens/
    splash/                 – animated startup (the mark draws itself on, then hands off)
    onboarding/             – Welcome (saved-server quick-reconnect), Server Setup, Connection Success
    home/                   – search entry, greeting, Recently Played/Added, Favorites, Recommended, Recently Played Albums
    search/                 – field, recent searches, grouped Songs/Artists/Albums/Playlists results
    library/                – tabbed Songs (sort) / Albums / Artists / Genres / Playlists / Local
    album/, artist/         – detail screens with Play/Shuffle and track lists
    playlist/               – create flow (name + photo/collage cover), detail (rename/delete, swipe-to-remove)
    now_playing/            – Now Playing (drag-to-seek ring), Queue (reorderable), Lyrics (tap-to-seek), Audio Info
    downloads/, favorites/  – offline library, favorited songs/albums/artists
    settings/               – Account/Servers/Playback/Downloads/Cache/Appearance(Font)/Behavior/About
```

## Lyrics providers

`lib/services/lyrics_service.dart` + `NavidromeMusicRepository.fetchEmbeddedLyrics`
fetch real lyrics for whatever's playing, in this order (see
`LyricsScreen._fetch` in `lib/screens/now_playing/lyrics_screen.dart`):

1. **Embedded tags** — `getLyricsBySongId` (an OpenSubsonic extension
   Navidrome supports), returning whatever the server already pulled out
   of the file's own ID3/Vorbis lyrics tags, synced or not. Skipped
   entirely for a server that doesn't implement the extension or a track
   with nothing embedded — not an error, just falls through to LRCLIB.
2. **LRCLIB** (lrclib.net) — free, keyless, matched by
   track/artist/album/duration, with a looser title+artist search as a
   second attempt if the exact lookup misses.

Settings → Lyrics provider is gone, and so is the word-by-word style switch.
The screen now renders each result at exactly the precision its data actually
has, so nothing claims more sync accuracy than exists:
- **Word-synced** data (an enhanced `.lrc` with inline `<mm:ss.xx>` tags, or a
  LRCLIB word-synced Lyricsfile — `lines[].words[].start_ms`, all integer
  milliseconds) renders as true karaoke, sweeping word by word.
- **Line-level** data renders as whole-line highlighting. The per-word timing
  computed on top of it is an estimate, and the footer states which of the two
  you are looking at rather than implying per-word precision.
- **Unsynced text** renders plain: no highlight, no auto-scroll. It used to be
  given evenly-spaced fake timings so the highlight had "something to work
  with", which highlighted a line unrelated to where the song actually was.

Spicy Lyrics was removed as an option because it cannot be called honestly from
this app: its API needs an application key, and every request is addressed by a
Spotify track ID, which a self-hosted Navidrome/OpenSubsonic library does not
carry. Word-level karaoke survives as a *rendering*, driven by real word timings
whenever the data has them.

The LRCLIB client identifies itself in every request (LRCLIB requires clients to,
via `User-Agent`/`Lrclib-Client`), honors `429`/`503` with the server's own
`Retry-After`, spaces requests out, caches results per track, and checks the
response content type before decoding — LRCLIB returns plain text, not JSON, for
malformed parameters. The search fallback ranks candidates by duration proximity
and title/artist match instead of taking the first row, and timings from a
recording whose length differs by more than 5s are never used to drive the
highlight (the text still shows, unsynced).

The blurred karaoke backdrop and the word-sweep accent color now come
from the track's *actual* cover art (see "Dynamic colors" below), not a
fixed per-track placeholder.

## Profile photo

Settings → Profile photo (`avatar_editor_screen.dart`) — pick an image,
pan/zoom with `InteractiveViewer` (pinch built in), rotate with the
buttons or slider, then it captures exactly what's inside the circular
guide via `RepaintBoundary.toImage()`. No cropping package — just
Flutter's own widgets. Shows up on Home's avatar once saved.

## Known limitations / honest caveats

- **Local file/folder import is Android/iOS/desktop-only, not web.**
  `flutter run -d chrome` is a reasonable way to preview the UI quickly,
  but tapping "Add a music folder"/"Add files" there used to crash the
  whole app: `file_picker`'s web backend has no real file paths (reading
  `PlatformFile.path` throws rather than returning null) and doesn't
  implement folder picking at all (`getDirectoryPath()` throws
  `UnimplementedError`) — and there's no `dart:io` filesystem for
  `AppState` to scan even if it did. Both methods now check `kIsWeb` and
  throw a clean `LocalImportUnsupportedException` up front instead, which
  every entry point (`lib/widgets/state_views.dart`'s `runLocalImport`
  helper) catches and turns into a snackbar — "try this on Android, iOS,
  or desktop instead" — rather than an unhandled crash. The Navidrome
  connection and real audio playback both work fine on web otherwise
  (plain HTTP + a URL-based audio source), this is specifically about
  files that live on the device's own filesystem.
- The real Navidrome connection and real audio playback (see "Backend
  architecture" below) were written against the Subsonic/OpenSubsonic
  spec and the `just_audio`/`http`/`crypto` package APIs from training
  knowledge — this sandbox has no Flutter runtime, network socket, or
  audio device, so none of it has actually run. Treat it as
  correctly-reasoned, not verified; see "What to actually test on your
  machine" below for the short list of things to check first.
- The splash's S-mark is hand-coded vector geometry (two rotated rounded
  bars), not an import of the actual designed asset — I have no way to
  render Flutter here to check it against the real logo, so treat it as a
  best-effort approximation, not a pixel-accurate reproduction. For exact
  brand fidelity, export the real mark as an SVG/PNG and swap it in.
- `.clamp()` is used in a few places in a way that's technically ambiguous
  under Dart's type rules (`num.clamp` returns `num`, not the more specific
  `int`/`double`) — it compiles fine on the Flutter SDK this was built
  against, but if you ever hit a `num`/`double` type error on an upgrade,
  that's almost certainly why.

## Reliability pass (v2.0.3)

- **Playback is now clock-based**, not counted in 1-second ticks — `next`/
  `previous`/auto-advance-at-track-end are all driven by one `_advance()`
  path, so skipping and auto-advancing can no longer silently do nothing
  the way the old per-tick counter sometimes did on real devices.
- **Autoplay** (Settings → Behavior) is wired end-to-end: when the queue
  runs out, `PlayerController.suggestionProvider` (bound in `AppShell`)
  pulls more songs by the same artist instead of just stopping.
- **Dynamic colors** and **Artwork style** now actually do something —
  both are read centrally in `ArtworkThumb` (`theme/dynamic_theme.dart`),
  so every card/thumbnail in the app responds without each screen needing
  its own wiring.
- **Reduce animations** now actually shortens/removes the page transitions
  (`page_transitions.dart` checks it), not just a stored, unused bool.
- **Lyrics sync is smooth**: the karaoke line now rebuilds every frame via
  `SmoothPositionBuilder` (a muted-when-paused `Ticker`) instead of
  stepping once a second with the rest of the app. Settings → Lyrics also
  gained Auto-scroll and Sync adjustment (±ms), both wired into the
  rendering.
- **Fixed two real overflow crashes** on Album/Artist detail: their header
  artwork was sized by `AspectRatio` off the available *width*, which
  could exceed the fixed-height header on wider screens. Now a fixed,
  safely-budgeted size.
- **Fixed the "off-center" look in Chrome**: `flutter run -d chrome`
  renders across the full desktop browser window, and everything actually
  was centering correctly — just relative to a much wider space than a
  phone screen. `MaterialApp.builder` now caps content to a phone-like
  460px and centers that, which is a no-op on an actual device.
- App version is centralized in `app_info.dart` (`kAppVersion`/
  `kAppBuild`) and shown in Settings → About — bump it there and in
  `pubspec.yaml`'s `version:` together on every release.

## Reliability pass (v2.1.0)

Fixes from testing against a real Navidrome server:

- **Real lyrics**, embedded-first — see `## Lyrics providers` above.
  Previously 100% placeholder filler text regardless of what was playing.
- **Library fetch is parallelized**: `NavidromeMusicRepository.fetchLibrary`
  used to `await` one `getAlbum` request per album in a row; it now runs
  up to 8 at once (`_mapWithConcurrency`), which is the main thing that
  made a real server's first connect feel slow. One album's request
  failing no longer fails the whole connect — just that album is skipped.
- **Fixed a real genre-browsing bug**: the Genres tab used to key songs by
  *artist*, so tapping a genre showed an artist's entire catalog if even
  one of their songs matched — including songs in other genres entirely.
  `MusicLibrarySnapshot.genreSongIds` (renamed from `genreArtistIds`) is
  now keyed by song, so a genre page shows only songs actually tagged
  with it.
- **Now Playing can add to a playlist** (and reach every other song
  action — Play next, Add to queue, Download, Audio info) via a new "⋮"
  button — previously the only way in was a long-press from a list, and
  there was no way at all to act on the song actually playing without
  first finding it again somewhere else.
- **Dynamic colors are now real colors**: Now Playing and Lyrics used to
  theme themselves off `Song.gradientColors` — a color picked
  deterministically from the song's *ID string*, unrelated to what the
  cover art actually looks like. `theme/dynamic_theme.dart`'s new
  `ArtworkPalette`/`ArtworkPaletteBuilder` extracts real colors from the
  track's own artwork (`package:palette_generator`), cached per track, and
  both screens (plus the Lyrics karaoke backdrop) now use that. Settings
  → Dynamic colors off still means the fixed brand gradient, as before;
  list rows/cards are unchanged (still the cheap deterministic color —
  right call there, since extracting a real palette per row would mean
  decoding every visible cover art just to color a placeholder).
- **Real lock-screen/notification controls**: previously `just_audio`
  played audio with no Android `MediaSession` behind it at all, so there
  was nothing for a lock screen, Bluetooth headset, or Android Auto to
  show or control. Now wired via `just_audio_background` — see
  `## Lock-screen & notification controls` above for the one manual setup
  step this needs.
- **A small custom icon set** (`lib/widgets/shuro_icons.dart`,
  `CustomPainter`-drawn like `AppLogo` — no SVG asset to bundle) replaces
  stock Material icons on the controls people look at most: play/pause/
  skip/shuffle/repeat, the favorite heart, and the song-actions sheet.
  Genre cards also got a big abstract mark per genre family (rock/metal →
  a bolt, pop/dance → a star, electronic → waves, hip-hop/R&B → a mic,
  jazz/classical → a double note, folk/acoustic → a leaf, anything else →
  a plain note) instead of being a flat color block with just a label.
  Scope note: this covers the highest-visibility spots, not literally
  every icon in the app (back arrows, settings rows, etc. are still stock
  Material icons) — going further is straightforward (follow the same
  `ShuroIcon(ShuroGlyph.…)` pattern) but wasn't worth the risk of
  shipping worse icons everywhere else without a way to actually render
  and check them first (this sandbox has no Flutter runtime).

## Reliability pass (v2.1.1)

From testing an actual `flutter run` against a real Navidrome server —
the first time this project has run on an actual Flutter SDK rather than
only being reasoned through and statically checked:

- **Fixed two real compile errors** caught by that first real build:
  `shuro_icons.dart`'s `_note()` helper still declared an unused third
  parameter that nothing was passing at its call site, and
  `now_playing_screen.dart` used `PlayerRepeatMode` after an earlier pass
  had removed its import (`models/download_state.dart`, where that enum
  actually lives) as "unused" — it wasn't. Also swept the whole `lib/`
  tree for the same class of bug (a type used in a file that doesn't
  import where it's declared) with a small heuristic script; nothing else
  turned up.
- **Streaming quality now actually changes the stream, not just a
  label.** Settings → Wi-Fi quality / Mobile data quality always had a
  picker, but the stream URL never carried the choice — Navidrome applied
  its own server-side default transcode to every track regardless.
  "Original" now sends `format=raw` (Subsonic/OpenSubsonic's signal to
  skip transcoding entirely and serve the file's own bytes — genuinely
  untranscoded audio), and High/Medium/Low send `maxBitRate` (320/160/96)
  and let the server pick its transcode format, the normal way Subsonic
  clients ask for a capped-quality stream. Which of the two settings
  applies is now resolved against the device's **real** current
  connection type via `connectivity_plus` (previously nothing detected
  Wi-Fi vs. mobile data at all, so "Mobile data quality" was decorative
  too) — no manual Android setup needed for this one, the plugin merges
  its own `ACCESS_NETWORK_STATE` permission into the manifest
  automatically.
- **Fixed a real settings bug**: "Download quality" read and wrote the
  *same* field as "Mobile data quality" under a different label, so
  changing one silently changed the other. It's now its own
  `AppState.downloadQuality` setting.
- **Backend error handling hardened**: `NavidromeApiClient` now retries
  once (after a short delay) on a transient network failure
  (`SocketException`) before giving up — a home LAN server drops a
  request far more often than a hosted one would (Wi-Fi/mobile handoff,
  router blips, the server machine briefly asleep), and a genuinely-down
  server or a real HTTP/auth error still fails normally, immediately.
  `PlayerController` now also handles a stream that errors out
  *mid-playback* (connection lost after a track already started) instead
  of only handling a failure to start one — previously that case had no
  handler at all, so the UI could keep showing "playing" over audio that
  had silently died, with no feedback.
- **Fixed artwork with no error fallback**: `ArtworkThumb` and
  `ArtworkRing` rendered cover art via `Image(image: ...)` with no
  `errorBuilder` — any failed load (server unreachable, a cover art ID
  that 404s, a LAN connection dropping) showed Flutter's default red/grey
  error box instead of the gradient-+-icon placeholder already built for
  exactly this case. Both now fall back to it on a failed load, not just
  when there's no artwork at all. This is used by nearly every card in
  the app, so it's a broad fix from one spot.

## Reliability pass (v2.2.0)

A full UI/UX audit of the app as it stood — two independent passes (one
done here, one an external review pasted in by the project owner) that
agreed on the same short list of problems: nothing the app actually
remembers across a restart, and several places where the UI claimed
something that wasn't true. This pass fixes the app's state/UI layer; it
deliberately does **not** touch playback internals (gapless, ReplayGain,
crossfade, bit-perfect output) or the server/backend protocol layer —
those are being built separately.

- **The app finally remembers things.** Nothing survived a restart before
  this pass — not settings, not favorites, not playlists, not saved
  servers, not listening history, not even which local folders you'd
  imported. All of it is now persisted on-device via `shared_preferences`
  (`lib/services/app_persistence.dart`) and restored on launch:
  settings, favorites, play history/artist affinity (the data ShuroPulse
  runs on), playlists, imported local folders (re-scanned on restore),
  saved servers, and — when "Remember queue" is on — the current queue
  and playback position, saved when the app is backgrounded and restored
  on next launch. **Honest caveat, disclosed in code comments where the
  data is written:** this is plain local key-value storage, not secure
  storage — a saved server's password sits on-device unencrypted. Worth
  upgrading to `flutter_secure_storage` later; not papered over here.
- **Audio Info panel no longer lies.** Every track's format/bit-depth/
  sample-rate/bitrate shown in Now Playing → Audio Info was hardcoded
  (16-bit / 44.1kHz / 1000kbps / FLAC) regardless of what the server
  actually sent — a FLAC and an MP3 looked identical. Navidrome's real
  OpenSubsonic response fields (`bitDepth`, `samplingRate`,
  `channelCount`, `suffix`, `bitRate`) are now parsed and shown instead,
  falling back to the old placeholder values only when a field is
  genuinely absent.
- **Fixed a real correctness bug**: the Audio Info sheet read
  `wifiQuality` directly even while on mobile data, so it could show the
  wrong quality/transcoding status. It now reads
  `effectiveStreamingQuality`, which already resolves Wi-Fi vs. mobile
  correctly everywhere else in the app.
- **"Clear cache" in Settings is now a real control**, backed by
  Flutter's own introspectable image cache (`PaintingBinding.instance
  .imageCache`) instead of a hardcoded, never-changing number with a
  button that did nothing. The separate "Audio cache" row was removed —
  there's no such concept distinct from Downloads, so a parallel fake
  number for it would just be a second lie instead of one.
- **Dead taps in Settings are gone.** Account / Storage location / Theme
  / Version rows had `onTap: () {}` — tappable-looking rows that silently
  did nothing. They're now genuinely non-interactive (no ripple), which
  is the honest state given this app has no account system beyond server
  login, no SAF storage picker, and a deliberately dark-only theme.
- **Pull-to-refresh on Home and Library now refreshes.** Both reloaded
  nothing and just played a fake spinner animation before; they now
  re-fetch the library from the connected server.
- **Saved-server reconnect now gives real feedback.** Tapping a saved
  server (in Settings → Servers, and on the Welcome screen's "Saved
  servers" list) used to fire off a reconnect with no loading state and
  no error if it failed — a bad saved password or an unreachable server
  looked identical to success. Both places now show a spinner on the
  tapped row while connecting and a snackbar if it fails.
- **Fixed a dead branch in "Remove server."** The flow meant to pop back
  to onboarding after removing your *last* server checked
  `connectionStatus == ConnectionStatus.disconnected` — a state
  `removeServer()` never actually produces (it falls back to `localOnly`
  instead), so that pop never fired. It now checks whether the server
  list is actually empty.
- **Deduplicated the three near-identical rename dialogs** (playlist
  rename ×2, server rename) into one shared `promptForRename` helper in
  `widgets/state_views.dart`, and gave each a proper hint text instead of
  an unlabeled text field.
- **Album/Artist detail screens no longer go blank on empty data.** An
  album with no tracks, or an artist with no popular songs / no albums in
  the connected library, now shows the same `EmptyStateView` used
  elsewhere instead of an unexplained empty section.

## What's real vs. simulated

- **Playback is real**: `PlayerController` is backed by an actual
  `just_audio` `AudioPlayer` — real decode, real position/duration
  streams, real seek. See "Backend architecture" below for what to
  actually verify on a device.
- **The Navidrome connection is real**: `AppState.connectToServer` opens a
  real `NavidromeMusicRepository`, pings the server, and fetches the whole
  library over the Subsonic/OpenSubsonic REST API. The three failure
  states (unreachable, invalid credentials, generic) are driven by real
  HTTP responses now, not a heuristic. Multiple servers are still
  supported (`AppState.servers`/`activeServer`) — unnamed ones default to
  "Server N" — and switching servers reconnects for real.
- **The catalog** comes from whichever `MusicRepository` is active —
  `NavidromeMusicRepository` once connected, nothing while disconnected or
  local-only. `data/mock_library.dart` and `MockMusicRepository` still
  exist as the interface's reference implementation (useful for UI work
  or tests without a live server) but nothing wires it in by default
  anymore. See "Backend architecture" below.
- **Local files**: `AppState.importLocalFiles()`/`importLocalFolder()` use
  `file_picker` to add device audio into `AppState.localSongs`; titles
  come from the filename since there's no real metadata/ID3 reading yet.
  These already play for real (just_audio opens the file path directly).
- **Downloads** simulate progress over ~1.2s per song
  (`AppState.startDownload`) rather than writing real files — the
  download UI (progress, storage usage) works, but "downloaded" songs
  still stream from wherever they came from rather than playing from a
  cached local copy. A real implementation would fetch the repository's
  stream URL to a file and resolve playback from that path when offline.
- **Lyrics are real**, from two real sources, tried in this order (see
  `lib/services/lyrics_service.dart` and `## Lyrics providers` below):
  1. **Embedded** — whatever the connected Navidrome server already
     extracted from the file's own tags (ID3 `USLT`/`SYLT`, Vorbis
     comments, …), via the OpenSubsonic `getLyricsBySongId` extension.
  2. **LRCLIB** (lrclib.net) — a free, keyless public lookup by
     track/artist/album/duration, used whenever nothing's embedded (or
     there's no server connected at all).
  A local-imported file skips both — its "artist" is just the placeholder
  string `"Local file"`, not real metadata to search with.
- **Artwork** uses real `NetworkImage(coverArtUrl)` once connected to a
  server (`navidrome_music_repository.dart` builds the URL per song/
  album/artist via `getCoverArt.view`); it falls back to a gradient + icon
  placeholder only where there's genuinely no art (local files, anything
  the mock repository returns). Playlist covers already support a
  user-picked photo (`AppState.pickImageBytes()` → `MemoryImage`).

## Backend architecture (real Navidrome + real audio)

This app no longer talks to `MockLibrary` from the UI layer at all — every
screen reads through `AppState`'s catalog getters/helpers
(`catalogSongs`, `songsForAlbum`, `searchCatalogSongs`, `audioSourceFor`,
…), and `AppState` is the *only* place that knows a backend exists. That
seam is `lib/backend/music_repository.dart`:

```dart
abstract class MusicRepository {
  Future<void> connect();                       // ping/auth check
  Future<MusicLibrarySnapshot> fetchLibrary();   // the whole library, once
  String? streamUrlFor(Song song, {StreamingQuality quality}); // null = nothing to play
  void dispose();
}
```

**Design choice: fetch everything once, cache it, filter client-side.**
`connectToServer` calls `connect()` then `fetchLibrary()` a single time and
caches the result (`AppState._librarySnapshot`). Every catalog
query — search, genre browsing, per-album/per-artist songs — filters that
in-memory snapshot synchronously, exactly like the old `MockLibrary` did.
That was a deliberate trade-off for a self-hosted *personal* library
(hundreds to low thousands of tracks): it means zero async rewrite of
`search_screen.dart`, the Genres tab, or the album/artist detail screens,
at the cost of not scaling to a huge multi-user streaming catalog or
picking up server-side changes without a reconnect. If your library is
much bigger than that, the fix is pagination/lazy-loading inside
`NavidromeMusicRepository.fetchLibrary()` — `AppState` and the screens
wouldn't need to change, since they only ever see the resulting
`MusicLibrarySnapshot`.

**Two implementations ship:**
- `MockMusicRepository` — wraps `data/mock_library.dart`. `connect()`
  never fails, `streamUrlFor()` always returns null (the sample catalog
  has no real audio behind it, by design — it should show the "can't
  play" snackbar, not silently fail). Nothing wires this in right now;
  it's there as the interface's reference implementation and a clean way
  to UI-test without a live server (`AppState(repositoryOverride: ...)`
  isn't wired up either — if you want a "try a demo library" entry point,
  construct one in `connectToServer`'s place and skip the network call).
- `NavidromeMusicRepository` + `NavidromeApiClient` — the real one.
  Subsonic/OpenSubsonic token auth (`token = md5(password + salt)`, a
  fresh random salt per client instance — the plaintext password is never
  sent). Endpoints used: `ping`, `getArtists`, `getAlbumList2` (paginated,
  `type=newest`, capped at 20 pages of 500 so a misbehaving server can't
  loop forever — this also happens to make "Recently Added" accurate for
  free, see below), `getAlbum` (per-album song list), plus the
  `stream.view`/`getCoverArt.view` URL builders — `stream.view` now carries
  the caller's `StreamingQuality` as real `format=raw` (Original —
  untranscoded) or `maxBitRate` (High/Medium/Low) query params, not just a
  Settings-screen label; see "Reliability pass (v2.1.1)" above.
  Deliberately **not**
  used: `search3`/`getGenres` — search filters the cached song list the
  same way `MockLibrary.search` did, and genre→artist-ID grouping is
  derived client-side from each fetched song's own `genre` field during
  `fetchLibrary()`, matching `MockLibrary.genreArtistIds`'s exact shape.
- Errors are classified into `MusicRepositoryFailure.{unreachable,
  invalidCredentials, unknown}` via `MusicRepositoryException`, which
  `AppState.connectToServer` maps onto the existing `ConnectionStatus`
  states — the UI's three error messages are unchanged, they're just
  driven by real server responses now.

**"Recently Played/Added" rails** (`AppState.recentlyAddedSongs/Albums`,
`recentlyPlayedSongs`) no longer come from hardcoded ID lists:
"Added" reads off the real newest-first album order from the server;
"Played" reads off `AppState.listeningHistory`, which is genuine in-app
play tracking, not server data (Subsonic has no durable per-user play
history endpoint this client relies on). Home's "Recommended" rail now
calls `ShuroPulse.forYou` (the real heuristic engine, see "Shuro Pulse"
below) instead of a hardcoded list.

**Real audio** (`lib/state/player_controller.dart`): a real `just_audio`
`AudioPlayer` replaced the old `Stopwatch`/`Timer` simulation entirely —
real `positionStream`/`playerStateStream`, real `play`/`pause`/`seek`.
Nothing about the public API changed (`playSong`, `togglePlayPause`,
`seekToProgress`, `next`/`previous`, queue management all still exist
with the same names/shapes — now `Future<void>` instead of `void`, which
every call site already used fire-and-forget, so no screen needed to
change). A new `AudioSourceResolver` callback — wired once in
`app.dart`'s `AppShell.initState` to `AppState.audioSourceFor` — tells the
player what to actually open: a local file's own path, or
`repository.streamUrlFor(song, quality: effectiveStreamingQuality)` for a
server song, resolved against Settings -> Wi-Fi/Mobile data quality and
the device's real current connection type. A song with **no**
real source behind it (anything from `MockMusicRepository`, or any song
if nothing's connected) surfaces as a snackbar
(`PlayerController.lastPlaybackError`, shown via `_showPlaybackErrors` in
`app.dart`) instead of crashing or silently doing nothing — this is the
*expected*, correct behavior for mock/demo content now that playback is
real, not a bug to chase.

### What to actually test on your machine

Nothing in this sandbox can run Flutter, open a socket, or play audio.
`flutter pub get`/`flutter run` *have* now been run for real (on your
machine, against `-d chrome`), which is how the two real compile errors
fixed in v2.1.1 were caught — everything else below is still only written
correctly against my best knowledge of the Subsonic/OpenSubsonic spec and
the `just_audio`/`http`/`crypto`/`connectivity_plus` APIs, **not executed
against a real server, a real network-type switch, or an Android device**
(Chrome on desktop doesn't exercise `just_audio_background`'s lock-screen
integration or `connectivity_plus`'s mobile-data detection at all — both
need an actual Android run). In rough priority order:

1. Run it on an actual Android device/emulator, not just Chrome — confirms
   the lock-screen/notification controls (after the manual
   `AndroidManifest.xml` step above) and lets Wi-Fi vs. mobile data
   actually differ, which Chrome can't simulate.
2. Connect to a real Navidrome server with correct and then deliberately
   wrong credentials/URL — confirm all three `ConnectionStatus` outcomes
   (connected, invalid credentials, unreachable) and that the fetched
   library actually populates Library/Search/Home.
3. Play a server song end-to-end — this exercises the token/salt auth on
   the `stream.view` URL, which is the one piece that's hardest to get
   subtly wrong (if it 401s, the salt/token pairing or URL encoding is
   the first thing to check in `NavidromeApiClient`).
4. Play a local-imported file, then a server song, back to back — checks
   the resolver's local-vs-URL branch in `PlayerController._jumpTo`.
5. Let a track play to completion with autoplay on/off, and with each
   repeat mode — exercises `_advance`'s real `ProcessingState.completed`
   path, which replaced the old tick-counter's `position >= duration`
   check.
6. Genre tab, Search, and an album/artist detail screen against a
   real library of a few hundred+ tracks — confirms the "fetch once,
   filter client-side" design actually feels instant rather than janky at
   your library's real size.
7. Switch Settings → Wi-Fi quality to something other than Original, then
   toggle your phone's Wi-Fi off (forcing mobile data) mid-session and
   play a new track — confirms `connectivity_plus` actually picks up the
   change and the next stream URL carries the *mobile* quality's
   `maxBitRate`, not the Wi-Fi one. Easiest to verify by watching your
   Navidrome server's own log/Active Streams page for the `maxBitRate`/
   `format` query param on each request.

### Extending this further

- **A different backend** (not Navidrome/Subsonic): implement
  `MusicRepository` against it and construct it in
  `AppState.connectToServer` instead of/alongside
  `NavidromeMusicRepository` — no screen changes needed.
  **Larger catalogs**: make `fetchLibrary()` on `NavidromeMusicRepository`
  paginate/lazy-load instead of aggregating everything up front; keep
  returning the same `MusicLibrarySnapshot` shape (or change
  `MusicRepository.fetchLibrary()`'s contract and update `AppState`
  accordingly — it's the only caller).
- **Offline downloads that actually play offline**: have
  `AppState.startDownload` fetch `repository.streamUrlFor(song)` to a real
  file (`http` + `dart:io`), then have `audioSourceFor` check
  `downloadedSongIds` before falling through to the repository's stream
  URL.

## Motion

One shared `risingRoute` (fade + gentle upward slide) for anything tied to
what's playing — mini player → Now Playing → Queue/Lyrics — and
`drillDownRoute` (fade + slide from the right) for regular navigation.
`BrandLoadingIndicator` and `ShimmerBox` cover connecting/loading states
instead of generic spinners. `AnimatedFavoriteIcon` gives every heart
toggle a small scale-pop. All built on Flutter's own implicit-animation
widgets — nothing extra running once a transition finishes.

## Shuro Pulse (Discover, Smart Playlists, Build with Shuro)

The Discover tab, Smart Playlists, "Build with Shuro", and every song's
"Build from this" sheet are all backed by one file: `lib/services/
shuro_pulse.dart`. It's a real, working heuristic layer — not hardcoded
lists — running entirely against `AppState`'s catalog getters (which read
from whichever `MusicRepository` is connected, see "Backend architecture"
above) plus its favorites, `listeningHistory`, and `artistAffinity`.
Nothing here calls out to a server itself, which is also why it's private
by construction.

What it does today:

- **For You** (`ShuroPulse.forYou`) — a single ranked list balancing
  affinity (favorited, liked artists, explicit feedback) against a small
  discovery nudge for anything never played. This stands in for the
  product doc's "Familiarity ↔ Discovery" balance; a real version would
  expose that ratio as a setting feeding straight into this scoring step.
- **Tonight's Flow** (`ShuroPulse.tonightsFlow`) — builds a *session*, not
  a ranked list: interleaves favorites, favorite-artist tracks, and
  everything else so familiar and unfamiliar songs are spread through the
  sequence rather than front/back-loaded. A crude stand-in for real
  transition/sequence optimization.
- **Because You Like <Artist>** (`ShuroPulse.becauseYouLike`) — one row
  per artist you already like or have given positive feedback on, each
  populated from other artists sharing a genre bucket. A real version
  would walk an actual similarity graph instead of `genreArtistIds`.
- **Rediscover / Deep Cuts / Fresh From Your Library** — straightforward
  filters over favorites-not-played-recently, non-top-played tracks by
  artists you know, and the server's newest-added songs, respectively.
- **Smart Playlists** (`ShuroPulse.smartPlaylistSongs`, `SmartPlaylist
  Preset`) — 10 presets (Rediscover, Deep Cuts, Late Night, Favorites Mix,
  Recently Added, Forgotten Favorites, High Energy, Chill, Focus, Long
  Drive). These are **live queries**: `Playlist.smartPreset` is the only
  thing stored, and `PlaylistDetailScreen` re-runs `smartPlaylistSongs`
  every time it's opened — never a frozen list of IDs.
- **Build from this** (`ShuroPulse.buildFrom`, `BuildFromMode`, reachable
  from every song's "⋮" menu) — radiates one seed track into a full queue
  via one of five rules (More like this / Same era / Deeper cuts /
  Surprise me / Smooth continuation).
- **Build with Shuro** (`ShuroPulse.songsForPrompt`) — turns a short
  free-text prompt into a playlist via regex-based intent detection
  (calm/energetic/forgotten/new/favorites + artist-name mentions), then
  ranks matches by the same affinity score as For You.
- **Feedback loop** (`AppState.recordArtistFeedback`, surfaced as "More
  like this / Less like this / Not interested" on Discover rows) — nudges
  `artistAffinity` up or down, which every method above reads from.

### What a real backend would change (and what it wouldn't)

Every `ShuroPulse` method takes `AppState` (or a song) as its only input
and returns a plain `List<Song>` — that's the seam a real implementation
would keep. None of the screens know or care that the engine underneath
is a handful of filters and sorts instead of a trained model; swapping the
engine is a `shuro_pulse.dart` change, not a screen rewrite.

What's explicitly **not** built here, because it's a genuine multi-week
effort that shouldn't be faked:

- **Persisted listening events** — `AppState.listeningHistory` is an
  in-memory list capped at 40 entries. A real version would log every
  play/skip/completion to local storage (Drift/SQLite is the natural
  choice for an offline-first, self-hosted app) with fields like
  `(song_id, played_at, ms_played, skipped, source)`, so recommendations
  survive app restarts and can look further back than 40 plays.
- **Real audio features** — `_energyOf()` is a deterministic hash
  standing in for actual tempo/energy/valence. A real version would either
  run audio analysis on import or read embedded/ReplayGain-adjacent
  metadata, store it per track, and use it instead of a hash.
- **A real similarity graph** — `becauseYouLike`/`buildFrom`'s "similar
  artist" step is a shared-genre lookup. A real version would build a
  `track_affinity`/`artist_affinity` table from co-occurrence in people's
  own playlists and listening sessions (collaborative signal), or call out
  to a metadata service — while keeping everything else (ranking,
  sequencing, the UI) unchanged.
- **Session/sequence optimization** — `tonightsFlow`'s pool-interleaving
  is a fixed pattern. A real version would score *transitions* (energy
  delta, key compatibility once real audio features exist), not just pick
  individual tracks, and search for a good ordering rather than round-
  robin through pools.
- **NL understanding for "Build with Shuro"** — `songsForPrompt`'s regex
  intent detection only recognizes a handful of moods and literal artist
  names. A real version would either expand the keyword/synonym tables
  significantly or hand the prompt to a small on-device or server-side
  model and parse structured constraints back out.

None of the above require touching `DiscoverScreen`, `SmartPlaylists
Screen`, `BuildWithShuroScreen`, or the "Build from this" sheet — they all
just call into `ShuroPulse` and render whatever `List<Song>` comes back.

## Notably not built

No equalizer screen — a fake one would be worse than none. No open-source
licenses page in Settings (removed ahead of a Play Store submission —
worth an independent check of your final dependency licenses before you
actually publish, since that's a product/legal decision, not a UI one).
No persisted recommendation backend (see "Shuro Pulse" above) — the
heuristic layer is real and working, but it resets with the app process.

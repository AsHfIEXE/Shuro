# Desktop UX research — 10 conventions to adopt in Shuro

Research date: 2026-10-23. Scope: Windows/Linux desktop music clients, focused on Navidrome/Subsonic clients (Feishin, Sonixd, Supersonic, Psysonic, NaviBeat) and local players (MusicBee, foobar2000, Dopamine, Lollypop, Elisa, Rhythmbox, Amberol, Cog). Cog is macOS/iOS — cited only as evidence for feature positioning, not layout.

**Method note (evidence tiers):** Every claim below is tagged `[V]` (verified from a cited web source or from Shuro's own source this run) or `[I]` (inference/design judgment — no direct source). Direct page fetches were unavailable this run; `[V]` web claims rest on search-result excerpts from the cited URLs. Shuro code facts were read directly from the repo.

---

## 0. What Shuro has today `[V]` (read from code)

| Area | Current state | File |
|---|---|---|
| Shell | Left sidebar (236px / 76px collapsed, rail items only), 68px header (page title + 220px Ctrl+K search pill + lyrics toggle), `IndexedStack` of 5 mobile-derived tabs, 348px lyrics inspector shown when open & width ≥1240, 100px bottom `PlayerDock` | `lib/widgets/desktop_shell.dart` |
| Menu | 30px Flutter-drawn in-app menu bar: Playback / View / Help + shortcuts dialog | `lib/widgets/desktop_menu_bar.dart` |
| Now playing | `DesktopNowPlaying` — three-column embedded pane (artwork \| transport+seek \| karaoke lyrics), replaces the content pane, not a route. But the dock artwork still *pushes the mobile* `NowPlayingScreen` route | `lib/widgets/desktop_now_playing.dart`, `desktop_shell.dart` `_PlayerDock` |
| Queue | Mobile `QueueScreen` pushed as a drill-down route from the dock; reorder via `ReorderableListView`; `playNext`/`addToQueue`/`clearQueue` exist on the controller | `lib/screens/now_playing/queue_screen.dart`, `lib/state/player_controller.dart` |
| Track lists | `SongTile` = `ListTile` (thumb/track no., title, artist, trailing). No columns, no sorting, no multi-select anywhere in the app | `lib/widgets/song_tile.dart`, `lib/screens/library/library_screen.dart` `_SongsTab` |
| Context menus | `ContextMenuRegion` → Flutter `showMenu` at cursor; per-song and per-group items incl. Play next / Add to queue | `lib/widgets/desktop_context_menu.dart` |
| Palette | Ctrl+Shift+P dialog, top-center; substring filter over label+section; ↑↓/Enter/Esc; fixed command list rebuilt per open | `lib/widgets/command_palette.dart` |
| Keys | Space (when not typing), Ctrl+←/→, Ctrl+L, Ctrl+K, Ctrl+1–5; text-field key guard `_letTextFieldKeepKeys` | `desktop_shell.dart` |
| OS integration | Tray icon + menu w/ playback (`tray_manager`), close→hide-to-tray (`window_manager`). Media session is **Android/iOS only** (`audio_service`); no MPRIS/SMTC on desktop | `lib/services/desktop_lifecycle.dart`, `lib/main.dart:110` |

---

## The 10 conventions, prioritized

### 1. A real track table: sortable column headers, configurable columns, compact density
**Source:** Supersonic — "Sort tracklist views by column and configure visible tracklist columns" (flathub.org/en/apps/io.github.dweymouth.supersonic) `[V]`; foobar2000 playlist view with user columns (foobar2000.org/components/view/foo_ui_columns) `[V]`; MusicBee customizable main-panel columns (getmusicbee.com/forum topic 29024) `[V]`.

Every well-regarded desktop client renders track lists as a table. Shuro's desktop surfaces reuse the mobile `SongTile` `ListTile`, which wastes horizontal space and offers no sorting — the single biggest "this is a phone app" signal.

**Do this in Shuro:**
- New `DesktopSongTable` widget (suggested `lib/widgets/desktop_song_table.dart`) used by `library_screen.dart` `_SongsTab`, `_GenreSongsScreen`, `_LocalTab`, `search_screen.dart`, and `playlist_detail_screen.dart` on desktop-width layouts. Keep `SongTile` for mobile/narrow builds.
- Default columns: `# (40px) | Title (flex) | Artist (160) | Album (200) | Duration (56) | ♥ (36) | download status (36)`. Header tap toggles asc/desc with an arrow indicator; column visibility persisted per-view (follow the existing `PlaybackPrefs`/`app_persistence.dart` pattern).
- Two densities: comfortable 44px rows, compact 32px (MusicBee "compact view" precedent `[V]`). Hover row reveals row actions; currently-playing row gets a persistent accent bar + "played since" state — foobar2000's arrow-only indicator is a documented user complaint (superuser.com/questions/611587) `[V]`.
- Rubber-band selection, see #2.

**Acceptance:** On the Library→Songs tab a user can sort by any column, hide columns, and see the playing track highlighted without hunting.

### 2. Multi-select with Ctrl/Shift-click, batch actions, and drag-as-a-unit
**Source:** Feishin v1.0.1 — "You can now select and drag/drop items from the list and other views directly to the queue … directly to playlists" (newreleases.io/project/github/jeffvli/feishin/release/v1.0.1) `[V]`; standard in foobar2000/MusicBee `[I]`.

Shuro has zero multi-select today `[V]` (grep found none). Every power workflow (queue 20 tracks, add album to playlist, download a batch) currently needs N right-clicks.

**Do this in Shuro:**
- Selection model inside `DesktopSongTable`: click = select one; Ctrl+click = toggle; Shift+click = range; Ctrl+A = select all; Esc = clear. Selected rows get a check overlay; count appears in the header (`_DesktopHeader` or table header row: "3 selected · Play next · Add to queue · More ⋮").
- Batch context menu: extend `desktop_context_menu.dart` `songContextMenuItems` with a plural variant reusing the group items that already exist ("Play / Shuffle / Add to queue for a group" `[V]` exists at `desktop_context_menu.dart:219`). Add "Add to playlist(s)" via existing `add_to_playlist_sheet.dart`, and "Download" via `DownloadService`.
- Drag-as-unit feeds #3 (drop on queue pane) and #6 (drop on sidebar playlist).

**Acceptance:** Shift-click 10 rows → right-click → Add to queue works in one gesture; drag selection onto the queue pane reorders/inserts.

### 3. Queue as a first-class pane beside the content, not a pushed route
**Source:** Feishin — "the playback queue pane on the right" (delightlylinux.wordpress.com/2026/08/24/feishin-music-player) `[V]`; Amberol — "drag and drop support to queue songs" (apps.gnome.org, Amberol page) `[V]`; foobar2000 makes the play queue the center of the UI `[I]`.

Shuro's queue button pushes the mobile `QueueScreen` route `[V]`, hiding the library — desktop users keep the library visible while curating what plays next.

**Do this in Shuro:**
- In `desktop_shell.dart`, mirror the `_LyricsInspector` pattern: an optional right-side `QueuePane` (suggested 320px) toggled by the dock's queue button (and Ctrl+Q / menu item). Reuse the `ReorderableListView` already in `queue_screen.dart` by extracting its list body into a shared widget.
- Drop target: dropping rows (from #2) inserts at the drop index; header row "PLAY QUEUE · n tracks · Clear (undoable)" reusing `player.clearQueue` which the menu already marks undoable `[V]`.
- Only one inspector at a time is fine (queue wins over lyrics, or stack as tabs in one inspector) `[I]`. Below ~1240px width, fall back to the existing pushed route — same pattern `_toggleLyrics` already uses for narrow windows `[V]`.
- Keyboard: Del removes selected queue rows (see #8).

**Acceptance:** Drag two songs from the album view into the queue pane between existing tracks; the library never leaves the screen.

### 4. OS media integration: MPRIS on Linux, SMTC on Windows, media keys everywhere
**Source:** Supersonic — "MPRIS and Mac OS media center integration" (flathub) `[V]`; Amberol — "MPRIS integration" (apps.gnome.org) `[V]`; Navidrome apps page lists desktop clients advertising "MPRIS/SMTC media integration" (navidrome.org/apps) `[V]`.

This is the #1 native-feel gap: Shuro's media session layer "exists on Android and iOS only" (`lib/main.dart:110`) `[V]`. Without MPRIS, Linux users can't pause from the GNOME shell / media keys; without SMTC, Windows users get no media overlay — tray menu aside, Shuro feels disconnected from the OS.

**Do this in Shuro:**
- Extend `desktop_lifecycle.dart` (it already owns `window_manager` + `tray_manager` and the `MediaControlsBridge`-style callbacks used by the tray) with: Linux — an MPRIS `org.mpris.MediaPlayer2.shuro` D-Bus service (via `package:dbus` or a small platform channel to a helper) exposing Play/Pause/Next/Previous/Seek + metadata + position; Windows — SMTC (`SystemMediaTransportControls`) via the existing Windows runner in `windows/`.
- Single source of truth: both bridges subscribe to `PlayerController` and forward transport commands to the same methods the tray already calls `[V]` (app.dart tray wiring). Playback state, position, and artwork thumbnail flow one way (controller → OS); commands flow back through the same entry points.
- Accept degraded behavior gracefully the way the tray code already does ("a tray/DBus call that never answers must not hold up runApp" `[V]`, main.dart:52).

**Acceptance:** On Ubuntu, GNOME's media HUD + keyboard media keys control Shuro; on Windows 11, the SMTC flyout shows track + art and pauses.

### 5. Make the queue/play-context model visible: "Up next" vs "From this album" vs playlists
**Source:** foobar2000 separates active playlist from playback queue `[V]` (Columns UI playlist switcher + queue, yuo.be / reddit.com/r/foobar2000 thread 1nk0gll); Feishin users explicitly request "queue presets / saved queue templates … unlike playlists, these wouldn't just be static song lists" (github.com/jeffvli/feishin/issues/1144) `[V]`; Sonixd/Feishin keep a distinct "play queue" apart from saved playlists `[V]` (client docs/descriptions).

Convention: **now-playing context** (the album/playlist/radio that started playback), **queue overrides** (Play next / Add to queue), and **playlists** (persisted) are three different things, and the UI labels which is which. Shuro's controller already models overrides (`playNext`, `addToQueue`) `[V]` but no surface shows them.

**Do this in Shuro:**
- Queue pane (#3) header shows context: "Up next — from *Album X*" or "Up next — your queue (3 added)". Rows manually queued get a subtle badge distinguishing them from context tracks `[I]`.
- `desktop_now_playing.dart`: add a one-line "Playing from Album/Playlist/Pulse mix" origin strip above the transport (data: track the origin when `PlayerController` starts a context; add `playbackOrigin` field) `[I]`.
- Playlist ≠ queue: playlist rows keep their context-menu "Play / Shuffle" starting a *new* context and clearing overrides (confirm-on-clear not needed; queue clear is already undoable `[V]`).

**Acceptance:** A user can tell why track 4 is next ("I queued it") without opening a dialog.

### 6. Sidebar carries playlists inline, and accepts drag-to-add
**Source:** Feishin — left sidebar lists playlists; release notes "drag and dropping … directly to playlists on the sidebar" (github.com/jeffvli/feishin/releases, newinlinux.com Feishin update article showing "left-hand sidebar with playlists") `[V]`; MusicBee sidebar tabs for Music/Playlists etc. `[I]`; Dopamine organizes views by artists/genres/albums/songs/playlists (dopamine.en.uptodown.com/windows, github.com/digmezzo→digimezzo/dopamine) `[V]`.

Shuro's `_DesktopSidebar` is nav-only; playlists live two levels deep (Library tab → Playlists tab) `[V]`.

**Do this in Shuro:**
- Add a "PLAYLISTS" section under the existing rail items: server + local playlists (top ~8 alphabetically, "See all" → Library→Playlists). Collapsed mode shows a single playlist icon opening a flyout.
- Wrap sidebar playlist rows as drop targets: dropping a multi-selection (from #2) adds songs (reuse `add_to_playlist_sheet.dart` logic / `AppState` playlist mutation). Show a hover highlight ring on the target row while dragging (Feishin behavior) `[V]`.
- Keep the section scrollable and independent of nav selection; playlists are destinations, not tabs `[I]`.

**Acceptance:** Drag three songs from Search onto a sidebar playlist → toast confirms "Added 3 to Late Night".

### 7. Now-playing expands in place from the dock — kill the route push
**Source:** Feishin/jellywatch describes Feishin as "Spotify-inspired … most feature-complete" client (jellywatch.app/hub/feishin-imp) `[V]`; the Spotify/desktop convention: clicking the dock artwork expands the full now-playing view over the content area in place, click again to return `[I]`. Amberol/Cog stay single-window `[V]`.

Shuro already built the right artifact — `DesktopNowPlaying`, an embedded three-column pane that "replaces the content pane … so the sidebar and bar stay visible" (`desktop_now_playing.dart` doc comment) `[V]` — but the dock's artwork tap pushes the mobile `NowPlayingScreen` route instead `[V]` (`_PlayerDock` onTap → `Navigator.push`).

**Do this in Shuro:**
- In `desktop_shell.dart` `_PlayerDock`: artwork/tap toggles `DesktopNowPlaying` as the content pane (state flag beside `_lyricsOpen`, e.g. `_nowPlayingOpen`); back/Escape or clicking the dock again returns to the tab stack. Below ~900px width (DesktopNowPlaying's own two-column fallback threshold `[V]`), keep the existing route as fallback.
- Add a menu item + palette entry ("Now playing", Ctrl+J `[I]`) so it's keyboard/mouse reachable from the menu bar; update `desktop_menu_bar.dart` View menu and the shortcuts dialog.
- Preserve `IndexedStack` tab state — the pane swaps like the lyrics inspector does, so nothing rebuilds `[V]` (same mechanism as `_LyricsInspector`).

**Acceptance:** Clicking dock artwork swaps the content pane to `DesktopNowPlaying` with sidebar + dock intact; no route animation, no lost scroll position on return.

### 8. Keyboard-first list navigation, not just transport keys
**Source:** Space = play/pause when a list is focused is the norm (quodlibet github.com/quodlibet/quodlibet/issues/1288; Apple Music support.apple.com guide) `[V]`; foobar2000 ships fully remappable shortcuts, recently extended to work inside the filter toolbar (yuo.be Columns UI 3.5.0, 2026-06-01) `[V]`; Shuro already guards Space/Ctrl+arrows from text fields (`_letTextFieldKeepKeys`) `[V]`.

Shuro has transport + navigation keys but no list keys: arrows don't move selection, Enter doesn't play, Del doesn't dequeue `[V]` (no evidence in code of list keyboard handling).

**Do this in Shuro:**
- `DesktopSongTable` (#1) owns a focus node: ↑/↓ move the selection cursor (scrolling as needed), Enter plays the selected row (replacing queue, matching every surveyed client `[I]`), Shift+↑/↓ extends selection, the context-menu key (and Shift+F10) opens the row's `ContextMenuRegion` menu at the row.
- Queue pane (#3): Del removes selected rows (undoable — reuse the undo stack).
- Ctrl+F from anywhere focuses the visible list's filter/scrolls to top of current tab's filter field if one exists `[I]`.
- Document all of it: update `desktop_menu_bar.dart` `_showShortcuts` and the Playback/View hint strings so the dialog is the single source of truth; the palette (#9) shows hints too (mechanism already exists — `CommandPaletteEntry.hint`) `[V]`.

**Acceptance:** A user can find a song (Ctrl+K), walk results with ↑/↓, play with Enter, queue with a context-menu key press — mouse never touched.

### 9. Command palette: fuzzy matching, recent-first, and the full command surface
**Source:** Palette conventions (VS Code Ctrl+Shift+P model) are the desktop norm users transfer `[I]`; foobar2000's filter-as-you-type toolbar shows query-driven narrowing in dense libraries `[V]` (yuo.be); Feishin's desktop recommendation + hotkey culture (github.com/jeffvli/feishin) `[V]`.

Shuro's palette does substring `contains` on label/section only, no ranking, no recents, and its command list is small (go-to ×5, 5 playback, 3 view, undo) `[V]`.

**Do this in Shuro:**
- Ranking in `command_palette.dart` `_filtered`: exact-prefix > word-start > subsequence (fuzzy) match, with matched-character highlighting; empty query shows recents (persist last ~5 run commands in `app_persistence.dart`) then all `[I]`.
- Grow the command list in `desktop_shell.dart` `_openCommandPalette` — every entry must keep wrapping an existing action (the file's own rule `[V]`): Now playing toggle (#7), queue pane toggle (#3), Play random (Pulse has the machinery), Go to Playlists/Downloads/Shelves/Spoken, Sleep timer, Equalizer, "Add current song to playlist…".
- Search-as-launcher: a ">" prefix mode or dedicated section that runs library search and jumps to `search_screen.dart` with the query — desktop users expect the palette to find *content*, not only commands `[I]`.

**Acceptance:** "pl r" ranks "Play random" first; previously-run commands top the list on open.

### 10. Platform-adaptive chrome: menu bar on Windows, hamburger on GNOME
**Source:** GNOME removed menu bars from app design — "Menu bars always show all options… occupies space" (discourse.gnome.org/t/why-gnome-3-user-interface-has-no-menus/27181) `[V]`; Windows 11 design: auto-rounded top-level windows, Mica, 4px spacing rhythm (learn.microsoft.com/en-us/windows/apps/design/signature-experiences/geometry; microsoft.design/articles/windows-11-design-principles-tenets) `[V]`; Flutter's `PlatformMenuBar` is macOS-only, so an in-app bar is the correct approach on Windows/Linux (nurobyte.medium.com Flutter-desktop article; docs.flutter.dev/platform-integration/desktop) `[V]`.

Shuro's 30px Flutter-drawn `DesktopMenuBar` is right for Windows (where menu bars are native) but reads as alien on GNOME, where apps use a header bar + app menu `[I]`.

**Do this in Shuro:**
- Detect desktop environment once in `desktop_lifecycle.dart` (e.g. `XDG_CURRENT_DESKTOP` via platform channel; Windows → "windows"). In `desktop_shell.dart`: Windows/KDE (and fallback) → render `DesktopMenuBar` as today; GNOME → hide the bar and expose the same three menus from a hamburger (⋮) at the right end of `_DesktopHeader`, which becomes the de-facto headerbar. No menu items are cut — only relocated `[I]`.
- Keep the existing shortcuts dialog; GNOME users lose nothing because all menu actions have palette/shortcut paths (#8, #9).
- Windows fit-and-finish: the OS rounds top-level windows automatically `[V]` — verify the 30px bar's color meets the title bar (it does: both `kCardColor`) and keep inner radii ≤8px on panes to echo the Win11 geometry rhythm `[I]`.

**Acceptance:** On Ubuntu GNOME there is no 30px menu strip; the same Playback/View/Help actions open from the header. On Windows 11 nothing changes.

---

## Complaints to design against (what users hate about Subsonic desktop clients)

1. **Gapless playback is the #1 pain.** Navidrome issue #745 ("perfect gapless playback likely isn't possible" via some stacks), #6309 (gapless broke, Oct 2026), r/navidrome "Gapless client for navidrome?" — all `[V]`. Community answer: true gapless comes from the player backend, e.g. MPV in Feishin (github navidrome discussion #2375) `[V]`; Cog markets itself as "gapless and bit-perfect" (apps.apple.com Cog) `[V]`; new Linux clients lead with "gapless, opt-in bit-perfect" (navidrome.org/apps) `[V]`. → Shuro: treat gapless as a headline playback feature, not UX polish; document `playback_engine.dart` behavior honestly in the UI.
2. **Electron weight.** Feishin praised for UX but called "too heavy on resources" (r/navidrome 1uy0u2u) `[V]`. → Shuro's Flutter shell is already the counter-position; keep the desktop shell light (the 3,400-line `desktop_now_playing.dart` builds fine, but lazy-build panes).
3. **Playback-stopping bugs & server-compat churn:** Feishin #655 (playback stops), #1923 (transcoding extension broke playback), #2234 (jukebox mode bugged/unmaintained) — all `[V]`. → Shuro: surface stream/transcode errors in the dock (`stream_probe.dart` already exists) instead of silently stopping.
4. **Clients get abandoned:** Sonixd is dead (last release 2024; it's now just Feishin's predecessor — github.com/jeffvli/sonixd) `[V]`. → keep data portable: server-side playlists/ratings first (Substreamer's 5-star sync via server is its most-praised feature, substreamer.org) `[V]`.
5. **Discoverability of power features:** r/navidrome thread "Smart Playlist Editor Not Found in Feishin" `[V]`. → Shuro: put smart playlists in the sidebar + palette, not only inside Settings/Pulse.

**Empty-result finding:** "Substreamer desktop" does not exist as a shipped product — it is iOS/Android only; the desktop question is an open reddit thread asking to compile it (r/substreamer vz3cl2) `[V]`. Cog is macOS/iOS `[V]`. Neither offers a Windows/Linux layout to copy.

---

## Out of scope / suggestions only
- Room/artist "party mode" (Lollypop `[V]`) — nice Pulse-adjacent idea, not a desktop convention.
- Fully user-composable panel layouts (foobar2000 Columns UI, MusicBee "Configure Layout" `[V]`) — deliberately not recommended; the maintenance cost contradicts Shuro's "one implementation per action" discipline `[V]`.
- Bit-perfect output toggle — playback-domain, flagged for the engine backlog.

## Source index (primary)
Feishin github.com/jeffvli/feishin · releases + newreleases.io v1.0.1 · delightlylinux.com 2026-08-24 · newinlinux.com · jellywatch.app/hub/feishin-imp · issues 655/1144/1923/2234, discussion 2360 · Sonixd github.com/jeffvli/sonixd · Supersonic github.com/dweymouth/supersonic + Flathub · Psysonic psysonic.de + github.com/Psychotoxical/psysonic · NaviBeat navibeat.app/linux · navidrome.org/apps + issues 745/6309 + discussion 2375 · MusicBee getmusicbee.com forum topics 25074/29024/40816/42382 + r/musicbee 17k4tq8 · foobar2000 foobar2000.org/components/view/foo_ui_columns + yuo.be (Columns UI 3.5.0) + superuser 611587 + r/foobar2000 1nk0gll, v9kqni · Dopamine github.com/digmezzo/dopamine + dopamine.en.uptodown.com/windows · Lollypop man.archlinux.org + wiki.gnome.org + wildskyf.github.io/lollypop-web · Elisa apps.kde.org/elisa · Amberol apps.gnome.org · Cog cog.losno.co + apps.apple.com · GNOME discourse.gnome.org/t/27181 · Microsoft learn.microsoft.com geometry + microsoft.design · Flutter docs.flutter.dev/platform-integration/desktop + nurobyte.medium.com · quodlibet github issue 1288 · Substreamer substreamer.org + r/substreamer vz3cl2

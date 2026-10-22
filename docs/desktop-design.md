# Desktop UI/UX Design — Shuro on Windows & Linux

Maps desktop media player conventions (Spotify, Rhythmbox, Lollypop,
MusicBee) to Shuro's existing brand and feature set. Every change is
**additive** — the phone UI is untouched.

---

## Core principle

Desktop users expect **everything visible simultaneously**. No page
scrolling for primary content, no full-screen takeovers, no pull-to-refresh.
Information density is higher. Controls are smaller but hover/discoverable.
Keyboard is first-class.

---

## 1. Shell layout

```
┌──────────┬─────────────────────────────────┬──────────┐
│ sidebar  │  content pane                    │ lyrics / │
│ (nav)    │  (library, search, discover…)    │ queue    │
│          │                                  │ panel    │
├──────────┴─────────────────────────────────┤          │
│  now-playing bar (persistent)              │          │
└────────────────────────────────────────────┴──────────┘
```

- **Sidebar**: collapsible (icons ↔ icons+labels). Sections: Home, Search,
  Discover, Library, Favorites, Downloads, Settings. Books & Podcasts
  toggle when ABS is connected.
- **Now-playing bar**: 76 dp. Artwork 48 → title/artist → seek bar with
  times → transport → volume → lyrics/queue toggles → favourite.
- **Lyrics side panel**: 340 dp, opens from the bar, shows the karaoke view
  next to content. On ≥1240 dp wide windows it's a persistent third pane.
- **Content pane**: whatever tab is active, filling the remaining space.

## 2. Now Playing (desktop)

Not a pushed route. A **toggleable center pane** that replaces the content
pane when opened (chevron on the bar, or double-click the artwork).

Three-column inside the pane:
- **Left**: large artwork (320 dp max), album/year below
- **Centre**: track title, artist, transport controls, seek bar with times,
  shuffle/repeat, volume
- **Right**: lyrics (karaoke, scroll-follow, reading mode)

On <1200 dp windows: two-column (artwork+controls left, lyrics right).
On <800 dp: falls back to the phone portrait layout (embedded in the shell,
not pushed as a route).

## 3. Sheets → Dialogs

On desktop, `showModalBottomSheet` becomes `showDialog` with a centred
dialog (max width 480 dp). Same content, different presentation:
- Song actions ⋮ → context menu at cursor position
- Quality selector → dropdown or radio dialog
- Sleep timer → dialog with presets + custom time
- Equalizer → dialog with band sliders (already done)
- Volume → inline in the now-playing bar (already done)

Implementation: check `isDesktop` at the call site and branch to
`showDialog` vs `showModalBottomSheet`.

## 4. Interaction changes

| Mobile | Desktop |
|---|---|
| Pull-to-refresh | Refresh button in the app bar |
| Swipe-to-skip | Transport buttons / keyboard |
| Bottom sheets | Dialogs / side panels |
| Long-press for actions | Right-click context menu |
| Swipe-up for lyrics | Lyrics side panel toggle |
| Tap ring to seek | Click ring to seek, drag to scrub |
| Full-screen immersive | Normal window with title bar |

## 5. Typography and density

- Body text: 13–14 dp (vs 16 dp on mobile)
- List rows: 40–48 dp tall (vs 56–72 dp on mobile)
- Section headers: 11 dp uppercase (unchanged)
- Lyrics: 18 dp desktop (vs 21 dp mobile), left-aligned
- Padding: 12–16 dp page margins (vs 20–24 dp mobile)
- Cards: 8 dp radius (vs 12 dp mobile), tighter gaps

## 6. Settings reorganisation (desktop)

Group by concern, not by mobile screen flow:
- **Playback**: quality tiers, crossfade, ReplayGain, speed, skip silence,
  equalizer
- **Library**: servers, sync, Wi-Fi-only, download location
- **Appearance**: fonts, artwork styles, backdrop, lyrics
- **System**: performance profile, startup, keyboard shortcuts reference
- **About**: version, device info, report, licences

Mobile-only settings (immersive screens, haptics) hidden on desktop.

## 7. Keyboard shortcuts

| Key | Action |
|---|---|
| Space | Play / pause |
| Ctrl+← / Ctrl+→ | Previous / next track |
| Ctrl+Shift+← / → | Seek −10 s / +10 s |
| Ctrl+1–5 | Switch tabs |
| Ctrl+L | Toggle lyrics panel |
| Ctrl+Q | Toggle queue panel |
| Ctrl+F | Focus search |
| Ctrl+, | Open settings |
| Ctrl+, then E | Equalizer |

## 8. Right-click context menus

Tracks, albums, artists and playlists get a `ContextMenuRegion` wrapper
that shows a desktop-style menu at the cursor position:
Play · Play next · Add to queue · Favourite · Download · Build from this ·
Go to album · Go to artist · Share.

Implementation: `showMenu(position: RelativeRect.fromLTRB(...))` at the
tap position, with the same items as the mobile ⋮ sheet.

## 9. Window management

- Default size: 1280×800
- Minimum size: 480×360 (below this the phone layout is used)
- Title: "Shuro" (or "Shuro — {track}" when playing)
- Remember size/position between launches (via `window_manager` package)

## 10. Implementation order

1. **Desktop NPV three-pane** — highest impact
2. **Context menus** (right-click) — desktop convention
3. **Sheet→dialog branching** — all call sites check `isDesktop`
4. **Refresh buttons** replace pull-to-refresh on desktop
5. **Settings grouping** — desktop category reorganisation
6. **Window manager integration** — remember size/position
7. **Lyrics left-align on desktop** — reading convention

# Desktop UX changelog — sortable table, shuffle/repeat states, header quick menu

Date: 2026-10-23. Implements three items from `docs/desktop-ux-research.md`
(conventions #1 desktop track table — scoped to the Library Songs tab as
requested, plus dock shuffle/repeat visibility and a top-right quick menu).
All changes are pure Dart, no platform channels. Nothing was committed; all
changes are in the working tree for review.

## 1. Sortable track table on the Library → Songs tab

**Files**

- `lib/widgets/desktop_song_table.dart` — **new file**.
  - `isNativeDesktop` getter: `!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)` — the same gate `home_screen.dart` uses for its desktop affordances.
  - `DesktopSongTable` (StatefulWidget): header row with sort buttons **Title / Artist / Album / Duration** plus a `#` index column and right-aligned Duration. Tapping a header sorts by that column; tapping the active header toggles ascending/descending; the active column gets a small up/down arrow in brand color and bold brand label. First tap of a new column starts ascending.
  - Denser desktop rows (44 px) instead of `SongTile`: `#`, Title (bold, brand-colored on the playing track), Artist, Album, Duration `m:ss`. Row tap plays the song with the *currently sorted* list as the queue (same `playSong(song, queue:)` contract the mobile list uses). Right-click opens the same `songContextMenuItems` menu `SongTile` already wraps itself in (`ContextMenuRegion`).
  - Column layout uses flex (Title 4 / Artist 3 / Album 3) with fixed 44 px index and 68 px duration columns, shared between header and rows, so cells stay aligned and nothing overflows on narrow windows.
- `lib/screens/library/library_screen.dart` — `_SongsTab` only.
  - Desktop builds (`isNativeDesktop`) render `DesktopSongTable` inside the existing `RefreshIndicator` instead of the `SongTile` `ListView`.
  - Album titles are resolved once per build from a `{album.id: album.title}` map over `AppState.catalogAlbums`; songs whose `albumId` has no server album (e.g. local imports) show `—`.
  - The mobile sort `PopupMenuButton` is hidden on desktop (the column headers are the sort UI there — two sort controls would fight). Mobile keeps it and the whole `SongTile` list **byte-for-byte unchanged**; `Play all` / `Shuffle` / song count and the empty/skeleton states are shared and untouched.

## 2. Shuffle + repeat visibility in the player dock

**File:** `lib/widgets/desktop_shell.dart` (`_Transport`, new `_DockToggleButton`).

- Shuffle and repeat are now `_DockToggleButton`s: exact **40×40 hit targets** (`SizedBox` + `Material`/`InkWell`, stadium-shaped hover/press), always-visible icons, no layout order change (still shuffle → prev → play → next → repeat, still hidden under the existing `< 980 px` compact mode).
- **Active state is unmistakable:** brand-colored icon over a soft brand wash (`kBrandColor` @ 16%) plus a 14×3 px brand underline bar beneath the icon. Inactive keeps a neutral `Colors.white60` icon with the underline slot transparent, so the icon never shifts position between states.
- Repeat additionally swaps to `Icons.repeat_one_rounded` when the mode is `one`, and tooltips state the mode (`Shuffle: on/off`, `Repeat: off/all/one`).
- Callbacks unchanged: `player.toggleShuffle` / `player.cycleRepeatMode`.

## 3. Top-right quick menu in the desktop header

**File:** `lib/widgets/desktop_shell.dart` (`_DesktopHeader`, call site in `_DesktopShellState`).

- After the existing lyrics toggle button there is a new compact `Icons.read_more_rounded` `PopupMenuButton` (tooltip "Quick actions") opening a small menu:
  - **Show/Hide lyrics panel — Ctrl+L** → the same `_toggleLyrics` callback the header lyrics button and Ctrl+L use (label reflects open state; on windows narrower than 1480 px the same callback still pushes the full lyrics screen).
  - **Command palette — Ctrl+Shift+P** → `_openCommandPalette`, the same callback the menu bar and the shortcut use.
  - **Collapse/Expand sidebar** (divider before it) → new `_toggleSidebar()` extracted in `_DesktopShellState`; the sidebar's own collapse button and the palette's "Collapse sidebar" entry now call the same method, so there is exactly one implementation of the toggle.
- The existing header buttons (search pill, lyrics toggle) are kept exactly as they were.

## Mobile / web safety

- Every new behaviour is behind `isNativeDesktop` (new table) or lives in desktop-only widgets (`DesktopShell`, `_DesktopHeader`, `_PlayerDock` are only built by the desktop shell path in `app.dart`). No mobile widget, layout, or callback was modified; the `_SongsTab` mobile branch is unchanged.

## Verification status (honest report)

- `flutter analyze --no-pub` was **not run**: this agent environment has no shell/exec tool, so the command (and any git operations) could not be executed here. Run before committing:
  ```powershell
  ${env:PROGRAMFILES(X86)}='C:\Program Files (x86)'; $env:LOCALAPPDATA=$env:LOCALAPPDATA; $env:PUB_CACHE="$env:LOCALAPPDATA\Pub\Cache"; flutter analyze --no-pub
  ```
- Compensating checks performed by reading the code: imports all referenced (`dart:io`, `kIsWeb`, `provider` watch, context-menu helpers), all called APIs verified against the repo (`playSong(song, {queue})`, `toggleShuffle`, `cycleRepeatMode`, `repeatMode`/`PlayerRepeatMode`, `songContextMenuItems`, `catalogAlbums`), no changes to any other call site of the touched widgets (`_DesktopHeader` and `_Transport` are private to the file).
- Commits: none, as instructed (author env vars for AsHfIEXE would be set at commit time by whoever commits).

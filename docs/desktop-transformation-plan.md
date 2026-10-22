# Shuro Desktop Transformation Plan

**Scope:** Windows and Linux first; macOS later. Preserve Shuro's product identity and application core. Do not turn the desktop edition into a reskinned Android app.

**Repository reviewed:** `AsHfIEXE/Shuro`, current `main` tree inspected on 22 October 2026.

## 1. Product direction

Shuro Desktop is a desktop music workspace for people who own their library or run a Navidrome/OpenSubsonic-compatible server. It should feel like a deliberate Windows/Linux application with a persistent workspace, dense-but-readable media browsing, keyboard-first operation, right-click actions, and native window behaviour.

Keep the Shuro signature:

- Self-hosted Navidrome / Subsonic / OpenSubsonic library integration.
- Local music files as a first-class source.
- Original-quality streaming unless the user explicitly sets a quality cap; never silently claim bit-perfect output.
- Shuro Pulse recommendations, smart playlists, and music discovery calculated locally.
- Immersive artwork, lyrics, favorites, downloads, offline playback, sleep timer, and playback history.
- Dark, cinematic, artwork-aware visual identity; privacy-first behaviour and no telemetry.

Change the *presentation and interaction model*, not the core product. Desktop users should see more useful information at once and should not have to operate phone-shaped screens with a mouse.

## 2. Current diagnosis from the repository

The code already contains valuable desktop foundations: `lib/widgets/desktop_shell.dart`, `lib/widgets/desktop_now_playing.dart`, `lib/widgets/desktop_context_menu.dart`, and `lib/services/desktop_lifecycle.dart`. Windows/Linux playback is configured through `just_audio_media_kit` and libmpv. The desktop build jobs exist in `.github/workflows/ci.yml` and the release workflow.

The problem is incomplete separation between desktop presentation and mobile presentation:

1. **The desktop shell still hosts mobile screens.** `lib/app.dart` selects `DesktopShell`, but sends it the existing tab children. `DesktopShell` renders them inside an `IndexedStack`. This means the shell may look desktop-like while each page still uses its Android layout, spacing, refresh gestures, navigation, and action surfaces.
2. **Mobile interaction patterns remain on desktop.** `HomeScreen` wraps content in `RefreshIndicator`; library lists and grids also use it. `showSongActionsSheet` and several settings flows still use `showModalBottomSheet`. These patterns should be replaced with desktop-specific actions, menus, dialogs, toolbar controls, and explicit refresh commands.
3. **Desktop-specific files are not enough if they are not the active route.** `desktop_now_playing.dart` contains a dedicated desktop player implementation, but the current `DesktopShell` source does not import it and pushes `NowPlayingScreen` instead. Verify this and either wire the desktop view in deliberately or remove it if it is obsolete. Do not leave parallel implementations that agents cannot tell apart.
4. **Context-menu infrastructure must be connected to real surfaces.** `desktop_context_menu.dart` exists, but the main desktop shell and shared action entry points need a clear path that selects a right-click menu on desktop and a bottom sheet on mobile.
5. **Settings remain mobile-shaped.** `SettingsScreen` is a long scrolling page with numerous bottom-sheet call sites. Desktop needs persistent categories/navigation and a stable content panel; control editors should use bounded dialogs or popovers.
6. **Platform capabilities are not the same as UI preferences.** The current equalizer is explicitly Android system DSP. Do not expose its sliders on Windows/Linux unless a genuine desktop DSP implementation is connected to the libmpv/media_kit processing path.
7. **Docs/specs can drift from implementation.** `docs/desktop-design.md` is an aspirational design note, but its shortcuts and interaction requirements should be reconciled with the actual shell before agents use it as the source of truth. Use one maintained desktop specification.

The right response is **not** a rewrite of the backend and not a broad “make all screens responsive” pass. It is a deliberate desktop presentation layer over the existing application core.

## 3. Target architecture

Keep the existing models, server APIs, repository abstractions, recommendation service, playback controller, persistence, lyrics parsing, download logic, and privacy boundaries as shared core wherever possible.

Split responsibilities conceptually into three layers:

```text
Shared application core
  models / backend / repositories / PlayerController / AppState
  Shuro Pulse / lyrics / downloads / persistence / source policy
                         |
                  presentation state
      shared commands, selections, table/grid state, dialogs
                         |
          +--------------+---------------+
          |                              |
     Mobile UI                      Desktop UI
     Android now                    Windows / Linux now
     mobile navigation              desktop workspace/navigation
     sheets / touch                 menus / shortcuts / dialogs
     phone density                  desktop density / multi-pane
```

Recommended code organization over time:

```text
lib/
  core/                         # Only if a gradual refactor warrants it
  presentation/
    mobile/                      # Existing mobile screens, migrated gradually
    desktop/
      shell/
      home/
      library/
      search/
      discover/
      now_playing/
      queue/
      settings/
      widgets/
  widgets/shared/                # Reusable content/data primitives, not mobile sheets
```

Do not move every existing file on day one. Add desktop page implementations beside the existing screens and route to them from `DesktopShell`. Extract shared business actions into small services/commands only when that prevents duplicated logic. Mobile can continue using its existing screens.

Introduce a presentation selector or route factory such as `DesktopPageFactory` that creates the desktop equivalent for each primary destination. It should not depend on arbitrary width checks scattered across each mobile page. Width breakpoints should adapt *desktop layouts to desktop window sizes*, not switch the desktop app back into Android navigation.

## 4. Desktop design system

### Workspace anatomy

For a normal desktop window, make the main application workspace persistent:

- **Left navigation:** 220–248 logical pixels wide with Shuro mark, Home, Search, Discover, Library, Favorites, Downloads, and Settings. Support collapse to roughly 64–72 px. Keep destinations stable rather than hiding common destinations in overflow.
- **Top command bar:** about 52–60 px tall. Include the current destination or breadcrumbs, global search, refresh/sync status when relevant, view switch (list/grid), sort/filter controls, and the page's primary action. Do not repeat mobile's oversized greeting/header on every screen.
- **Main content pane:** uses remaining space; controlled density and page-specific layout. Avoid wrapping the whole page in another mobile `Scaffold` when a desktop page can provide just its content body.
- **Inspector pane:** about 300–360 px, resizable/collapsible on wider windows. Tabs or switches for Up Next, lyrics, and track details. At narrower widths the inspector closes or becomes an explicit panel; it must not push the main content into unusable widths.
- **Persistent player dock:** approximately 80–92 px tall. Artwork/title/artist on the left; transport in the center; seek position and duration; volume/output, favorite, lyrics, queue, and more-actions on the right. No oversized phone touch targets or unnecessary vertical stack.

Start with a default window around 1280–1440 × 800–900 and a practical minimum around 900 × 600. When the window gets smaller, collapse the sidebar and hide the inspector before falling back to a phone UI. Keep a native title bar initially. Do not implement a custom frameless title bar until ordinary window sizing, dragging, snapping, maximize/restore, and accessibility are solid.

### Visual personality

Keep Shuro's dark palette, distinctive accent, album-art colour extraction, and cinematic artwork atmosphere. Apply those ideas with desktop restraint:

- Use artwork colour for small highlights, focus/selection, progress, and subtle backdrop accents—not as a full-screen animated background on every page.
- Reserve immersive blurred artwork for the dedicated Now Playing workspace, not all library screens.
- Prefer crisp dividers, compact but breathable rows, restrained corner radii, and consistent icon sizing.
- Use hover, focus, selected, disabled, and pressed states. Tooltips should explain icon-only controls.
- Support keyboard navigation, visible focus outlines, text scaling, screen readers, and reduced motion.
- Respect OS conventions: Ctrl on Windows/Linux; architect shortcuts so macOS can use Command later.

## 5. Desktop experience by area

### Home

Replace the mobile greeting-and-vertical-feed composition with a desktop dashboard that makes use of width:

- Continue listening / recently played.
- Recently added albums or tracks.
- Shuro Pulse recommendations in horizontally browsable, appropriately sized shelves.
- Explicit “Refresh library” / “Refresh server” action with loading and last-updated status.
- Local-library and connected-server empty states with clear primary actions.

Avoid pull-to-refresh. Do not make the only route to import a folder a large mobile-style button at the centre of an otherwise empty screen.

### Library

Provide a real desktop media browser:

- Songs in a sortable table/list with columns such as Title, Artist, Album, Duration, and optionally Format/Source. Column visibility and sort order can be persisted later.
- Albums/artists in a grid with bounded card dimensions; use the available width by adding columns, not enlarging cards without limit.
- Visible filter/search, sort, list/grid mode, refresh/rescan, and import commands.
- Multi-selection with Shift/Ctrl, keyboard focus, Enter to play/open, Delete with confirmation where applicable, and drag-and-drop queue support if implemented correctly.
- Right-click on tracks/albums/artists/playlists: Play, Play next, Add to queue, Favorite, Download, Add to playlist, Build from this, Go to album/artist, and relevant properties.
- Support dropping files/folders onto the library, if a reliable cross-platform drop target is implemented. Always show progress, cancellation, and import errors.

Do not build desktop tables by merely shrinking mobile `SongTile`s. Reuse track data and action commands, not necessarily the mobile row widget.

### Search

Treat Search as a first-class desktop destination with a predictable keyboard shortcut, focus-on-open, recent searches, grouped results, clear query, arrow-key movement, Enter to open/play, and context menus. Reuse the existing search/repository logic.

### Discover / Shuro Pulse

Preserve recommendation ranking and feedback logic. Use a desktop shelf/card grid with predictable dimensions, more results visible per viewport, explicit play/queue actions, and the same More like / Less like / Not interested feedback. No redesign should move recommendation computation to a remote service.

### Now Playing

Use a desktop composition, not just the mobile screen's “wide layout”:

- Artwork (roughly 280–400 px depending on window), track/album metadata, transport and timeline.
- A lyrics pane that is visible alongside controls at appropriate window sizes, with synced highlighting, click-to-seek, reading mode, and sync adjustment.
- Queue/lyrics/track-info should be panes or inspector tabs and not force a route push for every small task.
- Maintain the existing honest Audio Info language: source file metadata, server-requested quality, stream response, effects, and platform-reported output capability must remain distinct. Never promise bit-perfect output without verifiable evidence.
- Keep the immersive artwork animation optional and restrained; reduced motion must remain effective.

Inspect `desktop_now_playing.dart` and decide if it is the intended implementation. Either integrate and test it from the shell or retire it. Do not ask an agent to improve `NowPlayingScreen` for desktop while a second desktop player implementation sits unused.

### Queue and lyrics

Use the right inspector pane for Up Next and lyrics where width permits. Allow reordering with mouse and keyboard, per-row actions, remove, clear with confirmation, save as playlist, and clear visual separation between the current item and queued tracks. Lyrics should be selectable/readable at desktop sizes; auto-follow must pause when the user scrolls up and provide a Resume-follow control.

### Settings

Replace the single mobile-length list with a persistent category navigation + content pane:

- General / Startup & Window
- Library & Sources
- Servers
- Playback & Quality
- Audio Processing (only features genuinely supported on that platform)
- Lyrics & Appearance
- Downloads & Offline
- Privacy & Diagnostics
- About / Licenses

Use grouped forms, labels, explanatory text, and standard controls. Use a centred bounded dialog for destructive confirmations or complex short forms; use dropdowns/popovers for simple selectors. Do not display phone bottom sheets on desktop. Avoid nested navigation where selecting a category could update the main settings panel in place.

### Context actions and dialogs

Create a single action-command layer for operations such as `play`, `playNext`, `addToQueue`, `toggleFavorite`, `download`, `addToPlaylist`, `buildFromThis`, `openAlbum`, and `openArtist`. Presentation decides how to expose the commands:

- Mobile: existing bottom sheet where appropriate.
- Desktop: right-click context menus and `...` menus anchored to the clicked row/button.
- Both: same command implementation and state/error feedback.

Keep platform detection out of the actual business commands. Don't fork the queue/favorite/download behaviour simply because a menu is different.

## 6. Cross-platform capabilities

Windows/Linux should share as much UI as possible but not assume identical native capabilities. Introduce an explicit capability provider rather than scattered OS checks for each button. It should report whether the current target supports capabilities such as:

- System tray and close-to-tray.
- Media keys / system media session.
- Audio output and DSP/equalizer backend.
- Native notifications.
- Window restore/start-on-login (only if actually implemented).
- File/folder selection and drag-drop.

Each UI control must be backed by a real implementation or shown as unavailable with a clear reason. For example, Android's `AndroidEqualizer` must not be presented as if it controls libmpv DSP on desktop. Add desktop EQ only after choosing and testing a supported media_kit/libmpv filter path and verifying persistence and reset behaviour.

Do not add a macOS runner as part of this Windows/Linux pass. Do keep shortcuts, window actions, path access, and native capabilities behind small interfaces so macOS can be implemented deliberately later.

## 7. Refactoring sequence

### Phase 0 — Freeze the architecture boundary

1. Create a desktop feature inventory: current implementation, shared core dependency, desktop gap, tests, and target files.
2. Make one document the canonical desktop UX specification; reconcile `docs/desktop-design.md` with actual shortcuts and code.
3. Add a desktop page/route factory in the shell and choose one desktop Now Playing implementation.
4. Record a “do not change” list: API contracts, models, OpenSubsonic clients, Shuro Pulse ranking, source-quality policy, privacy/telemetry policy, download/source resolution, and playback queue invariants.

**Exit criteria:** no feature ambiguity; every desktop page has an owner and an explicit target widget.

### Phase 1 — Foundation and navigation

1. Define desktop window sizing, native title bar behaviour, sidebar collapse, top command bar, player dock, and inspector layout.
2. Add shared command actions and keyboard command registry, with text-input focus protection.
3. Wire existing tray/close lifecycle; make Show and Quit reliably reachable. Never hide the only window if no tray host exists.
4. Establish desktop theme metrics (density, typography, hover/focus, spacing, panel widths).

**Exit criteria:** shell behaves as a desktop app before feature pages are migrated.

### Phase 2 — The high-frequency path

Migrate in this order:

1. **Library** — desktop list/grid, search/sort/refresh/import toolbar, multi-select groundwork, context menus.
2. **Player dock + Now Playing** — wire the dedicated desktop player; build pane-oriented lyrics/queue; no mobile route push for common panel toggles.
3. **Search** — keyboard-first, grouped results, context actions.
4. **Queue** — precise reordering, keyboard and mouse support, clear/save actions.

Do not redesign all 1,800 lines of settings while these core interactions still behave like a phone.

### Phase 3 — Complete workspaces

1. Desktop Home / Shuro Pulse dashboard.
2. Desktop Discover and Favorites.
3. Desktop Settings with category navigation and capability-aware audio controls.
4. Desktop server management, downloads, playlist editing, diagnostics and metadata details.

### Phase 4 — Polish / quality gate

1. Accessibility, shortcut conflicts, focus traversal, empty/error/loading states.
2. Performance check for large libraries and many album artworks.
3. Verify normal, compact, high-DPI, keyboard-only, no-tray Linux, offline, and disconnected-server cases.
4. Run analyzer/tests and build both Windows and Linux release bundles.
5. Capture real Windows and Linux screenshots; add them only after the actual app has been built and inspected.

Each phase should be its own small reviewable change. Do not bundle the entire migration into one agent run.

## 8. Agent operating rules

Give coding agents one bounded issue at a time. The agent must:

1. Inspect the relevant existing widgets, service contracts, and tests before editing.
2. Preserve shared business logic and mobile behaviour unless the task explicitly requests a core fix.
3. Build a desktop-specific presentation instead of adding one-off `if (isDesktop)` branches throughout a mobile screen.
4. Never fake support for an OS/audio feature. Update capability handling and the UI together.
5. Keep accessibility semantics, hover/focus states, keyboard use, and reduced-motion support in scope.
6. Add/adjust tests for the behaviour introduced, run `flutter analyze --no-pub`, `flutter test --no-pub`, and the relevant `flutter build windows --release` / `flutter build linux --release` when environment permits.
7. Report exact files changed, commands run, results, limitations, and any follow-up needed.
8. **Never commit, push, create a PR, or modify the README unless the user specifically asks.** Produce a diff or working-tree changes for review instead.

## 9. Acceptance criteria for a “proper desktop app”

Do not call a page desktop-ready merely because it fits a large window. It is ready only when:

- It uses desktop-appropriate information density and multi-column space.
- Primary actions are reachable by mouse, keyboard, and context menu where relevant.
- No pull-to-refresh is required; refresh/rescan has a visible command and state.
- No mobile bottom sheet appears in desktop flows; the equivalent is a menu, anchored popover, or bounded dialog.
- Primary navigation remains persistent and does not turn common tasks into mobile-like route stacks.
- Focus and selection states are visible; text fields keep their normal editing shortcuts.
- Relevant actions operate on the same shared core state as mobile; no duplicate queue/favorites/recommendation logic.
- Audio capabilities are real, platform-aware, and honestly labelled.
- The layout is visually checked at 900×600, 1280×800, and 1920×1080, including narrow/compact behaviour.
- Windows and Linux builds and automated tests pass, or a precise environmental blocker is recorded.

## 10. First implementation ticket

**Ticket: Establish a real desktop presentation boundary without changing app logic.**

Scope:

1. Add a desktop page factory / destination model used by `DesktopShell`.
2. Wire a desktop-specific Now Playing component (after verifying `desktop_now_playing.dart`; don't leave duplicate dead implementations).
3. Add a reusable `DesktopActionPresenter` that presents a context menu on Windows/Linux and leaves the existing mobile bottom-sheet path untouched.
4. Add a desktop-only refresh command pattern and apply it to one destination first (Library) as a reference implementation.
5. Add a small test that proves desktop route selection chooses desktop widgets and mobile route selection continues to use mobile widgets.

Out of scope: backend rewrite, queue algorithm changes, recommendation changes, server API changes, UI redesign of every page, macOS support, new audio DSP, README rewrite, commit/push.

**Definition of done:** the architectural seam is clear, the Library is the first real desktop page using it, Now Playing has one deliberate desktop implementation, and existing mobile screens still work unchanged.

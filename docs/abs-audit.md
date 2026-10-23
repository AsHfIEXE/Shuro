# Audiobookshelf integration audit — incomplete data fetch

- **Date:** 2026-10-23
- **Repo:** `C:\Users\user\Desktop\shuro\shuro`
- **Scope:** read-only audit of the Audiobookshelf (ABS) integration; no source files were edited.
- **Files read in full:** `lib/backend/audiobookshelf_api.dart`, `lib/models/spoken_media.dart`, `lib/state/spoken_library_state.dart`, `lib/screens/library/spoken_library_screen.dart`. Cross-checked every `Spoken*`/`Audiobookshelf*` reference under `lib/` (only other consumers: `lib/main.dart:22,159` provider wiring, `lib/widgets/desktop_shell.dart:70-71` navigation).
- **Symptom audited:** "not properly fetching all data".

## Evidence tiers

- **[V-Code]** Verified by reading the code (file:line below).
- **[V-Doc]** Verified against the official API reference `api.audiobookshelf.org` via search excerpts this run (the site itself was not directly fetchable; excerpts quoted below). The pagination contract (`?limit=&page=`, default page 0) was also given as an established fact in the task brief.
- **[I]** Inference — plausible, needs a quick server-side check before acting.
- **[U]** Unverified (blocked, see note on redaction).

## ABS API baseline used for comparison

| Endpoint | Contract |
|---|---|
| `GET /api/libraries` | Unpaginated; returns `{libraries: [{id, name, mediaType: "book"\|"podcast", …}]}`. |
| `GET /api/libraries/{id}/items?limit=&page=&sort=` | Paginated: `{results, total, page, numPages, numPerPage}`. Docs: "Limit the number of returned results per page. If 0, no limit will be…" — i.e. `page` is 0-based and `limit=0` returns everything. |
| `GET /api/libraries/{id}/podcasts` | Podcast-library endpoint (per task brief); returns podcasts with episode data. |
| `GET /api/me/items/progress` | Batch progress endpoint (per task brief); unused by this app. |
| `GET /api/items/{id}/cover` | Cover image; an image request carries no `Authorization` header when loaded by the image widget, so the token must travel as a query param. |
| Auth | `Authorization: Bearer <token>` on all `/api` routes. |

Book metadata per docs: `authors` — "The authors of the book" (array), `narrators` — "Array of String, The narrators of the book". Podcast metadata has `author` (string).

---

## BUG 1 — CRITICAL: pagination ignored; only the first page (≤100 items) per library is fetched

**This is the "not all data" bug.** `[V-Code]` + `[V-Doc]`

`lib/backend/audiobookshelf_api.dart:63-69`

```dart
Future<List<SpokenItem>> items(SpokenLibrary library) async {
  final data = await _get('/libraries/${library.id}/items',
      {'limit': '100', 'sort': 'media.metadata.title'});
  final rows = data['results'] as List<dynamic>? ?? const [];
  return rows
      .whereType<Map<String, dynamic>>()
      .map((row) => _item(row, library.type))
      .toList();
}
```

- No `page` query param is ever sent, so the server always returns page 0.
- The response envelope contains `total` / `numPages` / `page` — all ignored.
- Consequence: every library with more than 100 items is silently truncated to its first 100 titles (sorted by title, so the cut is deterministic and looks "normal" — items are simply missing from the middle/end of the alphabet). Nothing errors, which matches the owner's report exactly.

**Fix (robust — page loop):**

```dart
Future<List<SpokenItem>> items(SpokenLibrary library) async {
  final out = <SpokenItem>[];
  var page = 0;
  while (true) {
    final data = await _get('/libraries/${library.id}/items', {
      'limit': '100',
      'page': '$page',
      'sort': 'media.metadata.title',
    });
    final rows = data['results'] as List<dynamic>? ?? const [];
    out.addAll(rows
        .whereType<Map<String, dynamic>>()
        .map((row) => _item(row, library.type)));
    final numPages = (data['numPages'] as num?)?.toInt() ?? 0;
    if (rows.isEmpty || page >= numPages - 1) break;
    page++;
  }
  return out;
}
```

**Fix (minimal alternative):** the docs state `limit=0` disables the limit — `'limit': '0'` fetches everything in one request. Prefer the loop for very large libraries to avoid giant single responses/timeouts (see BUG 8).

---

## BUG 2 — HIGH: one failing library fails the *entire* refresh (all-or-nothing `Future.wait`)

`[V-Code]` `lib/state/spoken_library_state.dart:95-104`

```dart
libraries = next;
final entries = await Future.wait(next.map(
    (library) async => MapEntry(library.id, await api.items(library))));
itemsByLibrary
  ..clear()
  ..addEntries(entries);
} on AudiobookshelfApiException catch (e) {
  error = e.message;
} catch (_) {
  error = 'Audiobookshelf could not refresh right now.';
}
```

- `Future.wait` throws if **any** library's `items()` call fails (15s timeout, a 4xx/5xx on one library, a decode hiccup). The whole `entries` list is then discarded: `itemsByLibrary` keeps stale/empty content, and the user sees a generic error banner instead of the libraries that *did* load.
- With BUG 1 fixed, large libraries issue many sequential page requests — the probability that at least one request fails once (and therefore nukes the whole view) goes up sharply.
- Interaction with BUG 3: a podcast library that misbehaves on the generic items endpoint takes down the book libraries too.

**Fix (per-library isolation + aggregated error):**

```dart
final entries = <MapEntry<String, List<SpokenItem>>>[];
final failures = <String>[];
await Future.wait(next.map((library) async {
  try {
    entries.add(MapEntry(library.id, await api.items(library)));
  } on AudiobookshelfApiException catch (e) {
    failures.add('${library.name}: ${e.message}');
  } catch (_) {
    failures.add('${library.name}: request failed');
  }
}));
itemsByLibrary
  ..clear()
  ..addEntries(entries);
if (failures.isNotEmpty) {
  error = 'Some libraries did not load — ${failures.join('; ')}';
}
```

---

## BUG 3 — HIGH: podcast data path is second-class; episodes can silently be `[]`, `/api/libraries/{id}/podcasts` never used

`[V-Code]` for the code facts below; `[I]` for the server-behavior conclusion.

- `lib/backend/audiobookshelf_api.dart:78-97` parses episodes exclusively from `media['episodes']` embedded in the **generic** `/api/libraries/{id}/items` list response. If that field is absent for podcast items (server version/config, `minified` responses, or a shape change), the `?? const []` default silently yields **zero episodes** — no error, no log.
- The dedicated podcast endpoint `/api/libraries/{id}/podcasts` (per the task brief's API contract) is **never called** anywhere in the repo (grep-verified: the only `_get` calls are `/me`, `/libraries`, `/libraries/{id}/items`).
- `/api/items/{id}` (full single item, guaranteed to carry expanded media) is likewise never used as a per-show fallback.
- Downstream, `spoken_library_screen.dart:171` renders `'${item.episodes.length} episodes'`, so an affected podcast shows "0 episodes" — a concrete "not all data" symptom that is invisible in logs.

**Fix (route podcast libraries to the podcast endpoint, fall back per item):**

```dart
Future<List<SpokenItem>> items(SpokenLibrary library) async {
  if (library.type == SpokenMediaType.podcast) {
    final data = await _get('/libraries/${library.id}/podcasts',
        {'sort': 'media.metadata.title'});
    final rows = data['podcasts'] as List<dynamic>? ??
        data['results'] as List<dynamic>? ??
        const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => _item(row, library.type))
        .toList();
  }
  // …existing paged book path from BUG 1…
}
```

(Note: confirm the exact response key — `podcasts` vs `results` — with one `curl` against your server; see "Verification commands" at the end. Also add a debug log when a podcast item parses with `episodes.isEmpty` so this failure mode can never be silent again.)

---

## BUG 4 — MEDIUM: failures masked into generic strings; "empty" and "failed" look identical in the UI

`[V-Code]`

- `lib/backend/audiobookshelf_api.dart:37-38` correctly raises `Audiobookshelf returned <status>.` for a 404/500, but:
  - `lib/state/spoken_library_state.dart:103-104` replaces **non-ABS** exceptions (timeout, socket, `jsonDecode` `FormatException` from `audiobookshelf_api.dart:40` which is thrown *outside* the status checks) with `'Audiobookshelf could not refresh right now.'` — status/path context lost.
  - `lib/state/spoken_library_state.dart:44-45` (`restore()`) collapses every failure — including a `FormatException` from corrupt persisted JSON at lines 40-41 — into "Saved Audiobookshelf connection could not be restored."
  - `lib/state/spoken_library_state.dart:38-39`: if the stored token is missing, `restore()` returns **silently** — the user who previously connected just sees the connect screen again with no explanation.
- `lib/screens/library/spoken_library_screen.dart:153` shows `'No items found in this library.'` for **both** genuinely empty libraries and libraries whose fetch died (with BUG 2, all of them). A 404 on one library is therefore indistinguishable from an empty library.

**Fix (state):** keep the thrown message and library context (see BUG 2 snippet); distinguish the two catch blocks:

```dart
} on AudiobookshelfApiException catch (e) {
  error = e.message;                       // e.g. "Audiobookshelf returned 404."
} on TimeoutException {
  error = 'Audiobookshelf timed out. Try again.';   // needs import 'dart:async'
} catch (e) {
  error = 'Audiobookshelf refresh failed ($e).';
}
```

**Fix (screen):** render per-library error state, e.g. pass a failure flag into `_LibrarySection` and show `'Could not load this library.'` instead of `'No items found…'` when the library's fetch failed.

---

## BUG 5 — MEDIUM: metadata field mismatches (author/narrator, cover URL)

`[V-Code]` for the code, `[V-Doc]` for the documented field shapes.

`lib/backend/audiobookshelf_api.dart:101-104`

```dart
creator: type == SpokenMediaType.book
    ? ((metadata['authorName'] ?? metadata['narratorName']) as String? ??
        'Unknown creator')
    : (metadata['author'] as String? ?? 'Podcast'),
```

- `metadata['narratorName']` is **not a documented ABS field** — docs define `narrators` as an *Array of String*. The narrator fallback is dead code; it can never fire.
- `authorName` is a convenience scalar that may be absent; the documented shape is `authors` — an array of `{id, name}` ("The authors of the book"). When `authorName` is missing but `authors` is present, every book falls back to `'Unknown creator'` → looks like missing data.
- Podcast branch (`metadata['author']`) matches the documented podcast metadata field — OK.

**Fix:**

```dart
String _bookCreator(Map<String, dynamic> metadata) {
  final authors = (metadata['authors'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((a) => a['name'] as String?)
      .whereType<String>()
      .toList();
  if (authors.isNotEmpty) return authors.join(', ');
  final narrators =
      (metadata['narrators'] as List<dynamic>? ?? const []).join(', ');
  if (narrators.isNotEmpty) return narrators;
  return metadata['authorName'] as String? ?? 'Unknown creator';
}
```

`lib/backend/audiobookshelf_api.dart:107`

```dart
coverUrl: _uri('/items/${row['id']}/cover').toString(),
```

- The URL itself is the correct path (`/api/items/{id}/cover`), but it carries **no token**. Image widgets send no `Authorization` header, so any future `Image.network(coverUrl)` will get a 401/redirect-to-login and render broken covers. `[I]` on the exact param the current server accepts — the conventional ABS client pattern is `?token=`.
- Today the screen never uses `coverUrl` (`spoken_library_screen.dart:163-168` draws icons), so this is a latent bug, not today's symptom.

**Fix:**

```dart
coverUrl: _uri('/items/${row['id']}/cover', {'token': token}).toString(),
```

---

## BUG 6 — LOW: `connect()` can crash on a malformed URL (null-assert)

`[V-Code]` `lib/state/spoken_library_state.dart:53`

```dart
if (!Uri.tryParse(trimmed)!.hasScheme || token.trim().isEmpty) {
```

`Uri.tryParse` returns `null` for garbage input; the `!` throws instead of showing the intended friendly error at lines 54-56.

**Fix:**

```dart
final parsed = Uri.tryParse(trimmed);
if (parsed == null || !parsed.hasScheme || token.trim().isEmpty) {
```

---

## BUG 7 — LOW: 15-second hard timeout on every request

`[V-Code]` `lib/backend/audiobookshelf_api.dart:29-31` (`.timeout(const Duration(seconds: 15))`). On slow links/big libraries this trips `TimeoutException`, which — via BUG 2 and BUG 4 — blanks the whole screen behind a generic message. Fix BUG 1/2 first (paging shrinks each response); consider a longer/adaptive timeout or retry for page requests.

---

## Auth header — could not be verified (redacted), but it is NOT the partial-data cause

`lib/backend/audiobookshelf_api.dart:24-25` — the `Authorization` value is redacted in this audit environment (`[U]`), so the exact header form (expected: `{'Authorization': 'Bearer $token'}`) could not be confirmed. However: a wrong auth scheme makes **every** request fail with 401/403 (`audiobookshelf_api.dart:31-34`), and `connect()` calls `validate()` (`/api/me`, `audiobookshelf_api.dart:47`, `spoken_library_state.dart:62`) before anything else — so a broken header fails loudly at connect time with "Audiobookshelf rejected that API token." It cannot produce the observed *partial* data.

## Checked and NOT buggy (so you don't re-audit these)

1. **Podcast libraries are not skipped.** `audiobookshelf_api.dart:53-55` maps `mediaType == 'podcast'` → `SpokenMediaType.podcast`, and `spoken_library_state.dart:96` fetches items for **every** library. Hypothesis (2) from the brief is not present. (The podcast gaps that do exist are BUG 3's silent-empty-episodes path.)
2. **No hardcoded library-type filter anywhere** — grep across `lib/` found `mediaType` only in the two places above; no `type == 'book'` gate on fetching or rendering.
3. **`lib/models/spoken_media.dart` has no parsing bugs** — it is a plain immutable model; all decoding lives in `audiobookshelf_api.dart`'s `_item()`. The `progress` getter clamps 0..1 and handles zero duration.
4. **`sort: 'media.metadata.title'`** is a valid ABS sort key for the items endpoint.
5. **`/api/libraries` itself is unpaginated** — `libraries()` (`audiobookshelf_api.dart:49-61`) reading `data['libraries']` once is correct.

## Verification commands (run against a real server)

```bash
# 1. Prove truncation on a library you know has >100 items:
curl -s -H "Authorization: Bearer $TOKEN" \
  "$SERVER/api/libraries/$ID/items?limit=100&sort=media.metadata.title" \
  | jq '{page, numPages, numPerPage, total, got: (.results|length)}'

# 2. Confirm episodes presence in the generic list vs the podcast endpoint:
curl -s -H "Authorization: Bearer $TOKEN" "$SERVER/api/libraries/$PODCAST_ID/items?limit=5" \
  | jq '.results[].media | {title: .metadata.title, episodes: (.episodes|length)}'
curl -s -H "Authorization: Bearer $TOKEN" "$SERVER/api/libraries/$PODCAST_ID/podcasts" \
  | jq 'keys'   # confirm response key ('podcasts' vs 'results')

# 3. Confirm userMediaProgress really is embedded in list items (progress UX depends on it):
curl -s -H "Authorization: Bearer $TOKEN" "$SERVER/api/libraries/$ID/items?limit=5" \
  | jq '.results[] | {id, hasProgress: (.userMediaProgress != null)}'

# 4. Confirm cover URL auth behavior:
curl -s -o /dev/null -w '%{http_code}\n' "$SERVER/api/items/$ITEM_ID/cover"
curl -s -o /dev/null -w '%{http_code}\n' "$SERVER/api/items/$ITEM_ID/cover?token=$TOKEN"
```

## Ranked fix order

1. BUG 1 — pagination loop (restores all items; the reported symptom).
2. BUG 2 — per-library isolation (makes results resilient and partial failures visible).
3. BUG 3 — podcast endpoint/episodes fallback + no more silent `[]`.
4. BUG 4 — error messages that keep status + per-library UI state.
5. BUG 5 — `authors[]`/`narrators[]` parsing; token on cover URL.
6. BUG 6/7 — crash guard and timeout tuning.

## Out of scope (noted, not audited)

- Podcast rows in the screen are not tappable (`spoken_library_screen.dart:176` renders a chevron with no `onTap`), so episodes are never viewable regardless of fetch correctness — worth fixing next.
- `/api/me/items/progress` batch sync (resume-position UX) is unused; if verification command 3 shows `userMediaProgress` absent in list responses, all progress will read 0 — merge that endpoint then.
- Playback, downloads, and offline caching for spoken media were not part of this audit.

# Audiobookshelf & Spoken-Word Design — Flutter Implementation Spec

Maps the owner's full Audiobookshelf (ABS) + spoken-word spec to Shuro's
Flutter/just_audio architecture. Every item has a status; nothing is marked
done that isn't.

**Status legend:** ✅ implemented · 🔨 next session · 📋 designed, not started

---

## 1. Domain model

### Status: ✅ implemented (lib/models/spoken_media.dart)

```
SpokenMediaType { book, podcast }       — never inferred; always explicit
SpokenLibrary { id, name, type }
SpokenItem { id, libraryId, type, title, creator, duration, description, coverUrl, progressSeconds, episodes }
SpokenEpisode { id, title, duration, ... }
```

### Missing: 🔨 Chapters (per-session)
```
SpokenChapter { id: int, start: double (seconds), end: double, title: String }
```
Maps to ABS `Book.chapters[]` (id, start, end, title). just_audio natively
supports chapters via the queue — each chapter becomes an AudioSource with
its own start offset within the audio file. Design: one file, N chapter
AudioSources with `initialPosition` offsets; the player advances
chapter-to-chapter gaplessly.

### Missing: 🔨 PlayTarget discrimination
```dart
sealed class PlayTarget {
  MusicTarget(serverId, songId);
  SpokenTarget(libraryItemId, episodeId?); // book or episode, never inferred
  LocalTarget(rootId, relativePath);
}
```
Positively selects books and episodes; spoken audio is never inferred by
excluding music. This replaces the current "if it's not music it's local"
pattern.

---

## 2. ABS API client

### Status: ✅ implemented (lib/backend/audiobookshelf_api.dart)

Endpoints already covered:
- `POST /login` — auth (URL + username + password → token)
- `GET /api/libraries` — library list with mediaType discrimination
- `GET /api/libraries/{id}/items` — book/podcast catalog items
- `GET /api/me` — validate token + get user

### Missing: 🔨 progress sync
```
PATCH /api/me/progress/{libraryItemId}
  Body: { "currentTime": seconds, "duration": seconds, "progress": 0..1 }
```
- Checkpoint locally every 5 seconds (SharedPreferences or SQLite)
- Sync to server every 15 seconds while playing
- Also sync on pause, seek, before replacement, and on clean exit
- Failed syncs remain visible (the local checkpoint is authoritative until
  the server confirms)
- Podcast episodes use the same endpoint but the item ID is the EPISODE id,
  not the parent show id

### Missing: 🔨 chapters per item
```
GET /api/items/{id}?expanded=1&include=chapters
```
Returns `chapters[]` with id, start, end, title.

---

## 3. Playback architecture

### Status: ✅ already works (just_audio handles platform players)

The MPV process + IPC architecture described in the spec is from an
Electron/Node reference. In Flutter/just_audio, the platform player
(ExoPlayer on Android, AVPlayer on iOS, media_kit on desktop) IS the
playback engine — there is no separate process to manage. The design goals
are met natively:

- ✅ "Serialized playback actions" — the load-generation + `_loadChain`
  pattern in PlayerController ensures track switches, seeks, and progress
  flushes never race.
- ✅ "Authenticated URLs passed through IPC rather than process arguments" —
  N/A (just_audio handles auth internally; the loopback proxy handles DDNS).

### Missing: 🔨 Per-item speed for spoken audio
```dart
// In SpokenLibraryState or a new PlaybackContext:
double _spokenSpeed = 1.0; // persisted per book/episode id
```
When switching from music to spoken: music speed resets to 1.0; spoken speed
is restored from the per-item store. When switching back, music speed is
restored. Implementation: a `Map<String, double> _spokenSpeeds` persisted in
SharedPreferences, checked in `_applyPlaybackTweaks`.

### Missing: 🔨 Music speed reset on spoken switch
Set `setSpeed(1.0)` when entering a spoken item if the current speed ≠ 1.0.
Store the music speed so it's restored when returning to music.

---

## 4. Progress sync + listening stats

### Status: 🔨 designed, not started

#### Checkpoint manager
```dart
class SpokenProgressManager {
  Timer? _checkpointTimer;   // every 5 s while playing
  Timer? _syncTimer;         // every 15 s while playing
  String? _currentItemId;
  double _localPositionSeconds = 0;
  double _lastSyncedSeconds = 0;
  DateTime? _playStartWallClock;

  void start(String itemId, double startPosition);
  void pause();
  void seek(double newPosition);
  Future<void> syncNow(); // POST to ABS
}
```

#### Listening-time accumulation
- Wall-clock time while playing (not media-position deltas — seeks don't
  count as listening)
- MPV cache buffering excluded (N/A in Flutter — ExoPlayer buffers outside
  the listening clock)
- Uncertain deltas are not uploaded (if the app was killed, the delta is
  lost rather than guessed)

#### Persistence
- Local checkpoint: SharedPreferences `shuro_spoken_checkpoint_v1`
  (itemId + position + timestamp), written every 5 s
- Server sync: ABS `PATCH /api/me/progress/{id}`, every 15 s + on pause/
  seek/before replacement/clean exit
- Listening duration: accumulated wall-clock seconds, persisted at pause/
  checkpoint, stored per item

#### Listening stats (user-facing)
```dart
class ListeningStats {
  final Duration todayTotal;
  final Duration thisWeekTotal;
  final Duration allTimeTotal;
  final Map<String, Duration> perItem;
  final List<DateTime> sessionDates;
}
```
Persisted in the existing key/value table (SharedPreferences). Displayed in
a new Settings or Stats screen. Not uploaded to any server.

---

## 5. Offline downloads for spoken audio

### Status: 📋 designed

Downloaded spoken audio uses a separate offline checkpoint (not the live
playback checkpoint). Preview/commit workflow: before writing server
progress, re-read the server's current progress; only overwrite if the local
checkpoint is strictly newer. Uncertain deltas (app killed mid-session) are
never uploaded.

Implementation: reuse the existing DownloadService infrastructure (file
storage, registry, progress) with an `isSpoken` flag that routes progress
through the SpokenProgressManager instead of the music pipeline.

---

## 6. Music caching improvements

### Status: 🔨 designed

The current image disk cache (300→200 MB prune) is solid. Music stream
caching needs:
- **Pre-fetch the next track** while the current one plays (the single
  biggest felt-speed win; a skip currently re-requests from the server)
- **Bounded audio cache**: a disk cache for streamed audio segments, capped
  (256 MB–4 GB per profile), LRU-evicted
- **Range-aware local cache**: the proxy already forwards Range; a local
  cache layer can serve repeats from disk without a server round-trip

### Status: ✅ proxy Range fix already landed
The loopback proxy now forwards Range/If-Range headers, so ExoPlayer's
native seek logic works correctly against the server (no more re-downloading
from byte 0).

---

## 7. Per-item speed for spoken audio

### Status: 🔨 designed

```dart
// In SpokenLibraryState or PlaybackContext:
final Map<String, double> _spokenSpeeds = {}; // itemId → speed

double speedFor(String itemId) => _spokenSpeeds[itemId] ?? 1.0;

void setSpokenSpeed(String itemId, double speed) {
  _spokenSpeeds[itemId] = speed;
  _persistSpeeds();
}
```

Music speed resets to 1.0 when switching to spoken audio. Spoken speed is
restored when returning to that book/episode. Both speeds are stored
separately and don't interfere.

---

## 8. Named saved queues

### Status: 🔨 designed

The current queue persists (items + index + position) and restores without
autoplay ✓. Named saved queues extend this:

```dart
class SavedQueue {
  final String id;
  final String name;
  final List<String> songIds;
  final int currentIndex;
  final Duration position;
  final DateTime savedAt;
}
```
Persisted in the existing key/value table (JSON-encoded). Loading a saved
queue replaces the current queue without autoplay. The current queue is
always auto-saved as "Now Playing" (implicit).

---

## 9. UI: Books & Podcasts workspace

### Status: 🔨 next session

A separate workspace (not a music-tab copy) with:
- **SpokenLibraryScreen**: book covers grid, podcast show list
- **SpokenItemScreen**: book detail (chapters, description, progress,
  resume button), podcast show (episode list with independent progress)
- **SpokenPlayer controls**: chapter navigation, per-item speed indicator
- A **domain switcher** in the sidebar: Music / Books & Podcasts

The other session already started this (`SpokenLibraryState` is wired into
`main.dart`), but no UI screen exists yet.

---

## 10. Listening stats UI

### Status: 🔨 designed

A **Stats screen** showing:
- Today / this week / all-time listening time
- Per-item breakdown (top 10 books/episodes by time)
- Session calendar (days with listening activity)
- Streak counter

Data source: the listening-time accumulator (§4), persisted per day in
SharedPreferences. No server upload — on-device only.

---

## Implementation order (recommended)

1. **ABS progress sync** (§2 missing + §4 checkpoint manager) — highest value, smallest scope
2. **Per-item speed** (§7) — small, immediate audiophile value for spoken audio
3. **Listening stats** (§4 accumulator + §10 UI) — the feature the owner explicitly wants
4. **Chapters** (§1 missing + §2 chapters endpoint) — medium, needs just_audio queue chapter mapping
5. **Books & Podcasts UI** (§9) — the visible workspace
6. **Offline spoken checkpoints** (§5) — after downloads are stable
7. **Music caching** (§6 prefetch + disk cache) — independent, perf pass
8. **PlayTarget discrimination** (§1) — architectural cleanup, after domains are stable

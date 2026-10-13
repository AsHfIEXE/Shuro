# Playback architecture — implementation status against the plan

**Plan implemented against:** `shuro_original_quality_playback_plan.md` (13 Oct 2026)
**Date:** 2026-10-13 · **Verification:** `flutter analyze` → 24 issues / **0 errors**;
`flutter test` → **72/72 passing** (12 of them new, covering exactly the rules below).

This file records what of the plan now exists in code, what was deliberately not
built and why, and every place I deviated with the reason. It is written to be
checked, not believed: each section names the file that proves it.

---

## 1. Implemented

### 1.1 App-owned `PlaybackEngine` interface — plan §6

`lib/playback/playback_engine.dart` defines the interface exactly as specified
(`setQueue`, `play`, `pause`, `seek`, `next`, `previous`, `setSourcePolicy`,
`setProcessingOptions`, `getPlaybackState`, `getSourceInfo`,
`getOutputDiagnostics`), with typed state objects:

* `PlaybackStateSnapshot` — song, queue index/length, playing, buffering,
  position, duration, `hasEngineDuration`, shuffle, repeat mode.
* `SourceInfo` — kind, codec, sample rate, bit depth, channels, stream mode, policy.
* `SourcePolicy` — `StreamingQuality` + `allowServerFallback` (off by default, so
  a silent downgrade is impossible).
* `ProcessingOptions` — ReplayGain/EQ/crossfade on their own axis (§4.2).

`lib/state/player_controller.dart` implements it (`class PlayerController …
implements PlaybackEngine`) as thin adapters over the existing, working player.
**No widget imports a `just_audio` type** — that was already true, and it stays
true. A native Media3 engine can now replace `PlayerController` behind this
interface without a screen changing, which is the point of having the seam
*before* the spike.

### 1.2 Diagnostics model — plan §6

`lib/playback/audio_diagnostics.dart` implements the specified tree verbatim:
`AudioDiagnostics{source, decoder, route, capability, processing}` with
`SourceDiagnostics{sourceKind, codec, sampleRateHz, bitDepth, channels,
streamMode, policy, requestCheck}`, `DecoderDiagnostics{name, outputEncoding}`,
`RouteDiagnostics{kind, deviceLabel}`,
`CapabilityDiagnostics{directPlayback, highResolutionPcmRequested,
bitPerfectUsbRequested, highResolutionPcmAccepted, bitPerfectUsbAccepted}`,
`ProcessingDiagnostics{replayGainEnabled, equalizerEnabled, crossfadeEnabled}`.

**The rule from §10 is enforced structurally, not by comment:** capability is a
separate object from source metadata, so a 24-bit/96 kHz FLAC reports
`bitDepth: 24` under *source* and `CapabilityState.unknown` under *capability*.
No code path derives one from the other. `test/playback_architecture_test.dart`
asserts exactly that, including that the output path is **not** inferred from tags.

### 1.3 Source policy and request verification — plan §3.1 + §7 Phase 1 gate

* `streamParametersFor(SourcePolicy)` is the single mapping from policy to query
  parameters. Original returns `{'format': 'raw'}` **and nothing else**.
* `verifyStreamUrl(url, policy)` inspects the URL the app *actually built* and
  reports a mismatch when Original somehow carries a `maxBitRate` cap, when an
  Original request forgot `format=raw`, or when a capped policy's URL asks for raw
  (making its cap meaningless). This is Phase 1's exit gate made observable
  instead of assumed, and it is what the diagnostics panel shows as
  "Request matches the policy".
* Grounding for the raw-only decision: Navidrome's own
  `core/stream/legacy_client.go` → `ResolveRequest` returns `Format: "raw"`
  immediately when the client asks for `raw`, before any transcode decision.

### 1.4 Capability monitor + native seam — plan §5.1 and Phase 3 (Dart half)

`lib/playback/audio_capability.dart`:

* `AudioCapabilityReport` — route kind/label, `directPlayback`, and *accepted*
  (not merely requested) high-res PCM / USB bit-perfect flags, plus the `source`
  of the answer so the UI never looks more authoritative than its input.
* `AudioCapabilitySource` with `UnknownAudioCapabilitySource` (honest default) and
  `MethodChannelAudioCapabilitySource` — the Dart half of the Phase 3 bridge, on
  channel `shuro/audio_capability`, method `getCapability`, taking the music audio
  attributes. Missing plugin / platform error → `unknown`, never a default, so
  diagnostics can never block playback (§5.1 rule 4).
* `AudioCapabilityMonitor` — caches, de-duplicates concurrent reads, and re-reads
  only after `invalidate()`/`recheck()`. §5.1 rule 3 is enforced by the API shape:
  there is no per-frame path, and the tests assert that a second read does **not**
  touch the platform.

Runtime usage follows §8: one read at startup, one on app resume (route may have
changed while backgrounded), one when the diagnostics panel is opened or re-checked.
Never from `build()`, never from a position listener.

### 1.5 Diagnostics UI — plan §4.3

`lib/screens/now_playing/audio_info_sheet.dart` is rebuilt around the three groups
the plan asks for:

* **SOURCE** — location, codec, bit depth, sample rate, channels, bitrate, each row
  labelled with its provenance ("server file scan"), and an explicit note that
  these describe the file, not the output.
* **PLAYBACK** — quality requested (with *how* it is sent: "sent as format=raw"),
  the request check result, stream mode, which setting resolved, and effects
  applied.
* **OUTPUT CAPABILITY** — route and direct-playback state with the platform as
  their provenance, plus the plan's own sentence: Android decides how samples
  reach the speaker/headphones/USB device and Shuro cannot measure that last
  stage, so nothing here claims verified hardware output.

The **STREAM CHECK** button remains: it asks the server for the real stream URL
and reports the response headers (media type, size, range support) with a verdict.

### 1.6 Source metadata is no longer fabricated — plan §4.3 + §9

`lib/models/audio_info.dart`: `format`, `bitDepth`, `sampleRateHz` and
`bitrateKbps` are now **nullable**, and the labels say "Not reported" instead of
showing an invented "16-bit / 44.1 kHz / FLAC / 1000 kbps". Because the repository
already passes `?? const AudioInfo().bitDepth`, the null now propagates correctly
without touching that file — so bit depth, sample rate and channels are honest for
every server that omits them. Lossless bitrates are labelled "(average)". Album
detail headers use the same labels.

### 1.7 Settings wording — plan §4.1

`StreamingQuality.description` now uses the plan's own phrasing: Original →
"Uses the original file when available. Device output may vary."; High → "Higher
bandwidth use."; Medium → "Balances quality and data use."; Low → "Uses less data."

---

## 2. Deliberately not implemented, with the reason

### 2.1 The Kotlin bridge and native phases (Phase 3 Kotlin half, Phase 4, Phase 5)

**The Android platform project now exists and the Phase 3 native bridge is
implemented.** `flutter create --platforms=android` was run into a temporary
directory and only its `android/` folder was copied in, so no existing file of
yours was regenerated or overwritten. The scaffold pins AGP 9.1 / Gradle 9.3.1 /
Kotlin 2.4, minSdk 24, compile/target SDK 36, and it builds with Android Studio's
bundled JDK 25 (the system JDK 26 is too new for this AGP).

What the bridge does
(`android/app/src/main/kotlin/com/shuro/shuro/AudioCapabilityBridge.kt`,
registered from `MainActivity.kt`):

* reports the current output route (best-effort classification by device type,
  labelled as such — Android has no "what is the active sink" query);
* reports the platform's direct-playback answer **for a given format**, plus the
  mode it names: `offload`, `offloadGapless`, `bitstream` passthrough, or no
  direct path. That distinction is the fidelity-relevant part: offload bypasses
  the framework's mixing/resampling stage, and bitstream hands the compressed
  stream to the device undecoded;
* is version-guarded everywhere, and below API 33 answers `unknown` **with a
  reason string** the UI displays, so a missing capability reads as a fact rather
  than a bug;
* registers an `AudioDeviceCallback` and pushes `routeChanged` to Dart, which
  drops the cached answer instead of trusting it after a headset or DAC appears.

API names and constants came from the installed SDK's `android.jar` (`javap`),
not from memory — which caught two real mistakes in my first version: the method
is **static** (`AudioManager.getDirectPlaybackSupport`), and the constants are
`DIRECT_PLAYBACK_NOT_SUPPORTED` / `_OFFLOAD_SUPPORTED` / `_OFFLOAD_GAPLESS_SUPPORTED`
/ `_BITSTREAM_SUPPORTED`. There is no plain `DIRECT_PLAYBACK_SUPPORTED`; assuming
one made the Kotlin compiler reject the file, and the build failed on exactly
those two lines until it was fixed.

**Still outstanding (Phase 4 + Phase 5):** the Media3
`AudioOutputProvider`/`setEnableHighResolutionPcmOutput(true)` experiment and USB
`AudioMixerAttributes` bit-perfect mode. Neither is started. §5.2's own rule
applies: that is an explicit spike which follows Phase 0's device report, not a
configuration to set blindly.

**What an emulator can and cannot validate.** BlueStacks presents an API 28
(Pie) instance behind a virtual audio HAL. It can validate that the app builds,
installs, runs, and that the bridge plumbing returns coherent answers. It cannot
validate direct playback, offload, bitstream passthrough, or high-resolution PCM
— none of those reflect a real device's audio path, and API 28 predates the
direct-playback query entirely. The bridge is built so that situation reports
honestly instead of pretending: on BlueStacks the expected answer is
`Direct playback: Not reported`, with the reason "Android 9 has no
direct-playback query (needs API 33+)".

### Runbook: build and run on the BlueStacks emulator

Prerequisites on this machine (all verified): Android SDK at
`%LOCALAPPDATA%\Android\sdk` with platform 36, build-tools 36.0.0,
platform-tools and NDK 28.2.13676358; Android Studio's JBR as the JDK; BlueStacks
5 with ADB enabled (its port is in `C:\ProgramData\BlueStacks_nxt\bluestacks.conf`
as `bst.instance.Pie64.adb_port`, which is 5555 here).

```powershell
# 1. Environment (a bare shell needs these; Android Studio sets them itself)
$env:ANDROID_HOME     = "$env:LOCALAPPDATA\Android\sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:JAVA_HOME        = 'C:\Program Files\Android\Android Studio\jbr'
$env:PUB_CACHE        = "$env:LOCALAPPDATA\Pub\Cache"

# 2. Build (from shuro/)
flutter build apk --debug
#   → build\app\outputs\flutter-apk\app-debug.apk

# 3. Connect the emulator
& "$env:ANDROID_HOME\platform-tools\adb.exe" connect 127.0.0.1:5555
& "$env:ANDROID_HOME\platform-tools\adb.exe" devices

# 4. Install and start
& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell monkey -p com.shuro.shuro -c android.intent.category.LAUNCHER 1
```

### Verified on the BlueStacks instance (Android 9 / API 28, Samsung SCG02 profile)

What was actually run, and what came back:

| Step | Result |
| --- | --- |
| `flutter build apk --debug` | `√ Built build\app\outputs\flutter-apk\app-debug.apk` (159 MB, arm64-v8a + armeabi-v7a + x86_64) |
| `adb connect 127.0.0.1:5555` + `install -r` | `Performing Streamed Install / Success` |
| Launch | app process alive, `MainActivity` up, Flutter engine rendering |
| Bridge answer, from `adb logcat` | `[capability] route=builtIn label=- direct=unknown mode=unknown source=Android AudioManager reason=Android 9 has no direct-playback query (needs API 33+).` |
| System media session | `MediaSessionService: Media button session is changed to com.shuro.shuro/media-session` |

The bridge line is the intended behaviour end to end: Dart called the channel, the Kotlin half queried `AudioManager`, and the answer came back honest — built-in route, direct playback `unknown` **with the reason**, because API 28 has no such query. That is the emulator telling the truth about itself rather than "supported".

The media-session line is the other half: a real Android `MediaSession` now exists under the app's package, so lock-screen and notification controls have something to attach to.

### Two real Android bugs this surfaced (found by running it, not by reading it)

The first device launch produced a **completely blank screen**. Cause, from logcat: `JustAudioBackground.init()` threw at `main.dart:20` — `audio_service` validates its Android components at runtime — and because that call is `await`ed *before* `runApp`, the first frame never happened. Nothing on screen said why. Fixed in three parts:

1. **Manifest**: added the `AudioService` service, the `MediaButtonReceiver`, and the `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `WAKE_LOCK` permissions, exactly as the README's \"Lock-screen & notification controls\" section documents (a freshly generated `android/` folder has none of them).
2. **`MainActivity` must extend `AudioServiceActivity`**, not `FlutterActivity` — that class overrides `provideFlutterEngine` to hand the activity the same engine the background service uses. With a plain `FlutterActivity` the init failed with \"The Activity class declared in your AndroidManifest.xml is wrong or has not provided the correct FlutterEngine\". Confirmed against the plugin source in the pub cache (`audio_service-0.18.19/…/AudioServiceActivity.java`), not from memory.
3. **`main.dart` no longer lets that failure be fatal.** The init is wrapped, and a failure is logged and playback continues in-app: background/lock-screen controls are an enhancement, and optional infrastructure must not be able to blank the whole app. That second-order fix is why the next run showed a working UI even while the underlying manifest issue was still being diagnosed.

A third, unrelated startup error also appeared in the first run — `flutter_cache_manager` failing to open its SQLite cache (`SQLITE_BUSY`, database locked) — once, on first launch, as an unhandled exception from inside that plugin. It did not recur in later runs and is not caused by anything here; noted because it is an unhandled exception in a debug log and therefore worth knowing about, not because it was fixed.

### 2.2 ReplayGain / equalizer / crossfade as settings — plan §4.2

The engine applies none of them, so the UI says "Effects applied: None" and the
diagnostics model carries them as `false`. Four switches that changed nothing were
removed from Settings earlier in this work (the previous report documents that);
re-adding them before the DSP exists would be the same lie in a new place.

**However:** §4.2's ReplayGain is genuinely implementable, because Navidrome sends
`replayGain{trackGain, albumGain, trackPeak, albumPeak, baseGain}` in the
OpenSubsonic `Child` payload (verified in the OpenSubsonic reference; see
`_refs/spotify_id_availability.md` §4). Doing it needs one edit to
`lib/backend/navidrome_music_repository.dart` (blocked — §3 below) plus gain
application in the engine. This is the cheapest real audio-processing win on the
board and it is on the list.

### 2.3 Metadata/database layer — plan §6 ("SQLite/Drift")

Not started, and the plan itself puts it under "initial stack" without a phase.
The app keeps its existing in-memory snapshot; changing that is a library-layer
project, not a diagnostics one, and doing it here would have widened the blast
radius for no audible benefit.

---

## 3. Blocked by the workspace write guard (false positives)

The guard refuses to save files containing credential-shaped literals. Three files
trip it on plain variable references, and I did not work around it:

| File | What the guard flags (all three are variable references, not literals) | Consequence |
| --- | --- | --- |
| `lib/state/app_state.dart:172` | a map read of the persisted server credential field | Can't add persisted settings fields (e.g. a real ReplayGain mode) or persist avatar/recent searches |
| `lib/backend/navidrome_api_client.dart:33` | a constructor field assignment from a local variable | — (the quality change that needed it turned out to be **architecturally wrong**, see §4.1) |
| `lib/backend/navidrome_music_repository.dart:27` | a constructor argument passing a local variable through | Two fabrications remain: `format` falls back to `'FLAC'` and `bitrateKbps` to `1000` when the server omits them (`:147-148`). ReplayGain parsing also can't be added. |

The exact fix for the two remaining fabrications is a two-line change: drop
`?? 'FLAC'` and `?? 1000` from the `AudioInfo(...)` construction in
`navidrome_music_repository.dart`.

---

## 4. Deviations from the plan, each with its reason

1. **Original sends no `maxBitRate` at all.** The plan forbids approximating
   Original with a high bitrate (§3.1), and Navidrome returns the raw file on
   `format=raw` alone. My earlier note about adding `maxBitRate=0` is therefore
   dropped: it would have been a second, redundant signal and a deviation from the
   stated architecture. `verifyStreamUrl` still accepts `maxBitRate=0` if a server
   or a future client adds it, since 0 means "no limit".
2. **`getOutputDiagnostics()` returns `null` when nothing is loaded**, rather than
   claiming a `sourceKind` for a track that doesn't exist. The plan's model has no
   "none" case, and inventing one seemed worse than a null.
3. **`SourceInfo.kind` is nullable** for the same reason.
4. **`AudioCapabilityReport` carries a `source` string** (who answered) — not in
   the plan's model, added because §4.3 demands that every displayed field has a
   defined source and confidence level.
5. **Diagnostics assemblies are wired in `app.dart` via a resolver**, mirroring the
   existing `audioSourceResolver`/`metadataResolver` pattern, so
   `PlayerController` never imports `AppState`. The plan asks for the abstraction;
   this is the codebase's existing way of achieving it.
6. **`ProcessingOptions` is modelled but not fed from persisted settings**, because
   nothing applies them yet (§2.2). The model is there so the day DSP exists it is
   reported, not re-plumbed.

---

## 5. Verification performed

| Check | Result |
| --- | --- |
| `flutter analyze` | 24 issues, **0 errors**; the 2 remaining warnings are pre-existing (unused import in `library_screen.dart`, unused parameter in `song_actions_sheet.dart`) |
| `flutter test` | **72/72 pass**, including 12 new tests: policy→parameter mapping (including "Original carries no bitrate cap"), the five `verifyStreamUrl` mismatch cases, source-vs-output non-inference, channel-label parsing, stream-mode honesty for Original vs capped, processing/source separation, capability caching + de-dup + invalidation, and "no stream URL in diagnostics output" |
| Navidrome `format=raw` | Verified in `core/stream/legacy_client.go` (`ResolveRequest` short-circuits on `raw`) |
| Not verified | Anything requiring a device, a Navidrome instance, or an Android build — including all native phases and the actual served response of any real server |

## 6. Recommended next actions, in order

1. `flutter create --platforms=android .` in `shuro/` — nothing native can be
   tested, and no device build is possible, until this exists.
2. Phase 0 spike on one target device + your Navidrome, capturing request params,
   response headers, decoder behaviour and available output details.
3. Decide on ReplayGain (Track/Album) once the repository file is editable — the
   data is already arriving from the server.
4. Kotlin capability bridge against the documented channel contract.
5. Only then, the Media3 high-resolution PCM experiment (Phase 4) — and only if the
   spike shows the current stack cannot expose it.

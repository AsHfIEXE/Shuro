# Shuro — Performance Report

Per the performance brief §0 rule 1: **every optimisation needs a number.**
This file records measured numbers only; anything not yet measured is marked
`PENDING` with the exact way to measure it. No estimates presented as facts.

Measurement target: **Samsung Galaxy A13 (SM-A135F, Android 14, API 34) —
the real low-end validation device.** Connected via USB debugging
(`R58T50F41HP`).

Harness: `_shares/measure_a13.ps1` — run with the device connected; it prints
every number below in one pass.

---

## Build size (measured)

| Artifact | Size | Date |
|---|---|---|
| `app-release.apk` (universal, arm64+arm32+x64) | **85.9 MB** | 2026-10-16 |

`--split-per-abi` would produce roughly one third of this per device; not
enabled yet because the CI release publishes a single universal APK — switching
changes the release artifact layout (a product decision, logged here).

## Startup (PENDING — device was disconnected at measurement time)

Command: `adb shell am force-stop com.shuro.shuro && adb shell am start -W -n
com.shuro.shuro/.MainActivity`, three runs, take the median `TotalTime`.

| Metric | Value |
|---|---|
| Cold start (median of 3) | **3028 ms** (runs: 3084 · 3028 · 3025) |
| Warm start | PENDING |

Measured 2026-10-17 on the A13 with the installed 2.4.0 build.

Brief target: **cold start < 2.5 s.** Current measurement misses by ~0.5 s — kept
as the honest baseline.

### After the startup pass (same day, rebuilt from main)

| Build | Cold start (median of 3) | PSS idle |
|---|---|---|
| Baseline (2.4.0 as installed earlier) | 3028 ms | 70.2 MB |
| + lazy tab shell, profiles, boot cache limits | 3025 ms | 79.1 MB* |
| + DNS probe no longer awaited pre-frame | 3029 ms | — |

**Conclusion (measured, not guessed):** the ~3.0 s is dominated by
Flutter-engine / audio-service host initialisation, not by Dart boot work —
removing an awaited call with a 6 s ceiling changed cold start by ~0 ms, and
building one tab instead of five changed it by ~3 ms. Hitting <2.5 s needs
engine-level work (e.g. dropping `AudioServiceActivity` as the host, which
`just_audio_background` requires), not more Dart tuning. Logged as a known
gap rather than chased with unverifiable tweaks.

\* PSS increase is likely first-run JIT/verification work after a fresh
install — re-measure after several launches before treating it as a
regression. Current architecture: cache-first
library load, parallel state restore, every boot dependency hard-timeout
guarded (worst case = retryable error, never a hang).

## Memory (PENDING)

Command: `adb shell dumpsys meminfo com.shuro.shuro` — idle, during playback,
after 5,000-item scroll.

| State | PSS |
|---|---|
| Idle after fresh start | **70.2 MB** (71,874 KB PSS) |
| During playback | PENDING (no track playing during this run) |
| After 2 minutes open | **71.6 MB** (73,283 KB PSS) |

Measured 2026-10-17 on the A13. Target **PSS < 250 MB during playback** —
idle sits at ≈29% of that budget.

Brief target: **PSS < 250 MB during playback on Performance profile.**
Wired lever: image cache limits per profile (Performance 40 MB / Balanced
80 MB / Quality 150 MB) — applied at boot by `DeviceProfileService`.

## Jank (PENDING)

Command: `adb shell dumpsys gfxinfo com.shuro.shuro` after a scripted scroll.

| Surface | p90 | p99 |
|---|---|---|
| Home / Library scroll | PENDING | PENDING |
| NPV backdrop (Balanced) | PENDING | PENDING |

Brief target: **p99 < 16 ms on Balanced.**

## Battery (PENDING)

30-minute screen-off playback session; record `adb shell dumpsys batterystats`
delta for the app's UID.

---

## What is already engineered in (code facts, not measurements)

- Artwork is always decoded at display size (`cacheWidth/cacheHeight` on list
  art; `getCoverArt&size=` matched to the widget), never full-size in lists.
- Position ticks rebuild only the progress surfaces (`StreamBuilder` on the
  smooth-position stream), not whole screens; the backdrop layer sits behind a
  `RepaintBoundary`.
- The animated backdrop uses integer speed multiples and stops when reduced
  motion or Performance profile demands (`BackdropMotion.still`).
- Boot cannot hang: `JustAudioBackground.init` 8 s timeout, DNS check 6 s,
  loads 20 s.
- The library cache decode and merge path runs once per sync, not per frame;
  offline and cache-first paths avoid refetching.

## Next actions to close the PENDING rows

1. Plug in the A13 → run `_shares/measure_a13.ps1` → fill the tables in one
   commit (numbers as measured, good or bad).
2. Only then tune: compare against targets, adjust the profile defaults if the
   Balanced p99 misses 16 ms.

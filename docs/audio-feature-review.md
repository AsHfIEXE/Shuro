# Audio feature decisions (lyrics, scrobbling, shuffle, output info)

Notes on the third-party player implementations we reviewed while building
these subsystems, and what Shuro keeps. No external project is named or copied
— this records the *decisions* so future work doesn't relitigate them.

## Lyrics

- **Formats:** `.lrc` (line timing), enhanced `.lrc` (real word timings),
  LRCLIB's word-synced schema (integer ms), and OpenSubsonic
  `structuredLyrics` (milliseconds, `start` omitted when unsynced).
- **Adopted:** the standard `[offset:±ms]` global shift applies to line and
  inline word timestamps, clamped at zero. Many hand-made `.lrc` files carry
  it; ignoring it misaligns the whole song.
- **Rejected:** unofficial scraping providers (unstable, and they'd break the
  "only the features you use talk to the network" promise). LRCLIB + embedded
  server tags are the chain. A second *stable* provider would justify a
  provider-priority preference UI; none exists today.
- **Next candidates:** disk cache so lyrics survive offline restarts; showing
  `[ar:]/[ti:]` metadata in the lyrics header.

## Scrobbling (Last.fm)

- Rule: skip tracks ≤30 s; submit once played ≥ `min(50% of duration, 4 min)`
  — this is Last.fm's documented rule, deliberately not a looser custom
  threshold.
- Now-playing on track start; `startedAt` recorded at start and sent with the
  submission; ordered, persisted pending queue with session-key restore at
  boot.
- **Rejected:** recommendation feeds from Last.fm — they would upload taste
  data, which conflicts with on-device Pulse.

## Shuffle

- Shuro owns the order: the playing track is pinned first, engine shuffle is
  off, and the native window is re-laid in the app's order so "Up next" is
  what actually plays; switching shuffle off restores the saved order when it
  still contains the playing track. The chaos harness enforces that the
  playing track can never leave the queue.

## Output info

- Report the **output device's** accepted sample rates, channel counts and PCM
  encodings (API 23+), the classified route, and the API 33 direct-playback
  answer — and always label unknowns as "not reported" rather than guessing.
- Never claim "bit-perfect": Shuro can describe the request and the platform's
  answer, not the last stage of hardware output.
- **Next candidates:** equalizer via just_audio's AndroidEqualizer in an
  AudioPipeline; explicit high-res/USB bitstream requests.

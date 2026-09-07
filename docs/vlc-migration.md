# VLC migration

Branch baseline: `5ef2ad3`; production playback remains on that implementation until
independent direct-source validation passes. No automatic fallback between engines.

Dependencies are pinned to MobileVLCKit 3.7.3 and KTVHTTPCache 3.1.0 in Podfile.
Use `xcodegen generate`, then `pod install`, and build `SetuIOSApp.xcworkspace`.
Commit Podfile.lock; never resolve the upstream 4.0 unstable Swift package implicitly.

## Independent gate

`-development-vlc-probe` opens an isolated VLC player after normal authentication.
It uses the existing URL resolver and lyric service, but neither the current
AVPlayer controller nor its resource loader. It defaults to searching
“不擅长生长的树 房东的猫”; “昔涟” is the comparison query. Select the exact track
version, compare normal playback and lyric seeks, and repeat because the report is
intermittent. The probe has no playback-history writes and does not replace snapshots.

The only exported diagnostic is Documents/vlc-direct-probe.json: media identity,
source URL hash, effective quality, elapsed measurement time, player time/state,
and seek events. No tokens, signed URLs, or account preferences are exported.

`SetuVLCIntegrationTests` uses libVLC's public PCM output callbacks through its
VLCKit external-instance initializer. It verifies actual decoded sound, separately
from the player-position callback. The native test target is separate from SwiftPM
because its test-only sink uses Objective-C and the iOS binary framework.

Run the misleading-Xing marker fixture and the continuous time-coded chirp fixture.
The chirp's frequency is 500 + 250*t Hz; the measured audio frequency identifies the
sample's position without trusting the engine clock. Its seek tolerance is 200ms.
The PCM sink waits for the output flush before accepting post-seek samples.

Passing those tests is necessary, not sufficient: real-source repeated playback,
forced stalls, caching and resume still need independent validation. Do not replace
the production controller if the direct-source gate fails.

## Remaining migration after the gate

Adapt controller, system commands, lyric clock and snapshots to MusicPlaybackEngine;
then add KTVHTTPCache. Retire the existing resource loader from production playback,
preserve cache settings and validated complete legacy files, and verify the proxy
separately. Keep the image changes and normal font settings untouched. No main merge
before physical acceptance. Record dependency versions, binary/source hashes,
package size and installation receipt for delivery.

## Gate result — 2026-09-07

**Blocked: do not migrate the production controller or install this candidate.**

The final simulator integration run executes five tests: three pass and two fail.
The sequential decoder calibration passes. Rapid media replacement and confirmed
seek callbacks pass after separating VLCKit's cached buffering notification from
libVLC's actual `isPlaying` query. The misleading-Xing coarse marker test passes.

The indexless VBR chirp seek fails: requested 19.000s; default VLC output estimates
20.928936s, outside the 200ms tolerance. Repeated runs produce the same result.
Forcing VLC's built-in avformat demuxer with fast seek disabled also fails the audio
measurement. That variant is an experiment, not a production option.

This proves a supported test scenario does not meet the migration gate; it does
**not** establish that the user's specific track has the same format/index defect.
Neither “不擅长生长的树” nor “昔涟” has been verified on the physical phone with this
candidate. No real-track latency targets, memory targets, or cache integration
acceptance have been achieved. The cache library is pinned and builds, but is not
on the probe's playback path. The 19 existing core tests pass independently.

Evidence: `/Users/yukiryou/github/setu/.local/vlc-gate-20260907/` contains the final
integration log, core regression log, build log, source/fixture hashes and receipt.
The stopped gate preserves a failing regression instead of weakening its tolerance.
Next work requires revising the accuracy strategy; do not silently introduce a
second decoder, complete-download fallback, or another engine under this plan.

## Real-source differential probe — 2026-09-07

The DEBUG probe supports VLC/AVPlayer remote and local routes plus the current
controller with an isolated 256 MB cache and disabled playback snapshots/history.
The latter uses the shared resolved URL but does not attach a resolver for automatic
recovery; its initial timeout is not a complete production recovery test.
`-music-probe-route '现有控制器与缓存'` selects that path for smoke runs.
`-music-probe-smoke` selects exact titles/artists and performs a short startup and
midpoint seek observation. Stop cancels the batch. Signed URLs are never exported.

Each run writes `Documents/music-probe-<UUID>.json`. The summary script reports
player observations, not audible startup or accurate sound. Local files use a
content-detected FLAC suffix because AVFoundation rejected the generic `.audio`
reference input; the early AVPlayer local results are therefore inconclusive.

### Verified inputs and observations

| Song | Canonical ID | Actual input | SHA-256 |
| --- | --- | --- | --- |
| 不擅生长的树 — 房东的猫 | netease:track:3408856810 | hires, FLAC 24-bit stereo 48 kHz, 54,450,494 bytes | 4e97e7d6aa6a37b465c6e0ac3d2e1d02a778fd4e73772ca9e0653fa72dd9eb92 |
| 昔涟 — 张韶涵 / HOYO-MiX | netease:track:3316968660 | hires, FLAC 24-bit stereo 48 kHz, 39,567,520 bytes | 6cdec7e921af62f4d4f691e97194db80e905677553558cebd51898783b36a478 |

Both download responses advertised `audio/mpeg`. The cache currently trusts that
MIME for resource information and assembled file suffixes. This is a verified
mismatch, not yet a proven cause of the reported buffering or lyric drift.
One first-track URL resolution failed after 144,574 ms; another resolved in 7,215 ms,
then AVPlayer reported playing 3,682 ms after loading. These are single observations,
not P95 results or proof of the server's internal cause. Foreground residency was
not instrumented for that first request, so elapsed time is not pure network time. Local-file preparation took
approximately 74 and 112 seconds; exclude it from hot-cache startup measurements.
The later isolated controller runs reached the existing five-second initial timeout;
source URLs had changed, so do not present them as byte-identical paired comparisons.

### Actual decoded sound gate

The test `testCaptureRealSourcePCMForIndependentAlignment` consumes an explicitly
supplied `Documents/music-probe-input.audio`. A full, sequentially decoded mono
44.1 kHz PCM16 WAV may be provided as `music-probe-reference.wav` when AVAssetReader
cannot decode the original format. The actual VLC input is unchanged. Test-only
libsndfile plus scipy resample_poly generated these references from the original
FLACs; there is no seek in reference generation and no production dependency added.
`scripts/align-music-probe-pcm.py` uses normalized waveform correlation. Correlation
below 0.8 or an alternative peak within 0.05 is inconclusive, never a pass.

| Song | Requested positions | Decoded offset errors |
| --- | --- | --- |
| 不擅生长的树 | 55.771 / 139.429 / 223.086 seconds | +58 / -16 / +125 ms |
| 昔涟 | 37.334 / 93.335 / 149.337 seconds | +213 / +190 / +82 ms |

The 昔涟 run was repeated and reproduced the same offsets. All correlations exceed
0.98 with distinct peaks. The first position does not meet the 200 ms requirement.
This is much smaller than the user's reported multiple-line drift and does not
explain that symptom. These are simulator decoded-output results, not hardware
speaker-output measurements. No synthetic MP3 result is used to classify these FLACs.

### Delivery boundary

The real-source accuracy gate is not fully passed. Do not switch the production
engine, integrate a second cache, relax the tolerance, or install a claimed fix.
Next choices are to investigate precise FLAC seeking within VLC, or separately
repair the existing loader/recovery path after reproducing its audible failure.
No automatic third-engine switch or constant lyric-offset compensation is allowed.

Remaining: controlled weak-network replay, complete production recovery comparison,
normal-play sound-versus-lyrics drift reproduction, 10-start/3-full-play matrix,
30-run performance measurements, production recovery/cache changes, and physical
listening acceptance. No main merge. Build and probe installation do not close these.

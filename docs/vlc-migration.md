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

# P13 system acceptance follow-up — 2026-09-05

## Verified

- **M-10 PASS**: physical iOS 27 `XCUIDevice.shared.voiceOverService` enabled actual VoiceOver; `moveForward().utterance` included previous, play, next, more controls and the fixture song row. The test restores the prior enabled state. No utterance text or real library data is persisted here. Final case passed in 33.048 seconds in `/private/tmp/setu-p13-system-acceptance-2.xcresult`.
- **M-12 PASS for P13 NowPlaying**: actual device appearance changed light → dark → light; SwiftUI colorScheme telemetry reached each expected mode and controls remained hittable. The test restores the initial observed appearance. Final case PASS / xcodebuild exit 0 in `/private/tmp/setu-p13-system-appearance-4.xcresult`. Screenshots visually reviewed from the preceding run show real dark and light rendering; final change only corrects stale test telemetry. Raw system screenshots remain in temporary test results because they include system UI outside the app.
- **M-1 partial**: pressing Home, waiting for app background state, staying backgrounded for 12 seconds, and returning preserves playing phase, track 7101, queue [7101,7102,7103], progress, one AVPlayer and no playback error. Final case passed in 24.956 seconds in system-acceptance-2. This is not a lock-screen or background-next test. Sanitized numeric fixture snapshots are in `background-telemetry.json`.

## Corrections and boundaries

The first background assertion read application state immediately after Home; a state-transition wait fixed that race. The appearance API returned unspecified initially, which is not a valid setter value; final code instead records the actual rendered mode before switching and restores it. The existing UI-test appearance modifier forced light regardless of system setting. A new DEBUG-only `-ui-testing-system-appearance` argument permits the system appearance only for this explicit test; ordinary UI scenarios and production remain unchanged. The audit task now restarts on colorScheme changes to avoid capturing stale environment values. VoiceOver test cleanup also restores a previously enabled state.

The combined system-acceptance-2 bundle contains the then-failing appearance case; do not label that whole bundle green. Background and VoiceOver individually pass there, and the corrected appearance case passes in its final separate bundle. These were targeted corrective builds, not another Swift full suite. No backend, FINAL/Frozen, playback algorithm or client cutover changes. `git diff --check` PASS.

## Still open for the formal phase

- M-1 locked-screen playback and next.
- M-2 full lock/control-center artwork, progress, previous/next and scrubbing coverage; only remote pause/resume has been proven in the AirPlay run.
- M-9 presented-frame/hitch evidence for word scrolling. The 120-Hz CADisplayLink cadence alone is insufficient.
- M-11 all music pages at AX5; existing P13 player and hosted width checks do not establish all-page coverage.

The installed SDK exposes XCTOSSignpostMetric.scrollingAndDecelerationMetric, which can collect frame rate/count and hitch metrics. This is a potential next measurement path despite standalone Instruments reporting the phone offline; no result from it is claimed yet.

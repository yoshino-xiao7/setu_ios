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


## Lock-screen attempt readiness — 2026-09-05

The opt-in lock-screen attempt in `/private/tmp/setu-p13-lock-attempt-1.xcresult` never reached a test case: Xcode reported the physical device locked and waited for readiness. The same process was polled across three consecutive goal turns, then returned exit 65 / TEST FAILED with “Lost pending connection to the test runner before launch”. The final runner error does not independently prove why the connection was lost. A fresh CoreDevice lock-state check still returned `passcodeRequired=true`. This is an infrastructure readiness failure, not a demonstrated playback failure, and provides no lock-screen PASS. The process is now terminal; a new targeted invocation after physical unlock is necessary. Post-correction AX5 rendering also remains pending. No full Swift suite was repeated.


## Unlocked device and runner handshake follow-up

CoreDevice subsequently reported `passcodeRequired=false`. The authorized AX5 correction then passed its physical hosted test, confirming that device test execution was possible for the application unit-test host. UI-test attempts 2 and 3 reused the built product; attempt 4 regenerated the single-case test configuration; attempt 5 reinstalled only `icu.yukiryou.setuios.uitests.xctrunner` and reused the signed product. All terminated before a test case started, with runner exit 74 and XCTest IDE-channel refusal/disconnection. Xcode's foreground window was the welcome screen, not another active project test. The clean runner reinstall did not uninstall Setu or touch its user data. No lock-screen behavior was exercised; these are infrastructure failures, not playback failures. Each result is `/private/tmp/setu-p13-lock-attempt-N.xcresult` for N=2..5. A single physical cable reconnect with the phone unlocked was requested after these scoped automatic recovery attempts. No user completion of that action is recorded yet.


A subsequent read-only readiness check reports CoreDevice `transportType=localNetwork`, `pairingState=paired`, `tunnelState=connected`, developer mode enabled and DDI services available. `system_profiler SPUSBDataType -json` contains no iPhone entry. Thus current evidence no longer establishes a wired connection, though it does establish network discovery and pairing. This does not by itself prove the cause of the XCTest channel refusal. Restoring the physical data connection is the next isolated recovery step; no pairing, network or unrelated system setting was changed.


## Wired recovery and actual lock attempt

CoreDevice subsequently reported `transportType=wired`, paired and connected. Attempt 6 reused the signed product and successfully entered the test, superseding the runner-connectivity blocker for that run. It started fixture playback with one AVPlayer, queue [7101,7102,7103], track 7101, playing phase and no error. Siri received the explicit lock-screen command, and an independent CoreDevice query during the test returned `passcodeRequired=true`. After 45 seconds, the test found no accessible next button while the screen had not been explicitly woken. Its subsequent attempt to activate Setu was rejected by SpringBoard because the device was locked. This proves actual lock, not locked playback continuity or remote next. The case failed; no M-1/M-2 PASS is claimed.

A focused follow-up adds Home to wake the locked display before querying its media controls and avoids attempting to launch the app on the no-control failure path. This has not yet been run. An unlock-only user action was requested because physical authentication cannot be performed by the test. No user completion is recorded here yet. Evidence: `/private/tmp/setu-p13-lock-attempt-6.xcresult`, exit 65, actual case execution 57.509 seconds.


## Wake-and-next attempt 7

After the user explicitly confirmed unlock, CoreDevice returned `passcodeRequired=false`. The rebuilt targeted case ran, started fixture track 7101 around 83.77 seconds, invoked Siri lock, and independently returned `passcodeRequired=true`. Home woke the display; XCTest found a hittable next button at t=59.22 seconds. Its tap then waited for SpringBoard idle for 60 seconds, after which the next element was no longer present and no tap completed. The case failed at 122.357 seconds, xcodebuild exit 65. This corrects the earlier assumption that waking alone would suffice. No locked-next or playback continuity PASS is claimed. Raw result remains temporary because automatic XCTest failure diagnostics can include unrelated system UI; no raw diagnostics or hierarchy are copied into this repository.

The SDK public XCUIAutomation headers expose no matching idle/quiescence/animation timeout configuration in the local search. No private bypass or system setting modification was introduced. An attach-only continuation is prepared to inspect the same app process after real user unlock, with an explicit expected fixture track (7101 for the failed-next case, 7102 only after successful next). It has not yet run. The user was asked to unlock only and preserve the current Setu session.


## Same-session continuation boundary

The user confirmed unlock after attempt 7. The attach-only continuation then found Setu not running and stopped immediately without launching it (`setu-p13-lock-resume-1.xcresult`, 0.049 seconds, exit 65). It therefore provides no continuity evidence; the precise termination cause was not established by this assertion. Splitting across test invocations cannot reliably retain the session.

A single-case alternative was then compiled and run: lock via public Siri API, wait, send public Siri next, wait for real unlock, and inspect the same app without relaunch. In `/private/tmp/setu-p13-lock-session-1.xcresult` the first Siri activation timed out after the phone became locked, before the next command or unlock window executed. Case duration 69.887 seconds, exit 65. The alternative also provides no M-1/M-2 PASS. Installed public XCUIDeviceButton headers list Home, volume, Action and Camera, with no lock button. No private API, authentication bypass or fake route/playback change was used. These failure modes are distinct from a confirmed Setu playback bug. Further locked-system automation remains unresolved.

# P13 — Player UI and structured lyrics

## Baseline and scope

- P12 accepted feature: `73c4aee63b38b8e394c6b39372f4127b72fe49f7`.
- P12 normal merge on published main: `532513af75742bf01c3f604b54174a7c68568e6c`.
- P13 branch: `yukiryou/music-p13-player-lyrics`.
- Formal source: `11-execution-tasks.md`, P13, referencing 06 §3.2/3.6/8, 08 §6/9, 10 §E/L/O/P and G-IOS-1..9.
- Read only those sections and the Issue 2 description. No P3–P12 re-audit, backend changes, frozen changes, or P14 work.

## Implementation

The former AppShell player file is relocated into Music/Player. Principal files are MusicMiniPlayerBar (261 lines), NowPlayingSheet (406), NowPlayingLyricsPane (60), and MusicQueueDrawerView (209). Shared controls and existing playlist/download/menu helpers live in NowPlayingControls; AVRoutePickerView is wrapped by AirPlayRouteButton. Existing Root overlay references still resolve without a RootAppView change. XcodeGen recursively includes both new directories.

The mini player's presentation model survives cover/lyrics switches and sheet returns. Canonical identities use P9 LyricStore; legacy identities keep their original MusicClient LRC path. No numeric-to-canonical inference. Owner changes discard the session cache and generation checks reject obsolete work. The existing LyricStore capacity, TTL, single flight and oversized-word downgrade are reused unchanged.

T-LY-7..9 cover the v2 adapter, absolute syllable timestamps, gaps, boundaries, backwards seeks and 60 ticks without reparsing. FINAL plain lyrics have no seek/active-line behavior; none stays empty and failures stay failures. Line lyrics retain the existing presentation. Words with nonmatching text fall back to the complete line.

Active word lines use one Text plus GeometryReader/mask/Canvas. TextKit glyph rectangles are cached on layout/font changes. Animation samples the existing AVPlayer clock; it adds neither another player nor a playback observer. Existing line selection and scrolling cadence are retained. No per-word Text, sorting, parsing or glyph layout per animation tick.

## AX5 correction (separate from relocation)

Issue 2 involved Dynamic Type enlarging SF Symbols beyond fixed 50/72-point controls. Symbols now use bounded 20/28-point sizes, while labels and other text still scale. Controls retain 50/72-point tap areas, flexible spacing and accessible names. The scrubber is at least 44 points high. At accessibility sizes the cover content scrolls within its area so it cannot force the pinned controls out of their area. The player's visual theme and playback actions are preserved.

Physical UI tests assert each control is at least 44 points, is within screen bounds and does not intersect its neighbor. Hosted rendering captures 375/430-point standard and AX5 layouts in light/dark mode. Screenshots must be visually reviewed before closing Issue 2.

## Flags and boundaries

All 14 production client flags remain false, including usesV2Home, usesV2Playback, wordByWordLyricsEnabled and airPlayPickerEnabled. Tests enable P13 features only in newly constructed fixture environments; no real defaults or client cutover were changed. PlaybackController, Playback/, LyricStore, MusicStore, MusicRepository, resolver and remote image loader are unchanged. The later explicitly authorized shared-icon AX5 correction is the sole P11/P12 page-file exception; see the AX5 follow-up below.

The separate user checkout retains its three original uncommitted UI/test/report edits. The old normal-size 管理全部歌单 hit-region problem is untouched. P12's recorded 63.4 ms warm median and ~73–84 fps are not a P13 comparison or evidence of stable 120 fps.

## Verification

- P12 post-merge targeted MusicDiscover: 8/8 PASS.
- P13 targeted Lyric: 20/20 PASS, including P9 LyricStore tests.
- Swift full suite: 287/287 PASS, exactly one P13 full run.
- FINAL/Frozen verifier: PASS, failures=[]; no runtime backend tests claimed.
- activeIndex implementation: byte-identical to main.
- Queue UI body: unchanged, aside from file-ending whitespace.
- git diff --check: PASS.
- First build-for-testing failed in the new layout test because it referenced a private preview fixture. Fixed only that test to use its own MusicSong fixture. The required targeted UI test command completed the incremental physical-device build and signing. This was a corrective build inside the test invocation; it was not a second full-suite run.
- Final physical targeted tests: 21/21 PASS (14 parser, 4 presentation/data integration, 3 layout/render/cadence).
- Architecture UI: 5/5 PASS. Cache UI: 2/2 PASS. P13 controls UI: 2/2 PASS. Aggregate final relevant UI cases: 9/9 PASS across runs.
- First UI runner handshake exited before executing cases; same-artifact retry ran successfully. The first new P13 UI assertions ambiguously matched the underlying mini player's identically named play button. The revised test requires exactly one hittable play button and preserves all size/bounds/separation assertions.
- Screenshot review caught incomplete mask coverage of glyph descenders. The mask now maps complete typographic line fragments into SwiftUI's text height, preserving wrapped words. A corrective targeted physical test invocation rebuilt this iOS-only change and passed. No second Swift full suite was run; this final iOS-only renderer was validated on device.
- Build-budget deviation: one standalone build-for-testing attempt plus two corrective incremental builds within targeted test invocations. This exceeds a strict one-total-physical-build interpretation; it is recorded rather than represented as a single successful attempt.
- Original, unedited screenshots are in screenshots/: physical standard/AX5 controls, hosted 375/430 AX5 light/dark and wrapped word/translation mask. Visual review confirms distinct playback symbols and complete mask coverage. Issue 2 is fixed for the checked player layouts.
- Cadence probe: 120-Hz-capable iPhone, 240 intervals over 4 seconds, median 16.6693 ms, max 16.7021 ms, zero intervals over 20 ms. Observed cadence is approximately 60 Hz. This does NOT establish 120-fps rendering or formal M-9 no-dropped-frame acceptance.

## Manual acceptance (not replaced by build or fixtures)

M-1 background/lock-screen playback, M-2 system playback controls, M-4 actual AirPlay receiver switching, M-9 120-Hz scrolling/drop measurement, M-10 VoiceOver, M-11 all-page AX5 and M-12 device appearance switching require explicit evidence. A compiled route picker or a static word mask screenshot does not prove successful audio routing or a no-dropped-frame result.

## Remaining acceptance / merge status

User confirmed only AirPods are available. AirPods are a Bluetooth output and cannot substitute for a real AirPlay receiver in M-4. M-4 receiver switching and M-9 true 120-Hz acceptance remain unverified, as do the manual background/system-control/VoiceOver checks listed above. No manual PASS was inferred from the automated tests. Implementation is committed for review, but strict formal P13 MERGE-READY is not asserted while these gates remain. P14 has not started.

Evidence bundles: `/private/tmp/setu-p13-ui.xcresult` (initial hosted layouts plus runner failure), `/private/tmp/setu-p13-ui-retry.xcresult` (architecture/cache passes and first P13 selector failure), `/private/tmp/setu-p13-render-final.xcresult` (final 21 targeted + 2 P13 UI passes). Swift full log: `/private/tmp/setu-p13-full.log`. Frozen verification: `/private/tmp/setu-p13-frozen.log`.

## Follow-up: Instruments connection check

The existing implementation and clean feature checkout were revalidated without another full suite or build. `devicectl device info processes` successfully contacted the paired physical iPhone; this is not a general claim that the device was disconnected. In contrast, `xctrace list devices` twice listed it offline. A process-scoped `Animation Hitches` recording against the existing test app then waited for the device and terminated with exit 13: `Timed out waiting for device to boot`. No completed rendering trace was produced, and M-9 remains unverified. The attempted trace did not change any feature flag. Together with the confirmed absence of an AirPlay receiver, remaining physical acceptance needs an external-state change; it cannot be closed by repeating the passing fixture tests.


## AirPlay hardware follow-up — 2026-09-05

The earlier receiver-availability blocker is superseded: the current Mac was used as a real AirPlay Receiver. M-4 physical v1/default-off AirPlay round-trip acceptance now passes, with one initial user output selection followed by automated Mac → iPhone → Mac and playback/system remote controls. See [hardware evidence](airplay/acceptance.md). Word-by-word flags remain off; this run verifies line-level LRC timing. Other outstanding P13 manual/120-Hz gates are unchanged, and P14 has not started.


## ProMotion configuration follow-up — 2026-09-05

The installed app previously omitted `CADisableMinimumFrameDurationOnPhone`. Apple's [ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays) requires this opt-in for requests above the default rate. The existing supplementary `Sources/SetuIOSApp/Info.plist` now declares the Boolean true. This three-line rendering configuration is a necessary small scope extension for P13's 120-Hz acceptance, not a client cutover flag or playback logic change. The first build-setting attempt did not enter the generated plist; that attempt was removed. The final installed product's plist was inspected and contains true.

Final targeted physical run: `MusicPlayerP13LayoutTests/testWordRenderingAndScrollingCadenceOnDevice`, 1/1 PASS, xcodebuild exit 0. Evidence: `/private/tmp/setu-p13-promotion-2.xcresult` and `/private/tmp/setu-p13-promotion-2.log`. 478 intervals over the four-second word-rendering/scroll workload, device maximumFPS 120, median 8.334667 ms, maximum 12.502 ms, zero intervals above 20 ms. This is approximately 120-Hz callback cadence and **does not prove zero dropped presented frames**. No P0 performance improvement claim. M-9 remains open pending stronger rendering evidence; Instruments still independently lists this otherwise XCTest-accessible physical device offline.

This continuation required two corrective targeted build/test invocations to validate the actual Info.plist artifact. No new Swift full-suite run. All client cutover flags stay false. `git diff --check` passes.


## System acceptance follow-up — 2026-09-05

M-10 actual VoiceOver speech now passes on device. M-12 actual light/dark/light transitions pass for P13 NowPlaying. Home-background playback continuity passes as a partial M-1 check, not a lock-screen pass. See [system evidence](system/acceptance.md) for final case identities, correction history and remaining full-scope gates. No full Swift suite rerun; all client flags remain false.


## Presented-rendering metrics follow-up — 2026-09-05

XCTest system scroll metrics now provide stronger evidence than the earlier display-link cadence: original word rendering reports 5/1/5 hitches across three iterations, so M-9 is **not passed**. The line-only control reports zero hitches; further isolation of P13 rendering is in progress. An async-Canvas experiment failed to eliminate hitches and was reverted. See [diagnostic evidence and failing checker](render/diagnosis.md). Do not treat performance-test execution success as performance acceptance.


## Word mask rendering follow-up — 2026-09-05

The P13 mask now batches its syllable rectangles into a single Path fill instead of repeated Canvas fills. Physical long-text/translation render test and screenshot review pass. The full scrolling workload measured 0/0/1 hitches in the first three iterations and zero hitches in all ten expanded iterations. Observed FPS remains about 82–83, and frame-count telemetry is unavailable; no stable-120-fps or unconditional M-9 PASS is asserted. See [all retained measurements](render/diagnosis.md). Playback, activeIndex and scrolling algorithms remain unchanged.


## Authorized shared-icon AX5 correction — 2026-09-05

The user approved only the one-line MusicIconButton font bound after the M-11 scope conflict was presented. The 44-point target is preserved; the unrelated 管理全部歌单 baseline is untouched. See [AX5 evidence](ax5/acceptance.md). Post-fix search-row device rendering passes 1/1; all six size/width images were reviewed and confirm the authorized overlap correction. Full M-11 coverage is not inferred from this row test. The separate lock-screen attempt did not execute: it waited for device unlock and then terminated with exit 65. CoreDevice still requires a passcode; see system evidence. No lock-screen acceptance is claimed.


## Current follow-up state

Authorized shared-icon AX5 correction committed as `1f353cf`; physical search-row rendering and review pass at both widths and all three text sizes. The phone later unlocked, superseding the lock-state blocker. UI-test execution now fails during XCTest IDE handshake even after scoped automatic runner recovery; see system evidence. Full locked-screen/M-2, M-9 and complete M-11 acceptance remain open, so P13 is not yet claimed MERGE-READY.

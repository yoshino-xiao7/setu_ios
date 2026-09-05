# Music Playback Contract 3.0.0 runtime acceptance — 2026-09-06

This document preserves the analysis after the user requested removal of test-generated files. Raw captures, result bundles, temporary scripts and build products are not long-term deliverables. See cleanup.md for removed and retained paths. No raw artifact is presented as still available after cleanup.

## Frozen Publication

Accepted local architecture commit: `16179163cee0b449bfc12d25df445e2de10a47b8`. The architecture repository has no remote, so the explicit local-baseline exception applies.

3.0 manifest SHA-256: `89e66e779cc3ddd0bdd690e7600fa040daca511daf24e6022f3ac375789188f0`.
2.0 preservation manifest SHA-256: `5c2f732582664f0e4a4fe47ef50c8dd90ca50a9ccfe067416f1ba45167b730e0`.
Frozen verifier PASS. Frozen content and P13 evidence/status were not changed. Backend copied OpenAPI/cases and iOS copied cases were compared byte-for-byte with Frozen. Cases SHA-256: `b38a3cb8396fd1ef42388eac98fc3ae735a502bc2de22d55f311ca2ba5ffce37`.

## Backend Implementation

Op07/Op08 are registered at the actual playback routes. Controller, provider, typed mapper, resolution service and injectable freshness policy reuse the existing `/song/url/v1` transport and shared token. No playback source SWR or provider-deadline invention. Unknown source deadline is nullable in 3.0; legacy success is rejected when its required deadline cannot be established. Trial/preview, malformed data and wrong identity are rejected. Source diagnostics redact URLs.

## Version Negotiation

Absent or exact `2.0.0` selects legacy; exact `3.0.0` selects the new representation. Invalid, empty, duplicate or unsupported selection returns INVALID_REQUEST. HTTP OWS is handled explicitly. Selected versions are echoed, including controlled errors after selection; 401 and negotiation failure do not incorrectly echo. No payload mixes expiresAt with refreshAt/sourceExpiresAt. Private/no-store and Cookie + version Vary are preserved.

## Freshness Policy

Development policy: `setu-freshness-20260905-v1`, 45 seconds. Three actual read-only resolutions at approximately 8.67/45.19/90.03 seconds returned the same source. Resolution times: 8666/187/29 ms. Current and original HTTPS HEAD probes returned 200 audio/mpeg. Source deadline remains unknown, never inferred from these probes.

Calibration analysis is committed in backend `docs/playback-3.0.0/calibration.json`. This is Setu reuse policy, not a provider validity guarantee. Cold resolution approaches the unchanged 10-second recovery budget. Healthy playback is never interrupted by refreshAt or refreshed by a timer. Expired prepared-next is discarded on consumption; a short policy can reduce preparation reuse. The documented 80 vs 40 resolutions/hour comparison is a hypothetical repeated-identity upper rate, not a measured production load.

Only a service drop-in configured MUSIC_PLAYBACK_FRESHNESS_ID and MUSIC_PLAYBACK_FRESHNESS_SECONDS. Rollback is unselected/0 plus normal restart. Timeout, limiter, breaker, token values, real database schema and production deployment were not changed.

## Backend Tests

Final targeted: 36 tests, zero failures/errors/skips (runtime 25, wiring 1, policy 4, auth census 6).
27 actual MockMvc HTTP-serialized JSON bodies passed the Frozen JSON schemas and privacy/cache/Vary checks, using both legacy and 3.0 schema selections. This checks serialization, not merely Java objects.

Feature CI PASS: https://github.com/yoshino-xiao7/setu_api_full/actions/runs/33975708604 at e483dc0cf2ba517353d438ddb8b67713c28404d7. Formal CI includes full Maven tests and isolated MySQL checks. The initial CI failed the newly introduced protected-route census; the census was corrected before merge. No real database migration was performed.

## Backend Master / Deployment

Accepted starting master: 6b3676e46a220cee0d9982226f99e60a80cb6042.
Normal non-force merge master: `8416c3373915dc857b54404449c8e7e5db3f4ba1`.
Development build/deploy PASS: https://github.com/yoshino-xiao7/setu_api_full/actions/runs/33976065786.
Downloaded CI artifact and running service JAR both SHA-256 `49c72f522889cacfb5fd7ea5047a36d1bffd51151fedabfe4cbaa8a768ff195a`. Runtime VERSION matched 8416c33; service active and health UP. Existing development global/FM gates were true. Only the existing authorized development pipeline was used.

A release-directory metadata inconsistency was observed; the runtime binding above uses the running JAR, VERSION and CI artifact hash, not that directory's existence. No unrelated deployment refactor was made.

## Backend 3.0 Smoke

Physical hosted smoke PASS: actual development endpoint, normal Setu auth, actual FM track and playback source. Explicit 3.0 gives playable HTTPS source, refreshAt and required sourceExpiresAt:null, exact response selection and no expiresAt. Default legacy returns 503 UPSTREAM_UNAVAILABLE for this unknown deadline. Invalid negotiation returns 400 INVALID_REQUEST. No URLProtocol fixture was used.

## iOS Migration

P14 candidate continued in yukiryou/music-p14-radio-fm. P9 explicitly selects 3.0 and checks the response selection. DTO requires refreshAt and a present-but-nullable sourceExpiresAt and rejects legacy field mixing. P10 memory cache and prepared/recovery consumption recheck freshness, use monotonic elapsed time to prevent wall-clock rollback extension, reject stale flights/user generations and isolate identity/quality/options/version keys. Failed forced resolution cannot restore stale cache. The existing one forced recovery and total loading budget remain.

Single AVPlayer, queue, PlaybackPhase, prepared-next algorithm, snapshot ownership and FM supply algorithm remain. The DEBUG-only development navigation seam opens the normal FM view with real auth/transport; it is not a fake scenario. Release and persisted client flags remain off.

## iOS Targeted Tests

Final targeted 77/77 PASS. Covers P9 DTO/header, P10 resolver/cache/prepared/recovery, typed identity/user reset and P14 feeder/context behavior. Frozen client-visible boundaries are exercised; the server-only requirement to justify a non-null provider deadline is not fabricated as client-observable evidence.

## P14 Real FM

Actual feeder/controller flow PASS: initial real audio progress, 52 serial user advances with actual playback progress, supply/refill, queue <=50 with final >=45, one Setu-owned block, typed identity, previous/mode/edit restrictions, user reset and reentry. Duration 173.861 seconds. No upstream fm_trash, like, playlist mutation or scrobble was added or called by these probes.

Actual unauthenticated failure path PASS: four HTTP attempts with existing 1/2/4-second backoff, duplicate refill request coalesced. Normal App FM page/control UI PASS after reinstalling the same UI runner to recover automation initialization. The first UI runner initialization timed out before assertions; this was not an App assertion failure.

An initial real playback flow failed to progress; its cause was not conclusively attributed. The diagnostic flow subsequently passed. The live test was corrected to rebind the resolver after user reset, as the normal App does; that correction is not asserted to explain the initial failure.

A separate manual handoff UI test verified actual FM/pause/block controls and retained the page for the user; PASS. The user explicitly confirmed the FM page and that lock-screen previous is unavailable. No separate claim of user-confirmed continuous background audio is inferred from that reply.

Core real FM behavior and lock-screen restriction are established. Complete continuous audio, memory and stall acceptance remains blocked by M-13 below. No request-storm or crash was observed in the successful bounded flows; this is not a long-duration performance claim.

## M-13

**EXTERNAL TOOLING BLOCKER. No M-13 PASS and no P14 closure.**

Normal App PID 18653 on physical iPhone 17, iOS 27.0 (24A5430a), Instruments 16.0 (27A5194q). Animation Hitches + Activity Monitor + Audio Client + Audio Statistics. Deferred mode.

Trace metadata: start 2026-09-06T00:27:22.203+08:00; end 2026-09-06T00:57:23.592+08:00; duration 1801.388688 seconds; end reason Time limit reached. This proves the requested recording window, not valid performance data or uninterrupted audio.

xctrace exited 2 after reporting:
- `Transferred trace file is malformed`
- `GPU Service reported error: Selected counter profile is not supported on target device`

The saved RunIssues database repeats both messages and identifies `Data stream: Time Mapping`. The partially saved trace was approximately 22 MiB and cannot support complete memory/stalls/audio conclusions. No retry or new recording was started after this explicit tool failure.

An earlier name-based attach selected the UI runner instead of the App. It was stopped and excluded (45.801239-second metadata window). The formal attempt used the verified numeric App PID. The auxiliary UI timing test recorded early background/missing-control assertions and is not a PASS; no such assertions recurred after returning the App to the foreground. The UI timer was temporarily paused/resumed while the App continued, to prevent its cleanup from ending the App before the independent 30-minute trace window. Its eventual 18 failures are preserved as auxiliary-run evidence, not hidden or substituted for Instruments data.

Finalization was slow: a measured 2-second sample showed approximately 4 MB arriving, about 2 MB/s; the active raw capture grew to approximately 19.17 GB. A placeholder output directory did not reflect that temporary raw size. Transfer volume explained ongoing activity, but only the final tool error establishes the blocker. No estimate of FPS, ordinary log, XCTest timer or subjective impression replaces the missing valid trace.

## Final Regression

Backend final targeted 36/36, 27 Frozen serialization validations, Frozen verifier and diff checks PASS. Feature CI and master deployment CI PASS.

iOS final targeted 77/77, the single new Swift full 306/306, connected physical build and diff checks PASS. The historical 295 result was not reused. Development used targeted tests; full was run exactly once. Later manual-handoff changes were confined to the UI-test target, passed its build/run and did not modify production or SwiftPM test sources. Several development builds occurred; only the final regression build is labeled final. No artificial one-build-total claim.

The already accepted P14 UI 10/10 was not mechanically rerun; the new real UI/navigation seam was exercised by this Goal's real UI tests. P13 AirPlay, AX5, M-2, M-9 and M-11 were not retested.

## P13 Remaining Evidence

Historical M-9/M-11 blockers and other P13 acceptance status remain unchanged. This document neither closes them nor repeats their acceptance.

## Feature Flags

All production client cutover defaults remain false. Only explicit DEBUG/test process overrides were used for development FM/playback. No token changes, upstream user mutations, real DB migration, timeout/limiter/breaker change or P15 work.

## Commits

Backend implementation: 76a556eaf7081afa6af950839c11d056b484ca17.
Backend census correction: e483dc0cf2ba517353d438ddb8b67713c28404d7.
Backend deployed master: 8416c3373915dc857b54404449c8e7e5db3f4ba1.
iOS production migration/tests: ce7cb9afc669373169845bbd0a13aa9b04e662e8.
iOS verified manual handoff: d1b9f4a06831c0adbfa7956cf6848665550f24ad.
No iOS push/merge or architecture remote publication is invented.

## Status

MUSIC PLAYBACK CONTRACT 3.0.0 DEVELOPMENT DEPLOYED.
BACKEND DUAL REPRESENTATION PASS.
IOS PLAYBACK 3.0.0 MIGRATED.
P14 CORE REAL FM FLOW AND LOCK-SCREEN PREVIOUS RESTRICTION VERIFIED.
M-13 EXTERNAL TOOLING BLOCKER.
P14 IMPLEMENTATION COMPLETE / ACCEPTANCE BLOCKED — NOT CLOSED / NOT FULL MERGE-READY ACCEPTANCE.
CLIENT CUTOVER OFF.

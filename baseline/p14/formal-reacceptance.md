# P14 formal reacceptance — 2026-09-05

## Fixed input

P13 candidate 78b5d84 is unchanged. P14 production implementation 3f18163. Accepted baseline remains targeted 39/39, Swift full 295/295, physical build PASS. This run does not repeat those checks or any P13 acceptance.

## Exact formal requirements

Read only P14 in 11-execution-tasks.md, its directly referenced acceptance rows T-FM-5..10 and G-IOS-1..9, and the manual M-13 definition.

P14 UI: flag=false hides entry; entry starts FM with current/upcoming tracks; block action removes locally and advances if current; previous is unavailable (including lock-screen previous), mode switching is disabled in sequence mode, drawer permits only block rather than queue editing. G-IOS-8 MusicArchitectureUITests and G-IOS-9 MusicCacheUITests are required shared UI guards. RadioFMUITests currently has two implemented cases (entry/default gate + fixture block flow, and FM accessibility layout); these do not alone prove all real FM behavior.

T-FM-5..10: previous capability; remaining <2 triggers exactly one refill with no duplicate in-flight request; head trimming at queue limit 50; sequence/no-edit context; leaving FM stops feeder; finite PlaybackQueue three regression cases preserved.

M-13 exact definition: “FM 连续播放 30 分钟无内存增长异常、无卡顿”. A short run, unit result, callback cadence or absence of crash is not equivalent. No numeric memory threshold is supplied by this row; none is invented.

Real FM must use actual development Backend/upstream supply. Formal P14 requires batch=4, remaining<2 refill, serial requests, 1/2/4-second retry (at most three retries), head trim to 50 retaining played history within the bound, Setu-owned block/current advance, previous/mode/edit restrictions, leaving/stopping and reentry/start, background playback and FM lock-screen previous variant. No upstream user mutation. User isolation and typed IDs are checked in the P14 flows without reopening prior phases.

## Infrastructure recovery

1. Re-resolved Xcode destination and device; paired, booted, developer services available; transport localNetwork.
2. Reinstalled the existing signed test runner without building or changing the App.
3. Ran test-without-building with parallel-testing-enabled=NO and one device destination, selecting only RadioFMUITests and G-IOS-8/9.

Result: 0 test cases executed. Runner stderr: connection peer refused dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface, then “Exiting due to IDE disconnection.” xcodebuild reports “Lost pending connection to the test runner after launch.” Bundle: /private/tmp/p14-reaccept-serial.xcresult; log: /private/tmp/p14-reaccept-serial.log. No product assertion ran; this is infrastructure evidence, not APP FAILURE.

A final distinct USB transport attempt is pending the physical cable connection. No repeated loop, no product changes, no full-suite or physical rebuild, no backend changes, no persisted flag changes.

## Superseding final result

USB confirmed transportType=wired. Same-artifact serial execution succeeded: 9/9 UI cases (G-IOS-8 five, G-IOS-9 two, FM entry/block and AX5 two). A further P14-only control case passed: previous and mode controls disabled, queue has block but no clear/up-next editing. Total newly passed UI cases: 10, failures: 0. The AX5 screenshot is a fixture unavailable-audio state with scrollable content; it does not prove real audio playback or complete viewport coverage. The initial two FM cases alone are not claimed to test playback audio. Raw screenshots stay in local xcresult/attachment output; no unrelated device chrome is added to Git.

The user confirmed https://api.yukiryou.icu as the development endpoint. Real UI probes used the normal app, normal existing session and ephemeral DEBUG NSArgumentDomain overrides, without any -ui-testing fixture arguments. Home displayed “音乐服务暂时不可用”. Two UI probes were SKIPPED, not PASS. A physical hosted integration probe used AppEnvironment.live()/MusicV2Client and existing normal keychain/cookie transport, without overriding URLProtocol or copying credentials. Direct GET /user/music/v2/radio/fm?limit=4 returned HTTP 503, UPSTREAM_UNAVAILABLE, retryable=true. Two diagnostic iterations were SKIPPED. We verified reaching the development backend but did not prove that the backend reached upstream. Zero actual FM tracks were obtained, and zero real block mutations were issued.

No successful real playback was established. Real refill/serial timing/head trim/backoff/block/typed IDs/user switching/background/lockscreen/reentry/no-stall behavior remains unverified; unit/fixture results are not substituted. The 503 is a real service prerequisite blocker, not evidence of a client correctness bug or a memory regression. Backend/server gates/provider configuration were not changed.

M-13: NOT EXECUTED — UPSTREAM PREREQUISITE BLOCKED. Actual continuous FM minutes measured: 0. USB Instruments now lists the physical iPhone online and offers Activity Monitor/Allocations/Time Profiler. Therefore an Instruments tooling failure is not claimed. Neither PASS nor an APP FAILURE can be assigned; labeling this as a tooling-only blocker would misclassify the observed service failure.

Test-infrastructure work only: live probes are archived as .swift.txt and removed from automatic suites to prevent future implicit live requests. FM control test remains. A runner-target build initially triggered dependency/resource work and was stopped; subsequent temporary projects had one test target and zero production dependencies. The App debug dylib (production implementation) hash remained unchanged. The main launcher hash changed during re-signing, so whole-bundle byte identity is not claimed. Regenerated resource sealing was repaired with existing signing metadata; no new production implementation/build acceptance is claimed. No Swift full or P13 tests were rerun. Temporary test projects are moved outside the worktree.

FINAL STATUS: P14 IMPLEMENTED / ACCEPTANCE BLOCKED. UI infrastructure blocker is resolved; actual development FM supply must become available before real playback and M-13 can be measured. This is not SOFTWARE ACCEPTANCE COMPLETE with only tooling evidence remaining. P13, Frozen, Backend and real production flag defaults remain unchanged; no P15.


## 2026-09-06 Playback Contract 3.0.0 runtime supersession

The previous upstream playback prerequisite is resolved by the deployed dual-representation backend and migrated iOS client. New targeted 77/77, the single new full 306/306, physical build, real FM serial flow and real page/control checks passed. The user confirmed the actual FM page and disabled lock-screen previous control. M-13 reached a 1801.388688-second recording window, but Instruments reported a malformed transferred trace and an unsupported GPU counter profile. It is EXTERNAL TOOLING BLOCKER, not M-13 PASS. P14 remains IMPLEMENTATION COMPLETE / ACCEPTANCE BLOCKED and is not closed. See [runtime analysis](../playback-3.0.0/acceptance.md) and [test artifact cleanup](../playback-3.0.0/cleanup.md). Raw current-Goal test artifacts were removed at the user's request after preserving analysis; unresolved older artifacts are listed for later cleanup. P13 statuses remain unchanged.

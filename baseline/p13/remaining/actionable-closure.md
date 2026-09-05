# P13 actionable acceptance closure

Base production commit: b444476. Scope: remaining M-11 App findings and M-2 evidence only. M-9 remains EXTERNAL TOOLING BLOCKER; no Instruments retry. No AirPlay, accepted lock-next, passed-page or basic regression rerun. Full baseline: 286/287 + isolated rerun PASS.

## Remaining finding matrix

| Page | Element | Finding | Attribution | Required action / status |
|---|---|---|---|---|
| Queue | Track title / artist | Forced one-line truncation at AX5 | APP BUG | AX5 multiline layout and complete accessible name/value implemented; physical targeted test waiting for unlocked device |
| Create playlist | Section description | Full screenshot visibly elides explanation | APP BUG | Local vertical ideal-size modifier implemented; corresponding physical test pending |
| Create playlist | Public toggle label | Element-only attachment crops hanging second line; full screenshot shows complete text | TOOLING ONLY: audit bounding rectangle | Retain original audit failure, no Toggle change |
| History | Timestamp Label | Cropped issue attachment omits hanging lines; full screenshot contains complete date | TOOLING ONLY: audit bounding rectangle | Retain evidence; no additional history rerun |
| Search song/album/artist | Search button Label | Audit reports clipping; full screenshot contains all glyphs | TOOLING ONLY: reported clipping not reproduced visually | Retain failure; do not relabel raw audit PASS |
| Typed album/artist, daily/new tracks | Play-all Label | Audit reports clipping; inspected full screenshots contain complete glyphs | TOOLING ONLY for inspected element | No shared control change; earlier audit aborted before remaining viewports |
| Typed playlist | Disabled favorite Label | Actual issue attachment is favorite-disabled text, not play-all; full screenshot shows complete wrapped text | TOOLING ONLY: audit bounding rectangle | Correct prior attribution; no App change |
| Fixed AX5 harness | Dynamic Type switching audit | Fixture pins AX5, font-switch audit unsupported | TOOLING ONLY | Preserve original unsupported result |
| System UI | XCTest idle wait | System animation/idling timeout | TOOLING ONLY | No repeated system-control automation |

Full page/all-state M-11 PASS is not inferred from screenshots or partial viewport audits. Untested modal/state coverage remains explicitly incomplete.

## M-2 evidence required

Formal M-2: lock screen/control center artwork, title and progress display correct; play/pause/previous/next/scrubbing functional. Preserve accepted lock continuation/next and Control Center pause/resume. Remaining: remote previous, remote scrub, displayed artwork/progress evidence. Existing native telemetry reports MPNowPlaying title/artist/progress consistency but not artwork or direct command-receipt events. Source registration alone is not acceptance.

## Production and validation

Only local queue row and create-playlist description layout changes are in progress. No player core or shared design-system component changed. No new full suite is required by this round's instructions. No cutover flag change.

## Post-unlock connection blocker

User confirmed unlock. The waiting queue run and one post-unlock targeted retry both ended before XCTest bootstrapping completed (runner code 74 / IDE disconnection), with no App assertions or screenshots. Neither is recorded as an App failure or PASS. CoreDevice reported transportType=localNetwork. Requested one cable reconnection; no further XCTest retry until connection state changes. Results: /private/tmp/p13-queue-closure.xcresult and /private/tmp/p13-queue-unlocked.xcresult.

Both local production layout changes compiled successfully using build-for-testing (/private/tmp/p13-local-layout-build.log). This is compilation only; their targeted physical acceptance remains pending. No full suite or Instruments was run.

The existing root-player fixture tracks have no artwork URL, so this fixture cannot establish M-2 populated artwork correctness. Preserve this evidence gap rather than treating title/artist consistency as artwork verification.

## Wired targeted runs

After user cable reconnection, CoreDevice reported wired/connected/paired. Queue targeted test executed (p13-queue-wired.xcresult): song title now fully wraps, but audit identified a different actual truncation in the queue caption. Caption now wraps at accessibility sizes; header icons use 20pt glyphs inside existing 44pt frames. Its follow-up p13-queue-caption.xcresult is waiting for unlock after compilation.

Create-playlist targeted test executed (p13-create-wired.xcresult). Full screenshot BBEF492F-5278-48F2-8639-D54D663B013B.png shows complete two-line description; this App finding is CLOSED. Raw audit still fails on public-toggle Label: its element attachment crops the hanging second line, while the full screenshot contains all four characters. No Toggle change or raw-audit PASS claim. Earlier code74 connection blocker is superseded by successful wired test execution.

Manual-remote preparation test gains an opt-in SETU_P13_PREPARE_PREVIOUS branch to select fixture track 7102 in App UI before requesting the missing system previous action. This does not claim a system next or previous PASS, alter remote handlers, or switch AirPlay. Pending build and execution.

## Queue closure

p13-queue-caption.xcresult: testQueue PASS (1 test, zero failures, 19.340s), with all three AX5 viewport audits PASS. Full first-viewport screenshot reviewed: complete caption and song title wrapping, header symbols contained inside retained 44pt targets. Queue App findings CLOSED. Create-playlist description finding already CLOSED with the preceding full screenshot. Known remaining audit bounding/unsupported reports and incomplete viewport/modal coverage remain unwaived; do not call the original failed audits PASS.

M-2 preparation built and ran to READY in p13-remaining-remote-prep.xcresult. Native-console session plays fixture 7102, queue [7101,7102,7103], index 1, one AVPlayer, Speaker route, title/artist consistent, no error. User asked only for lock-screen previous. No command PASS until action confirmation and corresponding telemetry transition. Safe log: /private/tmp/p13-remote-remaining.jsonl.

## Current outcome

All confirmed APP BUG entries in this round's remaining finding matrix are CLOSED: queue song/artist/caption truncation and create-playlist description truncation. Queue targeted audit passed three viewports. Create-playlist full screenshot validates its actual description fix, but the raw test remains failed on the unchanged Toggle Label bounding report. This is not full M-11 PASS: pre-existing tooling reports and incomplete viewport/modal coverage remain explicit.

M-2 remote previous and scrubbing are now evidenced by user-confirmed system actions and continuous native telemetry. Previous: track 7102/index1 → 7101/index0, continuing normally. Scrub: 56.758 → 180.718 seconds, then continuing beyond 197 seconds; identity/queue unchanged, MPNowPlaying elapsed follows playback, lyrics advance, one observed AVPlayer, URL count remains 3 and no error. See remote-previous-evidence.json and remote-seek-evidence.json. Post-previous lock check returned passcodeRequired=false; the lock-screen action is user-reported, not independently inferred from that check. Existing completed locked-playback/next and Control Center pause/resume were not repeated.

M-2 remains BLOCKED specifically on actual populated artwork and system presentation evidence (title/progress telemetry is not a display screenshot). Fixture artwork is absent. Do not invent populated-cover PASS or alter production fixtures merely to relabel this gate.

M-9 remains EXTERNAL TOOLING BLOCKER without retry. Full baseline remains 286/287 + isolated rerun PASS; no new full suite. No player core/shared component/Backend/FINAL/flags changed, no P14 or unrelated baseline fix. P13 IMPLEMENTED / ACCEPTANCE BLOCKED.

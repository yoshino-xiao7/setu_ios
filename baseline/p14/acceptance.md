# P14 — Private FM implementation

## Formal dependency decision

11-execution-tasks.md P14 is the earliest next formal phase. Its required P10 context/coordinator interfaces and P13 queue/player UI are present in the accepted candidate. The dependency graph/order table describes implementation dependencies and recommends P14 after P13 for the drawer branch; it does not require M-9 or M-11 completion. No FINAL/Frozen change or real flag enable is necessary.

P13 is separately preserved at yukiryou/music-p13-merge-ready / 78b5d84. Its status remains IMPLEMENTED / SOFTWARE ACCEPTANCE COMPLETE / EXTERNAL EVIDENCE BLOCKERS REMAIN. P13 evidence and tests are not rerun by this work.

## Implementation scope

RadioFMFeeder calls MusicV2Client directly with limit=4, outside MusicRepository. Its single in-flight task and generation reject cancelled/late responses. Failures and empty batches get bounded 1/2/4 second retries; exhausted empty responses remain retryable rather than terminal or fabricated success. Repeated tracks are retained.

The controller appends and trims already-played entries to the 50-item bound outside PlaybackQueue. FM uses the existing frozen-compatible .radio context, sequence mode, disabled previous commands and no queue editing. Blocking is a Setu POST; only success removes all local occurrences and advances the current track. A session-local blocked set rejects racing refill entries. No upstream fm_trash, legacy fallback or mutation replay is added. Switching to another context stops the feeder; user reset stops its private session.

FM's home entry is hidden while radioFMEnabled=false. The route is gated again at its destination. The page displays current/upcoming tracks and block/retry controls. Player changes only add FM conditionals; layout is retained. DEBUG preview wiring and UI tests use an in-memory flag with fake transport. Production defaults and persisted preferences are unchanged.

project.yml already recursively includes source/test directories; xcodegen regenerated project membership. No change to PlaybackQueue, Repository, URL resolver, NextItemPreparer, P10 collaborators, FINAL/Frozen, backend or migrations.

## Verification

Final targeted tests: 39/39 PASS (FM 8/8, finite queue 3/3). One end-of-phase full native Swift suite: 295/295 PASS. Logs: /private/tmp/p14-targeted-verified.log and /private/tmp/p14-full-once.log. Physical App and test-runner compilation/signing completed. UI execution is NOT ACCEPTED: initial device lock was cleared by the user, but both runner launches exited code 74 before XCTest connection (0 executed tests). The second launch reused the same artifact with test-without-building and selected RadioFMUITests plus G-IOS-8/9. No App UI assertions or screenshots were produced. Logs/bundles: /private/tmp/p14-ui-once.log, /private/tmp/p14-ui-once.xcresult, /private/tmp/p14-ui-final.log, /private/tmp/p14-ui-final.xcresult. Exported diagnostics confirm the testmanager connection succeeded but runner-to-IDE bootstrap failed; no production failure is inferred. Development runs are targeted RadioFM/MusicPlayback tests only. The initial default Swift build encountered sandbox macro access and then a stalled build engine; native SwiftPM is used. An in-progress compile also rejected source edits; that run produced no tests. First completed targeted run: FM 8/8, 37/39 cases passed, two cases reported four failing assertions; original local log retained; ordinary single-track capability guards were then narrowed to FM to preserve legacy behavior. No full-suite rerun is planned.

Physical 30-minute continuous playback/memory evidence (M-13) and real FM background/lock-screen behavior are not inferred from fixture tests. No existing P13 AirPlay, M-2, M-9 or passed AX5 acceptance is repeated.

## Status

P14 IMPLEMENTED / UNIT ACCEPTANCE COMPLETE / DEVICE UI ACCEPTANCE BLOCKED. Not P14 full acceptance or merge approval. G-IOS-1..7 pass through the single full unit run; G-IOS-8/9 and new P14 UI cases are unexecuted due runner bootstrap; G-IOS-10 physical compilation/signing succeeded. M-13 30-minute real FM memory/playback, background FM and real lock-screen previous remain unverified. Real client cutover is explicitly prohibited, so no real flag is enabled to attempt live FM acceptance. No next phase is started. P13 status remains fixed and independent.

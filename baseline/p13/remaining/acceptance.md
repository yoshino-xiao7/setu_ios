# P13 remaining acceptance — 2026-09-05

Scope: M-1/M-2 lock/remote, M-9 Instruments trace, M-11 AX5 pages only. No AirPlay rerun, no full Swift suite, no real flags changed, no P14.

## M-9 — EXTERNAL TOOLING BLOCKER

Instruments listed the physical iPhone online. The existing deterministic `-ui-testing-p13-word-scroll` fixture was launched without code changes. An initial name attachment did not match the process. Using the actual returned PID 14442, Animation Hitches began recording with a 30-second limit. It did not finish normally; a normal interrupt requested stopping, and after over four minutes the process remained in stopping. The task-scoped process was terminated. Final export of the resulting trace failed with `Document Missing Template Error`; no valid timing table was available. This is not a rendering PASS or an App performance failure. No further Instruments retry is planned for this run. Raw incomplete trace stays at `/private/tmp/p13-m9-formal-pid.trace`; logs and final export error use the same p13-m9 prefix. XCTest metrics are not used as a replacement.

## M-11 — in progress

The formal acceptance says all music pages have no overlap at AX5. The inventory is derived from AppRoute and the Music view/presentation files, and includes legacy/discovery Home, history, search song/artist/album tabs, library playlists and legacy detail, typed playlist/artist/album detail, rankings, daily, new tracks/albums, NowPlaying, lyrics, queue, and music modal surfaces (add to playlist, MV, recommended playlist, player menus). The administrative token page is outside client music scope.

The first fixed-AX5 fixture audit included dynamicType; multiple pages returned `Dynamic Type font sizes are unsupported`. The fixture's explicit `.dynamicTypeSize(.accessibility5)` prevents the audit from switching type sizes. This result is retained as a harness limitation, not dismissed as an App PASS. The second matrix audits actual AX5 textClipped and elementDetection and captures each viewport. A successful audit covers only its captured viewport. System idling/timeouts are recorded separately from App audit findings. Full-page completion still requires all inventory entries covered and reviewed.


## Current audit results and limits

`ax5-results.json` records 18 executed case results from the second and additional matrices. History and library-playlist “passes” from the preview host are invalidated because it lacked the actual Root navigation destination; corrected tests now require the destination navigation title before auditing. Search entry was incorrectly queried as SearchField: AX5 source uses TextField with label 搜索歌曲、歌手或专辑. The test locator is corrected. These are test harness faults, not App accessibility failures; corrected cases have been compiled but not yet run.

Typed album/artist/playlist, daily and new-tracks audits report Text clipped. Element attachments reviewed for daily/artist/new tracks identify the shared 播放全部 control; visual glyphs appear complete, so an actual App clipping cause is not yet established. Queue reports a truncated title with ellipsis. These findings remain unresolved, not waived and not labeled PASS. No production fix is made without an established App defect. Discovery Home, rankings, NowPlaying, lyrics and new-albums completed their captured-viewport audits. Whole-page/all-state acceptance is not inferred. Music modal surfaces still lack full coverage. Raw screenshots include unrelated system chrome and remain only in temporary xcresults.

## Lock / remote observation in progress

A native devicectl console launches the existing root-player/lyrics-playback/hardware-audit fixture with v1/default-off routing. No AirPlay switch is performed. A strict JSON whitelist forwards only fixture track/queue/progress/phase/Now Playing consistency, player counts, error and counters; other native output is discarded before storage. The App UI preparation case starts playback and ends without claiming remote acceptance. Native console and the same app session remain active after the case ends, confirmed by current telemetry timestamps. The user has been asked exactly once in this run to lock the phone and press next, then report completion. No completion reply or next-track transition has been observed yet; no lock/remote PASS is claimed. The coordinator source has no per-command event logger, so telemetry is not represented as a direct command-receipt log. Current output: `/private/tmp/p13-manual-remote-telemetry.jsonl`.

Only Tests and acceptance records changed in this run. No production code changes, full Swift suite, AirPlay rerun, real cutover flag or P14 work.


## Confirmed manual lock/next action

The user reported completion of exactly one lock-screen next action. Continuous native telemetry captured track 7101 at 517.05 seconds switching to 7102 at 0.124 seconds, then advancing normally. This is not a natural end (fixture duration 900 seconds). Queue stayed [7101,7102,7103], index changed 0→1, URL fixture requests increased once (2→3), one AVPlayer was observed, title/artist consistency stayed true and no error was reported. A contemporaneous independent CoreDevice check after user confirmation returned `passcodeRequired=true`, while the new track continued advancing in the native log. See `lock-next-evidence.json`. The user action plus the native state transition establishes lock-screen next and continued playback; no additional manual next is requested.

This evidence does not provide a direct remote-command receipt event (the existing coordinator has no event logger), lock-screen artwork validation, remote previous, or remote scrubbing. The aggregate M-1/M-2 gate remains partial; prior accepted control-center pause/resume evidence is retained without rerunning AirPlay.


The user was asked only to unlock after the successful lock/next capture so the remaining App-page AX5 audits can run; the latest check still reports locked. No repeated media action is requested. The corrected AX5 navigation/selector tests compiled successfully in `/private/tmp/p13-m11-navigation-build.log` but remain unexecuted pending unlock.

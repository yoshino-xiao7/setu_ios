# P13 M-9 physical-rendering diagnosis — 2026-09-05

**M-9 is not passed.** XCTest performance test execution returns success without a stored performance baseline; this is not the formal zero-hitch acceptance. `python3 baseline/p13/render/check_metrics.py baseline/p13/render/word.json` returns exit 1 and FAIL for the captured workload.

The workload uses the actual LyricScrollView and WordLyricText, 120 fixture lines with four words each, translation, a progressing clock, and three measured pairs of slow up/down gestures on the physical 120-Hz-capable iPhone. All network/client cutover flags remain off. An explicit DEBUG fixture avoids real library or account data. The test requires `TEST_RUNNER_SETU_P13_RENDER_METRICS=1`.

| Single-variable run | Hitches per iteration | FPS | Evidence |
| --- | --- | --- | --- |
| Original word rendering | 5 / 1 / 5 | 80.555 / 82.680 / 80.622 | word.json |
| Same workload, line-kind control | 0 / 0 / 0 | 82.397 / 82.624 / 82.638 | line-control.json |
| Word Canvas rendersAsynchronously=true | 3 / 2 / 3 | 81.013 / 81.653 / 81.277 | async-canvas.json |
| Word animation paused, same progressing line clock | 2 / 0 / 1 | See paused-word.json | paused-word.json |

These are small diagnostic samples, not a statistical claim of improvement. The async Canvas change was reverted because it did not resolve the symptom. The production word renderer and scrolling algorithm are unchanged by this continuation. Test-only line and paused-word controls remain explicitly named for continued diagnosis.

The metric service reports nonzero FPS and hitch counts but zero frame-count values for every run. Therefore the checker refuses PASS when frame counts are unavailable, even if a control has zero hitches. No stable 120-fps or gapless-presented-frame claim follows from these data. Standalone Instruments still listing the phone offline does not prevent XCTest from collecting these system scroll signpost metrics.

Ranked hypotheses tested/remaining:
1. Synchronous Canvas drawing alone: not sufficient; asynchronous drawing still has hitches.
2. Active-line creation and glyph layout: still to isolate by pinning the active line while preserving word animation.
3. High-frequency word updates plus scrolling: pausing updates reduces the observed count in this sample but does not eliminate it; more isolation needed.

Next diagnosis should keep one variable at a time, use this same failing command/fixture, avoid the forbidden LyricScrollView scrolling-algorithm rewrite, and recheck the full original word workload before accepting any fix. No rendering fix is claimed. No additional Swift full suite was run. Four targeted physical metric invocations were performed; build/test budget deviations remain explicitly recorded.

Result bundles are `/private/tmp/setu-p13-render-metrics-1.xcresult`, `/private/tmp/setu-p13-render-line-control-1.xcresult`, `/private/tmp/setu-p13-render-async-1.xcresult`, and `/private/tmp/setu-p13-render-static-1.xcresult`. Checked-in metrics omit device identifiers and names.


## Follow-up: combined Path mask

Fixed active-line/continuing animation control: 2/5/9 hitches. Active-line changes are not necessary to trigger the symptom. Pausing offscreen word animation via scroll visibility still yielded 3/2/8; that experiment was reverted. CPU diagnostic collection yielded numeric CPU metrics but no exported ktrace in either attachment or diagnostic export, so no call-stack localization is claimed. No memgraph was collected.

The retained change replaces repeated Canvas fills with one combined Path fill plus the same 45%-opacity background, preserving single Text + mask + GeometryReader, cached glyph coordinates, word timing and all scrolling logic. The original full word workload then measured 0/0/1 hitches in three iterations. An expanded ten-iteration run measured 0 hitches, 0 hitch duration and 0 hitch ratio in every iteration. Its FPS values span 82.329–83.227, **not stable 120 fps**. Both datasets are retained in path-3.json and path-10.json; neither earlier nonzero samples nor the unavailable frame-count metric are discarded. The strict existing checker therefore still refuses a full PASS on the zero frame-count field.

Long Unicode/wrapping/translation physical rendering test PASS. The unchanged glyph boundaries and complete mask coverage were visually checked in path-mask-AX5.png. This follow-up establishes a validated local rendering simplification and ten observed hitch-free iterations, not an unconditional zero-dropped-frame guarantee. M-9's remaining measurement limitations are explicit. No other manual gate is closed here.

Production experiments for asynchronous Canvas and scroll visibility were reverted. Only the combined Path mask remains. DEBUG-only diagnostic controls are retained for the unresolved measurements; no production client flag is enabled. No second Swift full suite was run.

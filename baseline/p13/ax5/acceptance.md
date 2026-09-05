# P13 AX5 follow-up — 2026-09-05

The user explicitly authorized only the shared icon correction after reviewing the scope conflict: “允许仅纳入这项 AX5 修复”. The prepared one-line patch is now applied to MusicIconButton in the isolated P13 worktree. The symbol uses a bounded 20-point semibold font and retains its existing 44 × 44-point target. No action, label, navigation, or text scaling changes. The unrelated normal-size 管理全部歌单 hit-region baseline and the original user checkout remain untouched.

Before correction, the three physical hosted layout cases passed their existing dimension assertions in `/private/tmp/setu-p13-ax5-pages-1.xcresult`. All 16 AX5 snapshots at 375/430 points were visually reviewed: playlist, album, artist, daily recommendations, releases, rankings, Home, and search row. The search-row action symbols visibly overlap at both widths. Test execution success does not establish visual acceptance. The fixture-only 375-point before image is `search-row-375-AX5.png`.

The detail/discovery snapshots establish only their captured viewports, not every scroll position or state. The test matrices now retain normal and AX3 sizes and add AX5. Post-correction physical rendering passed 1/1 in `/private/tmp/setu-p13-ax5-fixed-1.xcresult`, xcodebuild exit 0. All six screenshots (375/430 points, normal/AX3/AX5) were visually reviewed: the three action symbols are now separated and contained in their 44-point circles, and text remains independently scalable. Both AX5 after images are retained here. This closes the authorized search-row overlap correction, not every page/state of M-11.

`proposed-icon-scope.patch` is retained as the review artifact; it has already been applied and must not be applied a second time.

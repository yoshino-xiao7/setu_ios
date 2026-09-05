# P13 final evidence coverage

M-2: PASS. See now-playing-display-evidence.json. Current system cover/title/artist/progress/control display verified with physical device screenshots and compared with the same App song. Earlier accepted remote actions retained without repetition.

M-9: EXTERNAL TOOLING BLOCKER. No Instruments retry.

Production exception: a newly audited recommended-playlist detail exposed real AX5 title/description truncation (not a Label boundary artifact). A local expanded-summary option is enabled only by that modal at accessibility sizes; homepage defaults retain two-line summaries. No player core, flags, Backend or FINAL changes.

Full-suite baseline: 286/287; sole failure isolated rerun PASS. No full Swift run or complete UI suite this round.

## M-11 coverage matrix

PASS refers only to the actually audited viewports. APP FAILURE, TOOLING LIMITATION and NOT YET COVERED are distinct; untested states are not relabeled tooling failure. All previously confirmed App findings remain CLOSED. Raw failed audits are retained unchanged.

| Page | Audited | PASS | TOOLING ONLY | Not covered |
|---|---|---|---|---|
| Legacy Home | Yes | 3 viewports | — | Other states |
| Discovery Home | Yes | 3 viewports | — | Other states |
| Rankings | Yes | 3 viewports | — | Other states |
| New albums | Yes | 3 viewports | — | Other states |
| My playlists | Yes | 3 viewports, corrected Root destination | — | Other states |
| Legacy playlist detail | Yes | 3 viewports, corrected Root destination | — | Other states |
| Now Playing | Yes | Player viewport | — | Other states |
| Lyrics | Yes | 3 viewports | — | Other states |
| Queue | Yes | 3 viewports after App fixes | — | Other states |
| History | Yes | Icon finding CLOSED | Timestamp Label boundary report | Later viewports not completed |
| Search songs | Yes | AX5 navigation fixed | Search Label clipping report; complete glyphs in full image | Later viewports not completed |
| Search albums | Yes | AX5 navigation fixed | Same Search Label report | Later viewports not completed |
| Search artists | Yes | AX5 navigation fixed | Same Search Label report | Later viewports not completed |
| Typed album | Yes | — | Play-all Label report | Later viewports not completed |
| Typed artist | Yes | — | Play-all Label report | Later viewports not completed |
| Typed playlist | Yes | — | Disabled favorite multiline Label boundary | Later viewports not completed |
| Daily recommendations | Yes | — | Play-all Label report | Later viewports not completed |
| New tracks | Yes | — | Play-all Label report | Later viewports not completed |
| Create playlist | Yes | Description APP BUG CLOSED | Public toggle multiline Label boundary | Later states not completed |
| Add to playlist modal | Yes | 3 viewports | — | Other states |
| MV modal | Yes | 3 viewports; existing fixture unavailable-video state | — | Other states |
| Recommended playlist modal | Yes | Final scoped summary: 3 viewports PASS | — | Loaded-song state: fixture returned error; other states |
| More menu | Yes | Menu viewport | — | Other states |
| Sleep menu | Yes | Menu viewport | — | Other states |
| Quality menu | Yes | Menu viewport | — | Other states |

Global tooling limitation: fixed AX5 fixture prevents the font-switching dynamicType audit. Actual AX5 textClipped/elementDetection audits are recorded separately. Known Label boundary reports are not retried.

## Classification and execution

New modal batch: 5 PASS, 1 real APP FAILURE (recommended summary's hard two-line limit). The failure screenshot showed actual ellipses in both title and description. It was not waived as tooling. The expanded-summary targeted follow-up passed all three viewports; final scope-only refinement also passed all three viewports (47.937s, p13-m11-recommended-final.xcresult). Raw results remain in p13-m11-final-modals.xcresult and p13-m11-recommended-expanded.xcresult.

All 25 named music pages/modal surfaces in this matrix have now been entered and audited at least once. There are no wholly unattempted named pages in this inventory. This does not imply all data states or scroll positions passed: later viewports behind known Label audit reports, loaded recommended-song content and successful external MV playback remain NOT YET COVERED. Platform sharing/route system sheets are not claimed audited App pages. Existing fixed-AX5 and Label-boundary tooling limitations remain unchanged; no repeated retries of those findings.

Raw system screenshots are kept outside Git because they contain unrelated lock-screen chrome. Their local paths and SHA-256 values are recorded in now-playing-display-evidence.json. User only opened the lock-screen display for M-2 and subsequently unlocked for M-11. No additional playback operations or screenshot upload were requested.

Final status: M-2 PASS; known M-11 APP BUGS CLOSED, tooling and untested-state gaps retained. P13 IMPLEMENTED / SOFTWARE ACCEPTANCE COMPLETE / EXTERNAL EVIDENCE BLOCKERS REMAIN. Final git diff --check PASS. No full Swift, AirPlay, Instruments, or accepted player-action reruns.

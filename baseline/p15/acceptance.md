# P15 — iOS 用户库：喜欢歌曲与收藏歌单

## Formal phase and dependency

Authority: `docs/music-architecture/11-execution-tasks.md`, complete P15 section.
P15 is the earliest unfinished, non-superseded formal phase after P14. Its development prerequisites are accepted P7 and P11. P14 M-13 evidence is not a development prerequisite. No additional phase has been started.

Base: accepted P14 / Playback Contract 3.0 commit `9252339`.
Branch: `yukiryou/music-p15-library`.

## Implementation boundary

- Reuse accepted P9 data layer, P10 playback architecture, typed playback identity, Playback Contract 3.0, P11 details, P12 Home and P14 FM.
- Add per-account library/liked/saved resources and relation-preserving pagination. A nullable snapshot never erases the relation or prevents removal.
- O(1) liked/saved lookup. Missing IDs are unknown until the complete relation list is read; Home previews do not establish absence. Heart surfaces prepare membership before enabling a toggle.
- Optimistic likes/saves precede the mutation response. Failure restores the previous local state and reports an error. One foreground PUT/DELETE per toggle; background GET reconciliation never retries a write or falls back to v1.
- Invalidate all visited library page keys and Home after writes. Resource revisions reject stale reads; session generations reject old-account completions. Clear all library state on account change.
- Add liked and saved list pages, Home routes, optional song-row hearts, canonical NowPlaying heart and provider-only playlist save button. Existing legacy playback identities are not guessed into canonical IDs.
- Move MusicHistoryView and MusicPlaylistsView into Library byte-for-byte, without logic changes.
- Test-only preview transport hooks enable isolated P15 fixtures. They do not change persisted or real client flags.

MusicResource, MusicStore.write, MusicPlaybackController, Playback/, P14 FM, MusicRepository and backend FINAL/Frozen are unchanged.

## Verification

Final results are recorded in `verification.json`. Mock transport/UI validation and connected physical-device build are distinct evidence. No real user-library cutover is performed.

## M-13 deferred evidence

P14 SOFTWARE ACCEPTANCE COMPLETE.
P14 M-13 EXTERNAL EVIDENCE REMAINS / EXTERNAL EVIDENCE BLOCKED.
The approximately 30-minute capture ended with a damaged Instruments trace. It proves neither a memory/stall/audio continuity defect nor an M-13 PASS.

This P15 goal does not retry M-13. For a future dedicated evidence run, first record only 1–2 minutes and confirm normal Stop, saved file, successful reopening, and readable memory/stall/audio data. Only after that short trace succeeds may the formal 30-minute capture start.

All real client cutover flags remain false. No P16 work, irreversible migration, backend changes, or repeated P13/P14/Real FM/AirPlay acceptance.

### Verification sequence and bounded corrections

The single Swift full suite passed 312/312 and the single connected iPhone build passed. Subsequent UI verification found two P15-only issues: the saved-list cancel button also activated its row navigation, and page tasks keyed by an unobserved session token could fail to restart after account invalidation. The final code uses an independent borderless cancel button and observable userID task keys. These UI corrections are covered by final targeted Swift/UI tests and the final simulator app build. Per the goal's explicit one-run limit, the full Swift suite and connected-device build were not repeated after these corrections; they are not represented as exact-final-tree rebuild evidence.

The initial small-screen XCTest run was interrupted after prolonged accessibility queries, and the concurrent 430pt launch did not enter testing. Completed checks were retained; unfinished guards were run sequentially on the existing 390pt simulator. Final 375/430pt layout evidence comes from hosted UI screenshots, including the complete liked page, not an inferred device-size claim. No unrelated baseline test or UI was changed.

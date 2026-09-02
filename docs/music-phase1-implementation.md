# Music Phase 1 implementation

Scope: Cache First / SWR only. The approved plan is the workspace-level
`docs/music-performance-optimization-plan.md`. No player engine, URL resolver,
search UX, image decoding/cache, lyrics, Mini Player layout or backend changes.

## Data ownership

- `MusicRepository` is a Core actor with typed endpoint keys, an in-memory cache,
  injected time, shared in-flight tasks and revocable request tickets. Invalidation
  prevents a late response from repopulating a revoked key, even at the same timestamp.
- `MusicStore` is MainActor/Observable and owned by RootAppView. Views and sheets
  share it via the SwiftUI environment. History paging lives here without adopting
  Phase 5's PagingController migration.
- `MusicResource<Value>` separates value, error, isRefreshing and fetchedAt. Its
  LoadState projection always chooses an existing value first. Both refresh failure
  and an in-progress refresh retain content. View cancellation does not cancel
  shared data work; mutation invalidation and user reset revoke it.
- A user change synchronously clears all resources and swaps repositories before
  asynchronously cancelling the previous repository. Read and write completions
  are checked against the account generation. Playback entries also check the session
  token after URL resolution so a late old-user result cannot write new-user history.

## Cache policy

| Resource | TTL |
| --- | --- |
| Hot search / daily recommendations | 30 minutes |
| Recommended playlists / new songs / recommended playlist tracks | 10 minutes |
| User playlists / playlist detail | 5 minutes, plus exact write invalidation |
| History pages / history count | 60 seconds, plus playback / clear invalidation |

Fresh resources issue no GETs. Stale resources retain content while revalidating.
Explicit pull-to-refresh bypasses TTL but joins any already-running request.
The 5-minute and 60-second fallback TTLs make the plan's unspecified SWR fallback
concrete; daily recommendations use the permitted 30-minute option.

## Mutations and current-source adaptations

Successful mutations update only the affected in-memory list/detail and invalidate
only related repository keys. Creation, editing, deletion and song removal do not
reload the page. Batch operations retain each successful local update if a later
item fails. The three picker sheets remain separate and share the same playlist
resource; consolidating their UI is deferred to Phase 5.

The current backend has two relevant contract details not covered by the plan:

1. `DELETE .../songs/{songId}` actually deletes the playlist relation record `id`,
   not the upstream music `songId`. Store removal uses the relation ID.
2. Editing a playlist returns `"ok"`, not a playlist object. MusicClient now decodes
   that acknowledgement; Store applies the submitted metadata locally.

Adding a song also returns only `"ok"`. A local row uses a negative placeholder ID;
if removed before a detail refresh, Store first resolves its server relation ID.
This is one targeted detail GET, not a page reload or global invalidation.

History uses the backend's songId de-duplication and 50-record cap, immediately
prepends a local record, then reconciles count/IDs/order in the background. Search
has only its history-write call routed through Store; its UI/state remain Phase 3.
Recommended playlist sheets also retain track resources, without changing rendering.
Preview hosts inject Store so existing previews and UI fixtures keep working.

## Verification

Tests cover cache hit/expiry, force refresh, in-flight sharing, cancellation,
precise invalidation, old responses after reset, cold loading, SWR failure,
zero repeat home requests, retained detail resources, successful/failed mutations,
history paging, optimistic history and user switching. New UI tests exercise
home → search → back and playlists → detail → back → detail.

Store access timing is tested against 100 ms. This is not a physical-device
first-frame measurement. UI tests check content at navigation completion; they do
not inspect every rendered frame or replace production-domain packet capture.

Build/test results and remaining acceptance limitations are reported in the task.
Next phase: Phase 2, player and track transitions; it is not implemented here.

## Executed acceptance (2026-09-02)

| Check | Result |
| --- | --- |
| Baseline `swift test`, before changes | 120 tests, 0 failures |
| Final `swift test` | 134 tests, 0 failures |
| Final `swift test --filter Music` | 34 tests, 0 failures |
| Simulator App build | Passed; final iOS test build also passed |
| iPhone 17 Pro / iOS 27: all `SetuIOSAppTests` | 136 tests, 0 failures |
| `MusicCacheUITests`: home/search/back and detail reentry | 2 tests, 0 failures; screenshots reviewed |
| Existing music quality / AX5 UI cases in `UXFlowUITests` | 2 tests, 0 failures |
| `git diff --check` | Passed |
| 375pt / 430pt QA simulator checks | Not completed: Simulator Service Hub connection/install failure |

No tests were deleted, skipped, or weakened. The failed-mutation fixture uses an
actual HTTP 400 response. UI tests use a stable playlist-row identifier and a
configured successful search response, verify the query/results, then require
cached content immediately after returning (without waiting for content to load).

Empty-cache creation has an explicit regression: the server-returned new playlist
is immediately visible, and the previously unknown list is reconciled silently.

Final local evidence:

- `/tmp/setu-phase1-final-unit.log`
- `/tmp/setu-phase1-final-music.log`
- `/tmp/setu-phase1-final-build.log`
- `/tmp/setu-phase1-unit-final.xcresult`
- `/tmp/setu-phase1-navigation.xcresult`
- `/tmp/setu-phase1-accepted-screenshots/`

Physical-device first-frame timing and production-account API behaviour have not
been measured. The 100 ms assertion covers Store access, not physical rendering.

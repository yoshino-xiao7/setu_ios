# Music Phase 2 implementation

Scope: player and track transitions only. This builds on the completed Phase 1
Store/Repository/Resource implementation; those files and their tests are unchanged.
No search redesign, image cache, lyrics optimization, Mini Player placement changes,
APIClient/AuthSigner changes, or backend changes are included.

## Playback ownership

`MusicPlaybackController` lazily creates one AVPlayer. Pause, seek, track changes,
quality changes and stop retain it; stop clears its current item. Each replacement
removes the old item's KVO and NotificationCenter registrations. Queued callbacks
check the observed item's identity before acting. The periodic time observer and
player timeControlStatus observer are registered once. Remote command targets are
retained as tokens and removed on controller destruction.

Views call `play(track:in:queueName:playMode:)`. URL selection, preferred-quality
fallback, preparation and recovery are controller/resolver responsibilities. The
old explicit-quality closure is retained as a narrow test injection seam; the app
shell injects a PlaybackURLResolver object, not a controller-capturing closure.
Direct URL playback remains available for local playback fixtures.

Audio session category is configured at first playback by a private serial
PlaybackAudioSession actor. Blocking category/activation calls run off MainActor;
ordinary transitions reuse the activated session, and interruption recovery
activates it again. Pending activation is checked against the current item and
intent before it can start playback.
Headphone/Bluetooth removal still pauses. An interruption only resumes playback
when it was playing before the interruption and the system permits resumption.
Physical-device audio routing and background behaviour still need hardware checks.

## URL resolver

`PlaybackURLResolver` is a Core actor. Network requests stay off MainActor and use
MusicClient/APIClient. Cache and in-flight keys include track ID, requested quality,
and fallback policy, so explicit quality changes cannot accept an earlier standard
fallback. Each cached value includes URL, effective level, resolvedAt, expiresAt,
and fallback notice. Nothing is written to disk.

Lifetime is `max(0, min(expi ?? 600, 600) - 5)` seconds. The 5-second margin avoids
using an address on its expiry boundary. Missing expi uses the plan's 10-minute
cap. Force refresh bypasses cache while sharing an already-running matching request.
Reset cancels requests, revokes the generation and clears cache. A cancelled waiter
cannot cancel another consumer's shared work.

MusicClient accepts comma-separated IDs. Current backend evidence:
UserMusicController.getUrl accepts String id; MusicCatalogService.playableUrl
forwards it; NeteaseProxyService.proxyPlayableUrl forwards /song/url/v1 and annotates
each array member. No backend modification is needed. Resolver matches every
response and fallback by MusicUrlItem.id, never array position. Missing IDs fail
independently. VIP/TRIAL/region/copyright restrictions do not trigger repeated
resolution. Other unavailable preferred sources can fall back to standard once.

The resolver supports batched calls. Normal cold playback intentionally resolves
only the requested track; next-track resolution waits for current playback to be
stable. This preserves the user's stronger current-song-first requirement rather
than eagerly sending a current+next batch at every initial play.

## Queue and next item

PlaybackQueue owns tracks, index, mode and a pending random target. Random mode
selects once and uses that same target for preparation and the actual next action.
Play Next can override the pending random target. Queue edits reconcile the next
item; single-repeat mode reuses the current item and does not prepare another song.

NextItemPreparer owns at most one prepared item and one preparation task. It resolves
the next URL, awaits AVURLAsset.isPlayable, creates AVPlayerItem, and sets a small
10-second preferred forward buffer. It does not create another AVPlayer. Asset
playability is metadata preparation; it does not guarantee the entire audio buffer
is already resident before replacement.

Preparation starts from current-item likelyToKeepUp, with a 5-second fallback only
when the current player is actually playing. A hit requires matching track and
requested quality, an unexpired URL, and an item that has not failed. The controller
then replaces the exact prepared item without resolving its URL. A miss uses the
normal resolver path (which can still hit URL cache). Failure of speculative work
never changes playback error/UI. Seek preserves preparation. Direct selection,
changed targets, queue clearing, quality changes and user reset invalidate it.
Resuming a paused item also re-arms preparation if it is already stable.

## Recovery and concurrency

Buffering derives from timeControlStatus and item status, not advancing currentTime.
Initial `.failed` and failed-to-end notifications share one recovery path. Network /
AVFoundation failures or an expired address can force one fresh resolution and item
replacement. A second failure publishes a recoverable error and stops buffering.
An item loading episode has a total 10-second budget, including silent recovery;
a first unresolved item can trigger recovery after 5 seconds. Repeated stalls also
produce a visible error. User retry starts a new explicit attempt. No retry loop.
Queue advancement still probes past URL-level unavailable songs; exhausted item
recovery retains the current song with an error rather than silently hiding it.

Every new playback intent has a generation. The queue target is committed before
awaiting, so quick next taps progress from the last selected target. Late resolve,
quality, recovery, seek-completion and item callbacks cannot restore an older song.
Owned preparation, recovery and restored-play tasks are cancelled/revoked when
superseded. Pause during resolution stays paused when the response arrives.

User changes synchronously revoke controller state and replace the resolver, while
RootAppView retains Phase 1's synchronous Store reset. History is an asynchronous
Store write, not part of playback latency. Concurrent history writes for the same
track are coalesced, old-user tasks are cancelled, and Phase 1's request-generation
checks still reject late local updates. Playlist play-count writes are also off
the start-play path.

Snapshots are throttled to 15 seconds during playback. Encoding runs in a utility
task, and a per-user revision check prevents a superseded encoding from overwriting a newer
snapshot or cancelling another user's pending snapshot. Explicit pause/seek/queue edits enqueue a snapshot immediately.

## Instrumentation and verification

OS signposts: TrackTransition interval, PreparedItemHit event, TrackPlaying event.
For a physical-device trace, measure a user next action whose interval contains a
PreparedItemHit and ends at TrackPlaying; exclude interrupted/failed intervals.
Use the Network track or a proxy to verify no target-track /user/music/url request.
No URLs, account IDs or authentication material are logged.

Tests cover ID order/missing members, fallback/restrictions, TTL/force/quality keys,
in-flight batch/single sharing, reset/cancellation, player identity, exact prepared
item reuse with zero transport calls, queue edits/random/loop/single, seek retention,
quality invalidation, rapid skips/direct selection, user isolation, asynchronous
history/coalescing, pause during resolution, initial AVPlayerItem failure, one-shot
recovery and late/failed preload. Gates and expectations are used instead of fixed
sleeps. Existing Phase 1 and quality tests are retained unchanged.

Real production
Wi-Fi/high-latency/offline routing, lock screen/background/Bluetooth behaviour and
the <=300ms prepared-next target require a device/network trace; local fixture
tests are not presented as that measurement.

## Final verification

- Before Phase 2: `swift test --filter Music`: 34 passed, 0 failed.
- `swift test`: 165 passed, 0 failed (including 31 additional cases).
- `swift test --filter Music`: 65 passed, 0 failed.
- Full iOS Simulator app build passed; final iOS test invocation also rebuilds the app.
- iOS unit tests: 167 passed, 0 failed.
- MusicCacheUITests: 2 passed; existing quality/AX5 UI tests: 2 passed.
- No skipped/expected-failure tests, deleted tests or weakened assertions.
- Final diff review compared against a saved Phase 1 snapshot, not only HEAD.
  Phase 1 Store, Repository, tests and destination navigation are byte-identical.

Final accepted evidence (2026-09-02, iPhone 17 Pro / iOS 27 Simulator):

- `/tmp/setu-phase2-accepted-unit.log`: 165 passed.
- `/tmp/setu-phase2-accepted-music.log`: 65 passed.
- `/tmp/setu-phase2-build.log`: full simulator build passed.
- `/tmp/setu-phase2-accepted-ios.log` and `.xcresult`: 167 unit + 4 UI = 171 passed,
  0 failed, 0 skipped, 0 expected failures; final app build included.
- `/tmp/setu-phase2-accepted-summary.json`: machine-readable result summary.
- `/tmp/setu-phase2-only.diff`: review delta against the saved Phase 1 state.

An earlier result bundle exposed synchronous AVAudioSession main-thread diagnostics.
Activation was moved to the serial actor, and the complete unit/Music/iOS/UI suite
was rerun. The final result has no audio-session main-thread diagnostics; only the
pre-existing AuthSession test QoS warning remains. Compiler output has no new Swift
warnings; the existing AppIntents metadata notices remain.

The existing UI design was retained; exported music player and playlist detail
screenshots were reviewed. No physical next-to-playing timing was measured.
According to the plan's priority section, the next phase is Phase 4 (image caching).
It has not been started.

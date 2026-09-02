# Music Phase 4 implementation

Scope: image memory caching, coalescing, decoding, artwork and average color only.
Phase 1 Store/Repository/Resource and Phase 2 playback engine, queue, URL resolver,
next-item preparation and their existing tests remain unchanged. Phase 3 and 5
have not started.

## Shared loading path

The existing SetuRemoteImageLoader moved from SetuRemoteImage.swift into its own
component file. It remains the single image loader for ordinary remote images,
music rows, Mini Player, full-screen artwork and Now Playing. No dependency was added.

Old: view task → URLCache/network → Data → UIImage(data:) → view state.
New cold path: view task → shared flight → URLCache/network → background ImageIO
thumbnail and eager bitmap rasterization → decoded memory cache → view state.
New warm path: view body → synchronous thread-safe memory query → first-frame image.

SetuRemoteImageState is local to each view. The infrastructure cache is not
Observable. A freshly constructed view queries memory synchronously before its
.task can run. A changed key cannot display the previous key's local image.
Existing frames, clipping, corner radii, retry actions and placeholders are retained.

## Keys and memory budget

SetuImageKey contains canonical URL and SetuImageSize. Scheme/host case and URL
fragments are normalized; meaningful query parameters remain part of identity.
Music URLs reuse secureURLString and rewrite Netease's size parameter to the tier.

Four finite maximum-pixel tiers: thumbnail 200, medium 400, large 1200, fullScreen
3072. Ordinary views select the next tier covering max(width, height) × displayScale.
A 54pt row at 3x uses 200; a 100pt cover uses 400; a 360pt player cover uses 1200.
Unconstrained generic full-screen images use 3072. Explicit lock-screen music
artwork uses large, shared with Now Playing and average color.

NSCache stores an immutable wrapper containing the rasterized CGImage and its
UIImage/NSImage. Cost is bytesPerRow × height, including actual row padding.
The image cache has a 64 MiB totalCostLimit and countLimit 200; the tiny color-result
cache also has countLimit 200. NSCache eviction is advisory, not an exact process
RAM ceiling. Visible views, Now Playing, URLCache, transient decode buffers and
Core Image can hold additional memory.

A lock coordinates synchronous queries and generation-checked insertion. An iOS
memory warning clears image/color caches and changes the generation; already
running work cannot refill the cleared generation. It does not touch MusicStore
or playback state. Evicted data can be decoded again from URLCache or downloaded.

## Disk and transport

Retained the existing URLCache (64 MiB memory, 256 MiB disk, SetuRemoteImageCache)
and returnCacheDataElseLoad policy. No self-managed disk directory or disk LRU.
A URLProtocol test seeds a CachedURLResponse and proves that clearing decoded
memory and reloading performs zero network calls. This verifies the URLCache
layer, not physical disk persistence after process restart.

Real music CDN response headers and persistence still require a real image URL /
network or Proxyman verification. Preview fixtures intentionally omit remote
artwork, so they do not establish CDN Cache-Control behavior.

## Decode, coalescing and cancellation

Task.detached(priority: .utility) performs data access and decode. ImageIO uses
ShouldCache=false for the source, CreateThumbnailFromImageAlways,
CreateThumbnailWithTransform, ThumbnailMaxPixelSize and ShouldCacheImmediately.
A CGContext rasterization produces a ready bitmap before UIImage creation; the
original full-resolution UIImage(data:) path is removed from display loading.
The existing original-image export/save path is intentionally unchanged.

An actor owns one flight per key, shared by download and decode consumers. Flights
are removed on success/error; failures are not cached. The existing one transport
retry remains bounded. A failed decode drops a possibly corrupt URLCache response
so a later user retry can recover.

Cancelling one consumer does not cancel a shared transfer needed by another.
After shared completion, cancellation is checked before delivery. Per-view key
and revision checks prevent A from overwriting B after reuse. An abandoned
transfer may complete and benefit the cache; no task captures the loader itself.

## Now Playing and color

Now Playing synchronously reuses a large cached cover, or joins the shared loader.
Delivery checks track ID and cover URL before assigning MPMediaItemArtwork.
Playback engine, buffering, recovery and queue code are untouched.

The full-screen player's average color uses the same large decoded bitmap.
A shared CIContext renders CIAreaAverage on a background task. Both color flights
and resulting RGB values are keyed by artwork identity. The screen keeps only its
own keyed color and uses the existing soft-pink fallback on failure.

## Verification

Music baseline before changes: 65 passing tests. App build succeeded using Xcode
27 beta / iOS 27 simulator. Final iOS unit run: 183 passed, 0 failed, 0 skipped,
including 16 image tests. Music regression remains 65 passed.

Evidence: /tmp/setu-phase4-build.log, /tmp/setu-phase4-music.log,
/tmp/setu-phase4-final-unit.log and /tmp/setu-phase4-final-unit.xcresult.
The latter includes first-frame image attachments and a Now Playing integration
test that verifies synchronous MPMediaItemArtwork assignment from the large cache.

The first image test attempt exposed a test-server expectation being notified on
each retry; the one-shot notification was corrected. The first iOS rendering run
exposed mismatched Device RGB/sRGB fixtures; explicit sRGB fixed the fixture while
retaining all original channel thresholds. The final 183-test run passes.

No new Swift compiler warnings. Xcode emits its existing AppIntents metadata
notice; the final result bundle reports an existing AuthSessionTests QoS warning.
iOS 27 simulator ImageIO also emits CVPixelBuffer fallback messages while decoded
pixel and orientation assertions pass; physical-device behavior remains unmeasured.

The new image tests cover memory miss/hit/network count, normalized and tiered
keys, 10 concurrent consumers, decode/HTTP failure recovery, URLCache reuse,
memory clearing during an active load, EXIF transform, actual thumbnail pixels,
background decode/color work, local-view cancellation and A→B identity. iOS also
checks memory-warning clearing and synchronous first-frame pixels using
ImageRenderer at cover sizes derived from 375pt and 430pt layouts.

First-frame fixtures and sampling use explicit sRGB; device-dependent RGB spaces
must not be compared as though they contained raw sRGB channel values. Test
assertions are retained. No sleeps, skipped assertions or production workarounds
are used to make these tests pass.

Existing fixture UI tests validate navigation and layout, not live music CDN
images. Physical-device Instruments/Allocations/Network/Core Animation, 100-row
60fps, real peak memory and whole-page placeholder timing are separate checks
and must not be reported as automatically passing.

## Final checks and existing UI failures (2026-09-02)

| Check | Result | Evidence |
| --- | --- | --- |
| App build | PASS | /tmp/setu-phase4-build.log |
| Full SwiftPM suite | 178 passed, 0 failed | /tmp/setu-phase4-accepted-swift.log |
| Music filter | 65 passed, 0 failed | /tmp/setu-phase4-music.log |
| Full iOS unit suite | 183 passed, 0 failed, 0 skipped | /tmp/setu-phase4-final-unit.xcresult |
| Image tests | 13 macOS / 16 iOS passed | SetuRemoteImageCacheTests |
| Full existing UI suite | 33 passed, 4 failed, 1 existing opt-in skip | /tmp/setu-phase4-all-ios.xcresult |
| Explicitly enabled live public-image UI | 1 passed, 0 skipped | /tmp/setu-phase4-live-ui-main.xcresult |
| Welcome snapshot recheck, final Phase 4 build | 1 passed | /tmp/setu-phase4-welcome-recheck.xcresult |
| Phase 2 snapshot, same four failed UI cases | 3 failed identically, welcome case passed | /tmp/setu-phase4-baseline-ui.xcresult |
| git diff --check | PASS | Final working tree |

The initial all-iOS result also contains the now-fixed sRGB fixture failure. The
separate final 183-test unit run is the authoritative unit result. No production
source changed after the successful App build and unit run.

Across all 38 existing UI cases, 35 now have a passing execution and three retain
reproduced baseline failures. The full UI gate is not green:

1. RandomImageConsumptionUITests.testFirstHighResolutionOpenRequiresExplicitPointsConfirmation:
   line 22 expects the old “同一张图片重复查看不会再次扣分” copy; the unchanged
   view says “已解锁图片在本次浏览中再次查看不扣分”.
2. UXFlowUITests.testTwoAssetsApplyAndReturnWithNames: the asset picker does not
   open and “使用 电影感光影” is absent. The Phase 2 snapshot fails at the same
   scroll/tap assertions with the editor still visible.
3. UXFlowUITests.testUnauthorizedMainRoutesReturnAfterLogin: the music route does
   not show the expected “重新登录” control. The same Phase 2 build reproduces the
   music assertion and missing-button failure.

WelcomeFlowUITests.testSignedOutLaunchLeadsWithValueAndNativeAuthenticationChoices
initially failed while enumerating an accessibility snapshot, then passed on both
the Phase 2 snapshot and the final Phase 4 build with unchanged assertions. This
initial suite instability is retained in the record; a single rerun is not proof
that the whole UI suite is consistently stable.

The existing live test was enabled using an ephemeral xctestrun configuration,
not by editing its skip condition or assertions. A secondary simulator had an AX
initialization timeout; on the established main simulator the test actually ran
and passed (real public-image loading, preview and closing). Its screenshots were
visually inspected. This is not a music-CDN cache-header or request-count test.

The baseline was an isolated copy of the exact pre-Phase-4 source snapshot at
/tmp/setu-phase2-review-base, including the uncommitted Phase 1/2 work. It was built
under /tmp/setu-phase4-ui-baseline. Current-source UI tests are unmodified. Final
Phase 4 binaries were restored to the main simulator by the welcome recheck.

## Acceptance and remaining limits

- PASS: decoded memory cache, synchronous first-frame pixels, same-key repeat
  network count 0, 10 consumers sharing 1 transfer and 1 decode, URL/tier isolation,
  real downsample dimensions and EXIF transform, stale view delivery protection.
- PASS: Now Playing synchronous large-artwork reuse, background average-color
  calculation/cache, finite cache budget and iOS memory-warning clearing.
- PASS: prior Music unit tests and home/search return, playlist detail re-entry,
  Mini Player tab/layout, default/AX5 player quality UI regressions.
- FAIL (pre-existing): the three full-suite UI gates listed above. No test or
  unrelated business behavior was changed to hide them.
- Not automatically verified: actual music CDN Cache-Control, cross-process disk
  persistence, physical-device peak memory, Instruments main-thread traces,
  whole-page remote-cover timing, recycled 100-row search scrolling and 60fps.
  ImageRenderer covers the actual image components at 375pt/430pt-derived sizes;
  fixture navigation tests have no real music artwork and cannot prove these
  whole-page performance measurements.

Self-review compared the Phase-4-only diff against the saved Phase 2 snapshot.
Exactly eight files changed, including the generated Xcode project and this doc.
MusicStore, MusicRepository, PlaybackURLResolver, PlaybackQueue, NextItemPreparer,
MusicSearchView and RootAppView remain byte-identical to that snapshot. Controller
changes are confined to artwork loading/assignment. There is one shared image
loader; per-view observation remains local. No third-party dependency, custom
disk cache, search redesign, player-engine changes or Phase 5 cleanup was added.

## Next phase

Per the plan's priority order, Phase 3 (search) is next. It is not part of this change.

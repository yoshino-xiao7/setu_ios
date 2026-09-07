# Music audio cache

The player, next-item preparation and precise-seek preparation share one byte store.
Normal playback does not wait for a complete file. `CachedAudioAssetFactory` attaches
an asset-lifetime lease and an `AVAssetResourceLoaderDelegate`; the store fetches
missing 256 KiB ranges and coalesces overlapping reads. A server returning 200 can
feed the player before its full response finishes. No signed URL is saved in the
catalog or emitted by cache diagnostics.

## Settings and storage

“My account / Music cache” defaults to 1 GiB, with 256 MiB, 512 MiB and 2 GiB options.
Speculative work defaults to Wi-Fi only; Off and All networks are available. Low
Data Mode and playback buffering suspend speculative work. Settings/network changes
cancel the old preparation and re-evaluate the next target. Actual playback reads
can still be cached when speculative work is off.

The quota includes parts, complete files, the catalog, assembly scratch space and
remaining v1 cache files. Accounting is incremental, with directory reconciliation
at startup. LRU eviction skips leased sources. Clearing marks leased entries for
removal when released; capacity reductions can temporarily retain those leases.
Writing is disabled rather than interrupting playback when storage is unavailable.
Legacy complete audio is imported on a matching account/song/requested-quality key;
it is never spliced into a new partial stream. Actual response quality is recorded
separately. A refreshed URL requires a matching strong ETag and length to reuse
partial data; otherwise partial bytes are discarded.

## Seeking

Recognized MP4/FLAC containers and a structurally consistent MP3 Xing byte/TOC index
can use direct AVPlayer seeking. Missing or contradictory VBR indexes use complete,
precisely indexed audio, assembled from the same downloaded parts. Concurrent
foreground/background assembly shares one job. The selected time is committed only
after AVPlayer confirms it; synthetic audio tests also verify the decoded segment.
During preparation the original item keeps playing. Cancel/replace operations revoke
the pending intent. Restored playback offers cancellation and an explicit start-over
action instead of silently resetting its position.

A source without a trustworthy index or usable byte ranges can still need significant
preparation for an uncached seek. Cache size cannot remove source-resolution latency
or guarantee a particular network startup time.

## Verification

Run `swift test --filter 'MusicAudioCacheTests|MusicSeekTimingTests|MusicPlaybackControllerTests|PlaybackSnapshotStoreTests|NowPlayingCoordinatorTests'`.
The fixtures contain generated tones/noise. `scripts/generate-seek-timing-fixture.py`
creates the VBR fixture; `scripts/add-seek-fixture-index.py` creates its indexed peer.
UI coverage is `MusicCacheSettingsUITests`, at the default font size, including the
mini player. Regenerate the Xcode project with XcodeGen after adding sources.

For explicit, development-only physical-device measurements launch with
`-development-cache-benchmark`. This requires a signed-in saved track and Wi-Fi
prefetch permission. It samples cold, warm, restored and prepared-next playback ten
times each using up to two tracks from the saved queue. It does not submit listening
history or persist intermediate playback positions, and restores the original
position afterward. Results are written to `Documents/music-cache-benchmark.json`.
The measured endpoint is AVPlayer entering playing state; it is not a microphone
measurement. Build/install success does not establish the P95 acceptance targets.

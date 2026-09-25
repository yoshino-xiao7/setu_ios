import AVKit
import os
import SetuIOSCore
import SwiftUI

enum HanimeWatchLoadEvent {
    static func shouldApplyResult(ticket: Int, generation: Int, cancelled: Bool, error: Error? = nil) -> Bool {
        guard ticket == generation, !cancelled else { return false }
        if error is CancellationError { return false }
        return true
    }
}

enum HanimePlayerReload {
    static func shouldStart(currentID: String?, nextID: String?, hasPlayer: Bool) -> Bool {
        guard nextID != nil else { return false }
        if !hasPlayer { return true }
        return currentID != nextID
    }

    private static func ordered(_ streams: [HanimeStream]) -> [HanimeStream] {
        streams.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.isHLS != rhs.isHLS { return !lhs.isHLS && rhs.isHLS }
            return false
        }
    }

    /// A failed rendition must not bounce the viewer back up. iPad logs showed a stall
    /// downgrade to 480p followed by a `.failed` fallback that picked 1080p again and restarted
    /// from zero — so prefer the highest rank at or below what just failed, and only go higher
    /// when nothing at/below is left.
    static func nextPlayable(after current: HanimeStream?, in streams: [HanimeStream], excluding failed: Set<String>) -> HanimeStream? {
        let candidates = ordered(streams.filter { !failed.contains($0.id) && $0.id != current?.id })
        guard let rank = current?.rank, rank > 1 else { return candidates.first }
        return candidates.first(where: { $0.rank <= rank }) ?? candidates.first
    }
}

struct HanimeWorkDetailView: View {
    @Environment(RouterPath.self) private var router
    @Environment(MusicPlaybackController.self) private var musicPlayer
    @Bindable var environment: AppEnvironment
    let workID: String

    @State private var state: LoadState<HanimeWatchPage> = .idle
    @State private var loadGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                switch state {
                case .idle, .loading:
                    SetuCard { SetuEmptyState(title: "正在加载作品", systemImage: "play.rectangle", isLoading: true) }
                case .failed(let error):
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "作品加载失败", message: error.message, systemImage: "play.rectangle")
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                case .loaded(let page):
                    workHeader(page)
                    HanimePlayerView(
                        workID: workID,
                        streams: page.streams,
                        onStart: { musicPlayer.pause() },
                        refreshStreams: { (try? await environment.hanimeCatalogClient.work(id: workID).streams) ?? [] }
                    )
                    .id(workID)
                    relatedSection(page.related)
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("H 动漫")
        .task(id: workID) { await load() }
        .accessibilityIdentifier("hanime.work.page")
    }

    @ViewBuilder
    private func workHeader(_ page: HanimeWatchPage) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuImageTile(
                    urlString: page.work.coverURL,
                    accessibilityLabel: page.work.displayTitle,
                    aspectRatio: 16 / 9
                )
                Text(page.work.displayTitle)
                    .font(SetuTypography.title)
                    .foregroundStyle(SetuColor.textPrimary)
                if !page.work.subtitle.isEmpty {
                    Text(page.work.subtitle)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                ModuleFavoriteButton(environment: environment, snapshot: page.work.favoriteSnapshot)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func relatedSection(_ related: [HanimeWork]) -> some View {
        if !related.isEmpty {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    SetuSectionHeader(title: "同系列", subtitle: "\(related.count) 部")
                    ForEach(related) { work in
                        Button {
                            router.navigate(to: .hanimeWork(work.id))
                        } label: {
                            HStack(spacing: SetuSpacing.md) {
                                SetuImageTile(
                                    urlString: work.coverURL,
                                    accessibilityLabel: work.displayTitle,
                                    aspectRatio: 16 / 9
                                )
                                .frame(width: 108)
                                Text(work.displayTitle)
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hanime.related.\(work.id)")
                    }
                }
            }
        }
    }

    private func load() async {
        loadGeneration += 1
        let ticket = loadGeneration
        let id = workID
        state = .loading
        do {
            let page = try await environment.hanimeCatalogClient.work(id: id)
            guard HanimeWatchLoadEvent.shouldApplyResult(ticket: ticket, generation: loadGeneration, cancelled: Task.isCancelled) else { return }
            environment.moduleWatchHistoryStore.record(page.work.watchRecord)
            state = .loaded(page)
        } catch {
            guard HanimeWatchLoadEvent.shouldApplyResult(ticket: ticket, generation: loadGeneration, cancelled: Task.isCancelled, error: error) else { return }
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

struct HanimePlayerView: View {
    let workID: String
    let streams: [HanimeStream]
    var onStart: (() -> Void)?
    /// Re-scrapes the watch page so an expired direct link can be replaced mid-playback.
    var refreshStreams: (@MainActor () async -> [HanimeStream])? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var avPlayer: AVPlayer?
    @State private var itemObservers: [NSKeyValueObservation] = []
    @State private var stallObserver: NSObjectProtocol?
    @State private var failedIDs: Set<String> = []
    @State private var skippedIDs: Set<String> = []
    @State private var playbackError: String?
    @State private var isBuffering = false
    @State private var recoveryHint: String?
    @State private var refreshedStreams: [HanimeStream]?
    @State private var hasRefreshedLinks = false
    @State private var watchdogTask: Task<Void, Never>?
    @State private var recoveryTask: Task<Void, Never>?
    @State private var mediaServicesResetObserver: NSObjectProtocol?
    @State private var hasNudgedInPlace = false
    @State private var assets = HanimeAssetCache()
    @State private var monitor = HanimeStallMonitor()
    @State private var networkProfile = HanimeNetworkProfile()
    #if DEBUG && os(iOS)
    @State private var playbackLog = OSLog(subsystem: "icu.yukiryou.setuios", category: "HanimePlayback")
    #endif
    #if os(iOS)
    @State private var showingFullscreen = false
    #endif

    private var effectiveStreams: [HanimeStream] {
        refreshedStreams ?? streams
    }

    private var budget: HanimePlaybackBudget {
        HanimeRenditionPolicy.budget(isExpensiveNetwork: networkProfile.isExpensive)
    }

    /// HLS is the site's own adaptive stream; "HLS" is jargon to a viewer.
    private func qualityLabel(_ stream: HanimeStream) -> String {
        stream.isHLS ? "自动" : stream.quality
    }

    private var selectedStream: HanimeStream? {
        effectiveStreams.first(where: { $0.id == selectedID })
            ?? HanimeRenditionPolicy.pickStream(in: effectiveStreams, budget: budget)
    }

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                videoArea
                if let playbackError {
                    Text(playbackError)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.danger)
                    Button("重新加载播放") { retryPlayback() }
                        .buttonStyle(.borderedProminent)
                }
                if effectiveStreams.count > 1 {
                    Picker("清晰度", selection: Binding(
                        get: { selectedStream?.id ?? "" },
                        set: { selectQuality($0) }
                    )) {
                        ForEach(effectiveStreams) { stream in
                            Text(qualityLabel(stream)).tag(stream.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(SetuColor.brandPink)
                }
            }
        }
        .accessibilityIdentifier("hanime.player")
        .accessibilityValue(workID)
        .onAppear {
            installMediaServicesResetObserver()
            if selectedID == nil { selectedID = selectedStream?.id }
            if HanimePlayerReload.shouldStart(currentID: selectedID, nextID: selectedStream?.id, hasPlayer: avPlayer != nil) {
                configurePlayer()
            } else {
                avPlayer?.play()
            }
            startWatchdog()
        }
        .onDisappear {
            teardownPlayer()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let avPlayer {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    HanimeFullscreenPlayerView(player: avPlayer)
                        .ignoresSafeArea()
                    Button {
                        showingFullscreen = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .padding(SetuSpacing.lg)
                    .accessibilityLabel("退出全屏")
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var videoArea: some View {
        if effectiveStreams.isEmpty || (playbackError != nil && avPlayer == nil) {
            placeholder(message: playbackError ?? "暂未拿到播放地址", isLoading: false)
        } else if let avPlayer {
            Group {
                #if os(iOS)
                if HanimeRenderingPolicy.showsInlinePlayer(isFullscreenPresented: showingFullscreen) {
                    VideoPlayer(player: avPlayer)
                } else {
                    Color.black
                }
                #else
                VideoPlayer(player: avPlayer)
                #endif
            }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                .overlay { stallBadge }
                #if os(iOS)
                .overlay(alignment: .topTrailing) {
                    Button {
                        showingFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    .padding(SetuSpacing.sm)
                    .accessibilityLabel("全屏播放")
                }
                #endif
        } else {
            placeholder(message: "正在准备播放", isLoading: true)
        }
    }

    private func placeholder(message: String, isLoading: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                .fill(SetuColor.surfaceMuted)
            VStack(spacing: SetuSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(SetuColor.brandPink)
                } else {
                    Image(systemName: "play.rectangle")
                        .font(.title)
                        .foregroundStyle(SetuColor.brandPink)
                }
                Text(message)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(SetuSpacing.lg)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stallBadge: some View {
        if isBuffering || recoveryHint != nil {
            VStack(spacing: SetuSpacing.sm) {
                if recoveryHint == nil {
                    ProgressView()
                        .tint(.white)
                }
                if let recoveryHint {
                    Text(recoveryHint)
                        .font(SetuTypography.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(SetuSpacing.md)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
            .accessibilityIdentifier("hanime.player.stall")
        }
    }

    private func selectQuality(_ id: String) {
        guard selectedID != id else { return }
        selectedID = id
        // A deliberate quality change deserves a fresh recovery budget.
        skippedIDs = []
        monitor.resetBudget()
        recoveryHint = nil
        let quality = effectiveStreams.first(where: { $0.id == id })?.quality ?? "?"
        log("hanime.action user quality=\(quality) skippedCleared=\(skippedIDs.count)")
        configurePlayer()
    }

    private func retryPlayback() {
        // 从当前位置重挂，不要回到起点：以前点“重新加载播放”会从头播放，体感就是“卡顿后重新播放”。
        let resume = resumablePosition()
        failedIDs = []
        skippedIDs = []
        hasRefreshedLinks = false
        refreshedStreams = nil
        monitor.resetBudget()
        playbackError = nil
        recoveryHint = nil
        selectedID = selectedStream?.id
        log("hanime.action retry quality=\(selectedStream?.quality ?? "?") resume=\(resume.map { String(format: "%.1f", $0) } ?? "start")")
        configurePlayer(resumeAt: resume)
        startWatchdog()
    }

    private func resumablePosition() -> Double? {
        guard let seconds = avPlayer?.currentItem?.currentTime().seconds, seconds.isFinite, seconds > 1 else {
            return nil
        }
        return seconds
    }

    private func configurePlayer(resumeAt: Double? = nil) {
        releaseObservers()
        playbackError = nil
        guard let stream = selectedStream else {
            abandonPlayer()
            return
        }
        let item = AVPlayerItem(asset: assets.asset(for: stream.url, options: HanimeSite.mediaAssetOptions(for: stream.url)))
        HanimeRenditionPolicy.apply(budget, to: item, isHLS: stream.isHLS)
        observe(item, stream: stream)
        monitor.frames.attach(to: item)
        let player: AVPlayer
        if let existing = avPlayer {
            // Reuse the player for quality switch and recovery: a second AVPlayer means a
            // second decoder session, which is what makes video stop producing frames.
            existing.replaceCurrentItem(with: item)
            player = existing
        } else {
            let created = AVPlayer(playerItem: item)
            created.automaticallyWaitsToMinimizeStalling = true
            #if os(iOS)
            created.allowsExternalPlayback = false
            #endif
            avPlayer = created
            player = created
        }
        isBuffering = false
        hasNudgedInPlace = false
        monitor.resetForNewPlayback(at: resumeAt)
        monitor.noteMount(now: HanimeStallMonitor.now)
        onStart?()
        log("hanime.play quality=\(stream.quality) hls=\(stream.isHLS) "
            + "forwardBuffer=\(budget.forwardBufferSeconds)s resume=\(resumeAt.map { String(format: "%.1f", $0) } ?? "start") "
            + "sources=\(effectiveStreams.map { $0.isHLS ? "hls" : $0.quality }.joined(separator: ",")) "
            + "cookies=\(HanimeSite.mediaCookieCount(for: stream.url))")
        guard let resumeAt, resumeAt.isFinite, resumeAt > 1 else {
            player.play()
            return
        }
        seekForRecovery(player, item, to: resumeAt, tag: "resume", forward: false)
    }

    /// Recovery seeks normally land on the keyframe at or before the target: a frame-accurate seek
    /// on a long-GOP site MP4 has to fetch and decode from the previous keyframe, which is most of
    /// the visible black screen. A frozen video needs the opposite: land *after* the target so the
    /// bad sample is skipped instead of re-entered.
    private func seekForRecovery(_ player: AVPlayer, _ item: AVPlayerItem, to seconds: Double, tag: String, forward: Bool) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: time,
                    toleranceBefore: forward ? .zero : .indefinite,
                    toleranceAfter: forward ? .indefinite : .zero) { finished in
            Task { @MainActor in
                guard avPlayer === player, player.currentItem === item else { return }
                if !finished {
                    log("hanime.seek.failed tag=\(tag) position=\(String(format: "%.1f", seconds)) "
                        + "status=\(item.status == .readyToPlay ? "ready" : "notReady")")
                }
                player.play()
            }
        }
    }

    private func observe(_ item: AVPlayerItem, stream: HanimeStream) {
        itemObservers = [item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            let code = (error as NSError?)?.code ?? 0
            let domain = (error as NSError?)?.domain ?? ""
            Task { @MainActor in
                guard selectedID == stream.id else { return }
                // A cancelled load is our own replaceCurrentItem racing ahead of the old item;
                // failing over on it cascades (iPad log: 480p marked failed 1s after mounting).
                if domain == NSURLErrorDomain, code == NSURLErrorCancelled {
                    log("hanime.fail.ignored quality=\(stream.quality) cancelled")
                    return
                }
                failCurrentAndTryNext(stream, error: error)
            }
        }]
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                isBuffering = true
            }
        }
    }

    private func failCurrentAndTryNext(_ stream: HanimeStream, error: Error?) {
        let resume = resumablePosition()
        let code: String
        if let error = error as NSError? {
            // domain#code only: AVFoundation descriptions embed the signed URL.
            code = "\(error.domain)#\(error.code)"
        } else {
            code = "unknown"
        }
        if HanimePlayerFailureDisposition.classify(error) == .rebuildPlayer {
            log("hanime.mediaServices.reset source=itemFailed quality=\(stream.quality) resume=\(resume.map { String(format: "%.1f", $0) } ?? "start")")
            rebuildPlayerAfterMediaServicesReset(resumeAt: resume)
            return
        }
        releaseObservers()
        failedIDs.insert(stream.id)
        log("hanime.fail quality=\(stream.quality) error=\(code) resume=\(resume.map { String(format: "%.1f", $0) } ?? "start")")
        if let next = HanimePlayerReload.nextPlayable(after: stream, in: effectiveStreams, excluding: failedIDs) {
            selectedID = next.id
            configurePlayer(resumeAt: resume)
            return
        }
        stopWatchdog()
        abandonPlayer()
        playbackError = "无法开始播放，请再试一次"
    }

    private func releaseObservers() {
        itemObservers = []
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
        }
        stallObserver = nil
    }

    private func abandonPlayer() {
        monitor.frames.detach()
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
    }

    private func teardownPlayer() {
        stopWatchdog()
        releaseObservers()
        removeMediaServicesResetObserver()
        abandonPlayer()
    }

    private func installMediaServicesResetObserver() {
        guard mediaServicesResetObserver == nil else { return }
        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let resume = resumablePosition()
                log("hanime.mediaServices.reset source=notification resume=\(resume.map { String(format: "%.1f", $0) } ?? "start")")
                rebuildPlayerAfterMediaServicesReset(resumeAt: resume)
            }
        }
    }

    private func removeMediaServicesResetObserver() {
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
        mediaServicesResetObserver = nil
    }

    private func rebuildPlayerAfterMediaServicesReset(resumeAt: Double?) {
        guard selectedStream != nil else { return }
        stopWatchdog()
        releaseObservers()
        abandonPlayer()
        monitor.resetBudget()
        hasNudgedInPlace = false
        recoveryHint = "媒体服务已恢复，正在重建播放器"
        configurePlayer(resumeAt: resumeAt)
        startWatchdog()
    }

    // MARK: - Stall watchdog

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            let nanoseconds = UInt64(HanimeStallMonitor.sampleInterval * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await samplePlayback()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        isBuffering = false
    }

    private func samplePlayback() async {
        // Out of focus iOS stops video rendering on purpose; that is not a stall.
        guard scenePhase == .active, let player = avPlayer, let item = player.currentItem,
              item.status == .readyToPlay else {
            if avPlayer?.currentItem != nil {
                log("hanime.sample skipped phase=\(scenePhase == .active ? "active" : "background") "
                    + "itemStatus=\(avPlayer?.currentItem?.status.rawValue ?? -1)")
            }
            monitor.resetForNewPlayback(at: avPlayer?.currentItem?.currentTime().seconds)
            return
        }
        let time = item.currentTime()
        let position = time.seconds
        guard position.isFinite else { return }
        // 新 item 刚挂上时本来就还在等首帧，不要在那段时间里判停滞。
        guard !monitor.isWarmingUp(now: HanimeStallMonitor.now) else { return }
        let droppedTotal = await HanimePlaybackProbe.droppedVideoFramesTotal(in: item)
        let sample = HanimePlaybackSample(
            at: HanimeStallMonitor.now,
            positionSeconds: position,
            isClockRunning: player.timeControlStatus == .playing,
            isWaitingToPlay: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            renderedFrames: monitor.frames.framesInWindow(itemTime: time),
            droppedVideoFrames: monitor.droppedDelta(current: droppedTotal),
            bufferedAheadSeconds: HanimePlaybackProbe.bufferedAheadSeconds(in: item)
        )
        let action = monitor.consume(sample)
        #if DEBUG && os(iOS)
        // Hottest log site: keep the string building out of release builds.
        log("hanime.sample pos=\(String(format: "%.1f", sample.positionSeconds)) "
            + "ahead=\(String(format: "%.1f", sample.bufferedAheadSeconds)) "
            + "frames=\(sample.renderedFrames.map(String.init) ?? "n/a") "
            + "drop=\(sample.droppedVideoFrames.map(String.init) ?? "n/a") "
            + "clock=\(sample.isClockRunning ? "play" : (sample.isWaitingToPlay ? "waiting" : "paused")) "
            + "rate=\(String(format: "%.2f", player.rate)) action=\(action.logLabel)")
        #endif
        if case let .recover(reason, _) = action {
            logStall(reason: reason, sample: sample)
        }
        apply(action)
    }

    private func apply(_ action: HanimeWatchdogAction) {
        switch action {
        case .none:
            break
        case .healthy:
            isBuffering = false
            recoveryHint = nil
            // 一段健康播放之后，原地重拉重新可用。
            hasNudgedInPlace = false
        case .buffering:
            isBuffering = true
        case let .recover(reason, resumeAt):
            recover(from: reason, resumeAt: resumeAt)
        }
    }

    private func recover(from reason: HanimeRecoveryReason, resumeAt: Double) {
        let current = selectedStream
        isBuffering = false
        guard monitor.noteRecovery(now: HanimeStallMonitor.now) else {
            // 预算暂时用完只能退避，绝对不能关掉采样：真机上就是这样关死后，
            // 十几分钟里没有任何一行日志，十几秒的卡顿也无人接管。
            isBuffering = true
            recoveryHint = "视频停滞，正在等待重试窗口"
            log("hanime.recover.backoff reason=\(reason.logLabel) recoveries=\(monitor.recoveries)")
            return
        }
        let step = HanimeRecoveryPlan.step(
            reason: reason,
            current: current,
            streams: effectiveStreams,
            skipped: failedIDs.union(skippedIDs),
            refreshed: hasRefreshedLinks,
            canRefresh: refreshStreams != nil,
            canNudge: !hasNudgedInPlace
        )
        // `id` contains the URL, so a refreshed link for the same quality stays selectable.
        if let current { skippedIDs.insert(current.id) }
        // 以当前时钟位置为锚，不回跳到冻结前的位置：向后 seek 会再次落进同一个坏 sample
        // （日志里反复 resume=15.1 就是这个循环），音频已走远时回跳还会吞掉一段进度。
        let live = avPlayer?.currentItem?.currentTime().seconds ?? resumeAt
        let anchor = live.isFinite ? live : resumeAt
        let target = max(anchor - 1, 0)
        // 冻结类向前重同步（跳过坏 sample），链路类向后重拉（重新开口要字节）。
        let skipBadSample = reason == .videoFrozen || reason == .frameRateCollapse || reason == .clockStuck
        log("hanime.recover attempt=\(monitor.recoveries) reason=\(reason.logLabel) step=\(step.logLabel) "
            + "anchor=\(String(format: "%.1f", anchor)) advisory=\(String(format: "%.1f", resumeAt))")
        switch step {
        case .resumeInPlace:
            nudgeInPlace(at: anchor, forward: skipBadSample)
        case let .switchTo(stream):
            recoveryHint = "播放停滞，已改用 \(qualityLabel(stream)) 继续"
            selectedID = stream.id
            configurePlayer(resumeAt: target)
        case .refreshLinks:
            hasRefreshedLinks = true
            recoveryHint = "播放停滞，正在刷新播放地址"
            repairWithFreshLinks(current: current, resumeAt: target)
        case .giveUp:
            stopWatchdog()
            playbackError = "视频无法继续播放，请点重新加载播放"
        }
    }

    /// Cheapest recovery: re-seek on the *current* item. That re-opens the byte stream or jumps to
    /// the next keyframe without throwing the item away, so duration and the scrubber stay on screen.
    private func nudgeInPlace(at position: Double, forward: Bool) {
        guard let player = avPlayer, let item = player.currentItem else { return }
        hasNudgedInPlace = true
        isBuffering = true
        recoveryHint = "播放停滞，正在重新同步画面"
        item.cancelPendingSeeks()
        seekForRecovery(player, item,
                        to: forward ? position : max(position - 1, 0),
                        tag: forward ? "nudge-forward" : "nudge",
                        forward: forward)
        log("hanime.recover.nudge position=\(String(format: "%.1f", position)) forward=\(forward)")
    }

    private func repairWithFreshLinks(current: HanimeStream?, resumeAt: Double) {
        recoveryTask?.cancel()
        let refresh = refreshStreams
        recoveryTask = Task { @MainActor in
            let fresh = await refresh?() ?? []
            guard !Task.isCancelled else { return }
            let retry = fresh.first { $0.quality == current?.quality && $0.id != current?.id }
                ?? fresh.first { $0.quality == current?.quality }
                ?? HanimeRenditionPolicy.pickStream(in: fresh, budget: budget)
            guard let retry, retry.id != current?.id else {
                // 站点拦了或地址未变：保持采样，等下一次回充的预算再试。
                hasRefreshedLinks = false
                recoveryHint = "没能刷新播放地址，稍后自动重试"
                log("hanime.recover.refreshFailed streams=\(fresh.count)")
                return
            }
            refreshedStreams = fresh
            recoveryHint = "已刷新播放地址，继续播放"
            selectedID = retry.id
            configurePlayer(resumeAt: resumeAt)
        }
    }

    private func log(_ message: String) {
        #if DEBUG && os(iOS)
        os_log("%{public}@", log: playbackLog, type: .info, message)
        #endif
        #if os(iOS)
        HanimePlaybackLogFile.shared.append(message)
        #endif
    }

    private func logStall(reason: HanimeRecoveryReason, sample: HanimePlaybackSample) {
        let frames = sample.renderedFrames.map(String.init) ?? "n/a"
        let line = "hanime.stall reason=\(reason.logLabel) quality=\(selectedStream?.quality ?? "?") "
            + "position=\(String(format: "%.1f", sample.positionSeconds)) "
            + "bufferedAhead=\(String(format: "%.1f", sample.bufferedAheadSeconds)) "
            + "renderedFrames=\(frames) waiting=\(sample.isWaitingToPlay)"
        guard let item = avPlayer?.currentItem else {
            log(line)
            return
        }
        #if DEBUG && os(iOS)
        Task { @MainActor in
            let access = await HanimePlaybackProbe.accessLogSummary(for: item)
            log("\(line) \(access)")
        }
        #else
        log(line)
        #endif
    }
}

#if os(iOS)
private struct HanimeFullscreenPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
#endif

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

    static func nextPlayable(after current: HanimeStream?, in streams: [HanimeStream], excluding failed: Set<String>) -> HanimeStream? {
        streams
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                if lhs.isHLS != rhs.isHLS { return !lhs.isHLS && rhs.isHLS }
                return false
            }
            .first { !failed.contains($0.id) && $0.id != current?.id }
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
                            Text(stream.quality).tag(stream.id)
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
            if selectedID == nil { selectedID = selectedStream?.id }
            if HanimePlayerReload.shouldStart(currentID: selectedID, nextID: selectedStream?.id, hasPlayer: avPlayer != nil) {
                configurePlayer()
            } else {
                avPlayer?.play()
            }
            startWatchdog()
        }
        .onDisappear {
            stopWatchdog()
            avPlayer?.pause()
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
            VideoPlayer(player: avPlayer)
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
        configurePlayer()
    }

    private func retryPlayback() {
        failedIDs = []
        skippedIDs = []
        hasRefreshedLinks = false
        refreshedStreams = nil
        monitor.resetBudget()
        playbackError = nil
        recoveryHint = nil
        selectedID = selectedStream?.id
        configurePlayer()
        startWatchdog()
    }

    private func configurePlayer(resumeAt: Double? = nil) {
        releaseObservers()
        playbackError = nil
        guard let stream = selectedStream else {
            abandonPlayer()
            return
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: stream.url, options: HanimeSite.playbackAssetOptions))
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
        monitor.resetForNewPlayback(at: resumeAt)
        onStart?()
        log("hanime.play quality=\(stream.quality) hls=\(stream.isHLS) "
            + "forwardBuffer=\(budget.forwardBufferSeconds)s resume=\(resumeAt.map { String(format: "%.1f", $0) } ?? "start")")
        guard let resumeAt, resumeAt.isFinite, resumeAt > 1 else {
            player.play()
            return
        }
        let time = CMTime(seconds: resumeAt, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                guard avPlayer === player, player.currentItem === item else { return }
                player.play()
            }
        }
    }

    private func observe(_ item: AVPlayerItem, stream: HanimeStream) {
        itemObservers = [item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard selectedID == stream.id else { return }
                failCurrentAndTryNext(stream)
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

    private func failCurrentAndTryNext(_ stream: HanimeStream) {
        releaseObservers()
        failedIDs.insert(stream.id)
        if let next = HanimePlayerReload.nextPlayable(after: stream, in: effectiveStreams, excluding: failedIDs) {
            selectedID = next.id
            configurePlayer()
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
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
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
        case .buffering:
            isBuffering = true
        case let .recover(reason, resumeAt):
            recover(from: reason, resumeAt: resumeAt)
        }
    }

    private func recover(from reason: HanimeRecoveryReason, resumeAt: Double) {
        let current = selectedStream
        isBuffering = false
        guard monitor.noteRecovery() else {
            stopWatchdog()
            playbackError = "视频反复停滞，自动恢复已停止，请稍后再试"
            return
        }
        let step = HanimeRecoveryPlan.step(
            current: current,
            streams: effectiveStreams,
            skipped: failedIDs.union(skippedIDs),
            refreshed: hasRefreshedLinks,
            canRefresh: refreshStreams != nil
        )
        // `id` contains the URL, so a refreshed link for the same quality stays selectable.
        if let current { skippedIDs.insert(current.id) }
        let target = max(resumeAt - HanimeStallMonitor.rewindSeconds, 0)
        log("hanime.recover attempt=\(monitor.recoveries) reason=\(reason.logLabel) step=\(step.logLabel)")
        switch step {
        case let .switchTo(stream):
            recoveryHint = "播放停滞，已改用 \(stream.quality) 继续"
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
                stopWatchdog()
                playbackError = "没能拿到新的播放地址，请稍后再试"
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
        HanimePlaybackLogFile.shared.append(message)
        #endif
    }

    private func logStall(reason: HanimeRecoveryReason, sample: HanimePlaybackSample) {
        #if DEBUG && os(iOS)
        let frames = sample.renderedFrames.map(String.init) ?? "n/a"
        let line = "hanime.stall reason=\(reason.logLabel) quality=\(selectedStream?.quality ?? "?") "
            + "position=\(String(format: "%.1f", sample.positionSeconds)) "
            + "bufferedAhead=\(String(format: "%.1f", sample.bufferedAheadSeconds)) "
            + "renderedFrames=\(frames) waiting=\(sample.isWaitingToPlay)"
        guard let item = avPlayer?.currentItem else {
            log(line)
            return
        }
        Task { @MainActor in
            let access = await HanimePlaybackProbe.accessLogSummary(for: item)
            log("\(line) \(access)")
        }
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

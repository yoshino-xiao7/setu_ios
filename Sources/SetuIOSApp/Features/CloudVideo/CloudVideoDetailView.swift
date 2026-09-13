import AVFoundation
import AVKit
import SetuIOSCore
import SwiftUI

struct CloudVideoDetailView: View {
    @Environment(MusicPlaybackController.self) private var musicPlayer
    @Bindable var environment: AppEnvironment
    let videoID: Int

    @State private var detail: LoadState<CloudVideoItem> = .idle
    @State private var playback: CloudVideoPlayback?
    @State private var avPlayer: AVPlayer?
    @State private var playbackError: String?
    @State private var loadGeneration = 0
    @State private var selectedMaxHeight = CloudVideoQuality.maxHeight()
    @State private var availableHeights: [Int] = []
    @State private var itemObserver: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var allowSave = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var showingFullscreen = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                switch detail {
                case .idle, .loading:
                    SetuCard { SetuEmptyState(title: "正在加载视频", systemImage: "cloud", isLoading: true) }
                case .failed(let error):
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "视频加载失败", message: error.message, systemImage: "cloud")
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                case .loaded(let video):
                    playerCard
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            Text(video.title)
                                .font(SetuTypography.title)
                                .foregroundStyle(SetuColor.textPrimary)
                            Text("\(video.durationText) · \(video.ratingText)")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                            if let description = video.description, !description.isEmpty {
                                Text(description)
                                    .font(SetuTypography.body)
                                    .foregroundStyle(SetuColor.textPrimary)
                            }
                            if let tags = video.tags, !tags.isEmpty {
                                Text(tags)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("云视频")
        .task(id: videoID) { await load() }
        .onDisappear { persistAndStop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                saveProgress()
            }
        }
        .accessibilityIdentifier("cloudVideo.detail.page")
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let avPlayer {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    CloudVideoFullscreenPlayerView(player: avPlayer)
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
    private var playerCard: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                if let avPlayer {
                    VideoPlayer(player: avPlayer)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
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
                    ZStack {
                        RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                            .fill(SetuColor.surfaceMuted)
                        VStack(spacing: SetuSpacing.sm) {
                            if playbackError == nil {
                                ProgressView().tint(SetuColor.brandPink)
                            } else {
                                Image(systemName: "cloud")
                                    .font(.title)
                                    .foregroundStyle(SetuColor.brandPink)
                            }
                            Text(playbackError ?? "正在准备播放")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(SetuSpacing.lg)
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                qualityPicker
                if playbackError != nil {
                    Button("重新加载播放") { Task { await startPlayback() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .accessibilityIdentifier("cloudVideo.player")
    }

    private var qualityHeights: [Int] {
        CloudVideoQuality.optionHeights(available: availableHeights)
    }

    @ViewBuilder
    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            if qualityHeights.isEmpty {
                Text("正在读取该视频的真实转码档位")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            } else {
                Picker("画质上限", selection: Binding(
                    get: { CloudVideoQuality.capHeight(requested: selectedMaxHeight, available: qualityHeights) },
                    set: { height in
                        selectedMaxHeight = height
                        CloudVideoQuality.saveMaxHeight(height)
                        applyQualityCap(to: avPlayer?.currentItem)
                    }
                )) {
                    ForEach(qualityHeights, id: \.self) { height in
                        Text(CloudVideoQuality.label(for: height)).tag(height)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("cloudVideo.quality")
                Text("默认上限 720p，选项来自本片 HLS 档位，网速差会自动降低")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
    }

    private func load() async {
        loadGeneration += 1
        let ticket = loadGeneration
        detail = .loading
        playback = nil
        availableHeights = []
        persistAndStop()
        do {
            let item = try await environment.cloudVideoClient.detail(id: videoID)
            guard ticket == loadGeneration else { return }
            detail = .loaded(item)
            await startPlayback(generation: ticket)
        } catch {
            guard ticket == loadGeneration else { return }
            detail = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func startPlayback(generation: Int? = nil, resumeOverride: Double? = nil) async {
        let ticket = generation ?? loadGeneration
        playbackError = nil
        do {
            let ticketResponse = try await environment.cloudVideoClient.playback(id: videoID)
            guard ticket == loadGeneration else { return }
            playback = ticketResponse
            guard let url = ticketResponse.hlsURL else {
                playbackError = "播放地址无效"
                return
            }
            musicPlayer.pause()
            activateVideoSession()
            detachPlayer(save: true)
            let asset = AVURLAsset(url: url, options: CloudVideoHLSPlaylist.assetOptions(siteBaseURL: environment.config.siteBaseURL))
            let item = AVPlayerItem(asset: asset)
            applyQualityCap(to: item)
            observeItem(item)
            let player = AVPlayer(playerItem: item)
            avPlayer = player
            observeProgress(player)
            let resume = resumeOverride ?? Double(ticketResponse.resumePositionSeconds)
            if resume >= 5 {
                allowSave = false
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    Task { @MainActor in
                        guard ticket == loadGeneration else { return }
                        player.play()
                        allowSave = true
                    }
                }
            } else {
                allowSave = true
                player.play()
            }
            Task {
                let heights = await loadStreamHeights(from: url)
                guard ticket == loadGeneration else { return }
                if !heights.isEmpty {
                    availableHeights = heights
                }
                applyQualityCap(to: player.currentItem)
            }
            scheduleRefresh(ticketResponse, generation: ticket)
        } catch {
            guard ticket == loadGeneration else { return }
            playbackError = UserFacingErrorMapper.map(error).message
        }
    }

    private func scheduleRefresh(_ ticket: CloudVideoPlayback, generation: Int) {
        let delay = max(30, ticket.expiresAtDate.timeIntervalSinceNow - 90)
        Task {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard generation == loadGeneration else { return }
            let current = avPlayer?.currentTime().seconds
            await startPlayback(
                generation: generation,
                resumeOverride: current.flatMap { $0.isFinite ? $0 : nil }
            )
        }
    }

    private func applyQualityCap(to item: AVPlayerItem?) {
        guard let item else { return }
        guard !availableHeights.isEmpty else {
            item.preferredMaximumResolution = .zero
            return
        }
        let height = CloudVideoQuality.capHeight(requested: selectedMaxHeight, available: qualityHeights)
        item.preferredMaximumResolution = CloudVideoQuality.maximumResolution(forMaxHeight: height)
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemObserver = item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                playbackError = item.error?.localizedDescription ?? "无法开始播放，请再试一次"
            }
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                saveProgress()
            }
        }
    }

    private func observeProgress(_ player: AVPlayer) {
        if let timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 1),
            queue: .main
        ) { _ in
            Task { @MainActor in
                saveProgress()
            }
        }
    }

    private func persistAndStop() {
        detachPlayer(save: true)
    }

    private func detachPlayer(save: Bool) {
        if save {
            saveProgress()
        }
        if let timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        itemObserver = nil
        allowSave = false
        avPlayer?.pause()
        avPlayer = nil
    }

    private func saveProgress() {
        guard allowSave, let player = avPlayer else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        let duration = player.currentItem?.duration.seconds
        let durationSeconds = duration?.isFinite == true && (duration ?? 0) > 0 ? Int(duration!.rounded(.down)) : nil
        Task {
            try? await environment.cloudVideoClient.saveProgress(
                id: videoID,
                positionSeconds: Int(seconds.rounded(.down)),
                durationSeconds: durationSeconds
            )
        }
    }

    private func activateVideoSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    private func loadStreamHeights(from url: URL) async -> [Int] {
        var request = URLRequest(url: url)
        for (header, value) in CloudVideoHLSPlaylist.playbackHeaders(siteBaseURL: environment.config.siteBaseURL) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let playlist = String(data: data, encoding: .utf8) else {
                return []
            }
            return CloudVideoHLSPlaylist.streamHeights(fromMaster: playlist)
        } catch {
            return []
        }
    }
}

#if os(iOS)
private struct CloudVideoFullscreenPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
#endif

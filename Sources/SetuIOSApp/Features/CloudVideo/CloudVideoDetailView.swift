import AVFoundation
import AVKit
import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @State private var qualityGeneration = 0
    @State private var itemObserver: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var allowSave = false
    @State private var refreshTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var isNativeFullscreen = false
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
        .onDisappear {
            #if os(iOS)
            if isNativeFullscreen { return }
            #endif
            persistAndStop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                saveProgress()
                avPlayer?.pause()
            }
        }
        .accessibilityIdentifier("cloudVideo.detail.page")
    }

    @ViewBuilder
    private var playerCard: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                if let avPlayer {
                    #if os(iOS)
                    CloudVideoKitPlayer(
                        player: avPlayer,
                        heights: qualityHeights,
                        selectedHeight: CloudVideoQuality.capHeight(
                            requested: selectedMaxHeight,
                            available: qualityHeights
                        ),
                        onSelectHeight: { applySelectedMaxHeight($0) },
                        isFullscreen: $isNativeFullscreen
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                    #else
                    VideoPlayer(player: avPlayer)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
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

    private func applySelectedMaxHeight(_ height: Int) {
        selectedMaxHeight = height
        CloudVideoQuality.saveMaxHeight(height)
        qualityGeneration += 1
        let ticket = qualityGeneration
        Task { await reloadItemForQuality(generation: ticket) }
    }

    private func load() async {
        loadGeneration += 1
        let ticket = loadGeneration
        detail = .loading
        playback = nil
        availableHeights = []
        #if os(iOS)
        isNativeFullscreen = false
        #endif
        refreshTask?.cancel()
        refreshTask = nil
        detachPlayer(save: true)
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
            player.automaticallyWaitsToMinimizeStalling = true
            #if os(iOS)
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            player.allowsExternalPlayback = false
            #endif
            avPlayer = player
            observeProgress(player)
            guard ticket == loadGeneration else {
                abandon(player)
                return
            }
            let resume = resumeOverride ?? Double(ticketResponse.resumePositionSeconds)
            if resume >= 5 {
                allowSave = false
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    Task { @MainActor in
                        beginPlaying(player, generation: ticket)
                        if ticket == loadGeneration, avPlayer === player {
                            allowSave = true
                        }
                    }
                }
            } else {
                allowSave = true
                beginPlaying(player, generation: ticket)
            }
            Task {
                let heights = await loadStreamHeights(from: url)
                guard ticket == loadGeneration else { return }
                let before = CloudVideoQuality.playbackConstraints(
                    requested: selectedMaxHeight,
                    available: availableHeights
                )
                if !heights.isEmpty {
                    availableHeights = heights
                }
                let after = CloudVideoQuality.playbackConstraints(
                    requested: selectedMaxHeight,
                    available: availableHeights
                )
                if before != after {
                    qualityGeneration += 1
                    await reloadItemForQuality(generation: qualityGeneration)
                }
            }
            scheduleRefresh(ticketResponse, generation: ticket)
        } catch {
            guard ticket == loadGeneration else { return }
            playbackError = UserFacingErrorMapper.map(error).message
        }
    }

    private func scheduleRefresh(_ ticket: CloudVideoPlayback, generation: Int) {
        refreshTask?.cancel()
        let delay = max(30, ticket.expiresAtDate.timeIntervalSinceNow - 90)
        refreshTask = Task {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            let current = avPlayer?.currentTime().seconds
            await startPlayback(
                generation: generation,
                resumeOverride: current.flatMap { $0.isFinite ? $0 : nil }
            )
        }
    }

    private func reloadItemForQuality(generation: Int) async {
        guard generation == qualityGeneration else { return }
        guard let player = avPlayer, let url = playback?.hlsURL else {
            applyQualityCap(to: avPlayer?.currentItem)
            return
        }
        let time = player.currentTime()
        let shouldPlay = player.rate > 0 || player.timeControlStatus != .paused
        let asset = AVURLAsset(url: url, options: CloudVideoHLSPlaylist.assetOptions(siteBaseURL: environment.config.siteBaseURL))
        let item = AVPlayerItem(asset: asset)
        applyQualityCap(to: item)
        observeItem(item)
        player.replaceCurrentItem(with: item)
        observeProgress(player)
        let resume = time.seconds
        let seekTime = resume.isFinite && resume > 0 ? time : .zero
        allowSave = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        guard generation == qualityGeneration, avPlayer === player else { return }
        if shouldPlay {
            beginPlaying(player, generation: loadGeneration)
        }
        allowSave = true
    }

    private func beginPlaying(_ player: AVPlayer, generation: Int) {
        guard generation == loadGeneration, avPlayer === player else {
            abandon(player)
            return
        }
        player.play()
    }

    private func abandon(_ player: AVPlayer) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if avPlayer === player {
            avPlayer = nil
        }
    }

    private func applyQualityCap(to item: AVPlayerItem?) {
        guard let item else { return }
        let constraints = CloudVideoQuality.playbackConstraints(
            requested: selectedMaxHeight,
            available: availableHeights
        )
        item.preferredMaximumResolution = constraints.maximumResolution
        item.preferredPeakBitRate = constraints.peakBitRate
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
        loadGeneration += 1
        qualityGeneration += 1
        #if os(iOS)
        isNativeFullscreen = false
        #endif
        refreshTask?.cancel()
        refreshTask = nil
        detachPlayer(save: true)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
        avPlayer?.replaceCurrentItem(with: nil)
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
private struct CloudVideoKitPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var heights: [Int]
    var selectedHeight: Int
    var onSelectHeight: (Int) -> Void
    @Binding var isFullscreen: Bool

    func makeUIViewController(context: Context) -> CloudVideoPlayerViewController {
        let controller = CloudVideoPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        context.coordinator.sync(from: self)
        context.coordinator.chrome.attach(to: controller)
        context.coordinator.chrome.reveal()
        return controller
    }

    func updateUIViewController(_ controller: CloudVideoPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        let hadHeights = !context.coordinator.heights.isEmpty
        context.coordinator.sync(from: self)
        context.coordinator.chrome.attach(to: controller)
        if !hadHeights && !heights.isEmpty {
            context.coordinator.chrome.reveal()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let chrome = CloudVideoQualityChrome()
        weak var controller: CloudVideoPlayerViewController?
        var heights: [Int] = []
        private var isFullscreen: Binding<Bool> = .constant(false)

        func sync(from parent: CloudVideoKitPlayer) {
            heights = parent.heights
            isFullscreen = parent.$isFullscreen
            chrome.heights = parent.heights
            chrome.selectedHeight = parent.selectedHeight
            chrome.onSelect = parent.onSelectHeight
            chrome.refreshMenu()
            controller?.chrome = chrome
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            isFullscreen.wrappedValue = true
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.installChrome(on: playerViewController)
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                if !context.isCancelled {
                    self?.isFullscreen.wrappedValue = false
                }
                self?.installChrome(on: playerViewController)
            }
        }

        private func installChrome(on playerViewController: AVPlayerViewController) {
            if let presented = playerViewController.presentedViewController as? AVPlayerViewController {
                chrome.attach(to: presented)
            } else {
                chrome.attach(to: playerViewController)
            }
            chrome.reveal()
        }
    }
}

private final class CloudVideoPlayerViewController: AVPlayerViewController, UIGestureRecognizerDelegate {
    var chrome: CloudVideoQualityChrome?

    override func viewDidLoad() {
        super.viewDidLoad()
        showsPlaybackControls = true
        allowsPictureInPicturePlayback = false
        canStartPictureInPictureAutomaticallyFromInline = false
        view.backgroundColor = .black
        videoGravity = .resizeAspect
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleRevealTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        chrome?.attach(to: self)
    }

    @objc private func handleRevealTap() {
        chrome?.reveal()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private final class CloudVideoQualityChrome {
    var heights: [Int] = []
    var selectedHeight = CloudVideoQuality.defaultMaxHeight
    var onSelect: ((Int) -> Void)?

    private let container = CloudVideoChromePassthroughView()
    private let button = UIButton(type: .system)
    private var hideWork: DispatchWorkItem?
    private var menuOpen = false
    private var didConfigureButton = false
    private var lastMenuSignature = ""

    func attach(to controller: AVPlayerViewController) {
        guard let overlay = controller.contentOverlayView else { return }
        if container.superview !== overlay {
            container.removeFromSuperview()
            overlay.addSubview(container)
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                container.topAnchor.constraint(equalTo: overlay.topAnchor),
                container.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            ])
        }
        if button.superview !== container {
            configureButtonIfNeeded()
            container.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                button.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -72),
            ])
        }
        refreshMenu()
    }

    func reveal() {
        guard !heights.isEmpty else {
            button.isHidden = true
            container.isUserInteractionEnabled = false
            return
        }
        hideWork?.cancel()
        button.isHidden = false
        button.isUserInteractionEnabled = true
        container.isUserInteractionEnabled = true
        UIView.animate(withDuration: 0.2) {
            self.container.alpha = 1
        }
        scheduleHide()
    }

    func refreshMenu() {
        if heights.isEmpty {
            button.isHidden = true
            lastMenuSignature = ""
            return
        }
        let signature = "\(heights)-\(selectedHeight)"
        guard signature != lastMenuSignature else { return }
        lastMenuSignature = signature
        var configuration = UIButton.Configuration.plain()
        configuration.title = "\(selectedHeight)p"
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        var background = configuration.background
        background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        background.cornerRadius = 16
        configuration.background = background
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        button.configuration = configuration
        button.menu = UIMenu(
            title: "画质上限",
            children: heights.map { height in
                UIAction(
                    title: CloudVideoQuality.label(for: height),
                    state: height == selectedHeight ? .on : .off
                ) { [weak self] _ in
                    self?.menuOpen = false
                    self?.onSelect?(height)
                    self?.scheduleHide()
                }
            }
        )
    }

    private func configureButtonIfNeeded() {
        guard !didConfigureButton else { return }
        didConfigureButton = true
        container.alpha = 0
        container.isUserInteractionEnabled = false
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "cloudVideo.quality"
        button.accessibilityLabel = "画质上限"
        button.addAction(UIAction { [weak self] _ in
            self?.menuOpen = true
            self?.hideWork?.cancel()
            self?.container.alpha = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard let self, self.menuOpen else { return }
                self.menuOpen = false
                self.scheduleHide()
            }
        }, for: .touchDown)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !menuOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.menuOpen else { return }
            UIView.animate(withDuration: 0.25) {
                self.container.alpha = 0
            } completion: { finished in
                guard finished, self.container.alpha == 0 else { return }
                self.button.isUserInteractionEnabled = false
                self.container.isUserInteractionEnabled = false
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

private final class CloudVideoChromePassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
#endif

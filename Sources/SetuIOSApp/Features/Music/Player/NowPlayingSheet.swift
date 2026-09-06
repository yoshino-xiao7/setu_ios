import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum NowPlayingPage: String, CaseIterable, Identifiable {
    case cover
    case lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cover: "音乐"
        case .lyrics: "歌词"
        }
    }

    var systemImage: String {
        switch self {
        case .cover: "music.note"
        case .lyrics: "text.quote"
        }
    }
}

struct NowPlayingSheet: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) var dismiss

    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController

    @State var page: NowPlayingPage
    let lyrics: NowPlayingLyricsModel
    @State var scrubTime: Double = 0
    @State var isScrubbing = false
    @State var isDownloading = false
    @State var showingQueue = false
    @State var showingMore = false
    @State var pendingMoreAction: (() -> Void)?
    @State var playlistTrack: MusicPlaybackTrack?
    @State var mvTrack: MusicPlaybackTrack?
    @State var loadedArtworkAccent: (key: SetuImageKey, color: Color)?
    @State var feedback: SetuFeedback?
    @State var feedbackTask: Task<Void, Never>?
    @State var fileSharePayload: SystemFileSharePayload?

    init(environment: AppEnvironment, player: MusicPlaybackController, lyrics: NowPlayingLyricsModel, initialPage: NowPlayingPage = .cover) {
        self.environment = environment
        self.player = player
        self.lyrics = lyrics
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            detailBackground
                .ignoresSafeArea()

            if let track = player.currentTrack {
                VStack(spacing: SetuSpacing.md) {
                    detailHeader
                    nowPlayingPageContent(for: track)

                    bottomPanel(for: track)
                }
                .padding(.top, SetuSpacing.md)
                .padding(.bottom, SetuSpacing.lg)
                .task(id: track.id) {
                    await lyrics.load(identity: track.id, environment: environment)
                }
                .task(id: SetuImageKey.music(track.coverURLString, size: .large)) {
                    await loadArtworkAccent(for: track)
                }
            } else {
                SetuEmptyState(title: "暂无播放", message: "从音乐页选择一首歌开始播放", systemImage: "music.note")
                    .padding()
            }
        }
        #if DEBUG && os(iOS)
        .modifier(AirPlayHardwareAudit(player: player, lyrics: lyrics))
        #endif
        .overlay(alignment: .top) {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.top, SetuSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: feedback)
        .sheet(isPresented: $showingMore, onDismiss: {
            let action = pendingMoreAction
            pendingMoreAction = nil
            action?()
        }) {
            if let track = player.currentTrack { moreActions(for: track) }
        }
        .sheet(isPresented: $showingQueue) {
            MusicQueueDrawerView(player: player, onDismiss: { showingQueue = false })
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $playlistTrack) { track in
            AddPlaybackTrackToPlaylistSheet(environment: environment, track: track) { result in
                showFeedback(result)
            }
        }
        .sheet(item: $mvTrack) { track in
            NavigationStack {
                if let mvID = track.mvID, mvID > 0 {
                    MvPlaybackView(environment: environment, mvID: mvID) {
                        player.pause()
                    }
                    .padding(SetuSpacing.md)
                    .setuBackground()
        .setuFeedbackPresentation($feedback)
                    .navigationTitle("MV")
                    .musicInlineNavigationTitle()
                    .toolbar {
                        Button("关闭") {
                            mvTrack = nil
                        }
                    }
                } else {
                    SetuEmptyState(title: "暂无 MV", message: "当前歌曲没有可播放的 MV", systemImage: "play.rectangle")
                        .padding()
                        .setuBackground()
                }
            }
        }
        .sheet(item: $fileSharePayload) { payload in
            SystemFileShareSheet(fileURL: payload.fileURL) { result in
                switch result {
                case .completed:
                    showFeedback(.success("已完成保存或分享"))
                case .cancelled:
                    showFeedback(.info("已取消保存或分享"))
                case .failed(let message):
                    showFeedback(.error("保存或分享失败：\(message)"))
                }
            }
        }
        .onDisappear {
            feedbackTask?.cancel()
        }
    }

    // MARK: Header

    var detailHeader: some View {
        HStack(spacing: SetuSpacing.md) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(SetuColor.surfaceMuted.opacity(0.7), in: Circle())
            }
            .setuButtonFeedback(cornerRadius: 22)
            .accessibilityLabel("收起播放页")

            Spacer()

            if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 2) {
                    Text("正在播放")
                        .font(.caption2)
                        .foregroundStyle(SetuColor.textTertiary)
                    Text(queueCaption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button { showingMore = true } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多操作")
            .setuButtonFeedback()

        }
        .padding(.horizontal, SetuSpacing.lg)
    }

    // MARK: Pages

    @ViewBuilder
    func nowPlayingPageContent(for track: MusicPlaybackTrack) -> some View {
        ZStack {
            switch page {
            case .cover:
                coverPage(for: track)
                    .transition(.opacity)
            case .lyrics:
                lyricsPage(for: track)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
    }

    func coverPage(for track: MusicPlaybackTrack) -> some View {
        // Artwork adapts to whatever the page area offers, so controls stay
        // on-screen for iPhone SE and the art still fills a Pro Max.
        GeometryReader { proxy in
            let side = max(min(proxy.size.width - SetuSpacing.xxl * 2, proxy.size.height - SetuSpacing.xl * 2, 360), 120)
            let content = VStack(spacing: SetuSpacing.xl) {
                Spacer(minLength: 0)

                MusicArtworkView(
                    urlString: track.coverURLString,
                    width: side,
                    height: side,
                    cornerRadius: SetuRadius.lg,
                    artworkSize: .lockScreen,
                    onTap: {
                        PlayerHaptics.light()
                        showLyrics()
                    }
                )
                .shadow(color: SetuColor.brandPink.opacity(0.24), radius: 24, y: 16)
                .scaleEffect(player.isPlaying && !reduceMotion ? 1.0 : 0.92)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78), value: player.isPlaying)
                .accessibilityLabel("歌曲封面，点击查看歌词")

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width)
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { content.padding(.vertical, SetuSpacing.md) }
            } else {
                content.frame(height: proxy.size.height)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(trackSkipGesture)
    }

    func lyricsPage(for track: MusicPlaybackTrack) -> some View {
        NowPlayingLyricsPane(model: lyrics, player: player, onShowCover: showCover)
    }

    var trackSkipGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
                    ? value.predictedEndTranslation.width
                    : value.translation.width
                let vertical = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                    ? value.predictedEndTranslation.height
                    : value.translation.height
                guard abs(horizontal) > 48, abs(horizontal) > abs(vertical) * 1.2 else {
                    return
                }
                if horizontal < 0 {
                    guard player.canPlayNext else {
                        showFeedback(.warning("已经是最后一首"))
                        return
                    }
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: 1) }
                } else {
                    guard player.canPlayPrevious else {
                        showFeedback(.warning("已经是第一首"))
                        return
                    }
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: -1) }
                }
            }
    }

    // MARK: Background & helpers

    var detailBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (artworkAccentColor ?? SetuColor.brandSoft).opacity(0.42),
                    SetuColor.bgBase,
                    SetuColor.brandSoft.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    (artworkAccentColor ?? SetuColor.brandPink).opacity(0.36),
                    SetuColor.bgBase.opacity(0.08)
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
        }
    }

    var queueCaption: String {
        let name = player.queueName ?? "当前队列"
        let count = player.queueTracks.count
        if count > 1 {
            return "\(name) · \(count) 首"
        }
        return name
    }

    func showLyrics() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = .lyrics
        }
    }

    func showCover() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = .cover
        }
    }

    func showFeedback(_ nextFeedback: SetuFeedback) {
        feedbackTask?.cancel()
        feedback = nextFeedback
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }

    func download(_ track: MusicPlaybackTrack) async {
        isDownloading = true
        showFeedback(.info("正在准备下载"))
        defer { isDownloading = false }
        do {
            guard let resolver = player.urlResolver else { throw UserFacingError(message: "播放器尚未准备好") }
            let urlString = try await resolver.resolve(trackID: track.id, quality: .standard).url.absoluteString
            let filename = "\(track.title) - \(track.artist).mp3"
            let signed = try await environment.downloadClient.sign(url: urlString, filename: filename)
            guard let url = URL(string: signed.downloadUrl) else {
                showFeedback(.error("下载地址无效"))
                return
            }
            let fileURL = try await RemoteFileExportService.download(from: url, filename: filename)
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            showFeedback(.success("下载完成，请选择保存位置或分享方式"))
        } catch {
            showFeedback(.error(RemoteFileExportService.userMessage(for: error)))
        }
    }

    var artworkAccentColor: Color? {
        guard let track = player.currentTrack, let key = SetuImageKey.music(track.coverURLString, size: .large) else { return nil }
        if loadedArtworkAccent?.key == key { return loadedArtworkAccent?.color }
        return SetuRemoteImageLoader.shared.cachedAccent(for: key).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    func loadArtworkAccent(for track: MusicPlaybackTrack) async {
        guard let key = SetuImageKey.music(track.coverURLString, size: .large) else { return }
        do {
            let accent = try await SetuRemoteImageLoader.shared.averageColor(for: key)
            guard !Task.isCancelled, player.currentTrack?.id == track.id,
                  SetuImageKey.music(player.currentTrack?.coverURLString, size: .large) == key else { return }
            loadedArtworkAccent = accent.map { (key, Color(red: $0.red, green: $0.green, blue: $0.blue)) }
        } catch {
            // The existing soft-pink background remains the fallback.
        }
    }

    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

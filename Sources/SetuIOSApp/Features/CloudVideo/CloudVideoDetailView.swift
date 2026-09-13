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
                            Text(video.durationText)
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
        .onDisappear { avPlayer?.pause() }
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
                if playbackError != nil {
                    Button("重新加载播放") { Task { await startPlayback() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .accessibilityIdentifier("cloudVideo.player")
    }

    private func load() async {
        loadGeneration += 1
        let ticket = loadGeneration
        detail = .loading
        playback = nil
        avPlayer?.pause()
        avPlayer = nil
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

    private func startPlayback(generation: Int? = nil) async {
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
            let player = AVPlayer(url: url)
            avPlayer = player
            player.play()
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
            let currentTime = avPlayer?.currentTime()
            await startPlayback(generation: generation)
            if let currentTime {
                await avPlayer?.seek(to: currentTime)
            }
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

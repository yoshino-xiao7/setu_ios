import AVKit
import SetuIOSCore
import SwiftUI

/// In-app MV player. Loads the MV stream and plays it inline with AVKit's
/// `VideoPlayer` (with a native fullscreen control) instead of handing the URL
/// off to the browser.
struct MvPlaybackView: View {
    @Bindable var environment: AppEnvironment
    let mvID: Int
    /// Called once when the video actually starts, so the caller can pause music
    /// playback and avoid two audio streams at once.
    var onStart: (() -> Void)?

    @State private var urlState: LoadState<MusicMvUrlData?> = .idle
    @State private var resolutions: [MusicMvQuality] = []
    @State private var selectedResolution: Int?
    @State private var avPlayer: AVPlayer?
    #if os(iOS)
    @State private var showingFullscreen = false
    #endif

    var body: some View {
        VStack(spacing: SetuSpacing.md) {
            videoArea
            if resolutions.count > 1 {
                resolutionPicker
            }
        }
        .task(id: mvID) {
            await loadResolutions()
            await loadURL()
        }
        .onDisappear {
            avPlayer?.pause()
            avPlayer = nil
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let avPlayer {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    MvFullscreenPlayerView(player: avPlayer)
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
        switch urlState {
        case .idle, .loading:
            placeholder(message: "正在准备 MV", isLoading: true)
        case .failed(let message):
            VStack(spacing: SetuSpacing.md) {
                placeholder(message: message, isLoading: false)
                Button("重试") {
                    Task { await loadURL() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SetuColor.brandInk)
                .frame(minHeight: 44)
                .buttonStyle(.bordered)
            }
        case .loaded:
            if let avPlayer {
                VideoPlayer(player: avPlayer)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                    .shadow(color: SetuColor.brandPink.opacity(0.18), radius: 16, y: 10)
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
                        .accessibilityLabel("全屏播放 MV")
                    }
                    #endif
            } else {
                VStack(spacing: SetuSpacing.md) {
                    placeholder(message: "暂未拿到播放地址，可切换清晰度或重新获取。", isLoading: false)
                    Button("重新获取播放地址") {
                        Task { await loadURL() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var resolutionPicker: some View {
        Picker("清晰度", selection: $selectedResolution) {
            Text("默认").tag(Optional<Int>.none)
            ForEach(resolutions) { quality in
                Text("\(quality.br)P").tag(Optional(quality.br))
            }
        }
        .pickerStyle(.segmented)
        .tint(SetuColor.brandPink)
        .onChange(of: selectedResolution) {
            Task { await loadURL() }
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

    private func loadResolutions() async {
        guard resolutions.isEmpty else { return }
        do {
            let detail = try await environment.musicClient.mvDetail(id: mvID)
            resolutions = detail.data.brs ?? []
        } catch {
            // Resolution list is optional; playback still works at default quality.
        }
    }

    private func loadURL() async {
        urlState = .loading
        do {
            let response = try await environment.musicClient.mvUrl(id: mvID, resolution: selectedResolution)
            urlState = .loaded(response.data)
            configurePlayer(with: response.data)
        } catch {
            urlState = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func configurePlayer(with data: MusicMvUrlData?) {
        guard let urlString = data?.httpsURLString, let url = URL(string: urlString) else {
            avPlayer = nil
            return
        }
        let player = AVPlayer(url: url)
        avPlayer = player
        onStart?()
        player.play()
    }
}

#if os(iOS)
private struct MvFullscreenPlayerView: UIViewControllerRepresentable {
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

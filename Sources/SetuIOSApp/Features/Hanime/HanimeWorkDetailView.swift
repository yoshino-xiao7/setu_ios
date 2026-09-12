import AVKit
import SetuIOSCore
import SwiftUI

struct HanimeWorkDetailView: View {
    @Environment(RouterPath.self) private var router
    @Environment(MusicPlaybackController.self) private var musicPlayer
    @Bindable var environment: AppEnvironment
    let workID: String

    @State private var state: LoadState<HanimeWatchPage> = .idle

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
                    HanimePlayerView(streams: page.streams) {
                        musicPlayer.pause()
                    }
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
        state = .loading
        do {
            let page = try await environment.hanimeCatalogClient.work(id: workID)
            environment.moduleWatchHistoryStore.record(page.work.watchRecord)
            state = .loaded(page)
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

struct HanimePlayerView: View {
    let streams: [HanimeStream]
    var onStart: (() -> Void)?

    @State private var selectedID: String?
    @State private var avPlayer: AVPlayer?
    #if os(iOS)
    @State private var showingFullscreen = false
    #endif

    private var selectedStream: HanimeStream? {
        streams.first(where: { $0.id == selectedID }) ?? streams.max(by: { $0.rank < $1.rank })
    }

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                videoArea
                if streams.count > 1 {
                    Picker("清晰度", selection: Binding(
                        get: { selectedStream?.id ?? "" },
                        set: { selectedID = $0 }
                    )) {
                        ForEach(streams) { stream in
                            Text(stream.quality).tag(stream.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(SetuColor.brandPink)
                    .onChange(of: selectedID) {
                        configurePlayer()
                    }
                }
            }
        }
        .accessibilityIdentifier("hanime.player")
        .onAppear {
            if selectedID == nil { selectedID = selectedStream?.id }
            configurePlayer()
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
        if streams.isEmpty {
            placeholder(message: "暂未拿到播放地址", isLoading: false)
        } else if let avPlayer {
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

    private func configurePlayer() {
        avPlayer?.pause()
        guard let stream = selectedStream else {
            avPlayer = nil
            return
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: stream.url, options: HanimeSite.playbackAssetOptions))
        let player = AVPlayer(playerItem: item)
        avPlayer = player
        onStart?()
        player.play()
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

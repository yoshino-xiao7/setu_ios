import SetuIOSCore
import SwiftUI

struct AsmrWorkDetailView: View {
    @Environment(MusicPlaybackController.self) private var player
    @Bindable var environment: AppEnvironment
    let workID: String

    @State private var workState: LoadState<AsmrWork> = .idle
    @State private var tracksState: LoadState<[AsmrTrack]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                switch workState {
                case .loading, .idle:
                    SetuCard { SetuEmptyState(title: "正在加载作品", systemImage: "headphones", isLoading: true) }
                case .failed(let error):
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "作品加载失败", message: error.message, systemImage: "headphones")
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                case .loaded(let work):
                    workHeader(work)
                    trackList(for: work)
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("ASMR")
        .task { await load() }
        .accessibilityIdentifier("asmr.work.page")
    }

    @ViewBuilder
    private func workHeader(_ work: AsmrWork) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuImageTile(urlString: work.coverURL, accessibilityLabel: work.displayTitle, aspectRatio: 1)
                Text(work.displayTitle)
                    .font(SetuTypography.title)
                    .foregroundStyle(SetuColor.textPrimary)
                if !work.subtitle.isEmpty {
                    Text(work.subtitle)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                ModuleFavoriteButton(environment: environment, snapshot: work.favoriteSnapshot)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func trackList(for work: AsmrWork) -> some View {
        SetuCard {
            switch tracksState {
            case .loading, .idle:
                SetuEmptyState(title: "正在读取音轨", systemImage: "waveform", isLoading: true)
            case .failed(let error):
                SetuEmptyState(title: "音轨加载失败", message: error.message, systemImage: "waveform")
            case .loaded(let tracks):
                if tracks.isEmpty {
                    SetuEmptyState(title: "没有可播放的音轨", systemImage: "waveform")
                } else {
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        SetuSectionHeader(title: "音轨", subtitle: "\(tracks.count) 首")
                        ForEach(tracks) { track in
                            let current = player.currentTrack?.streamURL == track.url
                            Button {
                                play(track, in: tracks, work: work)
                            } label: {
                                HStack {
                                    Image(systemName: current && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .foregroundStyle(SetuColor.brandPink)
                                    Text(track.title)
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("asmr.track.\(track.id)")
                        }
                    }
                }
            }
        }
    }

    private func play(_ track: AsmrTrack, in tracks: [AsmrTrack], work: AsmrWork) {
        if player.currentTrack?.streamURL == track.url {
            player.toggle()
            return
        }
        let queue = AsmrPlayback.queue(tracks, work: work)
        guard let mapped = queue.first(where: { $0.streamURL == track.url }) else { return }
        player.play(
            url: track.url,
            track: mapped,
            context: .album(id: "asmr:\(work.id)", label: work.displayTitle),
            queueTracks: queue
        )
    }

    private func load() async {
        workState = .loading
        tracksState = .loading
        do {
            let work = try await environment.asmrCatalogClient.work(id: workID)
            workState = .loaded(work)
        } catch {
            workState = .failed(UserFacingErrorMapper.map(error))
        }
        do {
            let tracks = try await environment.asmrCatalogClient.tracks(workID: workID)
            tracksState = .loaded(tracks)
        } catch {
            tracksState = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

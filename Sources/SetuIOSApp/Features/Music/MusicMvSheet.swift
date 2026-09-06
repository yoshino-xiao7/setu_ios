import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct MusicMvSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let song: MusicSong

    @State private var detailState: LoadState<MusicMvDetail> = .idle

    var body: some View {
        NavigationStack {
            SetuBoard {
                urlSection
                detailSection
            }
            .accessibilityIdentifier("music.mv")
            #if DEBUG
                .accessibilityValue("details=\(MusicPerformanceProbe.shared.mvDetailCount)")
            #endif

            .setuBackground()
            .navigationTitle("MV")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        switch detailState {
        case .idle, .loading:
            MusicStateSection(title: "MV 详情", stateTitle: "正在加载 MV 详情", systemImage: "play.rectangle", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "MV 详情", stateTitle: "MV 详情加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let detail):
            Section {
                SetuRecordCard(
                    headline: detail.name, supporting: detail.desc ?? detail.briefDesc,
                    thumbnailURLString: detail.cover,
                    fields: [
                        .init(
                            "艺人", detail.artistName ?? detail.artists?.map(\.name).joined(separator: " / ") ?? song.artistNames,
                            isNumeric: false),
                        .init("发布时间", detail.publishTime ?? "暂无", isNumeric: false),
                        .init("播放量", detail.playCount.map(String.init) ?? "暂无"),
                        .init("时长", detail.duration.map(formatDuration) ?? "暂无", isNumeric: false),
                    ])

            }
        }
    }

    @ViewBuilder
    private var urlSection: some View {
        if let mvID = song.mv, mvID > 0 {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "播放 MV")
                        MvPlaybackView(environment: environment, mvID: mvID, suppliedResolutions: detailResolutions) {
                            player.pause()
                        }
                    }
                }

            }
        } else {
            MusicStateSection(title: "播放 MV", stateTitle: "暂无 MV", message: "该歌曲没有可播放的 MV", systemImage: "play.rectangle")
        }
    }

    private var detailResolutions: [MusicMvQuality] {
        if case .loaded(let detail) = detailState { return detail.brs ?? [] }
        return []
    }

    private func load() async {
        guard let mvID = song.mv, mvID > 0 else {
            detailState = .failed("该歌曲没有 MV")
            return
        }
        await loadDetail(mvID: mvID)
    }

    private func loadDetail(mvID: Int) async {
        detailState = .loading
        do {
            let response = try await environment.musicClient.mvDetail(id: mvID)
            guard !Task.isCancelled else { return }
            detailState = .loaded(response.data)
        } catch {
            guard !Task.isCancelled else { return }
            detailState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct MusicMvCoverView: View {
    let urlString: String

    var body: some View {
        MusicArtworkView(
            urlString: urlString,
            width: nil,
            height: 180,
            cornerRadius: 8,
            artworkSize: .lockScreen,
            systemImage: "play.rectangle"
        )
        .frame(maxWidth: .infinity)
    }
}

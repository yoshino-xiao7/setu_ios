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
            List {
                urlSection
                detailSection
            }
            .accessibilityIdentifier("music.mv")
            #if DEBUG
            .accessibilityValue("details=\(MusicPerformanceProbe.shared.mvDetailCount)")
            #endif
            .listStyle(.plain)
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
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "MV 详情")
                        if let cover = detail.cover {
                            MusicMvCoverView(urlString: cover)
                        }
                        VStack(spacing: SetuSpacing.sm) {
                            MusicMetadataRow(title: "标题", value: detail.name)
                            MusicMetadataRow(title: "艺人", value: detail.artistName ?? detail.artists?.map(\.name).joined(separator: " / ") ?? song.artistNames)
                            if let publishTime = detail.publishTime {
                                MusicMetadataRow(title: "发布时间", value: publishTime)
                            }
                            if let playCount = detail.playCount {
                                MusicMetadataRow(title: "播放量", value: "\(playCount)")
                            }
                            if let duration = detail.duration {
                                MusicMetadataRow(title: "时长", value: formatDuration(duration))
                            }
                        }
                        if let description = detail.desc ?? detail.briefDesc, !description.isEmpty {
                            Text(description)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                }
                .setuListRow()
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
                .setuListRow()
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

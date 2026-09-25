import SetuIOSCore
import SwiftUI

struct MusicSimilarRecommendationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RouterPath.self) private var router
    let track: MusicPlaybackTrack
    let environment: AppEnvironment
    let player: MusicPlaybackController

    @State private var state: LoadState<MusicV2SimilarTracks> = .idle
    @State private var selectedTab: RecommendationTab = .tracks

    enum RecommendationTab: String, CaseIterable, Identifiable {
        case tracks = "相似歌曲"
        case playlists = "包含歌单"
        var id: String { rawValue }
    }

    private var trackToken: MusicV2TrackID {
        switch track.id {
        case .legacy(let id):
            return MusicV2TrackID(rawValue: "netease:track:\(id)")
        case .canonical(let token):
            return token
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分类", selection: $selectedTab) {
                    ForEach(RecommendationTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SetuSpacing.md)
                .padding(.vertical, SetuSpacing.sm)

                contentView
            }
            .navigationTitle("相似推荐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task(id: track.id) {
                await loadSimilar()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .idle, .loading:
            SetuEmptyState(title: "正在寻找相似好歌", systemImage: "sparkles", isLoading: true)
                .frame(maxHeight: .infinity)
        case .failed(let message):
            SetuEmptyState(
                title: "加载失败",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { Task { await loadSimilar() } }
            )
            .frame(maxHeight: .infinity)
        case .loaded(let similar):
            if selectedTab == .tracks {
                similarTracksList(similar.tracks)
            } else {
                similarPlaylistsList(similar.playlists)
            }
        }
    }

    private func similarTracksList(_ tracks: [MusicV2Track]) -> some View {
        Group {
            if tracks.isEmpty {
                SetuEmptyState(title: "暂无相似歌曲", message: "网易云曲库暂未收录相关相似推荐", systemImage: "music.note")
                    .frame(maxHeight: .infinity)
            } else {
                List(tracks, id: \.id.rawValue) { simiTrack in
                    SimilarTrackRow(
                        track: simiTrack,
                        allTracks: tracks,
                        currentTitle: track.title,
                        player: player
                    )
                    .setuListRow()
                }
                .listStyle(.plain)
            }
        }
    }

    private func similarPlaylistsList(_ playlists: [MusicV2ProviderPlaylist]) -> some View {
        Group {
            if playlists.isEmpty {
                SetuEmptyState(title: "暂无包含歌单", message: "这首歌暂未被收录进精选歌单", systemImage: "music.note.list")
                    .frame(maxHeight: .infinity)
            } else {
                List(playlists, id: \.id.rawValue) { playlist in
                    SimilarPlaylistRow(playlist: playlist) {
                        dismiss()
                        router.navigate(to: .playlistDetailV2(playlist.id.rawValue))
                    }
                    .setuListRow()
                }
                .listStyle(.plain)
            }
        }
    }

    private func loadSimilar() async {
        state = .loading
        do {
            let result = try await environment.musicV2Client.similar(trackID: trackToken)
            state = .loaded(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct SimilarTrackRow: View {
    let track: MusicV2Track
    let allTracks: [MusicV2Track]
    let currentTitle: String
    let player: MusicPlaybackController

    private var playbackTrack: MusicPlaybackTrack {
        MusicPlaybackTrack(track: track)
    }

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(
                urlString: track.artwork?.url,
                width: 44,
                height: 44,
                cornerRadius: SetuRadius.sm,
                artworkSize: .thumbnail
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(1)
                Text(track.artists.map(\.name).joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Play next button
            Button {
                PlayerHaptics.light()
                player.playNext(playbackTrack)
            } label: {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.subheadline)
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首播放 \(track.title)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            PlayerHaptics.medium()
            Task {
                await player.play(
                    track: playbackTrack,
                    in: allTracks.map(MusicPlaybackTrack.init(track:)),
                    context: .singleTrack(trackID: .canonical(.init(rawValue: track.id.rawValue)), label: "相似推荐：\(currentTitle)")
                )
            }
        }
    }
}

private struct SimilarPlaylistRow: View {
    let playlist: MusicV2ProviderPlaylist
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SetuSpacing.md) {
                MusicArtworkView(
                    urlString: playlist.artwork?.url,
                    width: 52,
                    height: 52,
                    cornerRadius: SetuRadius.md,
                    artworkSize: .thumbnail
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: SetuSpacing.xs) {
                        if let count = playlist.playCount {
                            Label(formatCount(count), systemImage: "play.fill")
                                .font(.caption2)
                                .foregroundStyle(SetuColor.textTertiary)
                        }
                        if let trackCount = playlist.trackCount {
                            Text("• \(trackCount)首")
                                .font(.caption2)
                                .foregroundStyle(SetuColor.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000.0)
        } else if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000.0)
        }
        return "\(count)"
    }
}

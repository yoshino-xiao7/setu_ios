import SetuIOSCore
import SwiftUI

struct SimilarTrackItem: Identifiable, Sendable {
    let id: String
    let title: String
    let artistName: String
    let artworkURL: String?
    let playbackTrack: MusicPlaybackTrack
}

struct SimilarPlaylistItem: Identifiable, Sendable {
    let id: String
    let title: String
    let artworkURL: String?
    let trackCount: Int?
    let playCount: Int?
}

struct SimilarRecommendationsData: Sendable {
    let tracks: [SimilarTrackItem]
    let playlists: [SimilarPlaylistItem]
}

struct MusicSimilarRecommendationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RouterPath.self) private var router: RouterPath?
    let track: MusicPlaybackTrack
    let environment: AppEnvironment
    let player: MusicPlaybackController

    @State private var state: LoadState<SimilarRecommendationsData> = .idle
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

    private var legacySongID: Int? {
        switch track.id {
        case .legacy(let id):
            return id
        case .canonical(let token):
            let raw = token.rawValue
            if raw.starts(with: "netease:track:") {
                return Int(raw.replacingOccurrences(of: "netease:track:", with: ""))
            }
            return nil
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

    private func similarTracksList(_ tracks: [SimilarTrackItem]) -> some View {
        Group {
            if tracks.isEmpty {
                SetuEmptyState(title: "暂无相似歌曲", message: "网易云曲库暂未收录相关相似推荐", systemImage: "music.note")
                    .frame(maxHeight: .infinity)
            } else {
                List(tracks) { simiTrack in
                    SimilarTrackRow(
                        item: simiTrack,
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

    private func similarPlaylistsList(_ playlists: [SimilarPlaylistItem]) -> some View {
        Group {
            if playlists.isEmpty {
                SetuEmptyState(title: "暂无包含歌单", message: "这首歌暂未被收录进精选歌单", systemImage: "music.note.list")
                    .frame(maxHeight: .infinity)
            } else {
                List(playlists) { playlist in
                    SimilarPlaylistRow(playlist: playlist) {
                        dismiss()
                        router?.navigate(to: .playlistDetailV2(playlist.id))
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
            let tracks: [SimilarTrackItem] = result.tracks.map { simiTrack in
                SimilarTrackItem(
                    id: simiTrack.id.rawValue,
                    title: simiTrack.title,
                    artistName: simiTrack.artists.map(\.name).joined(separator: " / "),
                    artworkURL: simiTrack.artwork?.url ?? simiTrack.album?.artwork?.url,
                    playbackTrack: MusicPlaybackTrack(track: simiTrack)
                )
            }
            let playlists: [SimilarPlaylistItem] = result.playlists.map { simiPlaylist in
                SimilarPlaylistItem(
                    id: simiPlaylist.id.rawValue,
                    title: simiPlaylist.title,
                    artworkURL: simiPlaylist.artwork?.url,
                    trackCount: simiPlaylist.trackCount,
                    playCount: simiPlaylist.playCount
                )
            }

            if !tracks.isEmpty || !playlists.isEmpty {
                state = .loaded(SimilarRecommendationsData(tracks: tracks, playlists: playlists))
                return
            }
        } catch {
            // Fall through to NetEase direct API
        }

        guard let songID = legacySongID, songID > 0 else {
            state = .loaded(SimilarRecommendationsData(tracks: [], playlists: []))
            return
        }

        do {
            let cookie = environment.neteaseMusicSession.cookie
            async let songsTask = environment.neteaseMusicApiClient.fetchSimilarSongs(id: songID, cookie: cookie)
            async let playlistsTask = environment.neteaseMusicApiClient.fetchSimilarPlaylists(id: songID, cookie: cookie)
            let (simiSongs, simiPlaylists) = try await (songsTask, playlistsTask)

            let tracks: [SimilarTrackItem] = simiSongs.map { s in
                let artistName = s.artists.map(\.name).joined(separator: " / ")
                let playbackTrack = MusicPlaybackTrack(
                    id: s.id,
                    title: s.name,
                    artist: artistName,
                    album: s.album?.name ?? "",
                    coverURLString: s.album?.picUrl,
                    durationMilliseconds: s.duration ?? 0,
                    mvID: nil
                )
                return SimilarTrackItem(
                    id: "netease:track:\(s.id)",
                    title: s.name,
                    artistName: artistName,
                    artworkURL: s.album?.picUrl,
                    playbackTrack: playbackTrack
                )
            }

            let playlists: [SimilarPlaylistItem] = simiPlaylists.map { p in
                SimilarPlaylistItem(
                    id: "netease:playlist:\(p.id)",
                    title: p.name,
                    artworkURL: p.coverImgUrl,
                    trackCount: p.trackCount,
                    playCount: p.playCount
                )
            }

            state = .loaded(SimilarRecommendationsData(tracks: tracks, playlists: playlists))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct SimilarTrackRow: View {
    let item: SimilarTrackItem
    let allTracks: [SimilarTrackItem]
    let currentTitle: String
    let player: MusicPlaybackController

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(
                urlString: item.artworkURL,
                width: 44,
                height: 44,
                cornerRadius: SetuRadius.sm,
                artworkSize: .thumbnail
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(1)
                Text(item.artistName)
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Play next button
            Button {
                PlayerHaptics.light()
                player.playNext(item.playbackTrack)
            } label: {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.subheadline)
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首播放 \(item.title)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            PlayerHaptics.medium()
            Task {
                await player.play(
                    track: item.playbackTrack,
                    in: allTracks.map(\.playbackTrack),
                    context: .singleTrack(trackID: item.playbackTrack.contextTrackID, label: "相似推荐：\(currentTitle)")
                )
            }
        }
    }
}

private struct SimilarPlaylistRow: View {
    let playlist: SimilarPlaylistItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SetuSpacing.md) {
                MusicArtworkView(
                    urlString: playlist.artworkURL,
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

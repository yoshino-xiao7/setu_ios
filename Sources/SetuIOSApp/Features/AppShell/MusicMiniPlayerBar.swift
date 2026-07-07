import SetuIOSCore
import SwiftUI

struct MusicMiniPlayerBar: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var showingDetail = false

    var body: some View {
        if let track = player.currentTrack {
            Button {
                showingDetail = true
            } label: {
                HStack(spacing: 12) {
                    MusicArtworkView(urlString: track.coverURLString)
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(queueCaption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("停止播放")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDetail) {
                MusicNowPlayingDetailView(environment: environment, player: player)
            }
        }
    }

    private var queueCaption: String {
        let name = player.queueName ?? "当前歌单"
        let count = player.queueTracks.count
        if count > 1 {
            return "\(name) · \(count) 首"
        }
        return "\(name) · 正在播放"
    }
}

private struct MusicNowPlayingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var lyricState: LoadState<MusicLyricResponse> = .idle
    @State private var queueMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let track = player.currentTrack {
                    Section("正在播放") {
                        HStack(spacing: 14) {
                            MusicArtworkView(urlString: track.coverURLString)
                                .frame(width: 72, height: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(track.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(track.album)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack {
                            Button {
                                player.toggle()
                            } label: {
                                Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(role: .destructive) {
                                player.stop()
                                dismiss()
                            } label: {
                                Label("停止", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    lyricSection
                        .task(id: track.id) {
                            await loadLyric(songID: track.id)
                        }

                    queueSection
                } else {
                    ContentUnavailableView("暂无播放", systemImage: "music.note")
                }
            }
            .navigationTitle("歌词")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        if !player.queueTracks.isEmpty {
            Section(player.queueName ?? "当前队列") {
                if let queueMessage {
                    Text(queueMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(player.queueTracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        Task { await playQueuedTrack(track) }
                    } label: {
                        HStack(spacing: 12) {
                            MusicArtworkView(urlString: track.coverURLString)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.subheadline.weight(track.id == player.currentTrack?.id ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if index == player.currentQueueIndex {
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var lyricSection: some View {
        Section("歌词") {
            switch lyricState {
            case .idle, .loading:
                ProgressView("正在加载歌词")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let lyric):
                let rawLyric = lyric.lrc?.lyric ?? ""
                let translation = lyric.tlyric?.lyric ?? ""
                if rawLyric.isEmpty && translation.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "text.quote")
                } else {
                    if !rawLyric.isEmpty {
                        Text(rawLyric)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    if !translation.isEmpty {
                        DisclosureGroup("翻译歌词") {
                            Text(translation)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func loadLyric(songID: Int) async {
        lyricState = .loading
        do {
            lyricState = .loaded(try await environment.musicClient.lyric(songID: songID))
        } catch {
            lyricState = .failed(error.localizedDescription)
        }
    }

    private func playQueuedTrack(_ track: MusicPlaybackTrack) async {
        guard track.id != player.currentTrack?.id else { return }
        queueMessage = "正在切换歌曲"
        do {
            let response = try await environment.musicClient.url(songID: track.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                queueMessage = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可播放地址"
                return
            }
            player.play(url: url, track: track, queueName: player.queueName, queueTracks: player.queueTracks)
            queueMessage = nil
        } catch {
            queueMessage = error.localizedDescription
        }
    }
}

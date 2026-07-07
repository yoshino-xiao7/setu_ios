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
                            .lineLimit(1)
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
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.pink)
                            .frame(width: proxy.size.width * player.playbackProgress, height: 2)
                    }
                    .frame(height: 2)
                }
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
        let name = player.queueName ?? "当前队列"
        let count = player.queueTracks.count
        if count > 1 {
            return "\(name) · \(count) 首"
        }
        return name
    }
}

private struct MusicNowPlayingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var lyricState: LoadState<MusicLyricResponse> = .idle
    @State private var queueMessage: String?
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

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
                                Task { await playAdjacentTrack(offset: -1) }
                            } label: {
                                Image(systemName: "backward.fill")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!player.canPlayPrevious)

                            Button {
                                player.toggle()
                            } label: {
                                Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await playAdjacentTrack(offset: 1) }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!player.canPlayNext)

                            Button(role: .destructive) {
                                player.stop()
                                dismiss()
                            } label: {
                                Label("停止", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: { isScrubbing ? scrubTime : player.currentTimeSeconds },
                                    set: { newValue in
                                        scrubTime = newValue
                                        isScrubbing = true
                                    }
                                ),
                                in: 0...max(player.durationSeconds, 1),
                                onEditingChanged: { editing in
                                    if editing {
                                        isScrubbing = true
                                        scrubTime = player.currentTimeSeconds
                                    } else {
                                        player.seek(to: scrubTime)
                                        isScrubbing = false
                                    }
                                }
                            )
                            .disabled(player.durationSeconds <= 0)

                            HStack {
                                Text(formatTime(isScrubbing ? scrubTime : player.currentTimeSeconds))
                                Spacer()
                                Text(formatTime(player.durationSeconds))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
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
        await play(track)
    }

    private func playAdjacentTrack(offset: Int) async {
        guard let track = player.queuedTrack(offsetBy: offset) else { return }
        await play(track)
    }

    private func play(_ track: MusicPlaybackTrack) async {
        queueMessage = "正在准备播放"
        do {
            let response = try await environment.musicClient.url(songID: track.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                queueMessage = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "这首歌暂时无法播放"
                return
            }
            player.play(url: url, track: track, queueName: player.queueName, queueTracks: player.queueTracks)
            queueMessage = nil
        } catch {
            queueMessage = error.localizedDescription
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

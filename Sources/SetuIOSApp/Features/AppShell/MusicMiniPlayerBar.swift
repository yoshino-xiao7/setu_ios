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
                HStack(spacing: SetuSpacing.md) {
                    MusicArtworkView(urlString: track.coverURLString)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(1)
                        Text(queueCaption)
                            .font(.caption2)
                            .foregroundStyle(SetuColor.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(SetuColor.heroGradient, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }
                .padding(.horizontal, SetuSpacing.md)
                .padding(.vertical, SetuSpacing.sm)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                        .stroke(SetuColor.separator, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(SetuColor.heroGradient)
                            .frame(width: proxy.size.width * player.playbackProgress, height: 2)
                    }
                    .frame(height: 2)
                    .clipShape(Capsule())
                }
                .shadow(color: SetuColor.brandPink.opacity(0.16), radius: 14, y: 8)
                .padding(.horizontal, SetuSpacing.lg)
                .padding(.vertical, SetuSpacing.sm)
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
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                                SetuSectionHeader(title: "正在播放", subtitle: queueCaption)
                                HStack(spacing: SetuSpacing.md) {
                                    MusicArtworkView(urlString: track.coverURLString)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                        Text(track.title)
                                            .font(SetuTypography.headline)
                                            .foregroundStyle(SetuColor.textPrimary)
                                            .lineLimit(2)
                                        Text(track.artist)
                                            .font(.subheadline)
                                            .foregroundStyle(SetuColor.textSecondary)
                                        Text(track.album)
                                            .font(SetuTypography.caption)
                                            .foregroundStyle(SetuColor.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }

                                if player.isBuffering || player.playbackError != nil {
                                    playbackStatusRow
                                }

                                HStack(spacing: SetuSpacing.sm) {
                                    Button {
                                        player.cyclePlayMode()
                                    } label: {
                                        Image(systemName: player.playMode.systemImage)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("播放模式：\(player.playMode.title)")

                                    Button {
                                        Task { await player.userSkip(by: -1) }
                                    } label: {
                                        Image(systemName: "backward.fill")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!player.canPlayPrevious)

                                    Button {
                                        player.toggle()
                                    } label: {
                                        Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(SetuColor.brandPink)

                                    Button {
                                        Task { await player.userSkip(by: 1) }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!player.canPlayNext)

                                    Button(role: .destructive) {
                                        player.stop()
                                        dismiss()
                                    } label: {
                                        Image(systemName: "stop.circle")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("停止")
                                }

                                VStack(spacing: SetuSpacing.xs) {
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
                                    .tint(SetuColor.brandPink)
                                    .disabled(player.durationSeconds <= 0)

                                    HStack {
                                        Text(formatTime(isScrubbing ? scrubTime : player.currentTimeSeconds))
                                        Spacer()
                                        Text(formatTime(player.durationSeconds))
                                    }
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(SetuColor.textSecondary)
                                }
                            }
                        }
                    }
                    .setuListRow()

                    lyricSection
                        .task(id: track.id) {
                            await loadLyric(songID: track.id)
                        }

                    queueSection
                } else {
                    Section {
                        SetuEmptyState(title: "暂无播放", message: "从音乐页选择一首歌开始播放", systemImage: "music.note")
                    }
                    .setuListRow()
                }
            }
            .listStyle(.plain)
            .setuBackground()
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
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: player.queueName ?? "当前队列", subtitle: "\(player.queueTracks.count) 首歌曲")
                        if let queueMessage {
                            Text(queueMessage)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }

                        ForEach(Array(player.queueTracks.enumerated()), id: \.offset) { index, track in
                            Button {
                                Task { await playQueuedTrack(track) }
                            } label: {
                                HStack(spacing: SetuSpacing.md) {
                                    MusicArtworkView(urlString: track.coverURLString)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                        Text(track.title)
                                            .font(.subheadline.weight(track.id == player.currentTrack?.id ? .semibold : .regular))
                                            .foregroundStyle(SetuColor.textPrimary)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundStyle(SetuColor.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if index == player.currentQueueIndex {
                                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                            .foregroundStyle(SetuColor.brandPink)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .setuListRow()
        }
    }

    @ViewBuilder
    private var lyricSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "歌词")
                    switch lyricState {
                    case .idle, .loading:
                        SetuEmptyState(title: "正在加载歌词", message: "歌词会随当前歌曲自动刷新", systemImage: "text.quote", isLoading: true)
                    case .failed(let message):
                        SetuEmptyState(title: "歌词加载失败", message: message, systemImage: "exclamationmark.triangle")
                    case .loaded(let lyric):
                        let rawLyric = lyric.lrc?.lyric ?? ""
                        let translation = lyric.tlyric?.lyric ?? ""
                        if rawLyric.isEmpty && translation.isEmpty {
                            SetuEmptyState(title: "暂无歌词", message: "这首歌暂时没有可用歌词", systemImage: "text.quote")
                        } else {
                            if !rawLyric.isEmpty {
                                Text(rawLyric)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .textSelection(.enabled)
                            }
                            if !translation.isEmpty {
                                DisclosureGroup("翻译歌词") {
                                    Text(translation)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(SetuColor.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
        .setuListRow()
    }

    private var queueCaption: String {
        let name = player.queueName ?? "当前队列"
        let count = player.queueTracks.count
        if count > 1 {
            return "\(name) · \(count) 首"
        }
        return name
    }

    private func loadLyric(songID: Int) async {
        lyricState = .loading
        do {
            lyricState = .loaded(try await environment.musicClient.lyric(songID: songID))
        } catch {
            lyricState = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private var playbackStatusRow: some View {
        if let error = player.playbackError {
            HStack(spacing: SetuSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SetuColor.brandPink)
                Text(error)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("重新获取") {
                    Task { await player.retryCurrent() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        } else if player.isBuffering {
            HStack(spacing: SetuSpacing.sm) {
                ProgressView()
                Text("正在缓冲…")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func playQueuedTrack(_ track: MusicPlaybackTrack) async {
        guard track.id != player.currentTrack?.id else { return }
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

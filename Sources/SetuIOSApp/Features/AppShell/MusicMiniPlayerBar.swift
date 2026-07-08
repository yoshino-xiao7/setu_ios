import SetuIOSCore
import SwiftUI

struct MusicMiniPlayerBar: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var showingDetail = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: SetuSpacing.md) {
                MusicArtworkView(urlString: track.coverURLString, width: 48, height: 48, cornerRadius: SetuRadius.sm)

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
                        .frame(width: 44, height: 44)
                        .background(SetuColor.heroGradient, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                Button {
                    Task { await player.userSkip(by: 1) }
                } label: {
                    Image(systemName: "forward.fill")
                        .foregroundStyle(SetuColor.brandPink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!player.canPlayNext)
                .opacity(player.canPlayNext ? 1 : 0.35)
                .accessibilityLabel("下一首")
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
            .contentShape(RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .onTapGesture {
                showingDetail = true
            }
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.height < -36 {
                            showingDetail = true
                        } else if value.translation.width < -44 {
                            Task { await player.userSkip(by: 1) }
                        } else if value.translation.width > 44 {
                            Task { await player.userSkip(by: -1) }
                        }
                    }
            )
            .sheet(isPresented: $showingDetail) {
                MusicNowPlayingDetailView(environment: environment, player: player)
                    .presentationDragIndicator(.visible)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController

    @State private var lyricState: LoadState<MusicLyricResponse> = .idle
    @State private var queueMessage: String?
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var showingQueue = true
    @State private var actionMessage: String?
    @State private var isDownloading = false
    @State private var lyricFontScale: LyricFontScale = .medium
    @State private var keepsScreenAwakeForLyrics = false

    var body: some View {
        NavigationStack {
            ZStack {
                detailBackground
                    .ignoresSafeArea()

                if let track = player.currentTrack {
                    ScrollView {
                        VStack(spacing: SetuSpacing.xl) {
                            Capsule()
                                .fill(SetuColor.textTertiary.opacity(0.35))
                                .frame(width: 42, height: 5)
                                .padding(.top, SetuSpacing.sm)

                            artworkHero(for: track)

                            trackHeader(for: track)

                            if player.isBuffering || player.playbackError != nil {
                                SetuCard {
                                    playbackStatusRow
                                }
                                .padding(.horizontal, SetuSpacing.lg)
                            }

                            playbackScrubber
                                .padding(.horizontal, SetuSpacing.lg)

                            playbackControls
                                .padding(.horizontal, SetuSpacing.lg)

                            secondaryActions(for: track)

                            if let actionMessage {
                                SetuPill(text: actionMessage, systemImage: "info.circle", tone: .info)
                            }

                            lyricSection
                                .task(id: track.id) {
                                    await loadLyric(songID: track.id)
                                }

                            if showingQueue {
                                queueSection
                            }
                        }
                        .padding(.bottom, SetuSpacing.xxl)
                    }
                    .gesture(detailSwipeGesture)
                } else {
                    SetuEmptyState(title: "暂无播放", message: "从音乐页选择一首歌开始播放", systemImage: "music.note")
                        .padding()
                }
            }
            .navigationTitle("正在播放")
            .musicInlineNavigationTitle()
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .onChange(of: keepsScreenAwakeForLyrics) { _, enabled in
                setIdleTimerDisabled(enabled)
            }
            .onDisappear {
                setIdleTimerDisabled(false)
            }
        }
    }

    private var detailBackground: some View {
        ZStack {
            SetuColor.pageGradient
            RadialGradient(
                colors: [
                    SetuColor.brandSoft.opacity(0.45),
                    SetuColor.bgBase.opacity(0.08)
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
        }
    }

    private func artworkHero(for track: MusicPlaybackTrack) -> some View {
        GeometryReader { proxy in
            let artSize = min(proxy.size.width * 0.78, 360)
            MusicArtworkView(
                urlString: track.coverURLString,
                width: artSize,
                height: artSize,
                cornerRadius: SetuRadius.lg,
                artworkSize: .lockScreen
            )
            .shadow(color: SetuColor.brandPink.opacity(0.24), radius: 24, y: 16)
            .scaleEffect(player.isPlaying && !reduceMotion ? 1.02 : 0.98)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: player.isPlaying)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 380)
    }

    private func trackHeader(for track: MusicPlaybackTrack) -> some View {
        VStack(spacing: SetuSpacing.sm) {
            Text(track.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.artist)
                .font(.headline)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(1)
            Text(track.album)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textTertiary)
                .lineLimit(1)
            SetuPill(text: queueCaption, systemImage: "music.note.list", tone: .brand)
        }
        .padding(.horizontal, SetuSpacing.lg)
    }

    private var playbackScrubber: some View {
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
                if player.isBuffering {
                    Label("缓冲", systemImage: "hourglass")
                }
                Spacer()
                Text(formatTime(player.durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(SetuColor.textSecondary)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: SetuSpacing.md) {
            NowPlayingRoundButton(
                systemImage: player.playMode.systemImage,
                label: "播放模式：\(player.playMode.title)",
                tint: SetuColor.info,
                action: player.cyclePlayMode
            )

            NowPlayingRoundButton(
                systemImage: "backward.fill",
                label: "上一首",
                tint: SetuColor.brandInk,
                disabled: !player.canPlayPrevious
            ) {
                Task { await player.userSkip(by: -1) }
            }

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(SetuColor.heroGradient, in: Circle())
                    .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            NowPlayingRoundButton(
                systemImage: "forward.fill",
                label: "下一首",
                tint: SetuColor.brandInk,
                disabled: !player.canPlayNext
            ) {
                Task { await player.userSkip(by: 1) }
            }

            NowPlayingRoundButton(
                systemImage: showingQueue ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                label: "队列",
                tint: SetuColor.info
            ) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                    showingQueue.toggle()
                }
            }
        }
    }

    private func secondaryActions(for track: MusicPlaybackTrack) -> some View {
        HStack(spacing: SetuSpacing.md) {
            NowPlayingActionButton(title: "收藏", systemImage: "text.badge.plus") {
                actionMessage = "收藏到歌单请从歌曲列表入口操作"
            }

            NowPlayingActionButton(
                title: isDownloading ? "准备中" : "下载",
                systemImage: isDownloading ? "hourglass" : "arrow.down"
            ) {
                Task { await download(track) }
            }
            .disabled(isDownloading)

            ShareLink(item: "\(track.title) - \(track.artist)") {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SetuColor.surfaceMuted, in: Capsule())

            NowPlayingActionButton(title: "睡眠定时", systemImage: "moon.zzz") {
                actionMessage = "睡眠定时将在 P2 阶段接入"
            }
        }
        .padding(.horizontal, SetuSpacing.lg)
    }

    @ViewBuilder
    private var queueSection: some View {
        if !player.queueTracks.isEmpty {
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
                                MusicArtworkView(urlString: track.coverURLString, width: 44, height: 44, cornerRadius: SetuRadius.sm)
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
            .padding(.horizontal, SetuSpacing.lg)
        }
    }

    @ViewBuilder
    private var lyricSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "歌词", subtitle: "点击歌词可跳转播放进度")
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
                        HStack(spacing: SetuSpacing.sm) {
                            Picker("歌词字号", selection: $lyricFontScale) {
                                ForEach(LyricFontScale.allCases) { scale in
                                    Text(scale.title).tag(scale)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("歌词字号")

                            Toggle(isOn: $keepsScreenAwakeForLyrics) {
                                Image(systemName: "lightbulb")
                            }
                            .labelsHidden()
                            .tint(SetuColor.brandPink)
                            .accessibilityLabel("查看歌词时保持屏幕常亮")
                        }

                        LyricScrollView(
                            lines: LyricParser.parse(rawLyric, translation: translation),
                            currentTime: player.currentTimeSeconds,
                            fontScale: lyricFontScale,
                            onSeek: player.seek(to:)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, SetuSpacing.lg)
    }

    private var detailSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                if value.translation.height > 72 {
                    dismiss()
                } else if value.translation.width < -56 {
                    Task { await player.userSkip(by: 1) }
                } else if value.translation.width > 56 {
                    Task { await player.userSkip(by: -1) }
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
                    .tint(SetuColor.brandPink)
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

    private func download(_ track: MusicPlaybackTrack) async {
        isDownloading = true
        actionMessage = "正在准备下载"
        defer { isDownloading = false }
        do {
            let response = try await environment.musicClient.url(songID: track.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                actionMessage = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "这首歌暂时无法下载"
                return
            }
            let filename = "\(track.title) - \(track.artist).mp3"
            let signed = try await environment.downloadClient.sign(url: urlString, filename: filename)
            guard let url = URL(string: signed.downloadUrl) else {
                actionMessage = "下载地址无效"
                return
            }
            openURL(url)
            actionMessage = "已打开下载地址"
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

private struct NowPlayingRoundButton: View {
    let systemImage: String
    let label: String
    var tint: Color = SetuColor.brandPink
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(disabled ? SetuColor.textTertiary : tint)
                .frame(width: 50, height: 50)
                .background(SetuColor.surfaceMuted, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }
}

private struct NowPlayingActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SetuColor.brandInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(SetuColor.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func musicInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

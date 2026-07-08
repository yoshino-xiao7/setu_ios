import SetuIOSCore
import SwiftUI

#if os(iOS)
import CoreImage
import UIKit
#endif

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
    @State private var showingQueueManager = false
    @State private var playlistTrack: MusicPlaybackTrack?
    @State private var artworkAccentColor: Color?

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
            .sheet(isPresented: $showingQueueManager) {
                MusicQueueManagerSheet(player: player)
            }
            .sheet(item: $playlistTrack) { track in
                AddPlaybackTrackToPlaylistSheet(environment: environment, track: track)
            }
            .task(id: player.currentTrack?.id) {
                if let track = player.currentTrack {
                    await loadArtworkAccent(for: track)
                } else {
                    artworkAccentColor = nil
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
            LinearGradient(
                colors: [
                    (artworkAccentColor ?? SetuColor.brandSoft).opacity(0.42),
                    SetuColor.bgBase,
                    SetuColor.brandSoft.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    (artworkAccentColor ?? SetuColor.brandPink).opacity(0.36),
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
                label: "管理队列",
                tint: SetuColor.info
            ) {
                showingQueueManager = true
            }
        }
    }

    private func secondaryActions(for track: MusicPlaybackTrack) -> some View {
        HStack(spacing: SetuSpacing.md) {
            NowPlayingActionButton(title: "收藏", systemImage: "text.badge.plus") {
                playlistTrack = track
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

            Menu {
                ForEach(MusicSleepTimerOption.allCases) { option in
                    Button(option.title) {
                        player.startSleepTimer(option)
                        actionMessage = "睡眠定时：\(option.title)"
                    }
                }
                if player.sleepTimerTitle != nil {
                    Divider()
                    Button("取消定时", role: .destructive) {
                        player.cancelSleepTimer()
                        actionMessage = "已取消睡眠定时"
                    }
                }
            } label: {
                Label(player.sleepTimerTitle ?? "睡眠定时", systemImage: "moon.zzz")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SetuColor.surfaceMuted, in: Capsule())
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
        guard let resolution = await player.resolveTrackURL?(track) else {
            queueMessage = "播放器尚未准备好"
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: player.queueName, queueTracks: player.queueTracks, notice: notice)
            queueMessage = notice
        case .unavailable(let reason):
            queueMessage = reason
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

    private func loadArtworkAccent(for track: MusicPlaybackTrack) async {
        artworkAccentColor = nil
        #if os(iOS)
        guard let urlString = secureURLString(track.coverURLString, artworkSize: .thumbnail),
              let url = URL(string: urlString) else { return }
        do {
            let data = try await RemoteArtworkLoader.shared.data(from: url)
            guard !Task.isCancelled, let image = UIImage(data: data) else { return }
            let color = image.setuAverageColor.map(Color.init(uiColor:))
            await MainActor.run {
                if player.currentTrack?.id == track.id {
                    artworkAccentColor = color
                }
            }
        } catch {
            // The fixed soft-pink background remains the fallback when artwork is unavailable.
        }
        #endif
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

private struct MusicQueueManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var player: MusicPlaybackController

    var body: some View {
        NavigationStack {
            List {
                if player.queueTracks.isEmpty {
                    SetuEmptyState(title: "队列为空", message: "从音乐页选择歌曲后会显示在这里", systemImage: "music.note.list")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(player.queueTracks) { track in
                            queueRow(track)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        player.removeQueuedTrack(track)
                                    } label: {
                                        Label("移除", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove(perform: player.moveQueueTracks)
                    } header: {
                        Text(player.queueName ?? "当前队列")
                    } footer: {
                        Text("拖动可调整播放顺序，左滑可移除歌曲。")
                    }
                }
            }
            .musicQueueListStyle()
            .navigationTitle("播放队列")
            .musicInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if player.queueTracks.count > 1 {
                        Button("清空待播", role: .destructive) {
                            player.clearUpcomingTracks()
                        }
                    }
                    #if os(iOS)
                    EditButton()
                    #endif
                }
            }
        }
    }

    private func queueRow(_ track: MusicPlaybackTrack) -> some View {
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
            Spacer(minLength: SetuSpacing.sm)
            if track.id == player.currentTrack?.id {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(SetuColor.brandPink)
                    .accessibilityLabel("正在播放")
            } else {
                Menu {
                    Button {
                        player.playNext(track)
                    } label: {
                        Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button(role: .destructive) {
                        player.removeQueuedTrack(track)
                    } label: {
                        Label("移除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("队列操作")
            }
        }
        .frame(minHeight: 52)
    }
}

private struct AddPlaybackTrackToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let track: MusicPlaybackTrack
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        HStack(spacing: SetuSpacing.md) {
                            MusicArtworkView(urlString: track.coverURLString)
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(track.title)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .lineLimit(2)
                                Text(track.artist)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .setuListRow()
                }

                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "info.circle", tone: .info)
                    }
                }

                switch state {
                case .idle, .loading:
                    Section {
                        SetuEmptyState(title: "正在加载歌单", systemImage: "music.note.list", isLoading: true)
                    }
                case .failed(let error):
                    Section {
                        SetuEmptyState(title: "歌单加载失败", message: error, systemImage: "exclamationmark.triangle")
                    }
                case .loaded(let playlists):
                    if playlists.isEmpty {
                        Section {
                            SetuEmptyState(title: "暂无歌单", message: "先创建歌单再收藏当前歌曲。", systemImage: "music.note.list")
                        }
                    } else {
                        Section("选择歌单") {
                            ForEach(playlists) { playlist in
                                Button {
                                    Task { await add(to: playlist) }
                                } label: {
                                    HStack(spacing: SetuSpacing.md) {
                                        MusicArtworkView(urlString: playlist.coverUrl)
                                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                            Text(playlist.name)
                                                .font(SetuTypography.headline)
                                                .foregroundStyle(SetuColor.textPrimary)
                                                .lineLimit(1)
                                            Text("\(playlist.songCount ?? 0) 首")
                                                .font(SetuTypography.caption)
                                                .foregroundStyle(SetuColor.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(SetuColor.brandPink)
                                    }
                                    .frame(minHeight: 56)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("收藏到歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func add(to playlist: UserMusicPlaylist) async {
        message = "正在加入 \(playlist.name)"
        do {
            try await environment.musicClient.add(
                AddSongToPlaylistRequest(
                    songId: track.id,
                    songName: track.title,
                    artistName: track.artist,
                    albumName: track.album,
                    coverUrl: track.coverURLString,
                    duration: track.durationMilliseconds
                ),
                toPlaylist: playlist.id
            )
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

#if os(iOS)
private extension UIImage {
    var setuAverageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: inputImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        )
        guard let outputImage = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}
#endif

private extension View {
    @ViewBuilder
    func musicInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func musicQueueListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.automatic)
        #endif
    }
}

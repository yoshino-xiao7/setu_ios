import SetuIOSCore
import SwiftUI

#if os(iOS)
import CoreImage
import UIKit
#endif

struct MusicMiniPlayerBar: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    var onShowQueue: (() -> Void)?
    @State private var showingDetail = false
    @State private var initialDetailPage: NowPlayingPage = .cover
    @State private var isCollapsed = false

    var body: some View {
        if let track = player.currentTrack {
            HStack {
                if isCollapsed {
                    collapsedHandle(for: track)
                } else {
                    expandedBar(for: track)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .trailing : .center)
            .padding(.horizontal, isCollapsed ? 0 : SetuSpacing.md)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCollapsed)
            .sheet(isPresented: $showingDetail) {
                MusicNowPlayingDetailView(environment: environment, player: player, initialPage: initialDetailPage)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func expandedBar(for track: MusicPlaybackTrack) -> some View {
        HStack(spacing: SetuSpacing.sm) {
            Button {
                isCollapsed = true
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 36, height: 44)
            }
            .setuButtonFeedback(cornerRadius: 22)
            .accessibilityLabel("收起迷你播放器")

            MusicArtworkView(
                urlString: track.coverURLString,
                width: 44,
                height: 44,
                cornerRadius: SetuRadius.sm,
                onTap: { openDetail(.cover) }
            )

            Button {
                openDetail(.cover)
            } label: {
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .setuButtonFeedback()
            .accessibilityLabel("打开正在播放：\(track.title)")

            MiniPlayerCircularPlayButton(
                isPlaying: player.isPlaying,
                progress: player.playbackProgress
            ) {
                PlayerHaptics.light()
                player.toggle()
            }

            Button {
                onShowQueue?()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                    Text("\(player.queueTracks.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(SetuColor.brandInk)
                .frame(width: 48, height: 48)
                .background(SetuColor.surfaceMuted, in: Circle())
            }
            .setuButtonFeedback(cornerRadius: 24)
            .accessibilityLabel("查看当前播放列表")
        }
        .padding(.horizontal, SetuSpacing.sm)
        .padding(.vertical, SetuSpacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
        .shadow(color: SetuColor.brandPink.opacity(0.14), radius: 12, y: 6)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height < -36 {
                        openDetail(.cover)
                    } else if value.translation.width > 44 {
                        isCollapsed = true
                    }
                }
        )
    }

    private func collapsedHandle(for track: MusicPlaybackTrack) -> some View {
        Button {
            isCollapsed = false
        } label: {
            HStack(spacing: SetuSpacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SetuColor.brandInk)
                    .frame(width: 24, height: 44)

                MusicArtworkView(
                    urlString: track.coverURLString,
                    width: 42,
                    height: 42,
                    cornerRadius: SetuRadius.sm
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(SetuColor.heroGradient, in: Circle())
                }
            }
            .padding(.leading, SetuSpacing.xs)
            .padding(.trailing, SetuSpacing.sm)
            .padding(.vertical, SetuSpacing.xs)
            .frame(minWidth: 84, minHeight: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(SetuColor.separator, lineWidth: 1)
            }
            .shadow(color: SetuColor.brandPink.opacity(0.14), radius: 12, y: 6)
            .contentShape(Capsule())
        }
        .setuButtonFeedback(cornerRadius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("展开迷你播放器")
    }

    private func openDetail(_ page: NowPlayingPage) {
        initialDetailPage = page
        showingDetail = true
    }
}

private struct MiniPlayerCircularPlayButton: View {
    let isPlaying: Bool
    let progress: Double
    let action: () -> Void

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(SetuColor.surfaceMuted, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        SetuColor.heroGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(SetuColor.heroGradient)
                    .padding(6)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.leading, isPlaying ? 0 : 2)
            }
            .frame(width: 50, height: 50)
        }
        .setuButtonFeedback(cornerRadius: 25)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }
}

// MARK: - Queue drawer

struct MusicQueueDrawerView: View {
    @Bindable var player: MusicPlaybackController
    let onDismiss: () -> Void

    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(SetuColor.textTertiary.opacity(0.36))
                .frame(width: 40, height: 5)
                .padding(.top, SetuSpacing.sm)
                .padding(.bottom, SetuSpacing.md)

            HStack(spacing: SetuSpacing.md) {
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("当前播放")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(queueCaption)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if player.queueTracks.count > 1 {
                    Button(role: .destructive) {
                        PlayerHaptics.medium()
                        player.clearUpcomingTracks()
                        showToast("已清空待播歌曲")
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .setuButtonFeedback(cornerRadius: 22)
                    .accessibilityLabel("清空待播歌曲")
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(SetuColor.surfaceMuted, in: Circle())
                }
                .setuButtonFeedback(cornerRadius: 22)
                .accessibilityLabel("关闭当前播放")
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.bottom, SetuSpacing.sm)

            if let toast {
                SetuPill(text: toast, systemImage: "info.circle", tone: .info)
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.bottom, SetuSpacing.sm)
                    .transition(.opacity)
            }

            Divider().overlay(SetuColor.separator)

            if player.queueTracks.isEmpty {
                SetuEmptyState(title: "队列为空", message: "从音乐页选择歌曲后会显示在这里", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(SetuSpacing.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.queueTracks.enumerated()), id: \.element.id) { index, track in
                            MusicQueueDrawerRow(
                                track: track,
                                isCurrent: track.id == player.currentTrack?.id,
                                isPlaying: player.isPlaying,
                                play: {
                                    Task { await playQueuedTrack(track) }
                                },
                                playNext: {
                                    PlayerHaptics.light()
                                    player.playNext(track)
                                    showToast("已设为下一首播放")
                                },
                                remove: {
                                    player.removeQueuedTrack(track)
                                }
                            )
                            .padding(.horizontal, SetuSpacing.lg)

                            if index < player.queueTracks.count - 1 {
                                Divider()
                                    .overlay(SetuColor.separator)
                                    .padding(.leading, SetuSpacing.lg + 56)
                            }
                        }
                    }
                    .padding(.vertical, SetuSpacing.xs)
                }
                .frame(maxHeight: 420)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
        .shadow(color: SetuColor.brandPink.opacity(0.18), radius: 24, y: 14)
        .onDisappear {
            toastTask?.cancel()
        }
    }

    private var queueCaption: String {
        let name = player.queueName ?? "当前队列"
        let count = player.queueTracks.count
        return count > 1 ? "\(name) · \(count) 首" : name
    }

    private func playQueuedTrack(_ track: MusicPlaybackTrack) async {
        guard track.id != player.currentTrack?.id else { return }
        PlayerHaptics.light()
        guard let resolution = await player.resolveTrackURL?(track) else {
            showToast("播放器尚未准备好")
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: player.queueName, queueTracks: player.queueTracks, notice: notice)
            if let notice {
                showToast(notice)
            }
        case .unavailable(let reason):
            showToast(reason)
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

private struct MusicQueueDrawerRow: View {
    let track: MusicPlaybackTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let play: () -> Void
    let playNext: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(
                urlString: track.coverURLString,
                width: 44,
                height: 44,
                cornerRadius: SetuRadius.sm,
                onTap: play
            )

            Button(action: play) {
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(track.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? SetuColor.brandInk : SetuColor.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .setuButtonFeedback()
            .disabled(isCurrent)

            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("正在播放")
            } else {
                Menu {
                    Button {
                        playNext()
                    } label: {
                        Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label("移除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("队列操作")
            }
        }
        .frame(minHeight: 56)
    }
}

// MARK: - Now Playing (full player)

private enum NowPlayingPage: String, CaseIterable, Identifiable {
    case cover
    case lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cover: "音乐"
        case .lyrics: "歌词"
        }
    }

    var systemImage: String {
        switch self {
        case .cover: "music.note"
        case .lyrics: "text.quote"
        }
    }
}

private struct MusicNowPlayingDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController

    @State private var page: NowPlayingPage
    @State private var lyricState: LoadState<MusicLyricResponse> = .idle
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var isDownloading = false
    @State private var playlistTrack: MusicPlaybackTrack?
    @State private var mvTrack: MusicPlaybackTrack?
    @State private var artworkAccentColor: Color?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    init(environment: AppEnvironment, player: MusicPlaybackController, initialPage: NowPlayingPage = .cover) {
        self.environment = environment
        self.player = player
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            detailBackground
                .ignoresSafeArea()

            if let track = player.currentTrack {
                VStack(spacing: SetuSpacing.md) {
                    detailHeader

                    nowPlayingPageContent(for: track)

                    bottomPanel(for: track)
                }
                .padding(.top, SetuSpacing.md)
                .padding(.bottom, SetuSpacing.lg)
                .task(id: track.id) {
                    await loadLyric(songID: track.id)
                }
                .task(id: track.id) {
                    await loadArtworkAccent(for: track)
                }
            } else {
                SetuEmptyState(title: "暂无播放", message: "从音乐页选择一首歌开始播放", systemImage: "music.note")
                    .padding()
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.vertical, SetuSpacing.sm)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(SetuColor.separator, lineWidth: 1)
                    }
                    .padding(.top, SetuSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: toast)
        .sheet(item: $playlistTrack) { track in
            AddPlaybackTrackToPlaylistSheet(environment: environment, track: track)
        }
        .sheet(item: $mvTrack) { track in
            NavigationStack {
                if let mvID = track.mvID, mvID > 0 {
                    MvPlaybackView(environment: environment, mvID: mvID) {
                        player.pause()
                    }
                    .padding(SetuSpacing.md)
                    .setuBackground()
                    .navigationTitle("MV")
                    .musicInlineNavigationTitle()
                    .toolbar {
                        Button("关闭") {
                            mvTrack = nil
                        }
                    }
                } else {
                    SetuEmptyState(title: "暂无 MV", message: "当前歌曲没有可播放的 MV", systemImage: "play.rectangle")
                        .padding()
                        .setuBackground()
                }
            }
        }
        .onDisappear {
            toastTask?.cancel()
        }
    }

    // MARK: Header

    private var detailHeader: some View {
        HStack(spacing: SetuSpacing.md) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(SetuColor.surfaceMuted.opacity(0.7), in: Circle())
            }
            .setuButtonFeedback(cornerRadius: 22)
            .accessibilityLabel("收起播放页")

            Spacer()

            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textTertiary)
                Text(queueCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let timerTitle = player.sleepTimerTitle {
                SetuPill(text: timerTitle, systemImage: "moon.zzz.fill", tone: .info)
                    .accessibilityLabel("睡眠定时：\(timerTitle)")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, SetuSpacing.lg)
    }

    // MARK: Pages

    @ViewBuilder
    private func nowPlayingPageContent(for track: MusicPlaybackTrack) -> some View {
        ZStack {
            switch page {
            case .cover:
                coverPage(for: track)
                    .transition(.opacity)
            case .lyrics:
                lyricsPage(for: track)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
    }

    private func coverPage(for track: MusicPlaybackTrack) -> some View {
        // Artwork adapts to whatever the page area offers, so controls stay
        // on-screen for iPhone SE and the art still fills a Pro Max.
        GeometryReader { proxy in
            let side = max(min(proxy.size.width - SetuSpacing.xxl * 2, proxy.size.height * 0.62, 360), 120)
            VStack(spacing: SetuSpacing.xl) {
                Spacer(minLength: 0)

                MusicArtworkView(
                    urlString: track.coverURLString,
                    width: side,
                    height: side,
                    cornerRadius: SetuRadius.lg,
                    artworkSize: .lockScreen,
                    onTap: {
                        PlayerHaptics.light()
                        showLyrics()
                    }
                )
                .shadow(color: SetuColor.brandPink.opacity(0.24), radius: 24, y: 16)
                .scaleEffect(player.isPlaying && !reduceMotion ? 1.0 : 0.92)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78), value: player.isPlaying)
                .accessibilityLabel("歌曲封面，点击查看歌词")

                VStack(spacing: SetuSpacing.xs) {
                    Text(track.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("\(track.artist) — \(track.album)")
                        .font(.subheadline)
                        .foregroundStyle(SetuColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .padding(.horizontal, SetuSpacing.xl)

                if track.hasMV {
                    Button {
                        mvTrack = track
                    } label: {
                        Label("观看 MV", systemImage: "play.rectangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SetuColor.brandInk)
                            .frame(minHeight: 44)
                            .padding(.horizontal, SetuSpacing.lg)
                            .background(SetuColor.brandSoft.opacity(0.24), in: Capsule())
                    }
                    .setuButtonFeedback(cornerRadius: 22)
                    .accessibilityLabel("观看 \(track.title) 的 MV")
                }

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(trackSkipGesture)
    }

    private func lyricsPage(for track: MusicPlaybackTrack) -> some View {
        VStack(spacing: 0) {
            switch lyricState {
            case .idle, .loading:
                Spacer()
                SetuEmptyState(title: "正在加载歌词", systemImage: "text.quote", isLoading: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        PlayerHaptics.light()
                        showCover()
                    }
                Spacer()
            case .failed(let message):
                Spacer()
                SetuEmptyState(title: "歌词加载失败", message: message, systemImage: "exclamationmark.triangle")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        PlayerHaptics.light()
                        showCover()
                    }
                Spacer()
            case .loaded(let lyric):
                let rawLyric = lyric.lrc?.lyric ?? ""
                let translation = lyric.tlyric?.lyric ?? ""
                if rawLyric.isEmpty && translation.isEmpty {
                    Spacer()
                    SetuEmptyState(title: "暂无歌词", message: "这首歌暂时没有可用歌词", systemImage: "text.quote")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            PlayerHaptics.light()
                            showCover()
                        }
                    Spacer()
                } else {
                    LyricScrollView(
                        lines: LyricParser.parse(rawLyric, translation: translation),
                        currentTime: player.currentTimeSeconds,
                        expands: true,
                        onBackgroundTap: {
                            PlayerHaptics.light()
                            showCover()
                        }
                    ) { time in
                        PlayerHaptics.light()
                        player.seek(to: time)
                    }
                    .padding(.horizontal, SetuSpacing.sm)
                }
            }
        }
    }

    // MARK: Pinned bottom panel

    private func bottomPanel(for track: MusicPlaybackTrack) -> some View {
        VStack(spacing: SetuSpacing.md) {
            if player.playbackError != nil || player.isBuffering {
                playbackStatusRow
                    .padding(.horizontal, SetuSpacing.lg)
            }

            playbackScrubber
                .padding(.horizontal, SetuSpacing.lg)

            HStack(spacing: SetuSpacing.md) {
                NowPlayingRoundButton(
                    systemImage: player.playMode.systemImage,
                    label: "播放模式：\(player.playMode.title)",
                    tint: SetuColor.info
                ) {
                    PlayerHaptics.light()
                    player.cyclePlayMode()
                    showToast(player.playMode.title)
                }

                NowPlayingRoundButton(
                    systemImage: "backward.fill",
                    label: "上一首",
                    tint: SetuColor.brandInk,
                    disabled: !player.canPlayPrevious
                ) {
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: -1) }
                }

                Button {
                    PlayerHaptics.medium()
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(SetuColor.heroGradient, in: Circle())
                        .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
                }
                .setuButtonFeedback(cornerRadius: 36)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                NowPlayingRoundButton(
                    systemImage: "forward.fill",
                    label: "下一首",
                    tint: SetuColor.brandInk,
                    disabled: !player.canPlayNext
                ) {
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: 1) }
                }

                moreMenu(for: track)
            }
            .padding(.horizontal, SetuSpacing.lg)
        }
    }

    private func moreMenu(for track: MusicPlaybackTrack) -> some View {
        Menu {
            if track.hasMV {
                Button {
                    mvTrack = track
                } label: {
                    Label("观看 MV", systemImage: "play.rectangle")
                }
            }

            Button {
                playlistTrack = track
            } label: {
                Label("收藏到歌单", systemImage: "text.badge.plus")
            }

            Button {
                Task { await download(track) }
            } label: {
                Label(isDownloading ? "正在准备下载…" : "下载", systemImage: "arrow.down.circle")
            }
            .disabled(isDownloading)

            ShareLink(item: "\(track.title) - \(track.artist)") {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            Menu {
                ForEach(MusicSleepTimerOption.allCases) { option in
                    Button(option.title) {
                        player.startSleepTimer(option)
                        showToast("睡眠定时：\(option.title)")
                    }
                }
                if player.sleepTimerTitle != nil {
                    Divider()
                    Button("取消定时", role: .destructive) {
                        player.cancelSleepTimer()
                        showToast("已取消睡眠定时")
                    }
                }
            } label: {
                Label(player.sleepTimerTitle.map { "睡眠定时：\($0)" } ?? "睡眠定时", systemImage: "moon.zzz")
            }

            Divider()

            Button(role: .destructive) {
                player.stop()
                dismiss()
            } label: {
                Label("停止播放", systemImage: "stop.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(SetuColor.brandInk)
                .frame(width: 50, height: 50)
                .background(SetuColor.surfaceMuted, in: Circle())
        }
        .accessibilityLabel("更多操作")
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
                Text(formatTime(player.durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(SetuColor.textSecondary)
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

    private var trackSkipGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
                    ? value.predictedEndTranslation.width
                    : value.translation.width
                let vertical = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                    ? value.predictedEndTranslation.height
                    : value.translation.height
                guard abs(horizontal) > 48, abs(horizontal) > abs(vertical) * 1.2 else {
                    return
                }
                if horizontal < 0 {
                    guard player.canPlayNext else {
                        showToast("已经是最后一首")
                        return
                    }
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: 1) }
                } else {
                    guard player.canPlayPrevious else {
                        showToast("已经是第一首")
                        return
                    }
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: -1) }
                }
            }
    }

    // MARK: Background & helpers

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

    private var queueCaption: String {
        let name = player.queueName ?? "当前队列"
        let count = player.queueTracks.count
        if count > 1 {
            return "\(name) · \(count) 首"
        }
        return name
    }

    private func showLyrics() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = .lyrics
        }
    }

    private func showCover() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page = .cover
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
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

    private func download(_ track: MusicPlaybackTrack) async {
        isDownloading = true
        showToast("正在准备下载")
        defer { isDownloading = false }
        do {
            let response = try await environment.musicClient.url(songID: track.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                showToast(response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "这首歌暂时无法下载")
                return
            }
            let filename = "\(track.title) - \(track.artist).mp3"
            let signed = try await environment.downloadClient.sign(url: urlString, filename: filename)
            guard let url = URL(string: signed.downloadUrl) else {
                showToast("下载地址无效")
                return
            }
            openURL(url)
            showToast("已打开下载地址")
        } catch {
            showToast(error.localizedDescription)
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
        .setuButtonFeedback(cornerRadius: 25)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }
}

// MARK: - Haptics

enum PlayerHaptics {
    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Add to playlist

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
                                .setuButtonFeedback()
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
}

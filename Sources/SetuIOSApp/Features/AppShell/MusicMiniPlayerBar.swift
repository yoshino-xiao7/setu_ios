import SetuIOSCore
import SwiftUI

struct MusicQualityMenu: View {
    @Bindable var player: MusicPlaybackController
    @State private var notice: String?

    var body: some View {
        Menu {
            Picker("优先音质", selection: Binding(
                get: { player.audioQuality },
                set: { quality in
                    Task {
                        _ = await player.setAudioQuality(quality)
                        switch player.feedback {
                        case .failure(let error): notice = "\(error.title)\n\(error.message)"
                        case .error(let message), .warning(let message): notice = message
                        default: break
                        }
                    }
                }
            )) {
                ForEach(MusicAudioQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
        } label: {
            HStack(spacing: SetuSpacing.xs) {
                if player.isChangingQuality {
                    ProgressView()
                } else {
                    Image(systemName: "waveform")
                        .accessibilityHidden(true)
                }
                Text(player.audioQuality.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .disabled(player.isChangingQuality)
        .accessibilityLabel("优先音质：\(player.audioQuality.title)")
        .accessibilityHint("选择音质，实际可用音质取决于音源")
        .accessibilityIdentifier("music.quality")
        .alert("音质提示", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("好") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }
}

#if os(iOS)
import CoreImage
import UIKit
#endif

struct MusicMiniPlayerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    var onShowQueue: (() -> Void)?
    @State private var showingDetail = false
    @State private var initialDetailPage: NowPlayingPage = .cover
    @State private var isCollapsed = false
    #if DEBUG
    @StateObject private var lifetime = MusicMiniPlayerLifetime()
    #endif

    var body: some View {
        if let track = player.currentTrack {
            HStack {
                if isCollapsed {
                    collapsedHandle(for: track)
                } else {
                    expandedBar(for: track)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("music.mini-player")
            #if DEBUG
            .accessibilityValue(lifetime.diagnosticValue)
            #endif
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .trailing : .center)
            .padding(.horizontal, isCollapsed ? 0 : SetuSpacing.md)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: isCollapsed)
            .sheet(isPresented: $showingDetail) {
                MusicNowPlayingDetailView(environment: environment, player: player, initialPage: initialDetailPage)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func expandedBar(for track: MusicPlaybackTrack) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: SetuSpacing.sm) {
                    HStack(spacing: SetuSpacing.sm) {
                        collapseButton
                        artwork(for: track)
                        trackSummary(for: track, lineLimit: 2)
                    }
                    HStack(spacing: SetuSpacing.md) {
                        Spacer(minLength: 0)
                        playButton
                        queueButton
                    }
                }
            } else {
                HStack(spacing: SetuSpacing.sm) {
                    collapseButton
                    artwork(for: track)
                    trackSummary(for: track, lineLimit: 1)
                    playButton
                    queueButton
                }
            }
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

    private var collapseButton: some View {
        Button {
            isCollapsed = true
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 44, height: 44)
        }
        .setuButtonFeedback(cornerRadius: 22)
        .accessibilityLabel("收起迷你播放器")
    }

    private func artwork(for track: MusicPlaybackTrack) -> some View {
        MusicArtworkView(
            urlString: track.coverURLString,
            width: 44,
            height: 44,
            cornerRadius: SetuRadius.sm,
            onTap: { openDetail(.cover) }
        )
    }

    private func trackSummary(for track: MusicPlaybackTrack, lineLimit: Int) -> some View {
        Button {
            openDetail(.cover)
        } label: {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(lineLimit)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(lineLimit)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .setuButtonFeedback()
        .accessibilityLabel("打开正在播放：\(track.title)")
    }

    private var playButton: some View {
        MiniPlayerCircularPlayButton(
            isPlaying: player.isPlaying,
            progress: player.playbackProgress
        ) {
            PlayerHaptics.light()
            player.toggle()
        }
    }

    private var queueButton: some View {
        Button {
            onShowQueue?()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(player.queueTracks.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(SetuColor.brandInk)
            .frame(minWidth: 48, minHeight: 48)
            .background(SetuColor.surfaceMuted, in: Circle())
        }
        .setuButtonFeedback(cornerRadius: 24)
        .accessibilityLabel("查看当前播放列表")
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
                    .font(.system(size: 17, weight: .bold))
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

    @State private var feedback: SetuFeedback?
    @State private var feedbackTask: Task<Void, Never>?

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
                        showFeedback(.success("已清空待播歌曲"))
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

            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
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
                                    showFeedback(.success("已设为下一首播放"))
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
            feedbackTask?.cancel()
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
        _ = await player.play(track: track, in: player.queueTracks, context: player.context)
        if let feedback = player.feedback { showFeedback(feedback) }
    }

    private func showFeedback(_ nextFeedback: SetuFeedback) {
        feedbackTask?.cancel()
        feedback = nextFeedback
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            feedback = nil
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController

    @State private var page: NowPlayingPage
    @State private var lyricState: LoadState<[LyricLine]> = .idle
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var isDownloading = false
    @State private var playlistTrack: MusicPlaybackTrack?
    @State private var mvTrack: MusicPlaybackTrack?
    @State private var loadedArtworkAccent: (key: SetuImageKey, color: Color)?
    @State private var feedback: SetuFeedback?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var fileSharePayload: SystemFileSharePayload?

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
                .task(id: SetuImageKey.music(track.coverURLString, size: .large)) {
                    await loadArtworkAccent(for: track)
                }
            } else {
                SetuEmptyState(title: "暂无播放", message: "从音乐页选择一首歌开始播放", systemImage: "music.note")
                    .padding()
            }
        }
        .overlay(alignment: .top) {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.top, SetuSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: feedback)
        .sheet(item: $playlistTrack) { track in
            AddPlaybackTrackToPlaylistSheet(environment: environment, track: track) { result in
                showFeedback(result)
            }
        }
        .sheet(item: $mvTrack) { track in
            NavigationStack {
                if let mvID = track.mvID, mvID > 0 {
                    MvPlaybackView(environment: environment, mvID: mvID) {
                        player.pause()
                    }
                    .padding(SetuSpacing.md)
                    .setuBackground()
        .setuFeedbackPresentation($feedback)
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
        .sheet(item: $fileSharePayload) { payload in
            SystemFileShareSheet(fileURL: payload.fileURL) { result in
                switch result {
                case .completed:
                    showFeedback(.success("已完成保存或分享"))
                case .cancelled:
                    showFeedback(.info("已取消保存或分享"))
                case .failed(let message):
                    showFeedback(.error("保存或分享失败：\(message)"))
                }
            }
        }
        .onDisappear {
            feedbackTask?.cancel()
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

            if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 2) {
                    Text("正在播放")
                        .font(.caption2)
                        .foregroundStyle(SetuColor.textTertiary)
                    Text(queueCaption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SetuSpacing.xs) {
                MusicQualityMenu(player: player)
                if let timerTitle = player.sleepTimerTitle {
                    SetuPill(text: timerTitle, systemImage: "moon.zzz.fill", tone: .info)
                        .accessibilityLabel("睡眠定时：\(timerTitle)")
                }
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
            case .loaded(let lines):
                if lines.isEmpty {
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
                        lines: lines,
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
                    .id(track.id)
                    .accessibilityIdentifier("music.lyrics")
                    #if DEBUG
                    .accessibilityValue("parses=\(MusicPerformanceProbe.shared.parseCount)")
                    #endif
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
                    showFeedback(.info(player.playMode.title))
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
                        showFeedback(.success("睡眠定时：\(option.title)"))
                    }
                }
                if player.sleepTimerTitle != nil {
                    Divider()
                    Button("取消定时", role: .destructive) {
                        player.cancelSleepTimer()
                        showFeedback(.success("已取消睡眠定时"))
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
                .frame(minWidth: 44, minHeight: 44)
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
                        showFeedback(.warning("已经是最后一首"))
                        return
                    }
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: 1) }
                } else {
                    guard player.canPlayPrevious else {
                        showFeedback(.warning("已经是第一首"))
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

    private func showFeedback(_ nextFeedback: SetuFeedback) {
        feedbackTask?.cancel()
        feedback = nextFeedback
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }

    private func loadLyric(songID: MusicPlaybackIdentity) async {
        guard let legacyID = songID.legacyID else {
            lyricState = .failed(UserFacingError(message: "此歌曲的歌词入口尚未启用"))
            return
        }
        lyricState = .loading
        do {
            let response = try await environment.musicClient.lyric(songID: legacyID)
            try Task.checkCancellation()
            let lines = await Task.detached(priority: .utility) {
                LyricParser.parse(response.lrc?.lyric ?? "", translation: response.tlyric?.lyric)
            }.value
            guard !Task.isCancelled, player.currentTrack?.id == songID else { return }
            lyricState = .loaded(lines)
        } catch {
            guard !Task.isCancelled, player.currentTrack?.id == songID else { return }
            lyricState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func download(_ track: MusicPlaybackTrack) async {
        isDownloading = true
        showFeedback(.info("正在准备下载"))
        defer { isDownloading = false }
        do {
            let urlString: String
            if let id = track.id.legacyID {
                let response = try await environment.musicClient.url(songID: id, level: "standard")
                guard let item = response.data?.first, let url = item.playableURLString else {
                    showFeedback(.error(response.unavailableMessage)); return
                }
                urlString = url
            } else {
                guard let resolver = player.urlResolver else { throw UserFacingError(message: "播放器尚未准备好") }
                urlString = try await resolver.resolve(trackID: track.id, quality: .standard).url.absoluteString
            }
            let filename = "\(track.title) - \(track.artist).mp3"
            let signed = try await environment.downloadClient.sign(url: urlString, filename: filename)
            guard let url = URL(string: signed.downloadUrl) else {
                showFeedback(.error("下载地址无效"))
                return
            }
            let fileURL = try await RemoteFileExportService.download(from: url, filename: filename)
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            showFeedback(.success("下载完成，请选择保存位置或分享方式"))
        } catch {
            showFeedback(.error(RemoteFileExportService.userMessage(for: error)))
        }
    }

    private var artworkAccentColor: Color? {
        guard let track = player.currentTrack, let key = SetuImageKey.music(track.coverURLString, size: .large) else { return nil }
        if loadedArtworkAccent?.key == key { return loadedArtworkAccent?.color }
        return SetuRemoteImageLoader.shared.cachedAccent(for: key).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    private func loadArtworkAccent(for track: MusicPlaybackTrack) async {
        guard let key = SetuImageKey.music(track.coverURLString, size: .large) else { return }
        do {
            let accent = try await SetuRemoteImageLoader.shared.averageColor(for: key)
            guard !Task.isCancelled, player.currentTrack?.id == track.id,
                  SetuImageKey.music(player.currentTrack?.coverURLString, size: .large) == key else { return }
            loadedArtworkAccent = accent.map { (key, Color(red: $0.red, green: $0.green, blue: $0.blue)) }
        } catch {
            // The existing soft-pink background remains the fallback.
        }
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
    @Bindable var environment: AppEnvironment
    let track: MusicPlaybackTrack
    let onFeedback: (SetuFeedback) -> Void

    var body: some View {
        if let legacyID = track.id.legacyID {
        PlaylistSelectionSheet(presentation: .playback, requests: [
            AddSongToPlaylistRequest(songId: legacyID, songName: track.title, artistName: track.artist,
                                     albumName: track.album, coverUrl: track.coverURLString, duration: track.durationMilliseconds)
        ]) { playlist in
            onFeedback(.success("已加入 \(playlist.name)"))
        } summary: {
            HStack(spacing: SetuSpacing.md) {
                MusicArtworkView(urlString: track.coverURLString)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(track.title).font(SetuTypography.headline).foregroundStyle(SetuColor.textPrimary).lineLimit(2)
                    Text(track.artist).font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary).lineLimit(1)
                }
            }
        }
        } else {
            ContentUnavailableView("暂不支持此操作", systemImage: "music.note.list", description: Text("此歌曲的加入歌单入口尚未启用"))
        }
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

#if DEBUG
#Preview("迷你播放器 · 390 · 深色大字") {
    SetuFeaturePreviewHost(playerState: .listening) { environment, player in
        VStack {
            Spacer()
            MusicMiniPlayerBar(environment: environment, player: player)
                .padding(.bottom, SetuSpacing.lg)
        }
        .setuBackground()
    }
    .frame(width: 390, height: 220)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif

import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MusicQualityMenu: View {
    @Bindable var player: MusicPlaybackController
    var isNeteaseVIP: Bool = false
    var onPromptVIPLogin: (() -> Void)? = nil
    @State private var notice: String?

    var body: some View {
        Menu {
            Picker("优先音质", selection: Binding(
                get: { player.audioQuality },
                set: { quality in
                    if (quality == .lossless || quality == .hires) && !isNeteaseVIP {
                        onPromptVIPLogin?()
                    }
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
                    if (quality == .lossless || quality == .hires) && !isNeteaseVIP {
                        Text("\(quality.title) (VIP)").tag(quality)
                    } else {
                        Text(quality.title).tag(quality)
                    }
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
                Text(player.actualQualityTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .disabled(player.isChangingQuality)
        .accessibilityLabel("优先音质：\(player.audioQuality.title)，当前音质：\(player.actualQualityTitle)")
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

extension NowPlayingSheet {
    // MARK: Quick action bar

    func quickActionBar(for track: MusicPlaybackTrack) -> some View {
        HStack(spacing: 0) {
            // 1. Like
            Group {
                if environment.config.musicFeatureFlags.likedTracksEnabled,
                   !track.usesDirectStream,
                   case .canonical(let id) = track.id {
                    MusicLikeButton(id: id, environment: environment, iconOnly: true)
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(SetuColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            // 2. Sound quality capsule
            Group {
                if !track.usesDirectStream {
                    MusicQualityMenu(
                        player: player,
                        isNeteaseVIP: environment.neteaseMusicSession.isVIP,
                        onPromptVIPLogin: {
                            showingNeteaseLogin = true
                        }
                    )
                } else {
                    Text("直链")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SetuColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            // 3. Similar recommendations
            Button {
                PlayerHaptics.light()
                showingSimilar = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                    Text("相似")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(SetuColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
            }
            .setuButtonFeedback()
            .accessibilityLabel("相似推荐")
            .frame(maxWidth: .infinity)

            // 4. Add to playlist
            if !track.usesDirectStream {
                Button {
                    PlayerHaptics.light()
                    playlistTrack = track
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                        Text("收藏")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .setuButtonFeedback()
                .accessibilityLabel("收藏到歌单")
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
                .frame(maxWidth: .infinity)
            }

            // 5. More actions
            Button {
                PlayerHaptics.light()
                showingMore = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                    Text("更多")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(SetuColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
            }
            .setuButtonFeedback()
            .accessibilityLabel("更多操作")
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pinned bottom panel

    func bottomPanel(for track: MusicPlaybackTrack) -> some View {
        VStack(spacing: SetuSpacing.md) {
            quickActionBar(for: track)
                .padding(.horizontal, SetuSpacing.md)

            if !environment.neteaseMusicSession.isVIP, player.isVIPRestrictedOrTrial {
                vipPromptPill
            }

            if player.playbackError != nil || player.isBuffering {
                playbackStatusRow
                    .padding(.horizontal, SetuSpacing.lg)
            }

            playbackScrubber
                .padding(.horizontal, SetuSpacing.lg)

            HStack(spacing: 0) {
                NowPlayingRoundButton(
                    systemImage: player.playMode.systemImage,
                    label: "播放模式：\(player.playMode.title)",
                    tint: SetuColor.info,
                    disabled: player.context?.isInfinite == true
                ) {
                    PlayerHaptics.light()
                    player.cyclePlayMode()
                    showFeedback(.info(player.playMode.title))
                }

                Spacer(minLength: 4)

                NowPlayingRoundButton(
                    systemImage: "backward.fill",
                    label: "上一首",
                    tint: SetuColor.brandInk,
                    disabled: !player.canPlayPrevious
                ) {
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: -1) }
                }

                Spacer(minLength: 4)

                Button {
                    PlayerHaptics.medium()
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(SetuColor.heroGradient, in: Circle())
                        .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
                }
                .setuButtonFeedback(cornerRadius: 36)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                Spacer(minLength: 4)

                NowPlayingRoundButton(
                    systemImage: "forward.fill",
                    label: "下一首",
                    tint: SetuColor.brandInk,
                    disabled: !player.canPlayNext
                ) {
                    PlayerHaptics.light()
                    Task { await player.userSkip(by: 1) }
                }

                Spacer(minLength: 4)
                NowPlayingRoundButton(systemImage: "list.bullet", label: "播放列表", tint: SetuColor.brandInk) {
                    showingQueue = true
                }
            }
            .padding(.horizontal, SetuSpacing.lg)

        }
    }

    private var vipPromptPill: some View {
        Button {
            PlayerHaptics.light()
            showingNeteaseLogin = true
        } label: {
            HStack(spacing: SetuSpacing.xs) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25))
                Text("当前为试听/降级音质，登录网易云 VIP 畅享完整音质")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, SetuSpacing.md)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
            )
        }
        .setuButtonFeedback()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }


    // Present follow-up sheets only after More has finished dismissing.
    func afterMoreDismisses(_ action: @escaping () -> Void) {
        pendingMoreAction = action
        showingMore = false
    }

    func moreActions(for track: MusicPlaybackTrack) -> some View {
        NavigationStack {
            List {
                if environment.config.musicFeatureFlags.airPlayPickerEnabled {
                    HStack {
                        Text("隔空播放")
                        Spacer()
                        AirPlayRouteButton().frame(width: 44, height: 44)
                    }
                }
                if !track.usesDirectStream {
                    MusicQualityMenu(player: player)
                }
                if track.hasMV {
                    Button {
                        afterMoreDismisses { mvTrack = track }
                    } label: {
                        Label("观看 MV", systemImage: "play.rectangle")
                    }
                }

                if !track.usesDirectStream {
                    Button {
                        afterMoreDismisses { playlistTrack = track }
                    } label: {
                        Label("收藏到歌单", systemImage: "text.badge.plus")
                    }

                    Button {
                        afterMoreDismisses { Task { await download(track) } }
                    } label: {
                        Label(isDownloading ? "正在准备下载…" : "下载", systemImage: "arrow.down.circle")
                    }
                    .disabled(isDownloading)
                }

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
                    afterMoreDismisses {
                        player.stop()
                        dismiss()
                    }
                } label: {
                    Label("停止播放", systemImage: "stop.circle")
                }
            }
            .navigationTitle("更多操作")
            .musicInlineNavigationTitle()
            .toolbar { Button("完成") { showingMore = false } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    var playbackScrubber: some View {
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
            .frame(minHeight: 44)
            .accessibilityLabel("播放进度")
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
    var playbackStatusRow: some View {
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
        } else if player.isBuffering || player.isSeeking {
            HStack(spacing: SetuSpacing.sm) {
                ProgressView()
                    .tint(SetuColor.brandPink)
                Text(player.isSeeking ? "正在准备跳转…" : "正在缓冲…")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer(minLength: 0)
                if player.isSeeking {
                    Button("取消") { player.cancelPendingSeek() }.buttonStyle(.borderless)
                        .accessibilityIdentifier("music.seek.cancel")
                    if player.isRestoringPosition {
                        Button("从头播放") { player.restartFromBeginning() }.buttonStyle(.borderless)
                            .accessibilityIdentifier("music.seek.restart")
                    }
                }
            }
        }
    }

}

struct NowPlayingRoundButton: View {
    let systemImage: String
    let label: String
    var tint: Color = SetuColor.brandPink
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
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

struct AddPlaybackTrackToPlaylistSheet: View {
    @Bindable var environment: AppEnvironment
    let track: MusicPlaybackTrack
    let onFeedback: (SetuFeedback) -> Void

    var body: some View {
        PlaylistSelectionSheet(
            environment: environment,
            presentation: .playback,
            requests: [request],
            onAdded: { playlist in
                onFeedback(.success("已加入 \(playlist.name)"))
            },
            onNeteaseAdded: { playlist in
                onFeedback(.success("已加入网易云歌单《\(playlist.name)》"))
            }
        ) {
            HStack(spacing: SetuSpacing.md) {
                MusicArtworkView(urlString: track.coverURLString)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(track.title).font(SetuTypography.headline).foregroundStyle(SetuColor.textPrimary).lineLimit(2)
                    Text(track.artist).font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary).lineLimit(1)
                }
            }
        }
    }

    private var request: AddSongToPlaylistRequest {
        switch track.id {
        case .legacy(let id):
            return AddSongToPlaylistRequest(songId: id, songName: track.title, artistName: track.artist,
                albumName: track.album, coverUrl: track.coverURLString, duration: track.durationMilliseconds)
        case .canonical(let id):
            return AddSongToPlaylistRequest(trackId: id, songName: track.title, artistName: track.artist,
                albumName: track.album, coverUrl: track.coverURLString, duration: track.durationMilliseconds)
        }
    }
}

extension View {
    @ViewBuilder
    func musicInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

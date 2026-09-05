import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

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

extension NowPlayingSheet {
    // MARK: Pinned bottom panel

    func bottomPanel(for track: MusicPlaybackTrack) -> some View {
        VStack(spacing: SetuSpacing.md) {
            if player.playbackError != nil || player.isBuffering {
                playbackStatusRow
                    .padding(.horizontal, SetuSpacing.lg)
            }

            if environment.config.musicFeatureFlags.airPlayPickerEnabled {
                AirPlayRouteButton()
                    .frame(width: 44, height: 44)
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
                moreMenu(for: track)
            }
            .padding(.horizontal, SetuSpacing.lg)
        }
    }

    func moreMenu(for track: MusicPlaybackTrack) -> some View {
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SetuColor.brandInk)
                .frame(width: 50, height: 50)
                .background(SetuColor.surfaceMuted, in: Circle())
        }
        .accessibilityLabel("更多操作")
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

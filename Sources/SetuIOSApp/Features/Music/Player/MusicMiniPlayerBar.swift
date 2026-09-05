import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MusicMiniPlayerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    var onShowQueue: (() -> Void)?
    @State private var lyrics = NowPlayingLyricsModel()
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
            .onChange(of: environment.authSession.currentUser?.id) { _, _ in
                lyrics.invalidate()
            }
            .sheet(isPresented: $showingDetail) {
                NowPlayingSheet(environment: environment, player: player, lyrics: lyrics, initialPage: initialDetailPage)
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

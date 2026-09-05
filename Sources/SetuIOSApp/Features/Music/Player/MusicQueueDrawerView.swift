import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MusicQueueDrawerView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if player.queueTracks.count > 1 {
                    Button(role: .destructive) {
                        PlayerHaptics.medium()
                        player.clearUpcomingTracks()
                        showFeedback(.success("已清空待播歌曲"))
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .setuButtonFeedback(cornerRadius: 22)
                    .accessibilityLabel("清空待播歌曲")
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .setuButtonFeedback()
            .accessibilityLabel("\(track.title)，\(track.artist)")
            .accessibilityValue(isCurrent ? (isPlaying ? "正在播放" : "已暂停") : "待播放")
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

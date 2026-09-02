import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif


struct MusicSongRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: MusicSongRowModel
    private var song: MusicSong { model.song }

    init(song: MusicSong, onPlay: (() -> Void)? = nil, onPlayMv: (() -> Void)? = nil,
         onAddToPlaylist: (() -> Void)? = nil, onDownload: (() -> Void)? = nil) {
        self.init(model: MusicSongRowModel(song: song), onPlay: onPlay, onPlayMv: onPlayMv,
                  onAddToPlaylist: onAddToPlaylist, onDownload: onDownload)
    }

    init(model: MusicSongRowModel, onPlay: (() -> Void)? = nil, onPlayMv: (() -> Void)? = nil,
         onAddToPlaylist: (() -> Void)? = nil, onDownload: (() -> Void)? = nil) {
        self.model = model
        self.onPlay = onPlay
        self.onPlayMv = onPlayMv
        self.onAddToPlaylist = onAddToPlaylist
        self.onDownload = onDownload
    }
    var onPlay: (() -> Void)?
    var onPlayMv: (() -> Void)?
    var onAddToPlaylist: (() -> Void)?
    var onDownload: (() -> Void)?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        MusicArtworkView(urlString: model.coverURLString)
                        playableSongText
                    }
                    if hasActions {
                        actionsRow
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                HStack(spacing: SetuSpacing.md) {
                    MusicArtworkView(urlString: model.coverURLString)
                    playableSongText

                    if hasActions {
                        actionsGrid
                    }
                }
            }
        }
        .padding(.vertical, SetuSpacing.sm)
    }

    @ViewBuilder
    private var playableSongText: some View {
        if let onPlay {
            Button(action: onPlay) {
                songText
                    .frame(minHeight: 44)
            }
            .setuButtonFeedback()
            .accessibilityLabel("播放 \(song.name)")
        } else {
            songText
        }
    }

    private var songText: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(model.title)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)
            Text(model.artist)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
            Text(model.album)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textTertiary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var actionsGrid: some View {
        LazyVGrid(columns: actionColumns, alignment: .trailing, spacing: SetuSpacing.xs) {
            if model.hasMV {
                if let onPlayMv {
                    MusicIconButton(
                        systemImage: "play.rectangle.fill",
                        accessibilityLabel: "播放《\(song.name)》的 MV",
                        tint: SetuColor.info
                    ) {
                        onPlayMv()
                    }
                } else {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(SetuColor.brandPink)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("《\(song.name)》有 MV")
                }
            }
            if let onAddToPlaylist {
                MusicIconButton(
                    systemImage: "text.badge.plus",
                    accessibilityLabel: "将《\(song.name)》加入歌单",
                    tint: SetuColor.brandInk
                ) {
                    onAddToPlaylist()
                }
            }
            if let onDownload {
                MusicIconButton(
                    systemImage: "arrow.down",
                    accessibilityLabel: "下载 \(song.name)",
                    tint: SetuColor.success
                ) {
                    onDownload()
                }
            }
        }
        .frame(width: 92, alignment: .trailing)
    }

    private var actionsRow: some View {
        HStack(spacing: SetuSpacing.xs) {
            actionButtons
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.hasMV {
            if let onPlayMv {
                MusicIconButton(
                    systemImage: "play.rectangle.fill",
                    accessibilityLabel: "播放《\(song.name)》的 MV",
                    tint: SetuColor.info,
                    action: onPlayMv
                )
            } else {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("《\(song.name)》有 MV")
            }
        }
        if let onAddToPlaylist {
            MusicIconButton(
                systemImage: "text.badge.plus",
                accessibilityLabel: "将《\(song.name)》加入歌单",
                tint: SetuColor.brandInk,
                action: onAddToPlaylist
            )
        }
        if let onDownload {
            MusicIconButton(
                systemImage: "arrow.down",
                accessibilityLabel: "下载 \(song.name)",
                tint: SetuColor.success,
                action: onDownload
            )
        }
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.fixed(44), spacing: SetuSpacing.xs),
            GridItem(.fixed(44), spacing: 0)
        ]
    }

    private var hasActions: Bool {
        model.hasMV || onAddToPlaylist != nil || onDownload != nil
    }
}

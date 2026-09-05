import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif


struct MusicSongRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let title: String
    private let artist: String
    private let album: String
    private let coverURLString: String?
    private let hasMV: Bool

    init(song: MusicSong, onPlay: (() -> Void)? = nil, onPlayMv: (() -> Void)? = nil,
         onAddToPlaylist: (() -> Void)? = nil, onDownload: (() -> Void)? = nil,
         onArtist: (() -> Void)? = nil, onAlbum: (() -> Void)? = nil) {
        self.init(model: MusicSongRowModel(song: song), onPlay: onPlay, onPlayMv: onPlayMv,
                  onAddToPlaylist: onAddToPlaylist, onDownload: onDownload, onArtist: onArtist, onAlbum: onAlbum)
    }

    init(model: MusicSongRowModel, onPlay: (() -> Void)? = nil, onPlayMv: (() -> Void)? = nil,
         onAddToPlaylist: (() -> Void)? = nil, onDownload: (() -> Void)? = nil,
         onArtist: (() -> Void)? = nil, onAlbum: (() -> Void)? = nil) {
        title = model.title; artist = model.artist; album = model.album
        coverURLString = model.coverURLString; hasMV = model.hasMV
        self.onArtist = onArtist; self.onAlbum = onAlbum
        self.onPlay = onPlay
        self.onPlayMv = onPlayMv
        self.onAddToPlaylist = onAddToPlaylist
        self.onDownload = onDownload
    }
    init(track: MusicV2Track, onPlay: (() -> Void)? = nil,
         onArtist: (() -> Void)? = nil, onAlbum: (() -> Void)? = nil,
         isLiked: Bool = false, onToggleLike: (() -> Void)? = nil) {
        self.isLiked = isLiked; self.onToggleLike = onToggleLike
        title = track.title
        artist = track.artists.map(\.name).joined(separator: " / ")
        album = track.album?.title ?? "未知专辑"
        coverURLString = track.artwork?.url; hasMV = track.mvId != nil
        self.onPlay = onPlay; self.onArtist = onArtist; self.onAlbum = onAlbum
    }
    var isLiked = false
    var onToggleLike: (() -> Void)?
    var onArtist: (() -> Void)?
    var onAlbum: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPlayMv: (() -> Void)?
    var onAddToPlaylist: (() -> Void)?
    var onDownload: (() -> Void)?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        MusicArtworkView(urlString: coverURLString)
                        playableSongText
                    }
                    if hasActions {
                        actionsRow
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                HStack(spacing: SetuSpacing.md) {
                    MusicArtworkView(urlString: coverURLString)
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
        if onArtist != nil || onAlbum != nil {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                if let onPlay {
                    Button(action: onPlay) { titleText.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                        .setuButtonFeedback().accessibilityLabel("播放 \(title)")
                } else { titleText }
                metadata(text: artist, action: onArtist, color: SetuColor.textSecondary)
                metadata(text: album, action: onAlbum, color: SetuColor.textTertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if let onPlay {
            Button(action: onPlay) {
                songText
                    .frame(minHeight: 44)
            }
            .setuButtonFeedback()
            .accessibilityLabel("播放 \(title)")
        } else {
            songText
        }
    }

    private var titleText: some View {
        Text(title).font(SetuTypography.headline).foregroundStyle(SetuColor.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func metadata(text: String, action: (() -> Void)?, color: Color) -> some View {
        if let action {
            Button(action: action) {
                Text(text).font(SetuTypography.caption).foregroundStyle(color)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.setuButtonFeedback()
        } else {
            Text(text).font(SetuTypography.caption).foregroundStyle(color)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private var songText: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(title)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)
            Text(artist)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
            Text(album)
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
            likeButton
            if hasMV {
                if let onPlayMv {
                    MusicIconButton(
                        systemImage: "play.rectangle.fill",
                        accessibilityLabel: "播放《\(title)》的 MV",
                        tint: SetuColor.info
                    ) {
                        onPlayMv()
                    }
                } else {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(SetuColor.brandPink)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("《\(title)》有 MV")
                }
            }
            if let onAddToPlaylist {
                MusicIconButton(
                    systemImage: "text.badge.plus",
                    accessibilityLabel: "将《\(title)》加入歌单",
                    tint: SetuColor.brandInk
                ) {
                    onAddToPlaylist()
                }
            }
            if let onDownload {
                MusicIconButton(
                    systemImage: "arrow.down",
                    accessibilityLabel: "下载 \(title)",
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
        likeButton
        if hasMV {
            if let onPlayMv {
                MusicIconButton(
                    systemImage: "play.rectangle.fill",
                    accessibilityLabel: "播放《\(title)》的 MV",
                    tint: SetuColor.info,
                    action: onPlayMv
                )
            } else {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("《\(title)》有 MV")
            }
        }
        if let onAddToPlaylist {
            MusicIconButton(
                systemImage: "text.badge.plus",
                accessibilityLabel: "将《\(title)》加入歌单",
                tint: SetuColor.brandInk,
                action: onAddToPlaylist
            )
        }
        if let onDownload {
            MusicIconButton(
                systemImage: "arrow.down",
                accessibilityLabel: "下载 \(title)",
                tint: SetuColor.success,
                action: onDownload
            )
        }
    }

    @ViewBuilder private var likeButton: some View {
        if let onToggleLike {
            MusicIconButton(systemImage: isLiked ? "heart.fill" : "heart",
                accessibilityLabel: "\(isLiked ? "取消喜欢" : "喜欢") \(title)",
                tint: SetuColor.brandPink, action: onToggleLike)
        }
    }

    private var actionColumns: [GridItem] {
        [
            GridItem(.fixed(44), spacing: SetuSpacing.xs),
            GridItem(.fixed(44), spacing: 0)
        ]
    }

    private var hasActions: Bool {
        hasMV || onAddToPlaylist != nil || onDownload != nil || onToggleLike != nil
    }
}

#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicSearchRowLayoutTests: XCTestCase {
    func testLongSearchRowAt375And430PointsAndAccessibilityText() throws {
        let model = MusicSongRowModel(song: MusicSong(
            id: 1, name: "一首很长的歌曲名称 / A Long Search Result Title",
            artists: [.init(id: 1, name: "示例歌手与合作歌手")],
            album: .init(id: 2, name: "很长的专辑名称：夏日限定版本"), mv: 1
        ))
        for width in [375.0, 430.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = MusicSongRow(model: model, onPlay: {}, onPlayMv: {}, onAddToPlaylist: {}, onDownload: {})
                    .padding(.horizontal, 16)
                    .frame(width: width)
                    .background(Color.white)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, width)
                XCTAssertGreaterThanOrEqual(image.size.height, 88)
                let attachment = XCTAttachment(image: image)
                attachment.name = "music-search-row-\(Int(width))-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
#endif

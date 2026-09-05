#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicDetailLayoutTests: XCTestCase {
    func testArtistAlbumPlaylistAt375And430AndAccessibility() async throws {
        let environment = SetuPreviewEnvironment.make()
        let store = MusicStore(client: environment.musicClient, userID: 1)
        let player = MusicPlaybackController(persistsPlayback: false)
        let router = RouterPath()
        let artist = try JSONDecoder().decode(MusicV2ArtistDetail.self, from: MusicDetailPreviewFixtures.response(path: "/artists/detail", query: nil).1)
        let album = try JSONDecoder().decode(MusicV2AlbumDetail.self, from: MusicDetailPreviewFixtures.response(path: "/albums/detail", query: nil).1)
        let playlist = try JSONDecoder().decode(MusicV2PlaylistDetail.self, from: MusicDetailPreviewFixtures.response(path: "/playlists/detail", query: nil).1)
        store.artistDetail("netease:artist:detail").update(markStale: false) { $0 = artist }
        store.albumDetail("netease:album:detail").update(markStale: false) { $0 = album }
        store.playlistDetailV2("netease:playlist:detail").update(markStale: false) { $0 = MusicPlaylistDetailData(playlist) }
        let pages: [(String, AnyView)] = [
            ("artist", AnyView(ArtistDetailView(environment: environment, artistID: "netease:artist:detail"))),
            ("album", AnyView(AlbumDetailView(environment: environment, albumID: "netease:album:detail"))),
            ("playlist", AnyView(PlaylistDetailView(environment: environment, playlistID: .provider(.init(rawValue: "netease:playlist:detail")))))
        ]
        for (page, view) in pages {
            for width in [375.0, 430.0] {
                for size in [DynamicTypeSize.large, .accessibility3] {
                    let content = NavigationStack { view }
                        .environment(store).environment(router)
                        .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: player, store: store))
                        .environment(\.dynamicTypeSize, size)
                    let host = UIHostingController(rootView: content)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.frame = window.bounds
                    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    XCTAssertEqual(image.size.width, width)
                    XCTAssertEqual(host.view.bounds.width, width)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "p11-\(page)-\(Int(width))-\(size)"
                    attachment.lifetime = .keepAlways; add(attachment)
                    window.isHidden = true
                }
            }
        }
    }

    func testLoadingEmptyErrorAndUnauthorizedRenderForEachDetailResource() async throws {
        for page in ["artist", "album", "playlist"] {
            for state in ["loading", "empty", "error", "unauthorized"] {
                let resource = MusicResource<[String]>()
                if state == "error" || state == "unauthorized" {
                    let status = state == "unauthorized" ? 401 : 503
                    await resource.load(ttl: 0, now: Date(), force: true) {
                        throw APIError.httpStatus(status, message: "测试错误", requestID: nil, traceID: nil, code: nil)
                    }
                    XCTAssertEqual(resource.error?.action, state == "unauthorized" ? .signIn : .retry)
                } else if state == "empty" { resource.update { $0 = [] } }
                let content = VStack {
                    MusicDetailState(resource: resource, retry: {}) { values in
                        if values.isEmpty { ContentUnavailableView("暂无歌曲", systemImage: "music.note") }
                        else { Text("content") }
                    }
                }.frame(width: 375, height: 350)
                let renderer = ImageRenderer(content: content)
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "p11-\(page)-\(state)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
#endif

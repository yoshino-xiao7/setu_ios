#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicLibraryLayoutTests: XCTestCase {
    func testLikedTracks375And430WithHeartsAndAccessibility() async throws {
        let track = try JSONDecoder().decode(MusicV2Track.self, from: JSONSerialization.data(withJSONObject: MusicDiscoverPreviewFixtures.track))
        for width in [375.0, 430.0] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let view = MusicSongRow(track: track, onPlay: {}, isLiked: true, onToggleLike: {})
                    .environment(\.dynamicTypeSize, size).padding().frame(width: width)
                let host = UIHostingController(rootView: view)
                let fit = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                XCTAssertLessThanOrEqual(fit.width, width)
                XCTAssertGreaterThan(fit.height, 44)
                host.view.frame = CGRect(origin: .zero, size: fit)
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: fit).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
                let a = XCTAttachment(image: image); a.name = "p15-liked-row-\(Int(width))-\(size)"; a.lifetime = .keepAlways; add(a)
            }
        }
    }
    func testFullLikedPageAt375And430() async throws {
        let environment = SetuPreviewEnvironment.make()
        let store = MusicStore(client: environment.musicClient, userID: 1)
        let body = try JSONSerialization.data(withJSONObject: ["items": [["ownerId": "setu:user:1",
            "trackId": "netease:track:opaque%2Fp12", "likedAt": "2026-09-06T00:00:00Z",
            "track": MusicDiscoverPreviewFixtures.track]], "offset": 0, "limit": 20,
            "total": 1, "hasMore": false, "nextOffset": NSNull()])
        MusicV2URLProtocol.handler = { _ in .init(body: body) }
        defer { MusicV2URLProtocol.handler = nil }
        await store.loadLikedTracks(client: makeMusicV2Client())
        for width in [375.0, 430.0] {
            let content = NavigationStack { LikedTracksView(environment: environment) }.environment(store)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(host.view.bounds.width, width)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let a = XCTAttachment(image: image); a.name = "p15-liked-page-\(Int(width))"; a.lifetime = .keepAlways; add(a)
            window.isHidden = true
        }
    }

    func testUnauthorizedPageStateRenders() async throws {
        let resource = MusicResource<[String]>()
        await resource.load(ttl: 0, now: Date(), force: true) {
            throw APIError.httpStatus(401, message: "请先登录", requestID: nil, traceID: nil, code: nil)
        }
        XCTAssertEqual(resource.error?.action, .signIn)
        let content = List { MusicDetailState(resource: resource, retry: {}) { _ in Text("loaded") } }
        let host = UIHostingController(rootView: content)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 600); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let a = XCTAttachment(image: image); a.name = "p15-liked-unauthorized-state"; a.lifetime = .keepAlways; add(a)
    }

    func testLoadingStateRenders() throws {
        let resource = MusicResource<[String]>()
        let content = List { MusicDetailState(resource: resource, retry: {}) { _ in Text("loaded") } }
        let host = UIHostingController(rootView: content)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 600); host.view.layoutIfNeeded()
        if case .idle = resource.state {} else { XCTFail() }
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let a = XCTAttachment(image: image); a.name = "p15-liked-loading"; a.lifetime = .keepAlways; add(a)
    }
}

final class MiniPlayerAnchorTests: XCTestCase {
    func testKeepsTheReportedInsetWhenItSitsOnTheVisibleModuleBottom() {
        let module = CGRect(x: 0, y: 100, width: 390, height: 700)
        let y = MiniPlayerAnchor.overlayMinY(reportedInsetMinY: 736, moduleFrame: module, insetHeight: 64)
        XCTAssertEqual(y, 736)
    }

    func testIgnoresACoveredPageInsetThatWouldLiftTheBar() {
        let module = CGRect(x: 0, y: 100, width: 390, height: 700)
        let y = MiniPlayerAnchor.overlayMinY(reportedInsetMinY: 420, moduleFrame: module, insetHeight: 64)
        XCTAssertEqual(y, 736)
    }
}
#endif

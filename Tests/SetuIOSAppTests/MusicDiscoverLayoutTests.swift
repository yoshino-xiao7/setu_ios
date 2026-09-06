#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicDiscoverLayoutTests: XCTestCase {
    func testFourDiscoverPagesAt375And430AndAccessibility() async throws {
        let environment = SetuPreviewEnvironment.make(), router = RouterPath()
        let store = MusicStore(client: environment.musicClient, userID: 1)
        let player = MusicPlaybackController(persistsPlayback: false)
        try populate(store)
        for (page, view) in pages(environment, store) {
            for width in [375.0, 430.0] {
                for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
                    let content = NavigationStack { view }.environment(store).environment(router)
                        .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: player, store: store))
                        .environment(\.dynamicTypeSize, size)
                    let host = UIHostingController(rootView: content)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    host.view.frame = window.bounds; host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    XCTAssertEqual(image.size.width, width)
                    assertHorizontalBounds(host.view, width: width)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "p12-\(page)-\(Int(width))-\(size)"; attachment.lifetime = .keepAlways; add(attachment)
                    window.isHidden = true
                }
            }
        }
    }

    func testWarmHomeFirstRenderBudget() async throws {
        let environment = SetuPreviewEnvironment.make(), store = MusicStore(client: environment.musicClient, userID: 1)
        try populate(store)
        var durations: [Double] = []
        for iteration in 0..<6 {
            let start = CACurrentMediaTime()
            let content = NavigationStack {
                List { MusicHomeFeedContent(resource: store.homeFeed, flags: MusicFeatureFlags(), userID: 1, retry: {}) }
                    .listStyle(.plain).setuBackground()
            }.environment(store).environment(RouterPath())
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertEqual(image.size.width, 430)
            if iteration > 0 { durations.append((CACurrentMediaTime() - start) * 1000) }
            window.isHidden = true
            await Task.yield()
        }
        print("P12_WARM_HOME_RENDER_MS=\(durations)")
        // This measures cached in-process feed -> rendered window, including host construction.
        XCTAssertLessThan(durations.sorted()[durations.count / 2], 100)
    }

    private func populate(_ store: MusicStore) throws {
        let decoder = JSONDecoder()
        let home = try decoder.decode(MusicV2HomeFeed.self, from: MusicDiscoverPreviewFixtures.data(MusicDiscoverPreviewFixtures.home()))
        store.homeFeed.update(markStale: false) { $0 = home }
        let rankings = try decoder.decode(MusicV2Rankings.self, from: MusicDiscoverPreviewFixtures.response(path: "/user/music/v2/rankings", query: nil).1)
        store.rankings.update(markStale: false) { $0 = rankings }
        let daily = try decoder.decode(MusicV2RecommendedTracks.self, from: MusicDiscoverPreviewFixtures.response(path: "/user/music/v2/recommend/tracks", query: nil).1)
        store.dailyRecommendations.update(markStale: false) { $0 = daily }
        let tracks = try decoder.decode(MusicV2NewTracks.self, from: MusicDiscoverPreviewFixtures.response(path: "/user/music/v2/new-releases/tracks", query: nil).1)
        store.releaseTracks(.all).update(markStale: false) { $0 = .init(items: tracks.items.items, source: tracks.source, nextOffset: tracks.items.nextOffset, loadedOffsets: [0]) }
    }
    private func pages(_ environment: AppEnvironment, _ store: MusicStore) -> [(String, AnyView)] {
        [("home", AnyView(List { MusicHomeFeedContent(resource: store.homeFeed, flags: MusicFeatureFlags(), userID: 1, retry: {}) }.listStyle(.plain).setuBackground())),
         ("rankings", AnyView(RankingsView(environment: environment))),
         ("newReleases", AnyView(NewReleasesView(environment: environment))),
         ("dailyRecommend", AnyView(DailyRecommendView(environment: environment, player: MusicPlaybackController())))]
    }
    private func assertHorizontalBounds(_ view: UIView, width: Double) {
        // Horizontal carousels intentionally have wider content; vertical list viewport must not.
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
            XCTAssertLessThanOrEqual(scroll.bounds.width, width + 1)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        }
        for child in view.subviews { assertHorizontalBounds(child, width: width) }
    }
}
#endif

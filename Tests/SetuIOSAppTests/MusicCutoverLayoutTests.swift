#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicCutoverLayoutTests: XCTestCase {
    func testSearchAndHistoryAt375And430IncludingAccessibility() async throws {
        let environment = SetuPreviewEnvironment.make()
        let store = MusicStore(client: environment.musicClient, userID: 1)
        let player = MusicPlaybackController(), router = RouterPath()
        store.canonicalHistory.update { $0 = .init(items: [], nextOffset: nil, total: 0) }
        let pages: [(String, AnyView)] = [
            ("search", AnyView(MusicCutoverSearchView(environment: environment, initialQuery: nil))),
            ("history", AnyView(MusicCanonicalHistoryView(environment: environment)))
        ]
        for (name, page) in pages {
            for width in [375.0, 430.0] {
                for size in [DynamicTypeSize.large, .accessibility5] {
                    let host = UIHostingController(rootView: NavigationStack { page }.environment(store).environment(router)
                        .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: player, store: store))
                        .environment(\.dynamicTypeSize, size))
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
                    window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                    host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    XCTAssertEqual(image.size.width, width)
                    let attachment = XCTAttachment(image: image); attachment.name = "cutover-\(name)-\(width)-\(size)"; attachment.lifetime = .keepAlways; add(attachment)
                    window.isHidden = true
                }
            }
        }
    }
}
#endif

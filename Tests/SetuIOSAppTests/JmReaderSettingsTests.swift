import XCTest
@testable import SetuIOSCore

final class JmReaderSettingsTests: XCTestCase {
    func testDefaultsToPagedReadingAndRemembersContinuousScrolling() {
        let defaults = UserDefaults(suiteName: "jm-reader-mode-\(UUID().uuidString)")!
        XCTAssertEqual(JmReaderSettings.mode(defaults: defaults), .paged)

        JmReaderSettings.save(.continuous, defaults: defaults)
        XCTAssertEqual(JmReaderSettings.mode(defaults: defaults), .continuous)

        defaults.set("unknown", forKey: JmReaderSettings.storageKey)
        XCTAssertEqual(JmReaderSettings.mode(defaults: defaults), .paged)
    }
}

final class JmVisiblePageResolverTests: XCTestCase {
    func testPicksThePageThatFillsMostOfTheViewport() {
        let viewport = CGRect(x: 0, y: 100, width: 100, height: 200)
        XCTAssertNil(JmVisiblePageResolver.index(viewport: viewport, frames: [:]))

        let onlyFirst = JmVisiblePageResolver.index(
            viewport: viewport,
            frames: [0: CGRect(x: 0, y: 100, width: 100, height: 200)]
        )
        XCTAssertEqual(onlyFirst, 0)

        let mostlySecond = JmVisiblePageResolver.index(
            viewport: viewport,
            frames: [
                0: CGRect(x: 0, y: 0, width: 100, height: 140),
                1: CGRect(x: 0, y: 140, width: 100, height: 220),
                2: CGRect(x: 0, y: 360, width: 100, height: 200),
            ]
        )
        XCTAssertEqual(mostlySecond, 1)
    }
}

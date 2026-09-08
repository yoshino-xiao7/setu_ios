import Foundation
import XCTest
@testable import SetuIOSCore

final class ArtworkModelsTests: XCTestCase {
    func testPIDBatchDeduplicatesWithoutSilentlyDroppingInvalidInput() throws {
        XCTAssertEqual(try PixivPIDInput.parse("123，456\n123 789"), [123,456,789])
        for invalid in ["", "123 bad", "12.5", "-1", "0", "001", "１２３", "2147483648"] {
            XCTAssertThrowsError(try PixivPIDInput.parse(invalid), invalid)
        }
        XCTAssertThrowsError(try PixivPIDInput.parse((1...101).map(String.init).joined(separator: ",")))
    }
    func testOptionalStatisticsAndOpaqueIdentifiersDecodeWithoutInventedCounts() throws {
        let json = #"{"source":"gallery","id":"upload-123","pid":"99999999999999999","title":"work","artist":{"id":"77","name":"artist"},"kind":"illust","pageCount":2,"pages":[{"index":0,"pid":"99","width":800,"height":1000},{"index":0,"pid":"100","width":800,"height":1000}],"tags":[],"bookmarked":false,"restricted":false,"aiGenerated":false}"#
        let value = try JSONDecoder().decode(BrowserArtwork.self, from: Data(json.utf8))
        XCTAssertEqual(value.pid, "99999999999999999")
        XCTAssertNil(value.views)
        XCTAssertNil(value.bookmarks)
        XCTAssertNotEqual(value.pages[0].id, value.pages[1].id)
    }
}

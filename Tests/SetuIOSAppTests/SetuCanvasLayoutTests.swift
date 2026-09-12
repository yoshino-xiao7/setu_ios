import XCTest
@testable import SetuIOSApp

final class SetuCanvasLayoutTests: XCTestCase {
    func testPhonePortraitStaysSingleColumnAndUnconstrained() {
        let canvas = SetuCanvasLayout(size: CGSize(width: 375, height: 812))
        XCTAssertFalse(canvas.isRegularWidth)
        XCTAssertFalse(canvas.isLandscape)
        XCTAssertFalse(canvas.usesTwoPane)
        XCTAssertEqual(canvas.masonryColumnCount, 2)
        XCTAssertEqual(canvas.dashboardColumnCount, 1)
        XCTAssertEqual(canvas.readableMaxWidth, .infinity)
        XCTAssertEqual(canvas.pageGutter, 16)
    }

    func testPhoneProMaxPortraitMatchesCompactRules() {
        let canvas = SetuCanvasLayout(size: CGSize(width: 430, height: 932))
        XCTAssertFalse(canvas.isRegularWidth)
        XCTAssertFalse(canvas.usesTwoPane)
        XCTAssertEqual(canvas.masonryColumnCount, 2)
        XCTAssertEqual(canvas.readableMaxWidth, .infinity)
    }

    func testIPadPortraitUsesReadableWidthAndThreeMasonryColumns() {
        let canvas = SetuCanvasLayout(size: CGSize(width: 834, height: 1194))
        XCTAssertTrue(canvas.isRegularWidth)
        XCTAssertFalse(canvas.isLandscape)
        XCTAssertFalse(canvas.usesTwoPane)
        XCTAssertEqual(canvas.masonryColumnCount, 3)
        XCTAssertEqual(canvas.dashboardColumnCount, 1)
        XCTAssertEqual(canvas.readableMaxWidth, 760)
        XCTAssertEqual(canvas.pageGutter, 24)
    }

    func testIPadLandscapeUsesTwoPaneAndFourMasonryColumns() {
        let canvas = SetuCanvasLayout(size: CGSize(width: 1194, height: 834))
        XCTAssertTrue(canvas.isRegularWidth)
        XCTAssertTrue(canvas.isLandscape)
        XCTAssertTrue(canvas.usesTwoPane)
        XCTAssertEqual(canvas.masonryColumnCount, 4)
        XCTAssertEqual(canvas.dashboardColumnCount, 2)
        XCTAssertEqual(canvas.readableMaxWidth, .infinity)
        XCTAssertEqual(canvas.miniPlayerMaxWidth, 560)
    }

    func testIPadSplitOneThirdStaysCompactLikePhone() {
        let canvas = SetuCanvasLayout(size: CGSize(width: 320, height: 834))
        XCTAssertFalse(canvas.isRegularWidth)
        XCTAssertFalse(canvas.usesTwoPane)
        XCTAssertEqual(canvas.masonryColumnCount, 2)
        XCTAssertEqual(canvas.readableMaxWidth, .infinity)
    }

    func testUnspecifiedCanvasDoesNotClampPhoneLayoutTests() {
        let canvas = SetuCanvasLayout(size: .zero)
        XCTAssertEqual(canvas.readableMaxWidth, .infinity)
        XCTAssertEqual(canvas.masonryColumnCount, 2)
        XCTAssertFalse(canvas.usesTwoPane)
    }

    func testMasonryFillsShortestColumnFirst() {
        let columns = SetuMasonryLayout.columns(
            from: [5.0, 5.0, 5.0, 1.0, 1.0],
            count: 3
        ) { $0 }
        XCTAssertEqual(columns[0], [5, 1])
        XCTAssertEqual(columns[1], [5, 1])
        XCTAssertEqual(columns[2], [5])
    }
}

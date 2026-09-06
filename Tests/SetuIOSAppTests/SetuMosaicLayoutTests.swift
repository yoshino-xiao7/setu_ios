import XCTest
@testable import SetuIOSApp

final class SetuMosaicLayoutTests: XCTestCase {
    func testEmptyInput() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [], columns: 2), [[], []]) }
    func testSingleColumnPreservesAllItems() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [1, 0.5, 2], columns: 1), [[0, 1, 2]]) }
    func testZeroColumnsReturnsEmpty() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [1], columns: 0), []) }
    func testNegativeColumnsReturnsEmpty() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [1], columns: -1), []) }
    func testEqualRatiosRoundRobinWithLeftmostTieBreak() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [1, 1, 1, 1, 1], columns: 2), [[0, 2, 4], [1, 3]]) }
    func testPortraitPushesNextItemsToShorterColumn() { XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: [0.25, 1, 1, 1], columns: 2), [[0], [1, 2, 3]]) }
    func testColumnHeightDifferenceDoesNotExceedLargestItem() {
        let ratios: [CGFloat] = [0.5, 1, 2, 0.75, 1.5, 0.25, 1, 3, 2]
        let columns = SetuMosaicLayout.distribute(aspectRatios: ratios, columns: 3)
        let heights = columns.map { $0.reduce(CGFloat.zero) { $0 + 1 / ratios[$1] } }
        XCTAssertLessThanOrEqual(heights.max()! - heights.min()!, ratios.map { 1 / $0 }.max()!)
    }
    func testInvalidRatiosUseSquareFallback() {
        let ratios: [CGFloat] = [0, -1, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: ratios, columns: 2), [[0, 2, 4], [1, 3, 5]])
    }
    func testEveryItemAppearsOnceAndColumnOrderIsStable() {
        let ratios: [CGFloat] = [1, 0.5, 2, 1, 0.25, 2, 3]
        let columns = SetuMosaicLayout.distribute(aspectRatios: ratios, columns: 3)
        XCTAssertEqual(columns.flatMap { $0 }.sorted(), Array(ratios.indices))
        for column in columns { XCTAssertEqual(column, column.sorted()) }
    }
    func testRepeatedInputProducesSameDistribution() {
        let ratios: [CGFloat] = [1, 0.5, 2, 1, 0.25, 2, 3]
        XCTAssertEqual(SetuMosaicLayout.distribute(aspectRatios: ratios, columns: 3), SetuMosaicLayout.distribute(aspectRatios: ratios, columns: 3))
    }
}

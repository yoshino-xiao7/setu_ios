import XCTest
@testable import SetuIOSApp

final class SetuBentoPackerTests: XCTestCase {
    func testEmptyInput() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [], columns: 4), []) }
    func testSingleItem() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [2], columns: 4), [[0]]) }
    func testWideItemsUseSeparateRows() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [4, 4], columns: 4), [[0], [1]]) }
    func testSmallItemsShareRow() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [2, 2], columns: 4), [[0, 1]]) }
    func testWideItemStartsNextRow() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [2, 4], columns: 4), [[0], [1]]) }
    func testOversizedItemsClampToCapacity() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [8, 2], columns: 4), [[0], [1]]) }
    func testZeroColumnsFallsBackToSingleColumn() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [2, 4, 2], columns: 0), [[0], [1], [2]]) }
    func testNegativeColumnsAndInvalidUnitsStayValid() { XCTAssertEqual(SetuBentoPacker.pack(columnUnits: [-1, 0, 9], columns: -2), [[0], [1], [2]]) }
    func testOrderIsNeverRearrangedToFillHoles() {
        let units = [2, 4, 2, 2, 4, 2, 2, 2]
        let rows = SetuBentoPacker.pack(columnUnits: units, columns: 4)
        XCTAssertEqual(rows, [[0], [1], [2, 3], [4], [5, 6], [7]])
        XCTAssertEqual(rows.flatMap { $0 }, Array(units.indices))
    }
    func testRepeatedInputProducesSameRows() {
        let units = [4, 2, 2, 4, 2, 4]
        XCTAssertEqual(SetuBentoPacker.pack(columnUnits: units, columns: 4), SetuBentoPacker.pack(columnUnits: units, columns: 4))
    }
}

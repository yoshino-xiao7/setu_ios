import XCTest
@testable import SetuIOSApp

final class LyricParserTests: XCTestCase {
    func testParsesTimedLyricsAndSortsOutOfOrderLines() {
        let lines = LyricParser.parse("""
        [00:12.50]第二句
        [00:01.00]第一句
        [00:03.5]中间句
        """)

        XCTAssertEqual(lines.map(\.text), ["第一句", "中间句", "第二句"])
        XCTAssertEqual(lines.map(\.time), [1.0, 3.5, 12.5])
    }

    func testParsesMultipleTimeTagsForSameText() {
        let lines = LyricParser.parse("[00:01.00][00:05.25]重复副歌")

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.text), ["重复副歌", "重复副歌"])
        XCTAssertEqual(lines.map(\.time), [1.0, 5.25])
    }

    func testParsesVariableFractionDigits() {
        let lines = LyricParser.parse("""
        [01:02.3]十分之一秒
        [01:03.045]三位毫秒
        [01:04]无毫秒
        """)

        XCTAssertEqual(lines.map(\.time), [62.3, 63.045, 64.0])
    }

    func testMergesTranslatedLinesByTimestamp() {
        let lines = LyricParser.parse(
            """
            [00:01.00]Hello
            [00:02.00]World
            """,
            translation: """
            [00:02.00]世界
            [00:01.00]你好
            """
        )

        XCTAssertEqual(lines.map(\.translation), ["你好", "世界"])
    }

    func testFallsBackToPlainLyricsWithoutTimestamps() {
        let lines = LyricParser.parse(
            """
            第一行
            第二行
            """,
            translation: """
            Line one
            Line two
            """
        )

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time, 0)
        XCTAssertEqual(lines[0].text, "第一行")
        XCTAssertEqual(lines[0].translation, "Line one")
        XCTAssertEqual(lines[1].time, 1)
    }

    func testActiveIndexTracksCurrentPlaybackTime() {
        let lines = LyricParser.parse("""
        [00:01.00]A
        [00:03.00]B
        [00:05.00]C
        """)

        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 0.2), 0)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 3.4), 1)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 9.0), 2)
    }
    func testOneParseForSixtyProgressUpdatesAndForwardBackwardSeeks() {
        let before = MusicPerformanceProbe.shared.parseCount
        let lines = LyricParser.parse("[00:01]A\n[00:20]B\n[00:50]C")
        XCTAssertEqual(MusicPerformanceProbe.shared.parseCount - before, 1)
        for second in 0..<60 {
            XCTAssertEqual(LyricParser.activeIndex(in: lines, at: Double(second)), second < 20 ? 0 : (second < 50 ? 1 : 2))
        }
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 2), 0)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 55), 2)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 55), 2, "Paused progress is stable")
        XCTAssertEqual(MusicPerformanceProbe.shared.parseCount - before, 1)
        XCTAssertTrue(lines.allSatisfy { $0.translation == nil })
        let next = LyricParser.parse("[00:00]New track")
        XCTAssertEqual(next.map(\.text), ["New track"])
        XCTAssertEqual(MusicPerformanceProbe.shared.parseCount - before, 2)
        print("Lyrics: 60 time updates and seeks, 1 parse; next track adds 1 parse")
    }

    func testEmptyLyricsAndTranslationOnlyFallback() {
        XCTAssertEqual(LyricParser.parse(""), [])
        XCTAssertNil(LyricParser.activeIndex(in: [], at: 10))
        let translationOnly = LyricParser.parse("", translation: "仅翻译")
        XCTAssertEqual(translationOnly.map(\.text), ["仅翻译"])
        XCTAssertNil(translationOnly.first?.translation)
    }

    func testBinarySearchPreservesLastDuplicateTimestampAndBoundarySemantics() {
        let lines = LyricParser.parse("[00:03]B\n[00:03]C\n[00:01]A")
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: -1), 0)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 2.999), 0)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: 3), 2)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: .infinity), 2)
        XCTAssertEqual(LyricParser.activeIndex(in: lines, at: .nan), 0)
    }

}

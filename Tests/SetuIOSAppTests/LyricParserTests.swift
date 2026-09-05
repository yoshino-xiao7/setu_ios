import XCTest
import SetuIOSCore
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

extension LyricParserTests {
    func testV2LineAdapterMatchesLegacyBinarySearchAndTranslation() throws {
        let lyric = try lyricFixture(kind: "line", lines: #"{"text":"A","words":[],"startMs":1000,"durationMs":2000,"translation":"甲"},{"text":"B","words":[],"startMs":3000,"durationMs":1000,"translation":null}"#)
        let v2 = LyricParser.parse(lyric), v1 = LyricParser.parse("[00:01]A\n[00:03]B")
        for time in [-1.0, 0, 1, 2.9, 3, 4, 60, 1] {
            XCTAssertEqual(LyricParser.activeIndex(in: v2, at: time), LyricParser.activeIndex(in: v1, at: time))
        }
        XCTAssertEqual(v2.first?.translation, "甲")
        XCTAssertTrue(v2.allSatisfy(\.isTimed))
    }

    func testV2SyllableAbsoluteTimeBoundariesGapsAndBackwardsSeek() throws {
        let line = try XCTUnwrap(LyricParser.parse(wordFixture()).first)
        let samples: [(Int, Int, Double)] = [(0,0,0), (1000,0,0), (1100,0,0.5), (1200,0,1), (1299,0,1), (1300,1,0), (1500,1,0.5), (1700,1,1), (2000,1,1), (1100,0,0.5)]
        for (time, index, ratio) in samples {
            let progress = try XCTUnwrap(LyricParser.syllableProgress(in: line, at: time))
            XCTAssertEqual(progress.index, index)
            XCTAssertEqual(progress.ratio, ratio, accuracy: 0.0001)
        }
    }

    func testV2SixtyTicksAndSeeksNeverReparse() throws {
        let fixture = try wordFixture()
        let before = MusicPerformanceProbe.shared.parseCount
        let lines = LyricParser.parse(fixture)
        for tick in 0..<60 {
            _ = LyricParser.activeIndex(in: lines, at: Double(tick) / 30)
            _ = LyricParser.syllableProgress(in: lines[0], at: tick * 33)
        }
        _ = LyricParser.syllableProgress(in: lines[0], at: 1100)
        XCTAssertEqual(MusicPerformanceProbe.shared.parseCount - before, 1)
    }

    func testV2PlainNoneAndLineNeverInventWordTiming() throws {
        let plain = LyricParser.parse(try lyricFixture(kind: "plain", lines: #"{"text":"正文","words":[],"startMs":null,"durationMs":null,"translation":"text"}"#))
        XCTAssertFalse(plain[0].isTimed)
        XCTAssertNil(LyricParser.syllableProgress(in: plain[0], at: 1000))
        XCTAssertEqual(plain[0].translation, "text")
        XCTAssertTrue(LyricParser.parse(try lyricFixture(kind: "none", lines: "")).isEmpty)
        let line = LyricParser.parse(try lyricFixture(kind: "line", lines: #"{"text":"行","words":[],"startMs":1000,"durationMs":2000,"translation":null}"#))[0]
        XCTAssertNil(LyricParser.syllableProgress(in: line, at: 1500))
    }

    func testMismatchedWordTextFallsBackToWholeLine() throws {
        let line = LyricParser.parse(try lyricFixture(kind: "word", lines: #"{"text":"完整正文","words":[{"text":"不同","startMs":0,"durationMs":100}],"startMs":0,"durationMs":100,"translation":null}"#))[0]
        XCTAssertEqual(line.text, "完整正文")
        XCTAssertTrue(line.words.isEmpty)
    }

    private func wordFixture() throws -> MusicV2Lyric {
        try lyricFixture(kind: "word", lines: #"{"text":"你好世界","words":[{"text":"你好","startMs":1000,"durationMs":200},{"text":"世界","startMs":1300,"durationMs":400}],"startMs":1000,"durationMs":700,"translation":"Hello world"}"#)
    }

    private func lyricFixture(kind: String, lines: String) throws -> MusicV2Lyric {
        try JSONDecoder().decode(MusicV2Lyric.self, from: Data("{\"trackId\":\"netease:track:1\",\"kind\":\"\(kind)\",\"lines\":[\(lines)],\"hasTranslation\":true,\"contributors\":[]}".utf8))
    }
}

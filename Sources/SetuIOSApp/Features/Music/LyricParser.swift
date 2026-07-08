import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: String
    let time: TimeInterval
    let text: String
    var translation: String?
}

enum LyricParser {
    static func parse(_ rawLyric: String, translation rawTranslation: String? = nil) -> [LyricLine] {
        let baseLines = parseTimedLines(rawLyric)
        guard !baseLines.isEmpty else {
            return fallbackLines(rawLyric, translation: rawTranslation)
        }

        let translatedLines = Dictionary(
            parseTimedLines(rawTranslation ?? "").map { (roundedKey($0.time), $0.text) },
            uniquingKeysWith: { first, _ in first }
        )

        return baseLines.map { line in
            LyricLine(
                id: line.id,
                time: line.time,
                text: line.text,
                translation: translatedLines[roundedKey(line.time)]
            )
        }
    }

    static func activeIndex(in lines: [LyricLine], at currentTime: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var candidate: Int?
        for (index, line) in lines.enumerated() where currentTime >= line.time {
            candidate = index
        }
        return candidate ?? 0
    }

    private static func parseTimedLines(_ raw: String) -> [LyricLine] {
        raw.components(separatedBy: .newlines)
            .flatMap(parseTimedLine)
            .sorted { lhs, rhs in
                if lhs.time == rhs.time {
                    return lhs.text < rhs.text
                }
                return lhs.time < rhs.time
            }
            .enumerated()
            .map { index, line in
                LyricLine(
                    id: "\(roundedKey(line.time))-\(index)",
                    time: line.time,
                    text: line.text,
                    translation: nil
                )
            }
    }

    private static func parseTimedLine(_ rawLine: String) -> [LyricLine] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }

        var cursor = line.startIndex
        var times: [TimeInterval] = []

        while cursor < line.endIndex, line[cursor] == "[" {
            guard let end = line[cursor...].firstIndex(of: "]") else { break }
            let tagStart = line.index(after: cursor)
            let tag = String(line[tagStart..<end])
            if let time = parseTimeTag(tag) {
                times.append(time)
            }
            cursor = line.index(after: end)
        }

        guard !times.isEmpty else { return [] }
        let text = String(line[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        return times.map { time in
            LyricLine(id: "\(roundedKey(time))", time: time, text: text, translation: nil)
        }
    }

    private static func parseTimeTag(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]),
              seconds >= 0 else {
            return nil
        }
        return minutes * 60 + seconds
    }

    private static func fallbackLines(_ rawLyric: String, translation rawTranslation: String?) -> [LyricLine] {
        let base = rawLyric
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let translated = (rawTranslation ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = base.isEmpty ? translated : base
        return source.enumerated().map { index, text in
            LyricLine(
                id: "plain-\(index)",
                time: TimeInterval(index),
                text: text,
                translation: base.isEmpty ? nil : translated[safe: index]
            )
        }
    }

    private static func roundedKey(_ time: TimeInterval) -> Int {
        Int((time * 1000).rounded())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

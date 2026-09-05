import Foundation

/// Legacy values and canonical tokens are separate domains, even when their text resembles one another.
public enum MusicPlaybackIdentity: Hashable, Sendable, Codable, Comparable, ExpressibleByIntegerLiteral {
    case legacy(Int)
    case canonical(MusicV2TrackID)

    public init(integerLiteral value: Int) { self = .legacy(value) }
    public var legacyID: Int? { if case .legacy(let id) = self { return id }; return nil }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.legacy(let a), .legacy(let b)): return a < b
        case (.canonical(let a), .canonical(let b)): return a.rawValue < b.rawValue
        case (.legacy, .canonical): return true
        case (.canonical, .legacy): return false
        }
    }
    private enum CodingKeys: String, CodingKey { case version, kind, value }
    public init(from decoder: Decoder) throws {
        // Old snapshots encoded the Int directly. Never infer a provider token from it.
        if let value = try? decoder.singleValueContainer().decode(Int.self) { self = .legacy(value); return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Unsupported playback identity version")
        }
        switch try c.decode(String.self, forKey: .kind) {
        case "legacy": self = .legacy(try c.decode(Int.self, forKey: .value))
        case "canonical": self = .canonical(try c.decode(MusicV2TrackID.self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown playback identity kind")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        switch self {
        case .legacy(let id): try c.encode("legacy", forKey: .kind); try c.encode(id, forKey: .value)
        case .canonical(let id): try c.encode("canonical", forKey: .kind); try c.encode(id, forKey: .value)
        }
    }
}

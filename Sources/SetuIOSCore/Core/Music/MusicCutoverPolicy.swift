import Foundation

public enum MusicClientRelease {
    public static func header(version: String, build: String) -> String? {
        let value = "ios:\(version):\(build)"
        guard value.utf8.count <= 96, !value.contains("\n"), !value.contains("\r"),
              value.range(of: #"^ios:[0-9]{1,4}(\.[0-9]{1,4}){1,3}:[A-Za-z0-9][A-Za-z0-9._-]{0,39}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
    public static var current: String? {
        header(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0",
               build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }
}

public struct MusicRolloutCapabilities: Decodable, Sendable {
    public let version: Int
    public let admitNewPlaybackSession: Bool
    public let validForSeconds: Int
    public var permitsAdmission: Bool { version == 1 && admitNewPlaybackSession && (1...30).contains(validForSeconds) }
}

/// Local durable UI pin, scoped by backend and account. Never converts canonical IDs to legacy.
@MainActor
public enum MusicHistoryCohort {
    private static func key(base: URL, owner: Int) -> String { "music.history.v2.\(base.absoluteString).\(owner)" }
    public static func usesV2(base: URL, owner: Int?, flag: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard let owner else { return false }
        return flag || defaults.bool(forKey: key(base: base, owner: owner))
    }
    public static func pin(base: URL, owner: Int, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(base: base, owner: owner))
    }
}

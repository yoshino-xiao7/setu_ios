#if DEBUG
import Foundation
import SwiftUI

/// Count-only diagnostics for local tests; no song, account, URL or credential data.
final class MusicPerformanceProbe: @unchecked Sendable {
    static let shared = MusicPerformanceProbe()
    private let lock = NSLock()
    private var players = 0
    private var parses = 0
    private var mvDetails = 0
    var playerCount: Int { lock.withLock { players } }
    var parseCount: Int { lock.withLock { parses } }
    var mvDetailCount: Int { lock.withLock { mvDetails } }
    func playerCreated() { lock.withLock { players += 1 } }
    func playerReleased() { lock.withLock { players -= 1 } }
    func lyricParsed() { lock.withLock { parses += 1 } }
    func mvDetailRequested() { lock.withLock { mvDetails += 1 } }
}

final class MusicMiniPlayerLifetime: ObservableObject {
    let id = UUID()
    init() { MusicPerformanceProbe.shared.playerCreated() }
    deinit { MusicPerformanceProbe.shared.playerReleased() }
    var diagnosticValue: String { "instances=\(MusicPerformanceProbe.shared.playerCount);identity=\(id)" }
}
#endif

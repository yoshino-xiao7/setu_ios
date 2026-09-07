import Foundation

/// A low-frequency derived view. The controller's fine-grained observable
/// properties remain the source of truth for progress and controls.
enum PlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed

    static func derive(hasTrack: Bool, isBuffering: Bool, isPlaying: Bool, hasError: Bool) -> Self {
        if hasError { return .failed }
        if !hasTrack { return .idle }
        if isBuffering { return .loading }
        return isPlaying ? .playing : .paused
    }
}

/// Monotonic, injectable timing; resolving, delivery and seeking have distinct budgets.
struct PlaybackTiming: Sendable {
    var resolveSeconds: Double = 20
    var noProgressSeconds: Double = 15
    var operationSeconds: Double = 60
    var now: @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    var sleep: @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
}

struct PlaybackDowngradePolicy {
    private(set) var attempts = 0
    private var stalls: [Double] = []
    mutating func endedStall(start: Double, end: Double) {
        if end - start >= 1 { stalls.append(end) }
        stalls.removeAll { end - $0 > 30 }
    }
    func shouldDowngrade(now: Double, waitingSince: Double, receiving: Bool) -> Bool {
        receiving && attempts < 2 && (now - waitingSince >= 8 || stalls.filter { now - $0 <= 30 }.count + (now - waitingSince >= 1 ? 1 : 0) >= 3)
    }
    mutating func takeNext(after quality: String) -> String? {
        guard attempts < 2 else { return nil }
        let next: String?
        switch quality {
        case "hires", "lossless": next = "exhigh"
        case "exhigh", "higher": next = "standard"
        default: next = nil
        }
        guard let next else { return nil }
        attempts += 1; stalls = []; return next
    }
}

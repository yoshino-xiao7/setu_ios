import Foundation
import SetuIOSCore

/// Runtime-only sink. Tests/previews do not install it. No URLs, queries or identifiers are accepted.
@MainActor
enum MusicClientObservation {
    static var client: MusicV2Client?
    static var playbackV2 = false
    static func emit(_ event: String, start: TimeInterval? = nil, v2: Bool, count: Int = 1) {
        guard let client else { return }
        let elapsed = start.map { max(0, min(300000, (ProcessInfo.processInfo.systemUptime - $0) * 1000)) } ?? 0
        Task { await client.observe(event: event, durationMs: elapsed, transport: v2 ? "v2" : "v1", count: count) }
    }
}

#if os(iOS)
import MetricKit

/// Only counts matching-build diagnostics; never serializes stacks or diagnostic payloads.
final class MusicCrashObservation: NSObject, MXMetricManagerSubscriber {
    static let shared = MusicCrashObservation()
    private override init() { super.init(); MXMetricManager.shared.add(self) }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let count = payloads.flatMap { $0.crashDiagnostics ?? [] }
            .filter { $0.applicationVersion == version && $0.metaData.applicationBuildVersion == build }.count
        guard count > 0 else { return }
        Task { @MainActor in MusicClientObservation.emit("client.crash", v2: MusicClientObservation.playbackV2, count: min(20, count)) }
    }
}
#endif

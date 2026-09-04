import Foundation

/// Central cutover decision for later UI phases. P9 installs the route without changing any call
/// site, and production defaults keep every route on the legacy closure.
public struct MusicDataLayerRouter: Sendable {
    public let flags: MusicFeatureFlags

    public init(flags: MusicFeatureFlags) { self.flags = flags }

    public func value<Value: Sendable>(
        for feature: MusicFeatureRoute,
        legacy: @Sendable () async throws -> Value,
        v2: @Sendable () async throws -> Value
    ) async throws -> Value {
        if flags.isEnabled(feature) { return try await v2() }
        return try await legacy()
    }
}

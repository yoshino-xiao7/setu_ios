import Foundation

public struct ResolvedPlaybackURL: Sendable {
    public let trackID: Int
    public let url: URL
    public let effectiveLevel: String
    public let resolvedAt: Date
    public let expiresAt: Date
    public let notice: String?
    public let usedFallback: Bool

    public func isValid(at date: Date) -> Bool { date < expiresAt }
}

/// Session-scoped, memory-only URL cache. Batch responses are always matched by ID.
public actor PlaybackURLResolver {
    public typealias Outcome = Result<ResolvedPlaybackURL, UserFacingError>
    private struct Key: Hashable {
        let id: Int
        let quality: MusicAudioQuality
        let allowsFallback: Bool
    }
    private struct Flight {
        let token: UUID
        let task: Task<[Int: Outcome], Never>
    }
    private let fetch: @Sendable ([Int], MusicAudioQuality) async throws -> MusicUrlResponse
    private let now: @Sendable () -> Date
    private var cache: [Key: ResolvedPlaybackURL] = [:]
    private var flights: [Key: Flight] = [:]
    private var generation = UUID()

    public init(client: MusicClient, now: @escaping @Sendable () -> Date = { Date() }) {
        fetch = { try await client.url(songIDs: $0, level: $1.rawValue) }
        self.now = now
    }

    public init(now: @escaping @Sendable () -> Date = { Date() },
                fetch: @escaping @Sendable ([Int], MusicAudioQuality) async throws -> MusicUrlResponse) {
        self.now = now
        self.fetch = fetch
    }

    public func resolve(trackID: Int, quality: MusicAudioQuality, force: Bool = false,
                        allowsFallback: Bool = true) async throws -> ResolvedPlaybackURL {
        let results = try await resolve(ids: [trackID], quality: quality, force: force, allowsFallback: allowsFallback)
        guard let result = results[trackID] else { throw UserFacingError(message: "音乐服务未返回这首歌曲") }
        return try result.get()
    }

    public func resolve(ids: [Int], quality: MusicAudioQuality, force: Bool = false,
                        allowsFallback: Bool = true) async throws -> [Int: Outcome] {
        try Task.checkCancellation()
        let owner = generation
        let keys = Array(Set(ids)).sorted().map { Key(id: $0, quality: quality, allowsFallback: allowsFallback) }
        var result: [Int: Outcome] = [:]
        var pending: [Key: Flight] = [:]
        var missing: [Key] = []
        for key in keys {
            if !force, let cached = cache[key], cached.isValid(at: now()) {
                result[key.id] = .success(cached)
            } else if let flight = flights[key] {
                pending[key] = flight
            } else {
                missing.append(key)
            }
        }
        if !missing.isEmpty {
            let requested = missing.map(\.id)
            let fetch = self.fetch, now = self.now
            let flight = Flight(token: UUID(), task: Task {
                await Self.fetchURLs(ids: requested, quality: quality, allowsFallback: allowsFallback, now: now, fetch: fetch)
            })
            for key in missing { flights[key] = flight; pending[key] = flight }
        }
        for (key, flight) in pending {
            let outcomes = await flight.task.value
            guard owner == generation else { throw CancellationError() }
            let outcome = outcomes[key.id] ?? .failure(UserFacingError(message: "音乐服务未返回这首歌曲"))
            if flights[key]?.token == flight.token {
                flights[key] = nil
                if case .success(let value) = outcome { cache[key] = value }
            }
            result[key.id] = outcome
        }
        try Task.checkCancellation()
        return result
    }

    public func reset() {
        generation = UUID()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        cache.removeAll()
    }

    private static func fetchURLs(ids: [Int], quality: MusicAudioQuality, allowsFallback: Bool,
                                  now: @Sendable () -> Date,
                                  fetch: @Sendable ([Int], MusicAudioQuality) async throws -> MusicUrlResponse) async -> [Int: Outcome] {
        var results: [Int: Outcome] = [:]
        var retry: [Int] = []
        do {
            let response = try await fetch(ids, quality)
            for id in ids {
                // Never use data.first: one unavailable song must not borrow another song's URL.
                let item = response.data?.first { $0.id == id }
                results[id] = outcome(item: item, id: id, quality: quality, fallback: false, now: now())
                if case .failure = results[id], !isRestricted(item), allowsFallback, quality != .standard { retry.append(id) }
            }
        } catch {
            let failure = UserFacingErrorMapper.map(error)
            for id in ids { results[id] = .failure(failure) }
            if failure.action != .signIn, !(error is CancellationError), allowsFallback, quality != .standard { retry = ids }
        }
        if !retry.isEmpty, !Task.isCancelled {
            do {
                let response = try await fetch(retry, .standard)
                for id in retry {
                    results[id] = outcome(item: response.data?.first { $0.id == id }, id: id,
                                          quality: quality, fallback: true, now: now())
                }
            } catch {
                let failure = UserFacingErrorMapper.map(error)
                if failure.action == .signIn { for id in retry { results[id] = .failure(failure) } }
            }
        }
        return results
    }

    private static func isRestricted(_ item: MusicUrlItem?) -> Bool {
        guard let item else { return false }
        return ["TRIAL", "VIP", "VIP_ONLY", "FEE_REQUIRED", "REGION_RESTRICTED", "LOGIN_INVALID"].contains(item.playability?.uppercased() ?? "")
            || item.unavailableMessage.contains("版权")
    }

    private static func outcome(item: MusicUrlItem?, id: Int, quality: MusicAudioQuality,
                                fallback: Bool, now: Date) -> Outcome {
        guard let item else { return .failure(UserFacingError(message: "音乐服务未返回这首歌曲")) }
        guard let string = item.playableURLString, let url = URL(string: string) else {
            return .failure(UserFacingError(message: item.unavailableMessage))
        }
        let level = item.level ?? (fallback ? "standard" : quality.rawValue)
        let actual = MusicAudioQuality(rawValue: level)
        let notice = fallback ? "\(quality.title)音质不可用，本曲使用标准音质" : actual.flatMap { $0 != quality ? "音源返回\($0.title)音质" : nil }
        // Missing expi uses the plan's conservative 10-minute cap; subtract a safety margin.
        let lifetime = max(0, min(Double(item.expi ?? 600), 600) - 5)
        return .success(ResolvedPlaybackURL(trackID: id, url: url, effectiveLevel: level, resolvedAt: now,
                                            expiresAt: now.addingTimeInterval(lifetime), notice: notice, usedFallback: fallback))
    }
}

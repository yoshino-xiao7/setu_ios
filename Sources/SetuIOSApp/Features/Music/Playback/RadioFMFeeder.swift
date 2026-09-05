import Foundation
import SetuIOSCore

/// Private, uncached batches. A generation rejects late responses even when a
/// transport ignores cancellation. Empty batches are retryable, never terminal.
@MainActor
final class RadioFMFeeder {
    typealias Fetch = @MainActor () async throws -> MusicV2RadioBatch
    private let fetch: Fetch
    private let sleep: @Sendable (UInt64) async throws -> Void
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var active = true

    init(fetch: @escaping Fetch,
         sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.fetch = fetch
        self.sleep = sleep
    }

    func refill(remaining: Int, receive: @escaping @MainActor (MusicV2RadioBatch) async -> Void,
                failure: @escaping @MainActor (Error?) -> Void) {
        guard active, remaining < 2, task == nil else { return }
        let ticket = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == ticket { self.task = nil } }
            for attempt in 0...3 {
                do {
                    if attempt > 0 { try await self.sleep(UInt64(1 << (attempt - 1)) * 1_000_000_000) }
                    guard self.active, self.generation == ticket, !Task.isCancelled else { return }
                    let batch = try await self.fetch()
                    guard self.active, self.generation == ticket, !Task.isCancelled else { return }
                    if !batch.tracks.isEmpty { await receive(batch); return }
                    if attempt == 3 { failure(nil) }
                } catch {
                    guard self.active, self.generation == ticket, !Task.isCancelled else { return }
                    if attempt == 3 { failure(error) }
                }
            }
        }
    }

    func stop() {
        active = false
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func waitForRefill() async { await task?.value }

    static func trimCount(count: Int, currentIndex: Int?) -> Int {
        min(max(count - 50, 0), max(currentIndex ?? 0, 0))
    }
}

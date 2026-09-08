import Foundation
import SwiftUI
import SetuIOSCore

/// A browser-session cache: capability URLs may rotate, but artwork/page/quality do not.
/// Original bytes still travel through ArtworkClient and its authenticated transport.
@MainActor
final class ArtworkImageStore {
    enum Quality: Int, CaseIterable, Sendable { case avatar, thumbnail, preview, original }
    private let memory = SetuImageMemoryCache(costLimit: 80 * 1024 * 1024, countLimit: 160)
    private let fetch: @Sendable (String) async throws -> Data
    private struct Flight { let id: UUID; let task: Task<SetuDecodedImage, Error> }
    private var flights: [SetuImageKey: Flight] = [:]

    init(fetch: @escaping @Sendable (String) async throws -> Data) { self.fetch = fetch }

    private func key(_ identity: String, _ quality: Quality) -> SetuImageKey {
        var url = URLComponents()
        url.scheme = "artwork-cache"; url.host = "image"; url.path = "/" + identity
        url.queryItems = [URLQueryItem(name: "quality", value: String(quality.rawValue))]
        return SetuImageKey(url: url.url!, size: quality == .avatar ? .thumbnail : quality == .thumbnail ? .large : .fullScreen)
    }

    func cached(_ identity: String, quality: Quality, fallback: Bool = true) -> SetuDecodedImage? {
        if let image = memory.image(for: key(identity, quality)) { return image }
        guard fallback else { return nil }
        for other in Quality.allCases.reversed() where other != quality {
            if let image = memory.image(for: key(identity, other)) { return image }
        }
        return nil
    }

    func load(_ path: String, identity: String, quality: Quality) async throws -> SetuDecodedImage {
        let key = key(identity, quality)
        if let image = memory.image(for: key) { return image }
        if let flight = flights[key] { return try await flight.task.value }
        let generation = memory.generation
        let id = UUID(), fetch = fetch, memory = memory
        let task = Task.detached(priority: .userInitiated) {
            let data = try await fetch(path)
            try Task.checkCancellation()
            let image = try SetuRemoteImageLoader.decodeImage(data, key: key)
            try Task.checkCancellation()
            guard memory.generation == generation else { throw CancellationError() }
            memory.insert(image, for: key, generation: generation)
            return image
        }
        flights[key] = Flight(id: id, task: task)
        defer { if flights[key]?.id == id { flights[key] = nil } }
        return try await task.value
    }

    func clear() {
        memory.removeAll()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
    }
}

private struct ArtworkImageStoreKey: EnvironmentKey {
    static let defaultValue: ArtworkImageStore? = nil
}
extension EnvironmentValues {
    var artworkImages: ArtworkImageStore? {
        get { self[ArtworkImageStoreKey.self] }
        set { self[ArtworkImageStoreKey.self] = newValue }
    }
}
extension BrowserArtwork {
    var transitionID: String { "\(source.rawValue):\(id)" }
    func imageIdentity(_ page: ArtworkPage) -> String { "\(transitionID):\(page.id)" }
}

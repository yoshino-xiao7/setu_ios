import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

public enum JmPagePrefetchWindow {
    public static let ahead = 3
    public static let behind = 1

    /// Current page first, then upcoming pages, then the previous page.
    public static func indices(current: Int, count: Int, ahead: Int = ahead, behind: Int = behind) -> [Int] {
        guard count > 0, current >= 0, current < count else { return [] }
        var ordered = [current]
        if ahead > 0 {
            for offset in 1...ahead {
                let index = current + offset
                if index < count { ordered.append(index) }
            }
        }
        if behind > 0 {
            for offset in 1...behind {
                let index = current - offset
                if index >= 0 { ordered.append(index) }
            }
        }
        return ordered
    }
}

@MainActor
@Observable
public final class JmPageImageLoader {
    public private(set) var revision = 0

    private let fetch: (JmPageImage) async throws -> Data
    #if canImport(UIKit)
    private var images: [String: UIImage] = [:]
    #endif
    private var failed: Set<String> = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var epochs: [String: Int] = [:]

    public init(fetch: @escaping (JmPageImage) async throws -> Data = JmPageImageLoader.defaultFetch) {
        self.fetch = fetch
    }

    #if canImport(UIKit)
    public func image(for page: JmPageImage) -> UIImage? {
        images[page.id]
    }
    #endif

    public func isFailed(_ page: JmPageImage) -> Bool {
        failed.contains(page.id)
    }

    public func isLoading(_ page: JmPageImage) -> Bool {
        tasks[page.id] != nil && !failed.contains(page.id)
    }

    public func prefetch(pages: [JmPageImage], currentIndex: Int) {
        let keep = Set(JmPagePrefetchWindow.indices(current: currentIndex, count: pages.count).compactMap { pages.indices.contains($0) ? pages[$0].id : nil })
        for (id, task) in tasks where !keep.contains(id) {
            invalidate(id, task: task)
        }
        #if canImport(UIKit)
        images = images.filter { keep.contains($0.key) }
        #endif
        failed = failed.intersection(keep)
        let ordered = JmPagePrefetchWindow.indices(current: currentIndex, count: pages.count)
        for (offset, index) in ordered.enumerated() {
            ensure(pages[index], priority: offset == 0 ? .userInitiated : .utility)
        }
        revision += 1
    }

    public func ensure(_ page: JmPageImage, priority: TaskPriority = .userInitiated) {
        #if canImport(UIKit)
        if images[page.id] != nil { return }
        #endif
        start(page, priority: priority)
    }

    public func retry(_ page: JmPageImage) {
        failed.remove(page.id)
        invalidate(page.id, task: tasks[page.id])
        start(page, priority: .userInitiated)
        revision += 1
    }

    public func cancelAll() {
        for id in Set(tasks.keys).union(epochs.keys) {
            invalidate(id, task: tasks[id])
        }
    }

    private func invalidate(_ id: String, task: Task<Void, Never>?) {
        epochs[id, default: 0] += 1
        task?.cancel()
        tasks[id] = nil
    }

    private func start(_ page: JmPageImage, priority: TaskPriority) {
        let id = page.id
        #if canImport(UIKit)
        guard images[id] == nil, tasks[id] == nil else { return }
        #else
        guard tasks[id] == nil else { return }
        #endif
        failed.remove(id)
        let epoch = epochs[id, default: 0] + 1
        epochs[id] = epoch
        tasks[id] = Task(priority: priority) { [fetch] in
            defer {
                if self.epochs[id] == epoch {
                    self.tasks[id] = nil
                }
            }
            do {
                let data = try await fetch(page)
                try Task.checkCancellation()
                guard self.epochs[id] == epoch else { return }
                #if canImport(UIKit)
                let decoded = await Task.detached(priority: .utility) {
                    JmImageDescrambler.descrambleUIImage(data: data, page: page)
                }.value
                try Task.checkCancellation()
                guard self.epochs[id] == epoch else { return }
                guard let decoded else {
                    self.failed.insert(id)
                    self.revision += 1
                    return
                }
                self.images[id] = decoded
                self.failed.remove(id)
                #endif
                self.revision += 1
            } catch is CancellationError {
                return
            } catch {
                guard self.epochs[id] == epoch else { return }
                self.failed.insert(id)
                self.revision += 1
            }
        }
    }

    public static func defaultFetch(_ page: JmPageImage) async throws -> Data {
        let request = JmAppToken.imageRequest(url: page.url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

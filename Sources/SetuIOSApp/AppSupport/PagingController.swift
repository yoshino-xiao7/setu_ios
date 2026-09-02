import Observation
import Foundation
import SetuIOSCore

/// 分页加载的通用状态机：吸收各列表视图重复的
/// hasMore / isLoadingMore / loadMoreError / 首屏 loading / 并发保护 / 按 ID 去重样板。
///
/// 用法（视图持有 `@State private var pager = PagingController<FavoriteItem>(pageSize: 30)`）：
/// ```swift
/// await pager.loadFirstPage { page in
///     let r = try await client.list(page: page, size: pager.pageSize)
///     return (r.items, r.total)
/// }
/// ```
/// 迁移注意：本地 key 一律不改；错误文案由调用方通过 `initialError`/`loadMoreError` 闭包或赋值定制。
@MainActor
@Observable
final class PagingController<Item: Identifiable> {

    struct PageResult {
        let items: [Item]
        let total: Int
    }

    enum LoadPhase: Equatable {
        case idle
        case loadingInitial
        case loadingMore
    }

    private(set) var items: [Item] = []
    private(set) var total = 0
    private(set) var phase: LoadPhase = .idle
    private(set) var initialError: UserFacingError?
    private(set) var loadMoreError: UserFacingError?

    private(set) var hasLoadedFirstPage = false
    private var reachedEnd = false

    let pageSize: Int
    private var nextPage = 1
    private var generation = 0

    init(pageSize: Int) {
        self.pageSize = pageSize
    }

    var hasMore: Bool { !reachedEnd && items.count < total }

    /// 首屏加载：items 为空时置 loading 态；失败写入 initialError（可用 onError 定制文案）并保留旧数据。
    func loadFirstPage(
        clearExisting: Bool = false,
        _ fetch: @MainActor (_ page: Int) async throws -> PageResult,
        onError: ((Error) -> String)? = nil
    ) async {
        generation += 1
        let currentGeneration = generation
        if clearExisting {
            items = []
            total = 0
            hasLoadedFirstPage = false
        }
        reachedEnd = false
        phase = items.isEmpty ? .loadingInitial : .loadingMore
        initialError = nil
        loadMoreError = nil
        do {
            let result = try await fetch(1)
            guard generation == currentGeneration else { return }
            var seen: Set<Item.ID> = []
            items = result.items.filter { seen.insert($0.id).inserted }
            hasLoadedFirstPage = true
            reachedEnd = result.items.isEmpty
            total = result.total
            nextPage = 2
        } catch {
            guard generation == currentGeneration else { return }
            initialError = mappedError(error, message: onError?(error))
        }
        phase = .idle
    }

    /// 加载下一页：并发调用与重复加载有保护；按 ID 去重追加；失败写入 loadMoreError（保留已加载数据）。
    func loadMore(
        _ fetch: @MainActor (_ page: Int) async throws -> PageResult,
        onError: ((Error) -> String)? = nil
    ) async {
        guard hasMore, phase != .loadingMore, phase != .loadingInitial else { return }
        let requestedPage = nextPage
        generation += 1
        let currentGeneration = generation
        phase = .loadingMore
        loadMoreError = nil
        do {
            let result = try await fetch(requestedPage)
            guard generation == currentGeneration, requestedPage == nextPage else { return }
            var existingIDs = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { existingIDs.insert($0.id).inserted })
            reachedEnd = result.items.isEmpty
            total = result.total
            nextPage += 1
        } catch {
            guard generation == currentGeneration else { return }
            loadMoreError = mappedError(error, message: onError?(error))
        }
        phase = .idle
    }
    func replaceItems(_ items: [Item], total: Int? = nil) {
        self.items = items
        if let total { self.total = total }
    }

    func invalidate(clearExisting: Bool = false) {
        generation += 1
        phase = .idle
        if clearExisting {
            items = []
            total = 0
            nextPage = 1
            reachedEnd = false
            hasLoadedFirstPage = false
        }
    }

    private func mappedError(_ error: Error, message: String?) -> UserFacingError {
        let mapped = UserFacingErrorMapper.map(error)
        guard let message, mapped.action != .signIn else { return mapped }
        return UserFacingError(title: mapped.title, message: message, action: mapped.action, diagnosticCode: mapped.diagnosticCode)
    }

}

import Foundation

public struct ModuleWatchRecord: Codable, Identifiable, Hashable, Sendable {
    public var module: ModuleFavoriteModule
    public var externalId: String
    public var title: String
    public var coverUrl: String?
    public var subtitle: String?
    public var viewedAt: Date

    public var id: String { "\(module.rawValue):\(externalId)" }

    public init(
        module: ModuleFavoriteModule,
        externalId: String,
        title: String,
        coverUrl: String? = nil,
        subtitle: String? = nil,
        viewedAt: Date = Date()
    ) {
        self.module = module
        self.externalId = externalId
        self.title = title
        self.coverUrl = coverUrl
        self.subtitle = subtitle
        self.viewedAt = viewedAt
    }
}

@MainActor
public final class ModuleWatchHistoryStore {
    public static let capacity = 100

    private let defaults: UserDefaults
    private let ownerID: () -> String

    public init(defaults: UserDefaults = .standard, ownerID: @escaping () -> String) {
        self.defaults = defaults
        self.ownerID = ownerID
    }

    public func records(module: ModuleFavoriteModule) -> [ModuleWatchRecord] {
        load(module: module)
    }

    public func record(_ item: ModuleWatchRecord) {
        var items = load(module: item.module).filter { $0.externalId != item.externalId }
        items.insert(item, at: 0)
        if items.count > Self.capacity {
            items = Array(items.prefix(Self.capacity))
        }
        save(items, module: item.module)
    }

    public func remove(module: ModuleFavoriteModule, externalId: String) {
        save(load(module: module).filter { $0.externalId != externalId }, module: module)
    }

    private func load(module: ModuleFavoriteModule) -> [ModuleWatchRecord] {
        guard let data = defaults.data(forKey: key(module: module)),
              let items = try? JSONDecoder().decode([ModuleWatchRecord].self, from: data) else { return [] }
        return items.sorted { $0.viewedAt > $1.viewedAt }
    }

    private func save(_ items: [ModuleWatchRecord], module: ModuleFavoriteModule) {
        defaults.set(try? JSONEncoder().encode(items), forKey: key(module: module))
    }

    private func key(module: ModuleFavoriteModule) -> String {
        "icu.yukiryou.setu.moduleWatchHistory.v1.\(ownerID()).\(module.rawValue)"
    }
}

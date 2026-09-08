import Foundation
import Observation
import Network

@MainActor @Observable
final class MusicCacheSettings {
    enum PrefetchPolicy: String, CaseIterable, Identifiable {
        case off, wifi, all
        var id: String { rawValue }
        var title: String { switch self { case .off: "关闭"; case .wifi: "仅 Wi-Fi"; case .all: "所有网络" } }
    }
    static let capacities = [256, 512, 1024, 2048]
    var capacityMB: Int { didSet { preferences.set(capacityMB, forKey: "music.cache.capacityMB"); apply() } }
    var policy: PrefetchPolicy { didSet { preferences.set(policy.rawValue, forKey: "music.cache.prefetch"); apply() } }
    private(set) var usedBytes: Int64 = 0
    private(set) var pendingRemoval = false
    private(set) var writesDisabled = false
    private(set) var permitsPrefetch = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored let cache: MusicAudioCache
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var connected = false
    @ObservationIgnored private var wifi = false
    @ObservationIgnored private var constrained = false
    @ObservationIgnored private var waiting = false
    @ObservationIgnored var onPolicyChange: (() -> Void)?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?
    init(cache: MusicAudioCache, preferences: UserDefaults = .standard, monitorsNetwork: Bool = true) {
        self.cache = cache; self.preferences = preferences
        let saved = preferences.integer(forKey: "music.cache.capacityMB")
        capacityMB = Self.capacities.contains(saved) ? saved : 1024
        policy = PrefetchPolicy(rawValue: preferences.string(forKey: "music.cache.prefetch") ?? "") ?? .wifi
        if monitorsNetwork {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in self?.setNetwork(connected: path.status == .satisfied, wifi: path.usesInterfaceType(.wifi), constrained: path.isConstrained) }
            }
            monitor.start(queue: DispatchQueue(label: "setu.music.cache-network"))
        }
        apply()
    }
    deinit { monitor.cancel() }
    func setNetwork(connected: Bool, wifi: Bool, constrained: Bool) {
        self.connected = connected; self.wifi = wifi; self.constrained = constrained; apply()
    }
    func playbackWaiting(_ waiting: Bool) { self.waiting = waiting; apply(restartPrefetch: false) }
    private func apply(restartPrefetch: Bool = true) {
        permitsPrefetch = connected && !constrained && (policy == .all || (policy == .wifi && wifi))
        let capacity = Int64(Self.capacities.contains(capacityMB) ? capacityMB : 1024) * 1024 * 1024
        let allowed = permitsPrefetch, waiting = waiting, cache = cache
        configurationTask?.cancel()
        configurationTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await cache.configure(capacity: capacity, prefetchAllowed: allowed, playbackWaiting: waiting)
            if restartPrefetch, !Task.isCancelled { self?.onPolicyChange?() }
        }
    }
    func refresh() async { let usage = await cache.usage(); usedBytes = usage.bytes; pendingRemoval = usage.pendingRemoval; writesDisabled = usage.writeDisabled }
    func clear() async { await cache.clear(); await refresh() }
}

@MainActor
final class MusicAudioRuntime {
    static let shared = MusicAudioRuntime()
    let cache: MusicAudioCache
    let assets: CachedAudioAssetFactory
    let settings: MusicCacheSettings
    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("setu-audio-v2", isDirectory: true)
        cache = MusicAudioCache(directory: directory, legacyDirectory: PreciseSeekAudioCache.persistentDirectory)
        assets = CachedAudioAssetFactory(cache: cache)
        settings = MusicCacheSettings(cache: cache)
    }
}

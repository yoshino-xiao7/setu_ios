import Foundation

@MainActor
@Observable
public final class CloudVideoUploadStore {
    public private(set) var items: [CloudVideoUploadItem]
    public private(set) var running = false
    public private(set) var pauseReason: CloudVideoUploadPauseReason = .none
    public var wifiOnly: Bool {
        didSet { persist() }
    }

    public var busy: Bool { running || items.contains { !$0.isTerminal } }
    public var queuedCount: Int { items.filter { !$0.isTerminal }.count }
    public var activeItem: CloudVideoUploadItem? {
        items.first { $0.phase == .uploading || $0.phase == .syncing || $0.phase == .preparing }
    }

    public var summary: String {
        if let blocked = pauseReason.message {
            return blocked
        }
        if let active = activeItem {
            let extra = queuedCount > 1 ? " · 排队 \(queuedCount - 1) 个" : ""
            if active.phase == .preparing {
                return "正在准备 \(active.title)\(extra)"
            }
            if active.attempts > 0, active.phase == .uploading {
                return "续传 \(active.title) \(active.percent)%\(extra)"
            }
            return "上传中 \(active.title) \(active.percent)%\(extra)"
        }
        if items.contains(where: { $0.phase == .waitingForWifi }) {
            return "等待 Wi-Fi · 排队 \(queuedCount) 个"
        }
        if queuedCount > 0 {
            return "排队 \(queuedCount) 个"
        }
        return ""
    }

    private let sessions: any CloudVideoUploadSessioning
    private let inbox: any CloudVideoInboxing
    private let tus: any CloudVideoTUSUploading
    private let persistence: any CloudVideoUploadPersisting
    private let network: any CloudVideoUploadNetworking
    private let conditions: any CloudVideoDeviceConditioning
    private let configuration: CloudVideoUploadConfiguration
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date
    private var pumpTask: Task<Void, Never>?
    private var currentUpload: Task<URL, Error>?

    public init(
        sessions: any CloudVideoUploadSessioning,
        inbox: any CloudVideoInboxing,
        tus: any CloudVideoTUSUploading,
        persistence: any CloudVideoUploadPersisting,
        network: any CloudVideoUploadNetworking,
        conditions: any CloudVideoDeviceConditioning = CloudVideoAlwaysReadyConditions(),
        configuration: CloudVideoUploadConfiguration = .init(),
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.inbox = inbox
        self.tus = tus
        self.persistence = persistence
        self.network = network
        self.conditions = conditions
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
        let snapshot = (try? persistence.load()) ?? CloudVideoUploadSnapshot()
        self.wifiOnly = snapshot.wifiOnly
        self.items = snapshot.items.map { item in
            var restored = item
            if restored.phase == .uploading || restored.phase == .syncing || restored.phase == .preparing {
                restored.phase = .queued
            }
            return restored
        }
        self.network.onChange = { [weak self] in
            Task { @MainActor in
                self?.startIfNeeded()
            }
        }
    }

    public static func live(sessions: any CloudVideoUploadSessioning) -> CloudVideoUploadStore {
        CloudVideoUploadStore(
            sessions: sessions,
            inbox: CloudVideoInbox(),
            tus: CloudVideoTUSClient(),
            persistence: CloudVideoUploadFilePersistence(),
            network: CloudVideoUploadPathMonitor(),
            conditions: CloudVideoProcessConditions()
        )
    }

    public func enqueue(_ drafts: [CloudVideoUploadDraft]) {
        for draft in drafts {
            items.append(
                CloudVideoUploadItem(
                    id: draft.id,
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "未命名视频"
                        : draft.title,
                    rating: draft.rating == "r18" ? "r18" : "all_ages",
                    fileName: draft.fileName,
                    fileURL: draft.sourceURL,
                    byteCount: draft.byteCount,
                    phase: .preparing
                )
            )
        }
        persist()
        startIfNeeded()
    }

    public func pause() {
        pauseReason = .user
        currentUpload?.cancel()
        persist()
    }

    public func resume() {
        pauseReason = .none
        startIfNeeded()
    }

    public func retry(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = .queued
        items[index].attempts = 0
        items[index].lastError = nil
        persist()
        startIfNeeded()
    }

    public func cancel(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if activeItem?.id == id {
            currentUpload?.cancel()
        }
        inbox.remove(itemId: item.id)
        persist()
        if let session = item.session {
            Task { try? await sessions.deleteAdminCloudVideo(id: session.id) }
        }
        startIfNeeded()
    }

    public func startIfNeeded() {
        refreshPauseReason()
        guard pauseReason == .none || pauseReason == .wifi else { return }
        guard pumpTask == nil else { return }
        guard items.contains(where: { $0.canRun }) else { return }
        pumpTask = Task { [weak self] in
            await self?.pump()
        }
    }

    private func pump() async {
        running = true
        defer {
            running = false
            pumpTask = nil
            persist()
            if pauseReason == .none, items.contains(where: { $0.canRun }) {
                startIfNeeded()
            }
        }
        while !Task.isCancelled {
            refreshPauseReason()
            if pauseReason == .session || pauseReason == .user || pauseReason == .power || pauseReason == .thermal {
                break
            }
            guard let index = items.firstIndex(where: { $0.canRun }) else { break }
            if pauseReason == .wifi {
                items[index].phase = .waitingForWifi
                persist()
                break
            }
            let itemId = items[index].id
            let ok = await uploadOne(itemId: itemId)
            if ok {
                if let finished = items.firstIndex(where: { $0.id == itemId }) {
                    let removed = items.remove(at: finished)
                    inbox.remove(itemId: removed.id)
                }
                persist()
                continue
            }
            guard let current = items.firstIndex(where: { $0.id == itemId }) else { continue }
            if pauseReason == .session {
                items[current].phase = .queued
                persist()
                break
            }
            items[current].attempts += 1
            if items[current].attempts >= configuration.maxAttempts {
                items[current].phase = .failed
                persist()
                continue
            }
            items[current].phase = .queued
            items[current].lastError = items[current].lastError ?? "上传中断，正在续传"
            persist()
            if configuration.retryPause > 0 {
                try? await sleep(configuration.retryPause)
            }
        }
    }

    private func uploadOne(itemId: String) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return false }
        do {
            if items[index].phase == .preparing {
                let local = try await inbox.materialize(
                    itemId: itemId,
                    from: items[index].fileURL,
                    fileName: items[index].fileName
                )
                guard let current = items.firstIndex(where: { $0.id == itemId }) else { return false }
                items[current].fileURL = local
            }
            guard let current = items.firstIndex(where: { $0.id == itemId }) else { return false }
            items[current].phase = .uploading
            persist()

            var session = try await ensureSession(itemId: itemId)
            session = try await refreshTicketIfNeeded(session)
            guard let sessionIndex = items.firstIndex(where: { $0.id == itemId }) else { return false }
            items[sessionIndex].session = session
            persist()

            let lastProgress = StallClock(now: now)
            let progress: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
                lastProgress.touch()
                Task { @MainActor in
                    guard let self, let latest = self.items.firstIndex(where: { $0.id == itemId }) else { return }
                    self.items[latest].uploadedBytes = sent
                    self.items[latest].byteCount = max(self.items[latest].byteCount, total)
                }
            }

            let fileURL = items[sessionIndex].fileURL
            let uploadURL = items[sessionIndex].tusUploadURL.flatMap(URL.init(string:))
            let chunkSize = configuration.chunkSize
            let upload = Task {
                try await self.tus.upload(
                    fileURL: fileURL,
                    session: session,
                    existingUploadURL: uploadURL,
                    chunkSize: chunkSize,
                    onProgress: progress
                )
            }
            currentUpload = upload
            let location = try await withStallWatch(upload, lastProgress: lastProgress)
            currentUpload = nil
            guard let done = items.firstIndex(where: { $0.id == itemId }) else { return false }
            items[done].tusUploadURL = location.absoluteString
            items[done].uploadedBytes = items[done].byteCount
            items[done].phase = .syncing
            persist()
            _ = try await sessions.syncAdminCloudVideo(id: session.id)
            return true
        } catch is CancellationError {
            currentUpload = nil
            return false
        } catch {
            currentUpload = nil
            guard let current = items.firstIndex(where: { $0.id == itemId }) else { return false }
            if Self.isSessionExpired(error) {
                pauseReason = .session
                items[current].lastError = CloudVideoUploadError.sessionExpired.errorDescription
                return false
            }
            if let uploadError = error as? CloudVideoUploadError, uploadError == .stall {
                items[current].lastError = uploadError.errorDescription
                return false
            }
            items[current].lastError = error.localizedDescription
            return false
        }
    }

    private func ensureSession(itemId: String) async throws -> CloudVideoUploadSession {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            throw CancellationError()
        }
        if let existing = items[index].session {
            return existing
        }
        let created = try await sessions.createUploadSession(title: items[index].title)
        if let current = items.firstIndex(where: { $0.id == itemId }) {
            items[current].session = created
            persist()
            if items[current].rating == "r18" {
                _ = try await sessions.updateAdminCloudVideo(
                    id: created.id,
                    update: AdminCloudVideoUpdate(rating: "r18")
                )
            }
        }
        return created
    }

    private func refreshTicketIfNeeded(_ session: CloudVideoUploadSession) async throws -> CloudVideoUploadSession {
        guard session.needsRefresh(now: now(), lead: configuration.ticketRefreshLead) else {
            return session
        }
        return try await sessions.refreshTusTicket(id: session.id)
    }

    private func withStallWatch(_ upload: Task<URL, Error>, lastProgress: StallClock) async throws -> URL {
        let timeout = configuration.stallTimeout
        guard timeout > 0 else {
            return try await upload.value
        }
        let watcher = Task { [sleep] in
            while !Task.isCancelled {
                let interval = min(15, timeout)
                if interval > 0 {
                    try await sleep(interval)
                }
                if lastProgress.isStalled(timeout: timeout) {
                    upload.cancel()
                    return
                }
            }
        }
        do {
            let value = try await upload.value
            watcher.cancel()
            return value
        } catch is CancellationError {
            watcher.cancel()
            if lastProgress.isStalled(timeout: timeout) {
                throw CloudVideoUploadError.stall
            }
            throw CancellationError()
        } catch {
            watcher.cancel()
            throw error
        }
    }

    private func refreshPauseReason() {
        if pauseReason == .user { return }
        if pauseReason == .session { return }
        if conditions.isLowPower {
            pauseReason = .power
            return
        }
        if conditions.isOverheating {
            pauseReason = .thermal
            return
        }
        if wifiOnly && !(network.isWifi && network.isSatisfied) {
            pauseReason = .wifi
            return
        }
        if !network.isSatisfied {
            pauseReason = .wifi
            return
        }
        pauseReason = .none
    }

    private func persist() {
        try? persistence.save(CloudVideoUploadSnapshot(wifiOnly: wifiOnly, items: items))
    }

    public static func isSessionExpired(_ error: Error) -> Bool {
        if case APIError.httpStatus(let status, _, _, _, _) = error, status == 401 || status == 403 {
            return true
        }
        return error as? CloudVideoUploadError == .sessionExpired
    }
}

final class StallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Date
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
        self.last = now()
    }

    func touch() {
        lock.withLock { last = now() }
    }

    func isStalled(timeout: TimeInterval) -> Bool {
        lock.withLock { now().timeIntervalSince(last) >= timeout }
    }
}

private extension CloudVideoUploadItem {
    var canRun: Bool {
        switch phase {
        case .preparing, .queued, .waitingForWifi, .uploading, .syncing:
            return true
        case .failed:
            return false
        }
    }

    var isTerminal: Bool { phase == .failed }
}

private extension CloudVideoUploadPauseReason {
    var message: String? {
        switch self {
        case .none: nil
        case .wifi: "等待 Wi-Fi"
        case .power: "低电量，上传已暂停"
        case .thermal: "设备过热，上传已暂停"
        case .session: "登录已过期，队列已暂停"
        case .user: "已暂停"
        }
    }
}

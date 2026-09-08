import Foundation
#if canImport(SetuPixivTransport)
import SetuPixivTransport
#endif

public struct PixivHTTPRequest: Encodable, Sendable {
    public let url: String
    public var method = "GET"
    public var headers: [String: String] = [:]
    public var body: String?
    public var max_bytes = 8 * 1024 * 1024
    public var image_mirror_host: String?
    #if DEBUG
    /// Fixed public image only; native code ignores request data for these diagnostic variants.
    public var public_image_probe: UInt8 = 0
    #endif
    public init(url: String) { self.url = url }
}
public struct PixivHTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let contentType: String
    public init(status: Int, data: Data, contentType: String) {
        self.status = status; self.data = data; self.contentType = contentType
    }
}
public protocol PixivHTTPTransport: Sendable {
    func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse
}
public struct PixivClientError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// Its isolated connection pool never shares the Setu SID cookie jar or HMAC headers.
public final class PixivNativeHTTPTransport: PixivHTTPTransport, @unchecked Sendable {
    private let queue: OperationQueue = PixivNativeHTTPTransport.makeQueue("api")
    private let mediaQueue: OperationQueue = PixivNativeHTTPTransport.makeQueue("media")
    private let executor: (@Sendable (PixivHTTPRequest) throws -> PixivHTTPResponse)?
    private let deadline: TimeInterval
    public init() { executor = nil; deadline = 45 }
    init(deadline: TimeInterval = 45, executor: @escaping @Sendable (PixivHTTPRequest) throws -> PixivHTTPResponse) {
        self.executor = executor; self.deadline = deadline
    }
    private static func makeQueue(_ name: String) -> OperationQueue {
        let queue = OperationQueue()
        queue.name = "icu.yukiryou.pixiv." + name
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }
    public func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        #if canImport(SetuPixivTransport)
        try Task.checkCancellation()
        let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let cancellation = PixivNativeCancellation()
        let executor = self.executor
        let enqueued = Date()
        let auditID = String(UUID().uuidString.prefix(8))
        let host = URL(string: request.url)?.host ?? ""
        let category = (["i.pximg.net", "s.pximg.net", "i-cf.pximg.net", "i.pixiv.re"].contains(host) || request.image_mirror_host == host) ? "media" : "api"
        let operation = PixivQueuedRequest(cancelNative: { cancellation.cancel() }) {
            let started = Date()
            PixivTimingAudit.record("\(auditID) \(category) started queue_ms=\(Int(started.timeIntervalSince(enqueued) * 1000))")
            if let executor { return try executor(request) }
            let response = payload.withCString { setu_pixiv_request($0, cancellation.pointer) }
            guard let response else { throw PixivClientError("Pixiv 网络服务不可用") }
            defer { setu_pixiv_response_free(response) }
            let value = response.pointee
            let error = value.error.map { String(cString: $0) } ?? "NETWORK_UNAVAILABLE"
            PixivTimingAudit.record("\(auditID) \(category) completed status=\(value.status) bytes=\(value.length) network_ms=\(Int(Date().timeIntervalSince(started) * 1000)) failed=\(!error.isEmpty) stage=\(error.isEmpty ? "complete" : error)")
            guard error.isEmpty else {
                if error == "CANCELLED" { throw CancellationError() }
                if category == "media" { throw PixivClientError("图片下载失败，请重试或在图片设置中切换图床") }
                throw PixivClientError(error.hasPrefix("ECH") ? "增强连接暂不可用，请检查网络后重试" : "无法连接 Pixiv，请检查当前网络后重试")
            }
            let data = value.length == 0 ? Data() : Data(bytes: value.bytes!, count: value.length)
            return PixivHTTPResponse(status: Int(value.status), data: data,
                contentType: value.content_type.map { String(cString: $0) } ?? "application/octet-stream")
        }
        let destination = category == "media" ? mediaQueue : queue
        return try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation { continuation in
                operation.startWaiting(continuation, deadline: deadline)
                destination.addOperation(operation)
            }
            try Task.checkCancellation()
            return result
        } onCancel: { operation.cancel() }
        #else
        throw PixivClientError("此构建尚未包含 Pixiv 增强连接组件")
        #endif
    }
}
/// Cancellation and the deadline finish the awaiting task even while queued.
/// An executing native request also receives cancellation and owns its buffer until it exits.
private final class PixivQueuedRequest: Operation, @unchecked Sendable {
    private let lock = NSLock()
    private let execute: @Sendable () throws -> PixivHTTPResponse
    private let cancelNative: @Sendable () -> Void
    private var continuation: CheckedContinuation<PixivHTTPResponse, Error>?
    private var result: Result<PixivHTTPResponse, Error>?
    private var timer: DispatchWorkItem?
    init(cancelNative: @escaping @Sendable () -> Void, execute: @escaping @Sendable () throws -> PixivHTTPResponse) {
        self.cancelNative = cancelNative; self.execute = execute
    }
    func startWaiting(_ continuation: CheckedContinuation<PixivHTTPResponse, Error>, deadline: TimeInterval) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result); return }
        self.continuation = continuation
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(PixivClientError("Pixiv 请求超时，请重试")))
            self?.cancel()
        }
        self.timer = timer
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline, execute: timer)
    }
    override func main() {
        guard !isCancelled else { return }
        finish(Result { try execute() })
    }
    override func cancel() {
        super.cancel()
        cancelNative()
        finish(.failure(CancellationError()))
    }
    private func finish(_ value: Result<PixivHTTPResponse, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        timer?.cancel(); timer = nil
        lock.unlock()
        continuation?.resume(with: value)
    }
}

#if canImport(SetuPixivTransport)
private final class PixivNativeCancellation: @unchecked Sendable {
    let pointer = setu_pixiv_cancellation_create()!
    func cancel() { setu_pixiv_cancel(pointer) }
    deinit { setu_pixiv_cancellation_free(pointer) }
}
#endif

public protocol PixivOnlineServing: Sendable {
    func binding() async throws -> PixivAccountBinding
    func authorize() async throws -> PixivAuthorization
    func complete(sessionID: String, code: String) async throws -> PixivAccountBinding
    func unlink() async throws
    func works(params: [String: String]) async throws -> ArtworkListResponse
    func detail(id: String) async throws -> BrowserArtwork
    func artists() async throws -> [ArtworkArtist]
    func spotlights() async throws -> [ArtworkSpotlight]
    func bookmark(id: String, enabled: Bool, visibility: String) async throws
    func follow(id: String, enabled: Bool) async throws
    func animation(workID: String) async throws -> ArtworkAnimation
    func animationStatus(id: String) async throws -> ArtworkAnimation
    func media(_ path: String) async throws -> Data
}

/// Opt-in metadata-only diagnostics; never writes URLs, headers, bodies or account identifiers.
private enum PixivTimingAudit {
    private static let lock = NSLock()
    static func record(_ value: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-media-audit"),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        lock.lock(); defer { lock.unlock() }
        let file = directory.appendingPathComponent("pixiv-media-timings.txt")
        let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let lines = (previous.split(separator: "\n").suffix(99).map(String.init) + [value]).joined(separator: "\n")
        try? lines.write(to: file, atomically: true, encoding: .utf8)
        #endif
    }
}

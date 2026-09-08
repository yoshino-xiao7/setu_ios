import Foundation

/// Selects a usable local connection using credential-free probes. OAuth and
/// mutations are sent once, after selection; media retains its native connection.
public actor PixivDirectHTTPTransport: PixivHTTPTransport {
    private enum Connection: Sendable { case enhanced, system }
    private let system: any PixivHTTPTransport
    private let enhanced: any PixivHTTPTransport
    private var selected: (connection: Connection, expires: Date)?
    private var pending: (id: UUID, task: Task<Connection, Error>)?

    public init() {
        system = PixivSystemHTTPTransport()
        enhanced = PixivNativeHTTPTransport()
    }
    init(system: any PixivHTTPTransport, enhanced: any PixivHTTPTransport) {
        self.system = system; self.enhanced = enhanced
    }
    public func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        guard let host = URL(string: request.url)?.host?.lowercased(),
              ["oauth.secure.pixiv.net", "app-api.pixiv.net"].contains(host) else {
            return try await enhanced.send(request)
        }
        _ = try PixivSystemHTTPTransport.validateRequest(request)
        let first = try await connection()
        let outcome: Result<PixivHTTPResponse, Error>
        do {
            let response = try await sendOnce(request, via: first)
            if response.status != 403 { return response }
            outcome = .success(response)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            outcome = .failure(error)
        }
        // Network changes invalidate the short-lived selection. Only safe reads
        // can retry, once, and only if a different connection passes its probe.
        if request.method == "GET", let next = try? await connection(), next != first {
            return try await sendOnce(request, via: next)
        }
        try Task.checkCancellation()
        return try outcome.get()
    }
    private func sendOnce(_ request: PixivHTTPRequest, via connection: Connection) async throws -> PixivHTTPResponse {
        try Task.checkCancellation()
        do {
            let response = try await transport(connection).send(request)
            try Task.checkCancellation()
            if response.status == 403 { invalidate(connection) }
            return response
        } catch {
            invalidate(connection)
            throw error
        }
    }
    private func transport(_ connection: Connection) -> any PixivHTTPTransport {
        connection == .enhanced ? enhanced : system
    }
    private func invalidate(_ connection: Connection) {
        if selected?.connection == connection { selected = nil }
    }
    private func connection() async throws -> Connection {
        try Task.checkCancellation()
        if let selected, selected.expires > Date() { return selected.connection }
        if let pending {
            let result = try await pending.task.value
            try Task.checkCancellation()
            return result
        }
        let id = UUID()
        let enhanced = self.enhanced, system = self.system
        let task = Task { try await Self.probe(enhanced: enhanced, system: system) }
        pending = (id, task)
        defer { if pending?.id == id { pending = nil } }
        let result = try await task.value
        selected = (result, Date().addingTimeInterval(30))
        try Task.checkCancellation()
        return result
    }
    private static func probe(enhanced: any PixivHTTPTransport, system: any PixivHTTPTransport) async throws -> Connection {
        try await withThrowingTaskGroup(of: Connection?.self) { group in
            // Prefer direct ECH; start the system alternative after a small head start.
            for (connection, transport) in [(Connection.enhanced, enhanced), (.system, system)] {
                group.addTask {
                    do {
                        if connection == .system { try await Task.sleep(for: .milliseconds(300)) }
                        var request = PixivHTTPRequest(url: "https://app-api.pixiv.net/v1/illust/recommended?filter=for_ios")
                        request.max_bytes = 64 * 1024
                        request.headers = ["User-Agent": "PixivAndroidApp/5.0.155 (Android 10.0; Pixel C)",
                            "App-OS": "Android", "App-OS-Version": "Android 10.0", "App-Version": "5.0.166"]
                        let response = try await transport.send(request)
                        guard [200, 400, 401].contains(response.status),
                              response.contentType.lowercased().contains("application/json"),
                              (try? JSONSerialization.jsonObject(with: response.data)) is [String: Any] else { return nil }
                        return connection
                    } catch { return nil }
                }
            }
            while let result = try await group.next() {
                if let result { group.cancelAll(); return result }
            }
            throw PixivClientError("暂时无法连接 Pixiv，请检查网络后重试")
        }
    }
}

final class PixivSystemHTTPTransport: PixivHTTPTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.configuration.httpCookieStorage = nil
        self.configuration.httpShouldSetCookies = false
        self.configuration.urlCredentialStorage = nil
        self.configuration.urlCache = nil
        self.configuration.httpAdditionalHeaders = nil
        self.configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration.timeoutIntervalForRequest = 25
        self.configuration.timeoutIntervalForResource = 35
    }

    static func validateRequest(_ request: PixivHTTPRequest) throws -> Bool {
        let isOAuth = request.url == "https://oauth.secure.pixiv.net/auth/token" && request.method == "POST"
        let isAPI = PixivAPIEndpoint.accepts(request)
        var allowedHeaders: Set<String> = ["user-agent", "app-os", "app-os-version", "app-version",
            "accept-language", "x-client-time", "x-client-hash", "content-type"]
        if isAPI { allowedHeaders.insert("authorization") }
        guard isOAuth || isAPI, request.url.utf8.count <= 8192,
              request.max_bytes > 0, request.headers.count <= 20,
              (request.body?.utf8.count ?? 0) <= 65536,
              request.headers.allSatisfy({
                  allowedHeaders.contains($0.key.lowercased()) && $0.value.utf8.count <= 16384 &&
                  !$0.value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) &&
                  ($0.key.lowercased() != "authorization" || $0.value.hasPrefix("Bearer "))
              }) else {
            throw PixivClientError("无效的 Pixiv 请求")
        }
        return isOAuth
    }

    func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        try Task.checkCancellation()
        let isOAuth = try Self.validateRequest(request)
        let session = URLSession(configuration: configuration, delegate: PixivOAuthNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var outgoing = URLRequest(url: URL(string: request.url)!)
        outgoing.httpMethod = request.method
        outgoing.allHTTPHeaderFields = request.headers
        outgoing.httpBody = request.body?.data(using: .utf8)
        outgoing.httpShouldHandleCookies = false
        do {
            let (stream, response) = try await session.bytes(for: outgoing)
            guard let http = response as? HTTPURLResponse else { throw PixivClientError("Pixiv 响应异常") }
            guard !(300..<400).contains(http.statusCode) else { throw PixivClientError("Pixiv 接口返回了意外跳转") }
            let limit = min(request.max_bytes, (isOAuth ? 1 : 8) * 1024 * 1024)
            guard response.expectedContentLength <= Int64(limit) else { throw PixivClientError("Pixiv 响应过大") }
            var data = Data()
            for try await byte in stream {
                try Task.checkCancellation()
                guard data.count < limit else { throw PixivClientError("Pixiv 响应过大") }
                data.append(byte)
            }
            return PixivHTTPResponse(status: http.statusCode, data: data,
                contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? PixivClientError { throw error }
            // URLSession errors can include request URLs. Keep the UI error fixed and credential-free.
            throw PixivClientError(isOAuth ? "无法连接 Pixiv 授权接口，请稍后重新登录" : "无法连接 Pixiv 作品接口，请稍后重试")
        }
    }
}

/// Shared by cursor validation and the transport that attaches account credentials.
enum PixivAPIEndpoint {
    static let readPaths: Set<String> = ["/v1/illust/recommended", "/v1/illust/ranking", "/v1/search/illust", "/v1/user/illusts", "/v1/user/bookmarks/illust", "/v2/illust/follow", "/v1/illust/detail", "/v2/illust/related", "/v1/user/recommended", "/v1/spotlight/articles", "/v1/ugoira/metadata"]
    static let writePaths: Set<String> = ["/v2/illust/bookmark/add", "/v1/illust/bookmark/delete", "/v1/user/follow/add", "/v1/user/follow/delete"]

    static func accepts(_ request: PixivHTTPRequest) -> Bool {
        guard let url = URLComponents(string: request.url), url.scheme == "https", url.host == "app-api.pixiv.net",
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              url.percentEncodedPath == url.path else { return false }
        switch request.method {
        case "GET": return readPaths.contains(url.path) && request.body == nil
        case "POST": return writePaths.contains(url.path) && url.query == nil
        default: return false
        }
    }
}

final class PixivOAuthNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

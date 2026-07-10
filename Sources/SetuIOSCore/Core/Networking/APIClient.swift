import Foundation

public struct APIClient: Sendable {
    public let config: AppConfig
    public let signer: AuthSigner
    public let sessionInvalidationNotifier: SessionInvalidationNotifier?
    public let signatureRefreshNotifier: SignatureRefreshNotifier?
    public var session: URLSession = .shared
    public var decoder: JSONDecoder = JSONDecoder()
    public var encoder: JSONEncoder = JSONEncoder()

    public init(
        config: AppConfig,
        signer: AuthSigner,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        sessionInvalidationNotifier: SessionInvalidationNotifier? = nil,
        signatureRefreshNotifier: SignatureRefreshNotifier? = nil
    ) {
        self.config = config
        self.signer = signer
        self.sessionInvalidationNotifier = sessionInvalidationNotifier
        self.signatureRefreshNotifier = signatureRefreshNotifier
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public static func liveSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return configuration
    }

    public static func liveSession() -> URLSession {
        URLSession(configuration: liveSessionConfiguration())
    }

    public func mobileSessionDiagnostics(
        hasSignSecret: Bool,
        expireAt: Date?,
        isSignedIn: Bool
    ) -> MobileSessionDiagnostics {
        let cookies = HTTPCookieStorage.shared.cookies(for: config.apiBaseURL) ?? []
        return MobileSessionDiagnostics(
            apiHost: config.apiBaseURL.host ?? config.apiBaseURL.absoluteString,
            cookieCount: cookies.count,
            hasSIDCookie: cookies.contains { $0.name == "SID" },
            hasSignSecret: hasSignSecret,
            expireAt: expireAt,
            isSignedIn: isSignedIn
        )
    }

    public func clearSessionCookies() {
        let cookies = HTTPCookieStorage.shared.cookies(for: config.apiBaseURL) ?? []
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    public func get<Value: Decodable & Sendable>(
        _ path: String,
        signed: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> Value {
        try await request(path, method: "GET", body: Optional<Data>.none, signed: signed, headers: headers)
    }

    public func post<Request: Encodable & Sendable, Value: Decodable & Sendable>(
        _ path: String,
        body: Request,
        signed: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> Value {
        let data = try encoder.encode(body)
        return try await request(path, method: "POST", body: data, signed: signed, headers: headers)
    }

    public func post<Value: Decodable & Sendable>(_ path: String, signed: Bool = true) async throws -> Value {
        try await request(path, method: "POST", body: Optional<Data>.none, signed: signed)
    }

    public func put<Request: Encodable & Sendable, Value: Decodable & Sendable>(
        _ path: String,
        body: Request,
        signed: Bool = true
    ) async throws -> Value {
        let data = try encoder.encode(body)
        return try await request(path, method: "PUT", body: data, signed: signed)
    }

    public func patch<Request: Encodable & Sendable, Value: Decodable & Sendable>(
        _ path: String,
        body: Request,
        signed: Bool = true
    ) async throws -> Value {
        let data = try encoder.encode(body)
        return try await request(path, method: "PATCH", body: data, signed: signed)
    }

    public func requestWithoutBody<Value: Decodable & Sendable>(
        _ path: String,
        method: String,
        signed: Bool = true
    ) async throws -> Value {
        try await request(path, method: method, body: Optional<Data>.none, signed: signed)
    }

    public func postMultipart<Value: Decodable & Sendable>(
        _ path: String,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        signed: Bool = true
    ) async throws -> Value {
        try await postMultipart(
            path,
            fileFieldName: fileFieldName,
            fileName: fileName,
            mimeType: mimeType,
            fileData: fileData,
            signed: signed,
            retryingSignatureError: true
        )
    }

    private func postMultipart<Value: Decodable & Sendable>(
        _ path: String,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        signed: Bool,
        retryingSignatureError: Bool
    ) async throws -> Value {
        guard let url = URL(string: path, relativeTo: config.apiBaseURL) else {
            throw APIError.invalidURL(path)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        let requestID = Self.makeRequestID()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if signed {
            await refreshSignatureIfNeeded()
            let headers = try signer.signedHeaders(method: "POST", path: url.path)
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let signatureError = isSignatureErrorResponse(response: httpResponse, data: data, signed: signed)
        if retryingSignatureError,
           signatureError,
           await refreshSignature(force: true) {
            return try await postMultipart(
                path,
                fileFieldName: fileFieldName,
                fileName: fileName,
                mimeType: mimeType,
                fileData: fileData,
                signed: signed,
                retryingSignatureError: false
            )
        }
        if signed && (httpResponse.statusCode == 401 || signatureError) {
            await sessionInvalidationNotifier?.notifyUnauthorized()
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeHTTPStatusError(response: httpResponse, data: data, requestID: requestID)
        }

        if let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data), let value = envelope.data {
            return value
        }
        return try decoder.decode(Value.self, from: data)
    }

    private func request<Value: Decodable & Sendable>(
        _ path: String,
        method: String,
        body: Data?,
        signed: Bool,
        headers: [String: String] = [:],
        retryingSignatureError: Bool = true
    ) async throws -> Value {
        guard let url = URL(string: path, relativeTo: config.apiBaseURL) else {
            throw APIError.invalidURL(path)
        }

        await refreshSignatureIfNeeded(signed: signed)
        let requestID = Self.makeRequestID()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.httpShouldHandleCookies = true
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers where !value.isEmpty {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if signed {
            let headers = try signer.signedHeaders(method: method, path: url.path)
            for (name, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let signatureError = isSignatureErrorResponse(response: httpResponse, data: data, signed: signed)
        if retryingSignatureError,
           signatureError,
           await refreshSignature(force: true) {
            return try await request(path, method: method, body: body, signed: signed, headers: headers, retryingSignatureError: false)
        }
        if signed && (httpResponse.statusCode == 401 || signatureError) {
            await sessionInvalidationNotifier?.notifyUnauthorized()
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeHTTPStatusError(response: httpResponse, data: data, requestID: requestID)
        }

        if Value.self == EmptyResponse.self {
            return EmptyResponse() as! Value
        }

        if Value.self == String.self, let string = String(data: data, encoding: .utf8) {
            return string as! Value
        }

        if let envelope = try? decoder.decode(APIEnvelope<Value>.self, from: data), let value = envelope.data {
            return value
        }
        return try decoder.decode(Value.self, from: data)
    }

    private func refreshSignatureIfNeeded(signed: Bool = true) async {
        guard signed, !signer.hasSignSecret() else { return }
        _ = await refreshSignature(force: false)
    }

    private func refreshSignature(force: Bool) async -> Bool {
        guard force || !signer.hasSignSecret() else { return true }
        return await signatureRefreshNotifier?.refreshSignature() ?? false
    }

    private func isSignatureErrorResponse(
        response: HTTPURLResponse,
        data: Data,
        signed: Bool
    ) -> Bool {
        guard signed, [400, 401, 403].contains(response.statusCode) else {
            return false
        }
        let payload = try? decoder.decode(APIErrorPayload.self, from: data)
        let message = (payload?.message ?? payload?.msg ?? String(data: data, encoding: .utf8) ?? "").lowercased()
        return message.contains("签名")
            || message.contains("signature")
            || message.contains("x-signature")
            || message.contains("timestamp")
            || message.contains("nonce")
    }

    private static func makeRequestID() -> String {
        UUID().uuidString.lowercased()
    }

    private func makeHTTPStatusError(response: HTTPURLResponse, data: Data, requestID: String) -> APIError {
        let payload = try? decoder.decode(APIErrorPayload.self, from: data)
        let message = payload?.message ?? payload?.msg
        let traceID = response.headerValue(named: "X-Trace-Id")
            ?? response.headerValue(named: "Trace-Id")
            ?? payload?.traceId
            ?? payload?.traceID
            ?? payload?.trace_id
        return .httpStatus(response.statusCode, message: message, requestID: requestID, traceID: traceID)
    }
}

public final class SessionInvalidationNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () async -> Void)?

    public init() {}

    public func setHandler(_ handler: (@Sendable () async -> Void)?) {
        lock.withLock {
            self.handler = handler
        }
    }

    public func notifyUnauthorized() async {
        let handler = lock.withLock { handler }
        await handler?()
    }
}

public final class SignatureRefreshNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () async -> Bool)?

    public init() {}

    public func setHandler(_ handler: (@Sendable () async -> Bool)?) {
        lock.withLock {
            self.handler = handler
        }
    }

    public func refreshSignature() async -> Bool {
        let handler = lock.withLock { handler }
        return await handler?() ?? false
    }
}

public struct EmptyResponse: Codable, Sendable {
    public init() {}
}

public enum APIError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int, message: String? = nil, requestID: String? = nil, traceID: String? = nil)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "无效接口路径：\(path)"
        case .invalidResponse:
            return "服务器响应无效"
        case .httpStatus(let status, let message, let requestID, let traceID):
            var parts = ["请求失败：HTTP \(status)"]
            if let message, !message.isEmpty {
                parts.append(message)
            }
            if let requestID, !requestID.isEmpty {
                parts.append("Request ID: \(requestID)")
            }
            if let traceID, !traceID.isEmpty {
                parts.append("Trace ID: \(traceID)")
            }
            return parts.joined(separator: "；")
        }
    }
}

private struct APIErrorPayload: Decodable {
    let message: String?
    let msg: String?
    let traceId: String?
    let traceID: String?
    let trace_id: String?
}

private extension HTTPURLResponse {
    func headerValue(named name: String) -> String? {
        let value = allHeaderFields.first { key, _ in
            guard let key = key as? String else {
                return false
            }
            return key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
        return value as? String
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

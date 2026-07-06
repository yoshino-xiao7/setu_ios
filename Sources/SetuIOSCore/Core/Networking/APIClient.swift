import Foundation

public struct APIClient: Sendable {
    public let config: AppConfig
    public let signer: AuthSigner
    public var session: URLSession = .shared
    public var decoder: JSONDecoder = JSONDecoder()
    public var encoder: JSONEncoder = JSONEncoder()

    public init(config: AppConfig, signer: AuthSigner, session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder(), encoder: JSONEncoder = JSONEncoder()) {
        self.config = config
        self.signer = signer
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public func get<Value: Decodable & Sendable>(_ path: String, signed: Bool = true) async throws -> Value {
        try await request(path, method: "GET", body: Optional<Data>.none, signed: signed)
    }

    public func post<Request: Encodable & Sendable, Value: Decodable & Sendable>(
        _ path: String,
        body: Request,
        signed: Bool = true
    ) async throws -> Value {
        let data = try encoder.encode(body)
        return try await request(path, method: "POST", body: data, signed: signed)
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

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if signed {
            let headers = try signer.signedHeaders(method: "POST", path: url.path)
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
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
        signed: Bool
    ) async throws -> Value {
        guard let url = URL(string: path, relativeTo: config.apiBaseURL) else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if signed {
            let headers = try signer.signedHeaders(method: method, path: url.path)
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        if Value.self == EmptyResponse.self, data.isEmpty {
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
}

public struct EmptyResponse: Codable, Sendable {
    public init() {}
}

public enum APIError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "无效接口路径：\(path)"
        case .invalidResponse:
            "服务器响应无效"
        case .httpStatus(let status):
            "请求失败：HTTP \(status)"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

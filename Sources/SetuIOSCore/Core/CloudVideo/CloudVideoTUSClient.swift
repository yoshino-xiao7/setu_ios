import Foundation
import Network

public protocol CloudVideoUploadNetworking: AnyObject, Sendable {
    var isSatisfied: Bool { get }
    var isWifi: Bool { get }
    var onChange: (@Sendable () -> Void)? { get set }
}

public protocol CloudVideoDeviceConditioning: Sendable {
    var isLowPower: Bool { get }
    var isOverheating: Bool { get }
}

public struct CloudVideoAlwaysReadyConditions: CloudVideoDeviceConditioning, Sendable {
    public init() {}
    public var isLowPower: Bool { false }
    public var isOverheating: Bool { false }
}

public final class CloudVideoUploadManualNetwork: CloudVideoUploadNetworking, @unchecked Sendable {
    public var isSatisfied: Bool
    public var isWifi: Bool
    public var onChange: (@Sendable () -> Void)?

    public init(isSatisfied: Bool = true, isWifi: Bool = true) {
        self.isSatisfied = isSatisfied
        self.isWifi = isWifi
    }

    public func update(isSatisfied: Bool, isWifi: Bool) {
        self.isSatisfied = isSatisfied
        self.isWifi = isWifi
        onChange?()
    }
}

public final class CloudVideoUploadPathMonitor: CloudVideoUploadNetworking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "icu.yukiryou.setuios.cloud-video-path")
    public private(set) var isSatisfied = true
    public private(set) var isWifi = true
    public var onChange: (@Sendable () -> Void)?

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.isSatisfied = path.status == .satisfied
            self.isWifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            self.onChange?()
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

public struct CloudVideoProcessConditions: CloudVideoDeviceConditioning, Sendable {
    public init() {}

    public var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public var isOverheating: Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return true
        default:
            return false
        }
    }
}

public protocol CloudVideoTUSUploading: Sendable {
    func upload(
        fileURL: URL,
        session: CloudVideoUploadSession,
        existingUploadURL: URL?,
        chunkSize: Int,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL
}

public struct CloudVideoTUSClient: CloudVideoTUSUploading, Sendable {
    private let urlSession: URLSession

    public init(session: URLSession = .shared) {
        self.urlSession = session
    }

    public func upload(
        fileURL: URL,
        session: CloudVideoUploadSession,
        existingUploadURL: URL?,
        chunkSize: Int,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let total = try fileSize(at: fileURL)
        var uploadURL = existingUploadURL
        var offset: Int64 = 0
        if let existing = uploadURL {
            offset = (try? await headOffset(uploadURL: existing, session: session)) ?? 0
        }
        if uploadURL == nil {
            let created = try await create(fileURL: fileURL, total: total, session: session)
            uploadURL = created.url
            offset = created.offset
        }
        let target = try requiredURL(uploadURL)
        onProgress(offset, total)
        while offset < total {
            try Task.checkCancellation()
            let chunk = try readChunk(from: fileURL, offset: offset, maxLength: chunkSize)
            offset = try await patch(
                uploadURL: target,
                offset: offset,
                chunk: chunk,
                session: session
            )
            onProgress(offset, total)
        }
        return target
    }

    private func create(
        fileURL: URL,
        total: Int64,
        session: CloudVideoUploadSession
    ) async throws -> (url: URL, offset: Int64) {
        let endpoint = try requiredURL(URL(string: session.tusEndpoint))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("\(total)", forHTTPHeaderField: "Upload-Length")
        request.setValue(metadataHeader(fileURL: fileURL, title: session.title), forHTTPHeaderField: "Upload-Metadata")
        applyAuth(session, to: &request)
        let (_, response) = try await urlSession.data(for: request)
        let http = try httpResponse(response)
        if http.statusCode == 409 {
            let location = locationURL(http, fallback: endpoint)
            let offset = (try? await headOffset(uploadURL: location, session: session)) ?? 0
            return (location, offset)
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, message: "TUS 创建失败")
        }
        return (locationURL(http, fallback: endpoint), 0)
    }

    private func headOffset(uploadURL: URL, session: CloudVideoUploadSession) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        applyAuth(session, to: &request)
        let (_, response) = try await urlSession.data(for: request)
        let http = try httpResponse(response)
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, message: "TUS 查询偏移失败")
        }
        if let raw = http.value(forHTTPHeaderField: "Upload-Offset"), let value = Int64(raw) {
            return value
        }
        return 0
    }

    private func patch(
        uploadURL: URL,
        offset: Int64,
        chunk: Data,
        session: CloudVideoUploadSession
    ) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
        applyAuth(session, to: &request)
        request.httpBody = chunk
        let (_, response) = try await urlSession.data(for: request)
        let http = try httpResponse(response)
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, message: "TUS 分片失败")
        }
        if let raw = http.value(forHTTPHeaderField: "Upload-Offset"), let value = Int64(raw) {
            return value
        }
        return offset + Int64(chunk.count)
    }

    private func applyAuth(_ session: CloudVideoUploadSession, to request: inout URLRequest) {
        request.setValue(session.authorizationSignature, forHTTPHeaderField: "AuthorizationSignature")
        request.setValue("\(session.authorizationExpire)", forHTTPHeaderField: "AuthorizationExpire")
        request.setValue("\(session.libraryId)", forHTTPHeaderField: "LibraryId")
        request.setValue(session.bunnyVideoId, forHTTPHeaderField: "VideoId")
    }

    private func metadataHeader(fileURL: URL, title: String) -> String {
        let filename = fileURL.lastPathComponent
        let filetype = "video/mp4"
        return [
            "filename \(Data(filename.utf8).base64EncodedString())",
            "filetype \(Data(filetype.utf8).base64EncodedString())",
            "title \(Data(title.utf8).base64EncodedString())"
        ].joined(separator: ",")
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func readChunk(from url: URL, offset: Int64, maxLength: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return handle.readData(ofLength: maxLength)
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return http
    }

    private func locationURL(_ response: HTTPURLResponse, fallback: URL) -> URL {
        if let location = response.value(forHTTPHeaderField: "Location"),
           let url = URL(string: location, relativeTo: response.url) {
            return url.absoluteURL
        }
        return fallback
    }

    private func requiredURL(_ url: URL?) throws -> URL {
        guard let url else { throw APIError.invalidURL("tus") }
        return url
    }
}

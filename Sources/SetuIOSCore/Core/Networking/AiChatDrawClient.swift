import Foundation

public struct AiChatDrawClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func createSession() async throws -> AiChatDrawSession {
        try await apiClient.post("/ai/chat-draw/sessions")
    }

    public func listSessions(page: Int = 1, pageSize: Int = 20, status: String = "ACTIVE") async throws -> PageResult<AiChatDrawSession> {
        try await apiClient.get("/ai/chat-draw/sessions?page=\(page)&pageSize=\(pageSize)&status=\(status)")
    }

    public func sessionDetail(id: Int) async throws -> AiChatDrawSessionDetail {
        try await apiClient.get("/ai/chat-draw/sessions/\(id)")
    }

    public func archiveSession(id: Int) async throws -> AiChatDrawSession {
        try await apiClient.post("/ai/chat-draw/sessions/\(id)/archive")
    }

    public func unarchiveSession(id: Int) async throws -> AiChatDrawSession {
        try await apiClient.post("/ai/chat-draw/sessions/\(id)/unarchive")
    }

    public func deleteSession(id: Int) async throws {
        let _: EmptyResponse = try await apiClient.requestWithoutBody("/ai/chat-draw/sessions/\(id)", method: "DELETE")
    }

    public func assets(sessionID: Int) async throws -> [AiChatDrawAsset] {
        try await apiClient.get("/ai/chat-draw/sessions/\(sessionID)/assets")
    }

    public func exportSession(id: Int) async throws -> AiChatDrawExport {
        try await apiClient.post("/ai/chat-draw/sessions/\(id)/export")
    }

    public func downloadExport(sessionID: Int) async throws -> Data {
        try await apiClient.getData("/ai/chat-draw/sessions/\(sessionID)/export/download")
    }

    public func uploadReferenceImage(data: Data, fileName: String = "reference.jpg", mimeType: String = "image/jpeg") async throws -> AiGenerationSourceImage {
        try await apiClient.postMultipart("/ai/generations/source", fileFieldName: "file", fileName: fileName, mimeType: mimeType, fileData: data)
    }

    public func analyzeReferenceImage(sessionID: Int?, sourceImageID: Int, nsfwMode: Bool?) async throws -> AiChatDrawImageAnalysis {
        try await apiClient.post(
            "/ai/chat-draw/analyze-image",
            body: AiChatDrawAnalyzeImageRequest(
                sessionId: sessionID,
                sourceImageId: sourceImageID,
                instruction: nil,
                nsfwMode: nsfwMode
            ),
            timeoutInterval: AiChatDrawBilling.sendTimeoutSeconds
        )
    }

    public func sendMessage(_ request: AiChatDrawSendRequest) async throws -> AiChatDrawSessionDetail {
        try await apiClient.post(
            "/ai/chat-draw/messages",
            body: request,
            timeoutInterval: AiChatDrawBilling.sendTimeoutSeconds
        )
    }

    public func streamMessage(
        _ request: AiChatDrawSendRequest
    ) -> AsyncThrowingStream<AiChatDrawStreamEvent, Error> {
        let raw = apiClient.postServerSentEventData(
            "/ai/chat-draw/messages/stream",
            body: request,
            timeoutInterval: AiChatDrawBilling.sendTimeoutSeconds
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await payload in raw {
                        let event = try JSONDecoder().decode(AiChatDrawStreamEvent.self, from: payload)
                        continuation.yield(event)
                        if event.kind == .done || event.kind == .error {
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct AiChatDrawAnalyzeImageRequest: Encodable, Sendable {
    let sessionId: Int?
    let sourceImageId: Int
    let instruction: String?
    let nsfwMode: Bool?
}

import Foundation

public struct AiChatDrawClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func createSession() async throws -> AiChatDrawSession {
        try await apiClient.post("/ai/chat-draw/sessions")
    }

    public func listSessions(page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiChatDrawSession> {
        try await apiClient.get("/ai/chat-draw/sessions?page=\(page)&pageSize=\(pageSize)")
    }

    public func sessionDetail(id: Int) async throws -> AiChatDrawSessionDetail {
        try await apiClient.get("/ai/chat-draw/sessions/\(id)")
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

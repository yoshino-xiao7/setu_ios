import Foundation
import XCTest
@testable import SetuIOSCore

final class AiChatDrawClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AiChatDrawClientMockURLProtocol.handler = nil
    }

    func testListSessionsEndpointAndDecoding() async throws {
        let capturedRequests = AiChatDrawClientRequestProbe()
        let session = URLSession(
            configuration: .aiChatDrawClientMock { request in
                Task { await capturedRequests.capture(request) }
                return """
                {"total":1,"page":1,"pageSize":20,"list":[{"id":9,"title":"雨夜猫娘","status":"ACTIVE","usage":{"promptTokens":10,"completionTokens":4,"totalTokens":14,"cacheHitTokens":0,"cacheMissTokens":10,"reasoningTokens":0}}]}
                """
            }
        )
        let client = AiChatDrawClient(apiClient: makeAPIClient(session: session))

        let result = try await client.listSessions(page: 1, pageSize: 20)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.list.first?.id, 9)
        XCTAssertEqual(result.list.first?.displayTitle, "雨夜猫娘")
        XCTAssertEqual(result.list.first?.usage?.promptTokens, 10)
        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/chat-draw/sessions?page=1&pageSize=20&status=ACTIVE"])
    }

    func testSendMessageUsesLongTimeoutAndDecodesJob() async throws {
        let capturedRequests = AiChatDrawClientRequestProbe()
        let session = URLSession(
            configuration: .aiChatDrawClientMock { request in
                Task { await capturedRequests.capture(request) }
                return """
                {"session":{"id":9,"title":"雨夜猫娘","status":"ACTIVE"},"messages":[{"id":2,"role":"assistant","content":"已安排生成","generationJobId":501,"generationJob":{"id":501,"promptCn":"雨夜猫娘","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"QUEUED","reviewStatus":"PENDING"},"pointsCost":0,"pointsCharged":false,"pointsRefunded":false,"adminFree":false}],"tokensPerPoint":1000,"rateLimitSeconds":30,"retryAfterSeconds":12,"adminFree":false}
                """
            }
        )
        let client = AiChatDrawClient(apiClient: makeAPIClient(session: session))

        let detail = try await client.sendMessage(
            AiChatDrawSendRequest(sessionId: 9, content: "画一只猫娘", nsfwMode: false)
        )

        XCTAssertEqual(detail.session.id, 9)
        XCTAssertEqual(detail.retryAfterSeconds, 12)
        XCTAssertEqual(detail.messages.first?.generationJobId, 501)
        XCTAssertEqual(detail.messages.first?.generationJob?.status, "QUEUED")
        let timeout = await capturedRequests.timeouts.first
        XCTAssertEqual(timeout, AiChatDrawBilling.sendTimeoutSeconds)
        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/chat-draw/messages"])
    }

    func testStreamMessageParsesSSEEventsAndStopsOnDone() async throws {
        let capturedRequests = AiChatDrawClientRequestProbe()
        let session = URLSession(
            configuration: .aiChatDrawClientMock { request in
                Task { await capturedRequests.capture(request) }
                return """
                data: {"type":"status","message":"已收到请求，开始处理…"}

                data: {"type":"delta","content":"好的，"}

                data: {"type":"delta","content":"开始画。"}

                data: {"type":"job","job":{"id":501,"promptCn":"雨夜猫娘","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"QUEUED","reviewStatus":"PENDING"}}

                data: {"type":"done","detail":{"session":{"id":9,"title":"雨夜猫娘","status":"ACTIVE"},"messages":[{"id":1,"role":"user","content":"画一只猫娘","status":"COMPLETED"},{"id":2,"role":"assistant","content":"好的，开始画。","generationJobId":501,"generationJob":{"id":501,"promptCn":"雨夜猫娘","width":768,"height":1024,"steps":28,"cfg":7.0,"status":"QUEUED","reviewStatus":"PENDING"},"status":"COMPLETED"}],"tokensPerPoint":1000,"rateLimitSeconds":30,"retryAfterSeconds":12,"adminFree":false}}

                """
            }
        )
        let client = AiChatDrawClient(apiClient: makeAPIClient(session: session))

        var kinds: [AiChatDrawStreamEvent.Kind] = []
        var draft = AiChatDrawStreamingDraft()
        var finalDetail: AiChatDrawSessionDetail?
        for try await event in client.streamMessage(
            AiChatDrawSendRequest(sessionId: 9, content: "画一只猫娘", nsfwMode: false)
        ) {
            kinds.append(event.kind)
            if event.kind == .done {
                finalDetail = event.detail
            } else if event.kind != .error {
                try draft.apply(event)
            }
        }

        XCTAssertEqual(kinds, [.status, .delta, .delta, .job, .done])
        XCTAssertEqual(draft.content, "好的，开始画。")
        XCTAssertEqual(draft.job?.id, 501)
        XCTAssertEqual(finalDetail?.session.id, 9)
        XCTAssertEqual(finalDetail?.messages.count, 2)
        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/chat-draw/messages/stream"])
        let accept = await capturedRequests.acceptHeaders.first
        XCTAssertEqual(accept, "text/event-stream")
        let timeout = await capturedRequests.timeouts.first
        XCTAssertEqual(timeout, AiChatDrawBilling.sendTimeoutSeconds)
    }

    func testSSEPayloadHelperJoinsMultilineData() {
        let payloads = AiChatDrawBilling.parseSSEDataPayloads(
            from: "data: {\"type\":\"delta\",\"content\":\"a\"}\n\ndata: {\"type\":\"done\"}\n\n"
        )
        XCTAssertEqual(payloads.payloads, [#"{"type":"delta","content":"a"}"#, #"{"type":"done"}"#])
        XCTAssertEqual(payloads.remainder, "")
    }

    func testSSEDataTaskDrainsIncrementalChunks() {
        var buffer = Data()
        buffer.append(contentsOf: #"data: {"type":"status","message":"hi"}"#.utf8)
        buffer.append(contentsOf: "\n\n".utf8)
        buffer.append(contentsOf: #"data: {"type":"delta","content":"你"#.utf8)
        let first = ServerSentEventDataTask.drainSSEPayloads(from: &buffer)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(String(data: first[0], encoding: .utf8), #"{"type":"status","message":"hi"}"#)
        XCTAssertFalse(buffer.isEmpty)

        buffer.append(contentsOf: #"好"}\n\n"#.utf8)
        let second = ServerSentEventDataTask.drainSSEPayloads(from: &buffer)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(String(data: second[0], encoding: .utf8), #"{"type":"delta","content":"你好"}"#)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testBillingHelpers() {
        XCTAssertEqual(AiChatDrawBilling.pricingText(tokensPerPoint: 1000), "每 1000 Token = 1 积分")
        XCTAssertEqual(AiChatDrawBilling.parseRetrySeconds(from: "请 18 秒后再试"), 18)
        XCTAssertEqual(AiChatDrawBilling.cooldownSeconds(retryAfterSeconds: 7), 7)
        XCTAssertTrue(AiChatDrawBilling.isClientDisconnectedMessage("这次对话失败了：客户端已断开"))
        XCTAssertTrue(
            AiChatDrawBilling.isTransientSendFailure(
                APIError.httpStatus(503, message: "客户端已断开", code: "AI_CHAT_DRAW_STREAM_CLOSED")
            )
        )
        XCTAssertTrue(
            AiChatDrawBilling.turnLikelySucceeded(
                content: "画一只猫",
                previousMessageCount: 0,
                detail: AiChatDrawSessionDetail(
                    session: AiChatDrawSession(
                        id: 1,
                        title: nil,
                        status: "ACTIVE",
                        usage: nil,
                        lastGenerationJobId: nil,
                        createdAt: nil,
                        updatedAt: nil
                    ),
                    messages: []
                )
            ) == false
        )

        let userOnly = try JSONDecoder().decode(
            AiChatDrawSessionDetail.self,
            from: Data(#"""
            {"session":{"id":1,"title":"t","status":"ACTIVE"},"messages":[{"id":1,"role":"user","content":"画一只猫","status":"COMPLETED"}],"tokensPerPoint":1000,"rateLimitSeconds":30}
            """#.utf8)
        )
        XCTAssertTrue(AiChatDrawBilling.userTurnPersisted(content: "画一只猫", detail: userOnly))
        XCTAssertFalse(
            AiChatDrawBilling.turnLikelySucceeded(
                content: "画一只猫",
                previousMessageCount: 0,
                detail: userOnly
            )
        )

        let withAssistant = try JSONDecoder().decode(
            AiChatDrawSessionDetail.self,
            from: Data(#"""
            {"session":{"id":1,"title":"t","status":"ACTIVE"},"messages":[{"id":1,"role":"user","content":"画一只猫","status":"COMPLETED"},{"id":2,"role":"assistant","content":"好的，开始画。","generationJobId":9,"status":"COMPLETED"}],"tokensPerPoint":1000,"rateLimitSeconds":30}
            """#.utf8)
        )
        XCTAssertTrue(
            AiChatDrawBilling.turnLikelySucceeded(
                content: "画一只猫",
                previousMessageCount: 0,
                detail: withAssistant
            )
        )
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = AiChatDrawClientTestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return APIClient(
            config: AppConfig(
                apiBaseURL: URL(string: "https://api.example.com")!,
                siteBaseURL: URL(string: "https://example.com")!
            ),
            signer: AuthSigner(keychain: keychain),
            session: session
        )
    }
}

private actor AiChatDrawClientRequestProbe {
    private(set) var urls: [String] = []
    private(set) var timeouts: [TimeInterval] = []
    private(set) var acceptHeaders: [String] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
        timeouts.append(request.timeoutInterval)
        acceptHeaders.append(request.value(forHTTPHeaderField: "Accept") ?? "")
    }
}

private final class AiChatDrawClientTestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func setString(_ value: String, for key: String) throws {
        lock.withLock { values[key] = value }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

private final class AiChatDrawClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static func aiChatDrawClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        AiChatDrawClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AiChatDrawClientMockURLProtocol.self]
        return configuration
    }
}

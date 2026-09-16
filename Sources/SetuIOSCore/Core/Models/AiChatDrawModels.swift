import Foundation

public struct AiChatDrawUsage: Decodable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cacheHitTokens: Int
    public let cacheMissTokens: Int
    public let reasoningTokens: Int

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        cacheHitTokens: Int = 0,
        cacheMissTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cacheHitTokens = cacheHitTokens
        self.cacheMissTokens = cacheMissTokens
        self.reasoningTokens = reasoningTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        cacheHitTokens = try container.decodeIfPresent(Int.self, forKey: .cacheHitTokens) ?? 0
        cacheMissTokens = try container.decodeIfPresent(Int.self, forKey: .cacheMissTokens) ?? 0
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
    }

    public var hasMeaningfulUsage: Bool {
        promptTokens + completionTokens + cacheHitTokens + cacheMissTokens > 0
    }

    public var summaryText: String {
        "输入 \(promptTokens) · 输出 \(completionTokens) · 命中缓存 \(cacheHitTokens) · 未命中缓存 \(cacheMissTokens)"
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens, completionTokens, totalTokens, cacheHitTokens, cacheMissTokens, reasoningTokens
    }
}

public struct AiChatDrawSession: Decodable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String?
    public let status: String?
    public let usage: AiChatDrawUsage?
    public let lastGenerationJobId: Int?
    public let createdAt: String?
    public let updatedAt: String?

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? "对话 #\(id)" : trimmed
        return isArchived ? "\(base)（已归档）" : base
    }

    public var isArchived: Bool {
        (status ?? "").caseInsensitiveCompare("ARCHIVED") == .orderedSame
    }

    public var isActive: Bool {
        !isArchived
    }
}

public struct AiChatDrawMessage: Decodable, Identifiable, Sendable {
    public let id: Int
    public let role: String
    public let content: String?
    public let reasoningContent: String?
    public let usage: AiChatDrawUsage?
    public let generationJobId: Int?
    public let generationJob: AiGenerationJob?
    public let pointsCost: Int
    public let pointsCharged: Bool
    public let pointsRefunded: Bool
    public let adminFree: Bool
    public let status: String?
    public let errorMessage: String?
    public let createdAt: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        usage = try container.decodeIfPresent(AiChatDrawUsage.self, forKey: .usage)
        generationJobId = try container.decodeIfPresent(Int.self, forKey: .generationJobId)
        generationJob = try container.decodeIfPresent(AiGenerationJob.self, forKey: .generationJob)
        pointsCost = try container.decodeIfPresent(Int.self, forKey: .pointsCost) ?? 0
        pointsCharged = try container.decodeIfPresent(Bool.self, forKey: .pointsCharged) ?? false
        pointsRefunded = try container.decodeIfPresent(Bool.self, forKey: .pointsRefunded) ?? false
        adminFree = try container.decodeIfPresent(Bool.self, forKey: .adminFree) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public var isUser: Bool { role == "user" }

    public var displayContent: String {
        content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoningContent, usage, generationJobId, generationJob
        case pointsCost, pointsCharged, pointsRefunded, adminFree, status, errorMessage, createdAt
    }
}

public struct AiChatDrawSessionDetail: Decodable, Sendable {
    public let session: AiChatDrawSession
    public let messages: [AiChatDrawMessage]
    public let cost: Int
    public let tokensPerPoint: Int
    public let rateLimitSeconds: Int
    public let retryAfterSeconds: Int
    public let adminFree: Bool

    public init(
        session: AiChatDrawSession,
        messages: [AiChatDrawMessage] = [],
        cost: Int = 0,
        tokensPerPoint: Int = AiChatDrawBilling.defaultTokensPerPoint,
        rateLimitSeconds: Int = AiChatDrawBilling.defaultRateLimitSeconds,
        retryAfterSeconds: Int = 0,
        adminFree: Bool = false
    ) {
        self.session = session
        self.messages = messages
        self.cost = cost
        self.tokensPerPoint = tokensPerPoint
        self.rateLimitSeconds = rateLimitSeconds
        self.retryAfterSeconds = retryAfterSeconds
        self.adminFree = adminFree
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(AiChatDrawSession.self, forKey: .session)
        messages = try container.decodeIfPresent([AiChatDrawMessage].self, forKey: .messages) ?? []
        cost = try container.decodeIfPresent(Int.self, forKey: .cost) ?? 0
        tokensPerPoint = try container.decodeIfPresent(Int.self, forKey: .tokensPerPoint)
            ?? AiChatDrawBilling.defaultTokensPerPoint
        rateLimitSeconds = try container.decodeIfPresent(Int.self, forKey: .rateLimitSeconds)
            ?? AiChatDrawBilling.defaultRateLimitSeconds
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds) ?? 0
        adminFree = try container.decodeIfPresent(Bool.self, forKey: .adminFree) ?? false
    }

    public var pricingText: String {
        AiChatDrawBilling.pricingText(tokensPerPoint: tokensPerPoint)
    }

    private enum CodingKeys: String, CodingKey {
        case session, messages, cost, tokensPerPoint, rateLimitSeconds, retryAfterSeconds, adminFree
    }
}

public struct AiChatDrawSendRequest: Encodable, Sendable {
    public let sessionId: Int?
    public let content: String
    public let nsfwMode: Bool?

    public init(sessionId: Int? = nil, content: String, nsfwMode: Bool? = nil) {
        self.sessionId = sessionId
        self.content = content
        self.nsfwMode = nsfwMode
    }
}

public struct AiChatDrawStreamEvent: Decodable, Sendable {
    public let type: String
    public let message: String?
    public let content: String?
    public let job: AiGenerationJob?
    public let detail: AiChatDrawSessionDetail?

    public var kind: Kind {
        Kind(rawValue: type) ?? .unknown
    }

    public enum Kind: String, Sendable {
        case status
        case delta
        case reasoning
        case job
        case done
        case error
        case unknown
    }
}

public struct AiChatDrawStreamingDraft: Sendable {
    public var status: String
    public var content: String
    public var reasoningContent: String
    public var job: AiGenerationJob?

    public init(
        status: String = "正在思考…",
        content: String = "",
        reasoningContent: String = "",
        job: AiGenerationJob? = nil
    ) {
        self.status = status
        self.content = content
        self.reasoningContent = reasoningContent
        self.job = job
    }

    public mutating func apply(_ event: AiChatDrawStreamEvent) throws {
        switch event.kind {
        case .status:
            status = event.message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? status
        case .delta:
            if let content = event.content { self.content += content }
        case .reasoning:
            if let content = event.content { reasoningContent += content }
        case .job:
            if let job = event.job { self.job = job }
        case .error:
            throw APIError.httpStatus(
                500,
                message: event.message ?? "对话流式传输失败",
                requestID: nil,
                traceID: nil,
                code: "AI_CHAT_DRAW_STREAM_ERROR"
            )
        case .done, .unknown:
            break
        }
    }
}

public enum AiChatDrawBilling {
    public static let defaultTokensPerPoint = 1000
    public static let defaultRateLimitSeconds = 30
    public static let sendTimeoutSeconds: TimeInterval = 600
    public static let pollIntervalNanoseconds: UInt64 = 2_500_000_000

    public static func pricingText(tokensPerPoint: Int = defaultTokensPerPoint) -> String {
        let value = max(1, tokensPerPoint)
        return "每 \(value) Token = 1 积分"
    }

    public static func cooldownSeconds(retryAfterSeconds: Int?) -> Int {
        guard let retryAfterSeconds, retryAfterSeconds > 0 else { return 0 }
        return retryAfterSeconds
    }

    public static func parseRetrySeconds(from message: String?, fallback: Int = defaultRateLimitSeconds) -> Int {
        guard let message,
              let match = message.range(of: #"(\d+)\s*秒"#, options: .regularExpression) else {
            return fallback
        }
        let digits = message[match].prefix { $0.isNumber }
        return max(1, Int(digits) ?? fallback)
    }

    public static func isTransientSendFailure(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpStatus(let status, let message, _, _, let code):
                if code == "AI_CHAT_DRAW_STREAM_CLOSED"
                    || code == "AI_CHAT_DRAW_STREAM_ERROR"
                    || isClientDisconnectedMessage(message) {
                    return true
                }
                return [408, 502, 503, 504].contains(status)
            case .invalidResponse:
                return true
            case .invalidURL:
                return false
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotConnectToHost
            ].contains(nsError.code)
        }
        let message = error.localizedDescription
        if isClientDisconnectedMessage(message) { return true }
        let lowered = message.lowercased()
        return lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("网络")
    }

    public static func isClientDisconnectedMessage(_ message: String?) -> Bool {
        guard let message, !message.isEmpty else { return false }
        return message.contains("客户端已断开")
            || message.localizedCaseInsensitiveContains("AI_CHAT_DRAW_STREAM_CLOSED")
    }

    public static func turnLikelySucceeded(
        content: String,
        previousMessageCount: Int,
        detail: AiChatDrawSessionDetail?
    ) -> Bool {
        guard let detail, detail.messages.count > previousMessageCount else { return false }
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return detail.messages.contains {
            $0.isUser && ($0.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
    }

    /// Rewrites stale "client disconnected" assistant text when a draw job already exists.
    public static func displayContent(for message: AiChatDrawMessage, job: AiGenerationJob?) -> String {
        let raw = message.displayContent
        guard isClientDisconnectedMessage(raw), job != nil else { return raw }
        return "已经开始处理你的绘画请求。如果画面还没出来，请稍候当前任务或刷新后再看。"
    }

    public static func parseSSEDataPayloads(from text: String) -> (payloads: [String], remainder: String) {
        var buffer = text
        var payloads: [String] = []
        while let range = buffer.range(of: "\n\n") {
            let chunk = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            if let payload = sseDataPayload(in: chunk) {
                payloads.append(payload)
            }
        }
        return (payloads, buffer)
    }

    public static func sseDataPayload(in chunk: String) -> String? {
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let dataLines = lines.compactMap { line -> String? in
            guard line.hasPrefix("data:") else { return nil }
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

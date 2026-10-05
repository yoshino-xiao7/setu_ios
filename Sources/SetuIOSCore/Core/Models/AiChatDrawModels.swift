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
    public let archivedAt: String?
    public let deleteAt: String?

    public init(
        id: Int,
        title: String? = nil,
        status: String? = nil,
        usage: AiChatDrawUsage? = nil,
        lastGenerationJobId: Int? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        archivedAt: String? = nil,
        deleteAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.usage = usage
        self.lastGenerationJobId = lastGenerationJobId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.deleteAt = deleteAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        usage = try c.decodeIfPresent(AiChatDrawUsage.self, forKey: .usage)
        lastGenerationJobId = try c.decodeIfPresent(Int.self, forKey: .lastGenerationJobId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt)
        deleteAt = try c.decodeIfPresent(String.self, forKey: .deleteAt)
    }

    private enum CodingKeys: String, CodingKey { case id, title, status, usage, lastGenerationJobId, createdAt, updatedAt, archivedAt, deleteAt }

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

public struct AiChatDrawAsset: Decodable, Identifiable, Sendable, Equatable {
    /// Generated assets may be synthesized from a generation job and therefore
    /// do not have a row id in `ai_chat_draw_asset`.
    public let id: Int?
    public let assetType: String
    public let sourceImageId: Int?
    public let generationJobId: Int?
    public let contentType: String?
    public let sizeBytes: Int?
    public let url: String?
    public let createdAt: String?

    public var stableID: String {
        if let id { return "asset-\(id)" }
        if let generationJobId { return "generated-\(generationJobId)" }
        if let sourceImageId { return "source-\(sourceImageId)" }
        return "asset-\(assetType)-\(createdAt ?? "unknown")"
    }
}

public struct AiChatDrawExport: Decodable, Sendable {
    public let id: Int?
    public let status: String
    public let downloadUrl: String?
    public let expiresAt: String?
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
    public let followUps: [String]
    public let sourceImageId: Int?
    public let referenceAnalysis: String?
    public let createdAt: String?
    public let assets: [AiChatDrawAsset]

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
        followUps = (try container.decodeIfPresent([String].self, forKey: .followUps) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        sourceImageId = try container.decodeIfPresent(Int.self, forKey: .sourceImageId)
        referenceAnalysis = try container.decodeIfPresent(String.self, forKey: .referenceAnalysis)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        assets = try container.decodeIfPresent([AiChatDrawAsset].self, forKey: .assets) ?? []
    }

    public var isUser: Bool { role == "user" }

    public var displayContent: String {
        content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoningContent, usage, generationJobId, generationJob
        case pointsCost, pointsCharged, pointsRefunded, adminFree, status, errorMessage, followUps, sourceImageId, referenceAnalysis, createdAt, assets
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

public struct AiChatDrawImageAnalysis: Codable, Sendable {
    public let sourceImageId: Int?
    public let summary: String?
    public let subjects: String?
    public let poseExpression: String?
    public let settingCamera: String?
    public let promptPositive: String?
    public let promptNegative: String?

    public init(
        sourceImageId: Int? = nil,
        summary: String? = nil,
        subjects: String? = nil,
        poseExpression: String? = nil,
        settingCamera: String? = nil,
        promptPositive: String? = nil,
        promptNegative: String? = nil
    ) {
        self.sourceImageId = sourceImageId
        self.summary = summary
        self.subjects = subjects
        self.poseExpression = poseExpression
        self.settingCamera = settingCamera
        self.promptPositive = promptPositive
        self.promptNegative = promptNegative
    }
}

public struct AiChatDrawSendRequest: Encodable, Sendable {
    public let sessionId: Int?
    public let content: String
    public let nsfwMode: Bool?
    public let aspectRatio: String?
    public let width: Int?
    public let height: Int?
    public let checkpoint: String?
    public let sourceImageId: Int?
    public let referenceAnalysis: String?
    public let redesignInstruction: String?
    public let generationMode: String?
    public let denoise: Double?

    public init(sessionId: Int? = nil, content: String, nsfwMode: Bool? = nil, aspectRatio: String? = nil, width: Int? = nil, height: Int? = nil, checkpoint: String? = nil, sourceImageId: Int? = nil, referenceAnalysis: String? = nil, redesignInstruction: String? = nil, generationMode: String? = nil, denoise: Double? = nil) {
        self.sessionId = sessionId
        self.content = content
        self.nsfwMode = nsfwMode
        self.aspectRatio = aspectRatio
        self.width = width
        self.height = height
        self.checkpoint = checkpoint
        self.sourceImageId = sourceImageId
        self.referenceAnalysis = referenceAnalysis
        self.redesignInstruction = redesignInstruction
        self.generationMode = generationMode
        self.denoise = denoise
    }
}

public struct AiChatDrawStreamEvent: Decodable, Sendable {
    public let type: String
    public let message: String?
    public let content: String?
    public let job: AiGenerationJob?
    public let followUps: [String]?
    public let detail: AiChatDrawSessionDetail?

    public var kind: Kind {
        Kind(rawValue: type) ?? .unknown
    }

    public enum Kind: String, Sendable {
        case status
        case delta
        case reasoning
        case job
        case followUps = "follow_ups"
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
    public var followUps: [String]

    public init(
        status: String = "正在思考…",
        content: String = "",
        reasoningContent: String = "",
        job: AiGenerationJob? = nil,
        followUps: [String] = []
    ) {
        self.status = status
        self.content = content
        self.reasoningContent = reasoningContent
        self.job = job
        self.followUps = followUps
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
        case .followUps:
            let items = (event.followUps ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty { followUps = items }
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
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorCancelled // often fired when the app is backgrounded mid-stream
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

    /// Recover only when the matching user turn already has a visible assistant reply
    /// (text and/or generation job). User-only rows mean the turn is still running.
    public static func turnLikelySucceeded(
        content: String,
        previousMessageCount: Int,
        detail: AiChatDrawSessionDetail?
    ) -> Bool {
        guard let detail, detail.messages.count > previousMessageCount else { return false }
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard let userIndex = detail.messages.lastIndex(where: {
            $0.isUser && ($0.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }) else {
            return false
        }
        return detail.messages.suffix(from: detail.messages.index(after: userIndex)).contains { message in
            guard !message.isUser else { return false }
            let hasText = !(message.content ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            let hasJob = message.generationJobId != nil || message.generationJob != nil
            return hasText || hasJob
        }
    }

    /// Backoff used when SSE ends without `done` while the server may still be finishing.
    /// Spans a few minutes so long LLM/tool turns can still surface after a silent disconnect.
    public static let recoverPollDelaysNanoseconds: [UInt64] = [
        0,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
        5_000_000_000,
        8_000_000_000,
        12_000_000_000,
        20_000_000_000,
        20_000_000_000,
        30_000_000_000,
        30_000_000_000,
        30_000_000_000,
    ]

    public static func userTurnPersisted(
        content: String,
        detail: AiChatDrawSessionDetail?
    ) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let detail else { return false }
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

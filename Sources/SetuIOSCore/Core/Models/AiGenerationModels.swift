import Foundation

public struct PageResult<Value: Decodable & Sendable>: Decodable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let list: [Value]
}

public struct AiGenerationJob: Decodable, Identifiable, Sendable {
    public let id: Int
    public let promptCn: String
    public let promptPositive: String?
    public let promptNegative: String?
    public let styleNotes: String?
    public let width: Int
    public let height: Int
    public let steps: Int
    public let cfg: Double
    public let seed: Int?
    public let checkpoint: String?
    public let generationMode: String?
    public let loraName: String?
    public let loraStrength: Double?
    public let secondLoraName: String?
    public let secondLoraStrength: Double?
    public let status: String
    public let workerStage: String?
    public let workerDetail: String?
    public let reviewStatus: String
    public let publicCategory: String?
    public let publicVisible: Bool?
    public let deleted: Bool?
    public let deleteStatus: String?
    public let imageUrl: String?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let pointsCost: Int?
    public let pointsCharged: Bool?
    public let pointsRefunded: Bool?
    public let errorMessage: String?
    public let userErrorMessage: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let completedAt: String?
    public let failedAt: String?

    public var statusTitle: String {
        switch status {
        case "QUEUED": "排队中"
        case "CLAIMED": "已接单"
        case "RUNNING": "生成中"
        case "UPLOADING": "上传中"
        case "COMPLETED": "已完成"
        case "FAILED": "失败"
        default: status
        }
    }
}

public struct AiGenerationCreateRequest: Encodable, Sendable {
    public let promptCn: String
    public let promptPositive: String?
    public let promptNegative: String?
    public let styleNotes: String?
    public let width: Int
    public let height: Int
    public let steps: Int
    public let cfg: Double
    public let seed: Int?
    public let checkpoint: String?
    public let generationMode: String
    public let loraName: String?
    public let loraStrength: Double?
    public let nsfwMode: Bool
    public let nsfwVisibilityLevel: String

    public init(
        promptCn: String,
        promptPositive: String? = nil,
        promptNegative: String? = nil,
        styleNotes: String? = nil,
        width: Int = 768,
        height: Int = 1024,
        steps: Int = 28,
        cfg: Double = 7,
        seed: Int? = nil,
        checkpoint: String? = nil,
        generationMode: String = "SINGLE",
        loraName: String? = nil,
        loraStrength: Double? = nil,
        nsfwMode: Bool = false,
        nsfwVisibilityLevel: String = "STANDARD"
    ) {
        self.promptCn = promptCn
        self.promptPositive = promptPositive
        self.promptNegative = promptNegative
        self.styleNotes = styleNotes
        self.width = width
        self.height = height
        self.steps = steps
        self.cfg = cfg
        self.seed = seed
        self.checkpoint = checkpoint
        self.generationMode = generationMode
        self.loraName = loraName
        self.loraStrength = loraStrength
        self.nsfwMode = nsfwMode
        self.nsfwVisibilityLevel = nsfwVisibilityLevel
    }
}

public struct AiPromptTranslateRequest: Encodable, Sendable {
    public let promptCn: String
    public let styleTags: String?
    public let negativePrompt: String?
    public let nsfwMode: Bool
    public let nsfwVisibilityLevel: String

    public init(
        promptCn: String,
        styleTags: String? = nil,
        negativePrompt: String? = nil,
        nsfwMode: Bool = false,
        nsfwVisibilityLevel: String = "STANDARD"
    ) {
        self.promptCn = promptCn
        self.styleTags = styleTags
        self.negativePrompt = negativePrompt
        self.nsfwMode = nsfwMode
        self.nsfwVisibilityLevel = nsfwVisibilityLevel
    }
}

public struct AiPromptTranslateResponse: Decodable, Sendable {
    public let id: Int?
    public let promptCn: String?
    public let styleTags: String?
    public let negativePrompt: String?
    public let status: String?
    public let positive: String?
    public let negative: String?
    public let styleNotes: String?
    public let errorMessage: String?
    public let createdAt: String?
    public let completedAt: String?
    public let failedAt: String?
}

public struct AiCapabilityItem: Decodable, Identifiable, Sendable {
    public let workerId: String?
    public let type: String?
    public let name: String
    public let displayName: String?
    public let sizeBytes: Int?
    public let metadataJson: String?

    public var id: String {
        [workerId, type, name].compactMap { $0 }.joined(separator: ":")
    }
}

public struct AiWorkerNode: Decodable, Identifiable, Sendable {
    public let workerId: String
    public let nodeName: String?
    public let version: String?
    public let status: String?
    public let message: String?
    public let lastSeenAt: String?

    public var id: String { workerId }
}

public struct AiCapabilityResponse: Decodable, Sendable {
    public let checkpoints: [AiCapabilityItem]
    public let loras: [AiCapabilityItem]
    public let vaes: [AiCapabilityItem]
    public let characters: [AiCapabilityItem]
    public let promptPresets: [AiCapabilityItem]
    public let workers: [AiWorkerNode]
}

public struct AiServiceStatusResponse: Decodable, Sendable {
    public let status: String
    public let online: Bool
    public let openNow: Bool
    public let available: Bool
    public let message: String?
    public let timezone: String?
    public let openStartTime: String?
    public let openEndTime: String?
    public let workerCount: Int?
    public let activeWorkerCount: Int?
    public let queuedCount: Int?
    public let runningCount: Int?
    public let uploadingCount: Int?
    public let estimatedWaitSeconds: Int?
    public let nextOpenTime: String?
    public let serverTime: String?
    public let lastSeenAt: String?
    public let workers: [AiWorkerNode]?

    public var statusTitle: String {
        if available {
            return "可用"
        }
        if online {
            return "在线但暂不可用"
        }
        return "离线"
    }
}

public struct AiImageURL: Decodable, Sendable {
    public let jobId: Int
    public let url: String
    public let expiresInSeconds: Int
}

public struct AiImageDownload: Decodable, Sendable {
    public let jobId: Int
    public let downloadUrl: String
    public let expires: Int?
}

public struct AiReviewSubmitRequest: Encodable, Sendable {
    public let category: String
    public let note: String?

    public init(category: String, note: String? = nil) {
        self.category = category
        self.note = note
    }
}

public struct AiGenerationReview: Decodable, Identifiable, Sendable {
    public let id: Int
    public let jobId: Int
    public let userId: Int
    public let category: String
    public let status: String
    public let submitNote: String?
    public let rejectReason: String?
    public let adminId: Int?
    public let createdAt: String?
    public let reviewedAt: String?
}

public struct AiDeleteRequestSubmitRequest: Encodable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct AiGenerationDeleteRequest: Decodable, Identifiable, Sendable {
    public let id: Int
    public let jobId: Int
    public let userId: Int
    public let reason: String?
    public let status: String
    public let rejectReason: String?
    public let adminId: Int?
    public let createdAt: String?
    public let reviewedAt: String?
}

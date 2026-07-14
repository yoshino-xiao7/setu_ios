import Foundation

public struct PageResult<Value: Decodable & Sendable>: Decodable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let list: [Value]
}

public struct AiGenerationJob: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int?
    public let apiKeyId: Int?
    public let source: String?
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
    public let characterId: String?
    public let secondLoraName: String?
    public let secondLoraStrength: Double?
    public let secondCharacterId: String?
    public let nsfwMode: Bool?
    public let nsfwVisibilityLevel: String?
    public let jobType: String?
    public let parentJobId: Int?
    public let status: String
    public let workerId: String?
    public let localJobId: String?
    public let comfyPromptId: String?
    public let workerStage: String?
    public let workerDetail: String?
    public let localRelativePath: String?
    public let localAbsolutePath: String?
    public let localStorageStatus: String?
    public let localImageRecordedAt: String?
    public let localImageDeletedAt: String?
    public let privateOssStatus: String?
    public let privateOssExpiresAt: String?
    public let privateOssDeletedAt: String?
    public let privateOssDeleteError: String?
    public let reviewStatus: String
    public let publicCategory: String?
    public let publicVisible: Bool?
    public let deleted: Bool?
    public let deleteStatus: String?
    public let deleteRequestId: Int?
    public let deletedAt: String?
    public let imageUrl: String?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let sizeBytes: Int?
    public let sha256: String?
    public let pointsCost: Int?
    public let pointsCharged: Bool?
    public let pointsRefunded: Bool?
    public let adminFree: Bool?
    public let errorMessage: String?
    public let userErrorMessage: String?
    public let qqNumber: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let completedAt: String?
    public let failedAt: String?

    public var statusTitle: String {
        switch status {
        case "QUEUED": "排队中"
        case "CLAIMED": "准备生成"
        case "RUNNING": "生成中"
        case "UPLOADING": "上传中"
        case "COMPLETED": "已完成"
        case "FAILED": "失败"
        default: "处理中"
        }
    }
}

public struct AiPublicWork: Decodable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let userId: Int?
    public let promptCn: String
    public let width: Int
    public let height: Int
    public let publicCategory: String?
    public let imageUrl: String?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let likeCount: Int
    public let favoriteCount: Int
    public let likedByMe: Bool
    public let favoritedByMe: Bool
    public let createdAt: String?
    public let completedAt: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        promptCn = try container.decode(String.self, forKey: .promptCn)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        publicCategory = try container.decodeIfPresent(String.self, forKey: .publicCategory)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        favoriteCount = try container.decodeIfPresent(Int.self, forKey: .favoriteCount) ?? 0
        likedByMe = try container.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
        favoritedByMe = try container.decodeIfPresent(Bool.self, forKey: .favoritedByMe) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case promptCn
        case width
        case height
        case publicCategory
        case imageUrl
        case imageWidth
        case imageHeight
        case likeCount
        case favoriteCount
        case likedByMe
        case favoritedByMe
        case createdAt
        case completedAt
    }
}

public struct AiGenerationDeleteCommandRequest: Encodable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct AiLocalImageDeleteCommand: Decodable, Identifiable, Sendable {
    public let id: Int
    public let jobId: Int
    public let workerId: String
    public let requestedByAdminId: Int
    public let reason: String?
    public let status: String
    public let attemptCount: Int?
    public let errorMessage: String?
    public let localRelativePath: String?
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
    public let characterId: String?
    public let secondLoraName: String?
    public let secondLoraStrength: Double?
    public let secondCharacterId: String?
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
        characterId: String? = nil,
        secondLoraName: String? = nil,
        secondLoraStrength: Double? = nil,
        secondCharacterId: String? = nil,
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
        self.characterId = characterId
        self.secondLoraName = secondLoraName
        self.secondLoraStrength = secondLoraStrength
        self.secondCharacterId = secondCharacterId
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

    public var userFacingUnavailableMessage: String {
        if !online {
            return "创作服务暂时离线，请稍后再试"
        }
        if !openNow {
            return "当前不在开放时间，请稍后再来"
        }
        return "当前暂无可用创作资源，请稍后重试"
    }
}

public struct AiControlStatus: Decodable, Sendable {
    public let commandId: Int?
    public let commandStatus: String?
    public let controlReady: Bool?
    public let comfyReady: Bool?
    public let localServiceReady: Bool?
    public let workerRunning: Bool?
    public let running: Bool?
    public let comfyUrl: String?
    public let localAiUrl: String?
    public let accepted: Bool?
    public let action: String?
    public let workerId: String?
    public let pid: Int?
    public let message: String?
    public let errorMessage: String?
    public let requestedAt: String?
    public let claimedAt: String?
    public let completedAt: String?

    public var commandStatusTitle: String {
        switch commandStatus {
        case "PENDING": "等待领取"
        case "CLAIMED": "已领取"
        case "SUCCEEDED": "已完成"
        case "FAILED": "执行失败"
        case nil: "未知"
        default: commandStatus ?? "未知"
        }
    }

    public var actionTitle: String {
        switch action {
        case "START": "启动"
        case "STOP": "停止"
        case "RESTART": "重启"
        case nil: "-"
        default: action ?? "-"
        }
    }

    public var stateMessage: String {
        if let commandStatus, commandStatus != "SUCCEEDED" {
            return "最新控制命令\(commandStatusTitle)"
        }
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if let running {
            return running ? "控制服务检测到 AI 绘图已运行" : "控制服务检测到 AI 绘图已停止"
        }
        return message ?? "等待本机控制服务回写状态"
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
    public let job: AiGenerationJob?
    public let createdAt: String?
    public let reviewedAt: String?

    public var statusTitle: String {
        switch status {
        case "WAITING": "待审核"
        case "APPROVED": "已通过"
        case "REJECTED": "已拒绝"
        default: "审核中"
        }
    }

    public var categoryTitle: String {
        switch category {
        case "GENERAL": "全年龄"
        case "R18": "R18"
        default: "其他"
        }
    }
}

public struct AiReviewRejectRequest: Encodable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
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
    public let job: AiGenerationJob?
    public let createdAt: String?
    public let reviewedAt: String?

    public var statusTitle: String {
        switch status {
        case "WAITING": "待审核"
        case "APPROVED": "已通过"
        case "REJECTED": "已拒绝"
        default: "处理中"
        }
    }
}

public struct AiDeleteRejectRequest: Encodable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

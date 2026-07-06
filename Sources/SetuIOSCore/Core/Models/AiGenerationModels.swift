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

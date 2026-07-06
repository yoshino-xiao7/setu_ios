import Foundation

public struct GalleryUploadBatchSummary: Decodable, Identifiable, Sendable {
    public let batchId: Int
    public let userId: Int
    public let pidMode: String
    public let status: String
    public let title: String?
    public let author: String?
    public let r18: Bool?
    public let itemCount: Int
    public let uploadedCount: Int
    public let approvedCount: Int
    public let rejectedCount: Int
    public let publishedCount: Int
    public let sharedPublicPid: Int?
    public let tags: [String]?
    public let createdAt: String
    public let reviewedAt: String?
    public let publishedAt: String?

    public var id: Int { batchId }

    public var statusTitle: String {
        GalleryUploadStatus.title(for: status)
    }
}

public struct GalleryUploadBatchDetail: Decodable, Identifiable, Sendable {
    public let batchId: Int
    public let userId: Int
    public let clientRequestId: String?
    public let pidMode: String
    public let status: String
    public let title: String?
    public let author: String?
    public let r18: Bool?
    public let aiType: Int?
    public let tags: [String]?
    public let items: [GalleryUploadItem]
    public let createdAt: String
    public let reviewedAt: String?
    public let publishedAt: String?

    public var id: Int { batchId }

    public var statusTitle: String {
        GalleryUploadStatus.title(for: status)
    }
}

public struct GalleryUploadItem: Decodable, Identifiable, Sendable {
    public let submissionId: Int
    public let clientItemId: String?
    public let itemIndex: Int?
    public let pageIndex: Int?
    public let filename: String?
    public let uploadStatus: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let status: String
    public let title: String?
    public let author: String?
    public let r18: Bool?
    public let aiType: Int?
    public let tags: [String]?
    public let width: Int?
    public let height: Int?
    public let sizeBytes: Int?
    public let contentType: String?
    public let sha256: String?
    public let phash: String?
    public let rejectReason: String?
    public let publicPid: Int?
    public let publicP: Int?
    public let previewUrl: String?
    public let previewExpiresAt: String?

    public var id: Int { submissionId }
    public var statusTitle: String { GalleryUploadStatus.title(for: status) }
}

public enum GalleryUploadStatus {
    public static func title(for status: String) -> String {
        switch status {
        case "UPLOADING":
            return "上传中"
        case "WAITING_MANUAL_REVIEW":
            return "等待人工审核"
        case "APPROVED":
            return "已通过"
        case "PUBLISHING":
            return "发布中"
        case "PUBLISHED":
            return "已发布"
        case "REJECTED":
            return "已拒绝"
        case "REJECT_DELETE_FAILED":
            return "拒绝后清理失败"
        case "CANCELED":
            return "已取消"
        case "PUBLISH_FAILED":
            return "发布失败"
        case "EXPIRED":
            return "已过期"
        default:
            return status
        }
    }
}

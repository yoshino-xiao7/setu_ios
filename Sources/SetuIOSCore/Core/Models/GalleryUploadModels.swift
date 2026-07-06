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
    public let objectKey: String?
    public let uploadStatus: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let uploadUrl: String?
    public let uploadMethod: String?
    public let uploadHeaders: [String: String]?
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

public struct GalleryUploadDefaults: Encodable, Sendable {
    public let title: String?
    public let author: String?
    public let r18: Bool?
    public let aiType: Int?
    public let tags: [String]?

    public init(title: String?, author: String?, r18: Bool?, aiType: Int?, tags: [String]?) {
        self.title = title
        self.author = author
        self.r18 = r18
        self.aiType = aiType
        self.tags = tags
    }
}

public struct GalleryUploadInitItem: Encodable, Sendable {
    public let clientItemId: String
    public let filename: String
    public let contentType: String
    public let sizeBytes: Int
    public let sha256: String?
    public let pageIndex: Int?
    public let title: String?
    public let author: String?
    public let r18: Bool?
    public let aiType: Int?
    public let tags: [String]?

    public init(
        clientItemId: String,
        filename: String,
        contentType: String,
        sizeBytes: Int,
        sha256: String? = nil,
        pageIndex: Int? = nil,
        title: String? = nil,
        author: String? = nil,
        r18: Bool? = nil,
        aiType: Int? = nil,
        tags: [String]? = nil
    ) {
        self.clientItemId = clientItemId
        self.filename = filename
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.pageIndex = pageIndex
        self.title = title
        self.author = author
        self.r18 = r18
        self.aiType = aiType
        self.tags = tags
    }
}

public struct GalleryUploadInitRequest: Encodable, Sendable {
    public let clientRequestId: String?
    public let pidMode: String
    public let defaults: GalleryUploadDefaults?
    public let items: [GalleryUploadInitItem]

    public init(clientRequestId: String?, pidMode: String, defaults: GalleryUploadDefaults?, items: [GalleryUploadInitItem]) {
        self.clientRequestId = clientRequestId
        self.pidMode = pidMode
        self.defaults = defaults
        self.items = items
    }
}

public struct GalleryUploadPolicy: Decodable, Sendable {
    public let provider: String
    public let region: String
    public let bucket: String
    public let endpoint: String
    public let prefix: String
    public let expiresAt: String
    public let maxSizeBytes: Int
    public let allowedContentTypes: [String]
    public let uploadUrl: String?
    public let uploadMethod: String?
    public let uploadHeaders: [String: String]?
}

public struct GalleryUploadCredentials: Decodable, Sendable {
    public let accessKeyId: String
    public let accessKeySecret: String
    public let securityToken: String
    public let expiration: String
}

public struct GalleryUploadInitResponse: Decodable, Sendable {
    public let batchId: Int
    public let clientRequestId: String?
    public let pidMode: String
    public let status: String
    public let uploadPolicy: GalleryUploadPolicy
    public let items: [GalleryUploadItem]
    public let credentials: GalleryUploadCredentials?
}

public struct GalleryUploadItemStatusRequest: Encodable, Sendable {
    public let uploadStatus: String
    public let objectKey: String?
    public let sha256: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(uploadStatus: String, objectKey: String? = nil, sha256: String? = nil, errorCode: String? = nil, errorMessage: String? = nil) {
        self.uploadStatus = uploadStatus
        self.objectKey = objectKey
        self.sha256 = sha256
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

public struct GalleryUploadCompleteItem: Encodable, Sendable {
    public let submissionId: Int
    public let objectKey: String
    public let etag: String?
    public let sha256: String?

    public init(submissionId: Int, objectKey: String, etag: String? = nil, sha256: String? = nil) {
        self.submissionId = submissionId
        self.objectKey = objectKey
        self.etag = etag
        self.sha256 = sha256
    }
}

public struct GalleryUploadCompleteRequest: Encodable, Sendable {
    public let items: [GalleryUploadCompleteItem]?

    public init(items: [GalleryUploadCompleteItem]?) {
        self.items = items
    }
}

public struct GalleryUploadCompleteResponse: Decodable, Sendable {
    public let batchId: Int
    public let status: String
    public let items: [GalleryUploadItem]
    public let message: String?
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

public struct GalleryAdminApproveRequest: Encodable, Sendable {
    public let remark: String?
    public let publishNow: Bool
    public let r18: Bool?
    public let aiType: Int?
    public let normalizedTags: [String]?

    public init(remark: String?, publishNow: Bool, r18: Bool?, aiType: Int?, normalizedTags: [String]?) {
        self.remark = remark
        self.publishNow = publishNow
        self.r18 = r18
        self.aiType = aiType
        self.normalizedTags = normalizedTags
    }
}

public struct GalleryAdminRejectRequest: Encodable, Sendable {
    public let reason: String
    public let severity: String?

    public init(reason: String, severity: String?) {
        self.reason = reason
        self.severity = severity
    }
}

public struct GalleryAdminReviewResponse: Decodable, Sendable {
    public let batchId: Int
    public let status: String
    public let ossDeleted: Bool?
    public let rejectedCount: Int?
    public let items: [GalleryAdminReviewItem]?
}

public struct GalleryAdminReviewItem: Decodable, Identifiable, Sendable {
    public let submissionId: Int
    public let imageId: Int?
    public let pid: Int?
    public let p: Int?

    public var id: Int { submissionId }
}

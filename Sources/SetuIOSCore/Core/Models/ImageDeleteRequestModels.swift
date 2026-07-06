import Foundation

public struct ImageDeleteRequestItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int
    public let userEmail: String
    public let userNickname: String
    public let pid: Int
    public let p: Int
    public let reason: String
    public let status: Int
    public let statusText: String
    public let createdAt: String
    public let imageTitle: String?
    public let imageAuthor: String?
    public let thumbnailUrl: String?

    public var statusTitle: String {
        if !statusText.isEmpty {
            return statusText
        }
        switch status {
        case 0:
            return "待审核"
        case 1:
            return "已批准"
        case 2:
            return "已拒绝"
        default:
            return "未知"
        }
    }
}

public struct ImageDeleteRequestDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int
    public let userEmail: String
    public let userNickname: String
    public let reason: String
    public let status: Int
    public let statusText: String
    public let createdAt: String
    public let pid: Int
    public let p: Int
    public let title: String?
    public let author: String?
    public let uid: Int?
    public let r18: Int?
    public let width: Int?
    public let height: Int?
    public let ext: String?
    public let aiType: Int?
    public let uploadDate: Int?
    public let urlOriginal: String?
    public let tags: [String]?
    public let adminId: Int?
    public let adminEmail: String?
    public let adminRemark: String?
    public let reviewedAt: String?

    public var statusTitle: String {
        if !statusText.isEmpty {
            return statusText
        }
        switch status {
        case 0:
            return "待审核"
        case 1:
            return "已批准"
        case 2:
            return "已拒绝"
        default:
            return "未知"
        }
    }
}

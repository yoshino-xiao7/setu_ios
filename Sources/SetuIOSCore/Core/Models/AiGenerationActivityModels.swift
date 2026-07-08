import ActivityKit
import Foundation

public struct AiGenerationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let status: String
        public let statusTitle: String
        public let detail: String
        public let updatedAt: Date

        public init(status: String, statusTitle: String, detail: String, updatedAt: Date) {
            self.status = status
            self.statusTitle = statusTitle
            self.detail = detail
            self.updatedAt = updatedAt
        }
    }

    public let jobID: Int
    public let title: String

    public init(jobID: Int, title: String) {
        self.jobID = jobID
        self.title = title
    }
}

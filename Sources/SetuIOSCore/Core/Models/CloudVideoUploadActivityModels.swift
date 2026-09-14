import Foundation

#if os(iOS)
import ActivityKit

public struct CloudVideoUploadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let title: String
        public let detail: String
        public let percent: Int
        public let queuedCount: Int

        public init(title: String, detail: String, percent: Int, queuedCount: Int) {
            self.title = title
            self.detail = detail
            self.percent = percent
            self.queuedCount = queuedCount
        }
    }

    public let queueOwner: String

    public init(queueOwner: String = "admin") {
        self.queueOwner = queueOwner
    }
}
#endif

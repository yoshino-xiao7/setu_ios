import Foundation

public struct DownloadSignRequest: Encodable, Sendable {
    public let url: String
    public let filename: String

    public init(url: String, filename: String) {
        self.url = url
        self.filename = filename
    }
}

public struct DownloadSignResponse: Decodable, Sendable {
    public let downloadUrl: String
}

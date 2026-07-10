import Foundation

public struct AppleAuthorizationPayload: Encodable, Sendable {
    public let identityToken: String
    public let nonce: String

    public init(identityToken: String, nonce: String) {
        self.identityToken = identityToken
        self.nonce = nonce
    }
}

public struct AppleBindingStatus: Decodable, Sendable {
    public let linked: Bool
    public let email: String?
}

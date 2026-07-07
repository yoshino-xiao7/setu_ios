import CryptoKit
import Foundation

public struct AuthSigner: Sendable {
    private let keychain: KeychainStoring
    private let secretKey = "signSecret"

    public init(keychain: KeychainStoring) {
        self.keychain = keychain
    }

    public func persistSignSecret(_ value: String) throws {
        try keychain.setString(value, for: secretKey)
    }

    public func clearSignSecret() throws {
        try keychain.remove(secretKey)
    }

    public func hasSignSecret() -> Bool {
        guard let secret = try? keychain.string(for: secretKey) else {
            return false
        }
        return !secret.isEmpty
    }

    public func signedHeaders(method: String, path: String, date: Date = Date()) throws -> [String: String] {
        guard let secret = try keychain.string(for: secretKey), !secret.isEmpty else {
            return [:]
        }

        let timestamp = String(Int64(date.timeIntervalSince1970 * 1000))
        let nonce = Self.makeNonce()
        let message = "\(timestamp):\(nonce):\(method.uppercased()):\(path)"
        return [
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Signature": Self.hmac(message: message, secret: secret),
        ]
    }

    public static func hmac(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

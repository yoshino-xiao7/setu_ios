import AuthenticationServices
import CryptoKit
import Foundation
import Security

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AppleAuthorizationCredential: Sendable {
    let identityToken: String
    let nonce: String
}

@MainActor
final class AppleAuthorizationService: NSObject {
    private var continuation: CheckedContinuation<AppleAuthorizationCredential, Error>?
    private var rawNonce: String?

    func authorize() async throws -> AppleAuthorizationCredential {
        let nonce = try Self.makeNonce()
        rawNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    static func userMessage(for error: Error) -> String {
        guard let authorizationError = error as? ASAuthorizationError else {
            return error.localizedDescription
        }
        switch authorizationError.code {
        case .canceled:
            return "你已取消 Apple 登录。"
        case .notHandled, .notInteractive:
            return "当前环境无法显示 Apple 登录，请回到前台后重试。"
        case .failed, .invalidResponse, .unknown:
            return "Apple 身份验证失败，请稍后重试。"
        default:
            return authorizationError.localizedDescription
        }
    }

    private static func makeNonce(length: Int = 32) throws -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AppleAuthorizationError.nonceGenerationFailed
            }
            for byte in bytes where remaining > 0 && byte < characters.count * (256 / characters.count) {
                result.append(characters[Int(byte) % characters.count])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleAuthorizationService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = rawNonce else {
                finish(.failure(AppleAuthorizationError.invalidCredential))
                return
            }
            finish(.success(AppleAuthorizationCredential(identityToken: identityToken, nonce: nonce)))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }

    private func finish(_ result: Result<AppleAuthorizationCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        rawNonce = nil
    }
}

extension AppleAuthorizationService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

enum AppleAuthorizationError: LocalizedError {
    case nonceGenerationFailed
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .nonceGenerationFailed:
            "无法创建安全的 Apple 登录请求，请重试。"
        case .invalidCredential:
            "Apple 返回的身份凭据无效，请重新授权。"
        }
    }
}

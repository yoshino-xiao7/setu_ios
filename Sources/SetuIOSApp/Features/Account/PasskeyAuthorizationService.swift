import AuthenticationServices
import Foundation
import SetuIOSCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class PasskeyAuthorizationService: NSObject {
    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationCredential, Error>?
    private var assertionContinuation: CheckedContinuation<PasskeyAssertionCredential, Error>?

    func createCredential(options: PasskeyPublicKeyOptions) async throws -> PasskeyRegistrationCredential {
        guard let rpID = options.relyingPartyID, !rpID.isEmpty else {
            throw PasskeyAuthorizationError.missingRelyingPartyID
        }
        guard let user = options.user else {
            throw PasskeyAuthorizationError.missingUser
        }
        let challenge = try Data(base64URLEncoded: options.challenge)
        let userID = try Data(base64URLEncoded: user.id)

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: user.name,
            userID: userID
        )
        request.displayName = user.displayName
        request.userVerificationPreference = .required

        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func assertCredential(options: PasskeyPublicKeyOptions) async throws -> PasskeyAssertionCredential {
        guard let rpID = options.relyingPartyID, !rpID.isEmpty else {
            throw PasskeyAuthorizationError.missingRelyingPartyID
        }
        let challenge = try Data(base64URLEncoded: options.challenge)
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required

        return try await withCheckedThrowingContinuation { continuation in
            assertionContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    static func userMessage(for error: Error) -> String {
        #if targetEnvironment(simulator)
        if (error as NSError).domain == ASAuthorizationError.errorDomain,
           let code = ASAuthorizationError.Code(rawValue: (error as NSError).code),
           code == .notHandled || code == .unknown || code == .failed {
            return "当前设备暂时无法使用通行密钥，请改用 Apple 或密码登录。"
        }
        #endif

        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                return "你已取消通行密钥操作。"
            case .unknown:
                return "通行密钥验证异常，请稍后重试。"
            case .failed:
                return "通行密钥验证失败，请确认设备解锁验证可用后重试。"
            case .invalidResponse:
                return "通行密钥返回了无效响应。"
            case .notHandled:
                return "当前设备暂时无法使用通行密钥，请改用 Apple 或密码登录。"
            case .matchedExcludedCredential:
                return "该通行密钥已存在或不可重复使用，请先删除后重试。"
            case .notInteractive:
                return "暂时无法打开通行密钥验证，请回到应用后重试。"
            case .deviceNotConfiguredForPasskeyCreation:
                return "当前设备还未配置通行密钥，请先在系统设置中开启密码、Face ID 或 Touch ID。"
            case .credentialImport, .credentialExport:
                return "当前系统不支持这项通行密钥凭据操作。"
            case .preferSignInWithApple:
                return "请改用 Apple 登录，或使用密码登录。"
            @unknown default:
                return "通行密钥暂时无法使用，请稍后重试。"
            }
        }

        if let passkeyError = error as? PasskeyAuthorizationError {
            switch passkeyError {
            case .invalidBase64URL:
                return "通行密钥验证信息已失效，请重新尝试。"
            default:
                return "暂时无法使用通行密钥，请稍后重试，或改用其他登录方式。"
            }
        }

        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain {
            return "通行密钥暂时无法使用，请稍后重试。"
        }

        return "通行密钥操作未完成，请稍后重试。"
    }
}

extension PasskeyAuthorizationService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            switch authorization.credential {
            case let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration:
                registrationContinuation?.resume(returning: PasskeyRegistrationCredential(
                    id: credential.credentialID.base64URLEncodedString(),
                    rawId: credential.credentialID.base64URLEncodedString(),
                    response: PasskeyAttestationResponse(
                        clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                        attestationObject: credential.rawAttestationObject?.base64URLEncodedString() ?? "",
                        transports: ["internal"]
                    )
                ))
                registrationContinuation = nil
            case let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion:
                assertionContinuation?.resume(returning: PasskeyAssertionCredential(
                    id: credential.credentialID.base64URLEncodedString(),
                    rawId: credential.credentialID.base64URLEncodedString(),
                    response: PasskeyAssertionResponse(
                        authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
                        clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                        signature: credential.signature.base64URLEncodedString(),
                        userHandle: credential.userID.base64URLEncodedString()
                    )
                ))
                assertionContinuation = nil
            default:
                let error = PasskeyAuthorizationError.unsupportedCredential
                registrationContinuation?.resume(throwing: error)
                assertionContinuation?.resume(throwing: error)
                registrationContinuation = nil
                assertionContinuation = nil
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            registrationContinuation?.resume(throwing: error)
            assertionContinuation?.resume(throwing: error)
            registrationContinuation = nil
            assertionContinuation = nil
        }
    }
}

extension PasskeyAuthorizationService: ASAuthorizationControllerPresentationContextProviding {
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

enum PasskeyAuthorizationError: LocalizedError {
    case missingRelyingPartyID
    case missingUser
    case invalidBase64URL
    case unsupportedCredential

    var errorDescription: String? {
        switch self {
        case .missingRelyingPartyID:
            "暂时无法开始通行密钥操作。"
        case .missingUser:
            "暂时无法确认通行密钥账号。"
        case .invalidBase64URL:
            "通行密钥验证信息无效。"
        case .unsupportedCredential:
            "系统返回了暂不支持的通行密钥凭据。"
        }
    }
}

private extension Data {
    init(base64URLEncoded value: String) throws {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: base64) else {
            throw PasskeyAuthorizationError.invalidBase64URL
        }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

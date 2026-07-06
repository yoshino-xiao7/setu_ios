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
            "Passkey RP ID 缺失，请检查后端 WebAuthn 配置。"
        case .missingUser:
            "Passkey 用户信息缺失。"
        case .invalidBase64URL:
            "Passkey challenge 编码无效。"
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

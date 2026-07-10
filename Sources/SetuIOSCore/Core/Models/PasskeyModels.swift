import Foundation

public struct PasskeyItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let nickname: String?
    public let transports: [String]?
    public let backupEligible: Bool?
    public let backupState: Bool?
    public let discoverable: Bool?
    public let lastUsedAt: String?
    public let createdAt: String?
    public let updatedAt: String?

    public var displayName: String {
        if let nickname, !nickname.isEmpty {
            return nickname
        }
        return "通行密钥 #\(id)"
    }
}

public struct PasskeyListResponse: Decodable, Sendable {
    public let list: [PasskeyItem]

    public init(from decoder: Decoder) throws {
        if let array = try? [PasskeyItem](from: decoder) {
            list = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
            if let values = try container.decodeIfPresent([PasskeyItem].self, forKey: key) {
                list = values
                return
            }
        }
        list = []
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case list
        case items
        case records
        case rows
        case content
    }
}

public struct PasskeyOptionsResponse: Decodable, Sendable {
    public let challengeId: String
    public let publicKey: PasskeyPublicKeyEnvelope
}

public struct PasskeyPublicKeyEnvelope: Decodable, Sendable {
    public let publicKey: PasskeyPublicKeyOptions

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode(PasskeyPublicKeyOptions.self, forKey: .publicKey) {
            publicKey = nested
        } else {
            publicKey = try PasskeyPublicKeyOptions(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case publicKey
    }
}

public struct PasskeyPublicKeyOptions: Decodable, Sendable {
    public let challenge: String
    public let rpId: String?
    public let rp: PasskeyRelyingParty?
    public let user: PasskeyUser?
    public let timeout: Int?
    public let userVerification: String?
    public let excludeCredentials: [PasskeyCredentialDescriptor]?
    public let allowCredentials: [PasskeyCredentialDescriptor]?

    public var relyingPartyID: String? {
        rpId ?? rp?.id
    }
}

public struct PasskeyRelyingParty: Decodable, Sendable {
    public let id: String?
    public let name: String?
}

public struct PasskeyUser: Decodable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
}

public struct PasskeyCredentialDescriptor: Decodable, Sendable {
    public let id: String
    public let type: String?
    public let transports: [String]?
}

public struct PasskeyRegistrationStartRequest: Encodable, Sendable {
    public let nickname: String

    public init(nickname: String) {
        self.nickname = nickname
    }
}

public struct PasskeyRegistrationFinishRequest: Encodable, Sendable {
    public let challengeId: String
    public let nickname: String
    public let credential: PasskeyRegistrationCredential

    public init(challengeId: String, nickname: String, credential: PasskeyRegistrationCredential) {
        self.challengeId = challengeId
        self.nickname = nickname
        self.credential = credential
    }
}

public struct PasskeyAuthenticationFinishRequest: Encodable, Sendable {
    public let challengeId: String
    public let credential: PasskeyAssertionCredential

    public init(challengeId: String, credential: PasskeyAssertionCredential) {
        self.challengeId = challengeId
        self.credential = credential
    }
}

public struct PasskeyRegistrationCredential: Encodable, Sendable {
    public let id: String
    public let rawId: String
    public let type: String
    public let clientExtensionResults: [String: Bool]
    public let response: PasskeyAttestationResponse

    public init(
        id: String,
        rawId: String,
        type: String = "public-key",
        clientExtensionResults: [String: Bool] = [:],
        response: PasskeyAttestationResponse
    ) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.clientExtensionResults = clientExtensionResults
        self.response = response
    }
}

public struct PasskeyAttestationResponse: Encodable, Sendable {
    public let clientDataJSON: String
    public let attestationObject: String
    public let transports: [String]?

    public init(clientDataJSON: String, attestationObject: String, transports: [String]? = nil) {
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
        self.transports = transports
    }
}

public struct PasskeyAssertionCredential: Encodable, Sendable {
    public let id: String
    public let rawId: String
    public let type: String
    public let clientExtensionResults: [String: Bool]
    public let response: PasskeyAssertionResponse

    public init(
        id: String,
        rawId: String,
        type: String = "public-key",
        clientExtensionResults: [String: Bool] = [:],
        response: PasskeyAssertionResponse
    ) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.clientExtensionResults = clientExtensionResults
        self.response = response
    }
}

public struct PasskeyAssertionResponse: Encodable, Sendable {
    public let authenticatorData: String
    public let clientDataJSON: String
    public let signature: String
    public let userHandle: String?

    public init(authenticatorData: String, clientDataJSON: String, signature: String, userHandle: String?) {
        self.authenticatorData = authenticatorData
        self.clientDataJSON = clientDataJSON
        self.signature = signature
        self.userHandle = userHandle
    }
}

import Foundation
import Security

/// The account behind a ChatGPT sign-in, from an ID token checked the way the
/// documentation asks: RS256 signature against OpenAI's published JWKS, then issuer,
/// audience (the issued client ID), expiry and the nonce of this attempt.
nonisolated struct ChatGPTIdentity: Codable, Equatable, Sendable {
    /// The validated `sub`: the account identity.
    let subject: String
    let email: String?
    let name: String?
}

nonisolated enum ChatGPTIDToken {
    enum Failure: Error, Equatable {
        case malformed
        case unsupportedAlgorithm
        case unknownKey
        case badSignature
        case wrongIssuer
        case wrongAudience
        case expired
        case wrongNonce
    }

    struct JWK: Decodable, Sendable {
        let kid: String?
        let kty: String
        let alg: String?
        let n: String?
        let e: String?
    }

    struct JWKS: Decodable, Sendable { let keys: [JWK] }

    private struct Header: Decodable { let alg: String; let kid: String? }

    private struct Claims: Decodable {
        let iss: String
        let sub: String
        let aud: Audience
        let exp: Double
        let nonce: String?
        let email: String?
        let name: String?
    }

    /// `aud` may be a string or an array of strings.
    private enum Audience: Decodable {
        case one(String), many([String])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .one(value) } else { self = .many(try container.decode([String].self)) }
        }
        func contains(_ value: String) -> Bool {
            switch self { case .one(let one): one == value; case .many(let many): many.contains(value) }
        }
    }

    static func validate(_ token: String, keys: JWKS, clientID: String, nonce: String, now: Date = Date(), leeway: TimeInterval = 120) throws -> ChatGPTIdentity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: String(parts[0])),
              let claimsData = Data(base64URLEncoded: String(parts[1])),
              let signature = Data(base64URLEncoded: String(parts[2])),
              let header = try? JSONDecoder().decode(Header.self, from: headerData),
              let claims = try? JSONDecoder().decode(Claims.self, from: claimsData) else { throw Failure.malformed }
        guard header.alg == "RS256" else { throw Failure.unsupportedAlgorithm }
        let candidates = keys.keys.filter { $0.kty == "RSA" && (header.kid == nil || $0.kid == header.kid) }
        guard !candidates.isEmpty else { throw Failure.unknownKey }
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        guard candidates.contains(where: { key in
            guard let publicKey = try? rsaPublicKey(key) else { return false }
            return SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil)
        }) else { throw Failure.badSignature }
        guard claims.iss == ChatGPTOAuth.issuer else { throw Failure.wrongIssuer }
        guard claims.aud.contains(clientID) else { throw Failure.wrongAudience }
        guard Date(timeIntervalSince1970: claims.exp).addingTimeInterval(leeway) > now else { throw Failure.expired }
        guard claims.nonce == nonce else { throw Failure.wrongNonce }
        return ChatGPTIdentity(subject: claims.sub, email: claims.email, name: claims.name)
    }

    /// Reads identity claims from a token already validated once, such as a stored one.
    static func unverifiedIdentity(_ token: String) -> ChatGPTIdentity? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONDecoder().decode(Claims.self, from: data) else { return nil }
        return ChatGPTIdentity(subject: claims.sub, email: claims.email, name: claims.name)
    }

    /// An RSA public key from a JWK's modulus and exponent, as a PKCS#1 DER structure.
    static func rsaPublicKey(_ jwk: JWK) throws -> SecKey {
        guard let n = jwk.n.flatMap(Data.init(base64URLEncoded:)), let e = jwk.e.flatMap(Data.init(base64URLEncoded:)) else { throw Failure.unknownKey }
        let der = derSequence([derInteger(n), derInteger(e)])
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: n.count * 8,
        ]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) else { throw Failure.unknownKey }
        return key
    }

    private static func derInteger(_ bytes: Data) -> Data {
        var value = Data(bytes.drop { $0 == 0 })
        if value.isEmpty { value = Data([0]) }
        if value[value.startIndex] & 0x80 != 0 { value.insert(0, at: value.startIndex) }
        return Data([0x02]) + derLength(value.count) + value
    }

    private static func derSequence(_ items: [Data]) -> Data {
        let body = items.reduce(Data(), +)
        return Data([0x30]) + derLength(body.count) + body
    }

    private static func derLength(_ length: Int) -> Data {
        guard length >= 0x80 else { return Data([UInt8(length)]) }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 { bytes.insert(UInt8(remaining & 0xFF), at: 0); remaining >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

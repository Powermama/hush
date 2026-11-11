import CryptoKit
import Foundation
import HushProvenance
import Security

struct InstallationSigningIdentity: Sendable {
    let signer: any ProvenanceSigner
    let keyKind: InstallationRegistration.KeyKind
    let fingerprint: String
}

final class InstallationKeyStore: Sendable {
    private let service = "com.decentralfreedom.hush.provenance"
    private let account = "installation-signing-key-v1"

    func loadOrCreate() throws -> InstallationSigningIdentity {
        if let stored = try read(), let identity = try? restore(stored) {
            return identity
        }

        let created: StoredKey
        if SecureEnclave.isAvailable,
           let secureKey = try? SecureEnclave.P256.Signing.PrivateKey() {
            created = StoredKey(kind: .secureEnclave, data: secureKey.dataRepresentation)
        } else {
            let softwareKey = SoftwareP256Signer()
            created = StoredKey(kind: .keychain, data: softwareKey.rawRepresentation)
        }
        try write(created)
        return try restore(created)
    }

    private func restore(_ stored: StoredKey) throws -> InstallationSigningIdentity {
        let signer: any ProvenanceSigner
        let keyKind: InstallationRegistration.KeyKind
        switch stored.kind {
        case .secureEnclave:
            signer = try SecureEnclaveP256Signer(dataRepresentation: stored.data)
            keyKind = .secureEnclave
        case .keychain:
            signer = try SoftwareP256Signer(rawRepresentation: stored.data)
            keyKind = .keychain
        }
        let publicKey = try signer.publicKeyRawRepresentation
        return InstallationSigningIdentity(
            signer: signer,
            keyKind: keyKind,
            fingerprint: Data(SHA256.hash(data: publicKey)).base64URLString
        )
    }

    private func read() throws -> StoredKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyStoreError.keychain(status)
        }
        return try JSONDecoder().decode(StoredKey.self, from: data)
    }

    private func write(_ value: StoredKey) throws {
        let data = try JSONEncoder().encode(value)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeyStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeyStoreError.keychain(addStatus) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private struct SecureEnclaveP256Signer: ProvenanceSigner, Sendable {
    private let key: SecureEnclave.P256.Signing.PrivateKey

    init(dataRepresentation: Data) throws {
        key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
    }

    var publicKeyRawRepresentation: Data { key.publicKey.x963Representation }

    func signature(for data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }
}

private struct StoredKey: Codable {
    enum Kind: String, Codable {
        case secureEnclave
        case keychain
    }

    let kind: Kind
    let data: Data
}

private enum KeyStoreError: Error {
    case keychain(OSStatus)
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

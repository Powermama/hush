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

    /// In the data protection keychain, so macOS never asks for access (see KeychainItem).
    private var item: KeychainItem { KeychainItem(service: service, account: account) }

    private func read() throws -> StoredKey? {
        let data: Data?
        do { data = try item.read() } catch let error as KeychainError { throw KeyStoreError.keychain(error.status) }
        guard let data else { return nil }
        return try JSONDecoder().decode(StoredKey.self, from: data)
    }

    private func write(_ value: StoredKey) throws {
        let data = try JSONEncoder().encode(value)
        do { try item.write(data) } catch let error as KeychainError { throw KeyStoreError.keychain(error.status) }
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

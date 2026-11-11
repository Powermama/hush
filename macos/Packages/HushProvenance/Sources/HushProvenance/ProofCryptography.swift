import CryptoKit
import Foundation

public protocol ProvenanceSigner: Sendable {
    var publicKeyRawRepresentation: Data { get throws }
    func signature(for data: Data) throws -> Data
}

public struct SoftwareP256Signer: ProvenanceSigner, Sendable {
    private let key: P256.Signing.PrivateKey

    public init() {
        key = P256.Signing.PrivateKey()
    }

    public init(rawRepresentation: Data) throws {
        key = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    public var rawRepresentation: Data { key.rawRepresentation }
    public var publicKeyRawRepresentation: Data { key.publicKey.x963Representation }

    public func signature(for data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }
}

public struct PreparedProof: Sendable {
    public let proofId: String
    public let expiresAt: String
    public let manifest: Data
    public let commitment: String
    public let ciphertext: Data
    public let ciphertextSha256: String
    public let decryptionKey: String
    public let assuranceLevel: Int

    public var ciphertextSize: Int { ciphertext.count }

    public func privateURL(baseURL: URL, slug: String) -> URL? {
        var components = URLComponents(
            url: baseURL.appending(path: "p").appending(path: slug),
            resolvingAgainstBaseURL: false
        )
        components?.fragment = "k=\(decryptionKey)"
        return components?.url
    }
}

public enum ProofPreparer {
    public static func prepare(
        manifest: ProofManifest,
        signer: any ProvenanceSigner,
        assuranceLevel: Int,
        encryptionKey: SymmetricKey = SymmetricKey(size: .bits256),
        nonce: AES.GCM.Nonce? = nil
    ) throws -> PreparedProof {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        let package = EncryptedProofPackage(
            manifest: manifestData.base64URLString,
            manifestSignature: try signer.signature(for: manifestData).base64URLString,
            installationPublicKey: try signer.publicKeyRawRepresentation.base64URLString
        )
        let packageData = try encoder.encode(package)
        let sealed = try nonce.map {
            try AES.GCM.seal(packageData, using: encryptionKey, nonce: $0)
        } ?? AES.GCM.seal(packageData, using: encryptionKey)
        guard let ciphertext = sealed.combined else {
            throw ProofPreparationError.missingCombinedCiphertext
        }
        let keyData = encryptionKey.withUnsafeBytes { Data($0) }
        return PreparedProof(
            proofId: manifest.proofId,
            expiresAt: manifest.expiresAt,
            manifest: manifestData,
            commitment: Data(SHA256.hash(data: manifestData)).base64URLString,
            ciphertext: ciphertext,
            ciphertextSha256: Data(SHA256.hash(data: ciphertext)).base64URLString,
            decryptionKey: keyData.base64URLString,
            assuranceLevel: assuranceLevel
        )
    }
}

public enum ProofAudioHasher {
    public static func hash(samples: [Float], sampleRate: Int) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("hush-audio-f32le-v1\n\(sampleRate)\n\(samples.count)\n".utf8))
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { hasher.update(bufferPointer: $0) }
        }
        return Data(hasher.finalize()).base64URLString
    }
}

public enum AIEditShare {
    public static func calculate(original: String, refined: String) -> Double {
        let source = tokens(in: original)
        let output = tokens(in: refined)
        guard !source.isEmpty || !output.isEmpty else { return 0 }
        let removed = output.difference(from: source).removals.count
        let unchanged = max(0, source.count - removed)
        return min(1, max(0, 1 - Double(unchanged) / Double(max(source.count, output.count))))
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private struct EncryptedProofPackage: Encodable {
    let version = 1
    let manifest: String
    let manifestSignature: String
    let installationPublicKey: String
    let signatureAlgorithm = "ES256"
}

public enum ProofPreparationError: Error {
    case missingCombinedCiphertext
}

extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

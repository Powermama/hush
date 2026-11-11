import Foundation
import OpenAPIRuntime

public struct InstallationRegistration: Sendable {
    public enum KeyKind: Sendable {
        case secureEnclave
        case keychain
    }

    public let id: String
    public let fingerprint: String

    public init(id: String, fingerprint: String) {
        self.id = id
        self.fingerprint = fingerprint
    }
}

public struct PublishedProof: Sendable {
    public let id: String
    public let slug: String
    public let privateURL: URL
    public let revocationSecret: String
    public let receiptSignature: String
}

public protocol ProofUploading: Sendable {
    func upload(_ data: Data, to url: URL, headers: [String: String]) async throws
}

public struct URLSessionProofUploader: ProofUploading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(_ data: Data, to url: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ProofPublisherError.uploadFailed
        }
    }
}

public actor ProofPublisher {
    private let api: any APIProtocol
    private let uploader: any ProofUploading
    private let proofURLBaseURL: URL

    public init(
        api: any APIProtocol,
        proofURLBaseURL: URL,
        uploader: any ProofUploading = URLSessionProofUploader()
    ) {
        self.api = api
        self.proofURLBaseURL = proofURLBaseURL
        self.uploader = uploader
    }

    public func enroll(
        signer: any ProvenanceSigner,
        keyKind: InstallationRegistration.KeyKind,
        appVersion: String,
        platformVersion: String
    ) async throws -> InstallationRegistration {
        let challengeOutput: Operations.createEnrollmentChallenge.Output
        do {
            challengeOutput = try await api.createEnrollmentChallenge()
        } catch {
            throw ProofPublisherError.registrationUnavailable(
                details: "Enrollment challenge transport failed: \(error)"
            )
        }
        guard case let .ok(challengeResponse) = challengeOutput else {
            if case let .undocumented(statusCode, _) = challengeOutput {
                throw ProofPublisherError.registrationUnavailable(
                    details: "Enrollment challenge returned HTTP \(statusCode)."
                )
            }
            throw ProofPublisherError.registrationUnavailable(
                details: "Enrollment challenge returned an unexpected response."
            )
        }
        let challenge = try challengeResponse.body.json
        let publicKey = try signer.publicKeyRawRepresentation.base64URLString
        let signature = try signer.signature(for: Data(
            canonicalEnrollmentRequest(
                challengeId: challenge.id,
                publicKey: publicKey,
                nonce: challenge.nonce
            ).utf8
        )).base64URLString
        let generatedKeyKind: Operations.enrollInstallation.Input.Body.jsonPayload.keyKindPayload =
            keyKind == .secureEnclave ? .secure_enclave : .keychain
        let enrollmentOutput: Operations.enrollInstallation.Output
        do {
            enrollmentOutput = try await api.enrollInstallation(body: .json(.init(
                challengeId: challenge.id,
                publicKey: publicKey,
                signature: signature,
                keyKind: generatedKeyKind,
                appVersion: appVersion,
                platformVersion: platformVersion
            )))
        } catch {
            throw ProofPublisherError.registrationUnavailable(
                details: "Installation enrollment transport failed: \(error)"
            )
        }
        switch enrollmentOutput {
        case let .created(response):
            let body = try response.body.json
            return InstallationRegistration(id: body.id, fingerprint: body.fingerprint)
        case let .badRequest(response):
            let error = try response.body.json.error
            throw ProofPublisherError.registrationRejected(
                code: error.code,
                message: error.message
            )
        case let .unauthorized(response):
            let error = try response.body.json.error
            throw ProofPublisherError.registrationRejected(
                code: error.code,
                message: error.message
            )
        case let .notFound(response):
            let error = try response.body.json.error
            throw ProofPublisherError.registrationRejected(
                code: error.code,
                message: error.message
            )
        case let .conflict(response):
            let error = try response.body.json.error
            throw ProofPublisherError.registrationRejected(
                code: error.code,
                message: error.message
            )
        case let .unprocessableContent(response):
            let error = try response.body.json.error
            throw ProofPublisherError.registrationRejected(
                code: error.code,
                message: error.message
            )
        case let .undocumented(statusCode, _):
            throw ProofPublisherError.registrationUnavailable(
                details: "Installation enrollment returned HTTP \(statusCode)."
            )
        }
    }

    public func publish(
        _ proof: PreparedProof,
        installationID: String,
        signer: any ProvenanceSigner
    ) async throws -> PublishedProof {
        let challengeOutput: Operations.createPublicationChallenge.Output
        do {
            challengeOutput = try await api.createPublicationChallenge(body: .json(.init(
                installationId: installationID
            )))
        } catch {
            throw ProofPublisherError.publicationUnavailable(
                details: "Publication challenge transport failed: \(error)"
            )
        }
        let challenge: Operations.createPublicationChallenge.Output.Ok.Body.jsonPayload
        switch challengeOutput {
        case let .ok(response):
            challenge = try response.body.json
        case let .notFound(response):
            let error = try response.body.json.error
            if error.code == "installation_not_found" {
                throw ProofPublisherError.installationNotFound
            }
            throw ProofPublisherError.publicationRejected(
                code: error.code,
                message: error.message
            )
        case let .badRequest(response):
            let error = try response.body.json.error
            throw ProofPublisherError.publicationRejected(
                code: error.code,
                message: error.message
            )
        case let .unauthorized(response):
            let error = try response.body.json.error
            throw ProofPublisherError.publicationRejected(
                code: error.code,
                message: error.message
            )
        case let .conflict(response):
            let error = try response.body.json.error
            throw ProofPublisherError.publicationRejected(
                code: error.code,
                message: error.message
            )
        case let .unprocessableContent(response):
            let error = try response.body.json.error
            throw ProofPublisherError.publicationRejected(
                code: error.code,
                message: error.message
            )
        case let .undocumented(statusCode, _):
            throw ProofPublisherError.publicationUnavailable(
                details: "Publication challenge returned HTTP \(statusCode)."
            )
        }
        let expiry = try parseDate(proof.expiresAt)
        let canonical = try canonicalProofRequest(
            proof: proof,
            challengeID: challenge.id,
            challengeNonce: challenge.nonce,
            installationID: installationID,
            expiry: expiry
        )
        let signature = try signer.signature(for: Data(canonical.utf8)).base64URLString
        let reservation = try await api.reserveProof(body: .json(.init(
            proofId: proof.proofId,
            challengeId: challenge.id,
            installationId: installationID,
            commitment: proof.commitment,
            ciphertextSha256: proof.ciphertextSha256,
            ciphertextSize: proof.ciphertextSize,
            expiresAt: expiry,
            assuranceLevel: proof.assuranceLevel,
            signature: signature
        ))).created.body.json
        guard reservation.id == proof.proofId,
              let uploadURL = URL(string: reservation.uploadUrl) else {
            throw ProofPublisherError.invalidReservation
        }
        try await uploader.upload(
            proof.ciphertext,
            to: uploadURL,
            headers: reservation.uploadHeaders.additionalProperties
        )
        let completed = try await api.completeProof(
            path: .init(id: reservation.id),
            body: .json(.init(completionToken: reservation.completionToken))
        ).ok.body.json
        guard completed.receipt.proofId == proof.proofId,
              completed.receipt.slug == reservation.slug,
              completed.receipt.commitment == proof.commitment,
              completed.receipt.ciphertextSha256 == proof.ciphertextSha256,
              completed.receipt.ciphertextSize == proof.ciphertextSize,
              let proofURL = URL(string: completed.proofUrl),
              isTrustedProofURL(proofURL),
              var components = URLComponents(url: proofURL, resolvingAgainstBaseURL: false) else {
            throw ProofPublisherError.invalidReceipt
        }
        components.fragment = "k=\(proof.decryptionKey)"
        guard let privateURL = components.url else {
            throw ProofPublisherError.invalidReceipt
        }
        return PublishedProof(
            id: reservation.id,
            slug: reservation.slug,
            privateURL: privateURL,
            revocationSecret: reservation.revocationSecret,
            receiptSignature: completed.receiptSignature
        )
    }

    private func isTrustedProofURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == proofURLBaseURL.scheme?.lowercased(),
              url.host?.lowercased() == proofURLBaseURL.host?.lowercased(),
              effectivePort(url) == effectivePort(proofURLBaseURL),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return false
        }
        let code = url.lastPathComponent
        guard code.utf8.count == 6,
              code.utf8.allSatisfy({ byte in
                  (65...90).contains(byte)
                      || (97...122).contains(byte)
                      || (48...57).contains(byte)
                      || byte == 45
                      || byte == 95
              }) else {
            return false
        }
        return url == proofURLBaseURL.appending(path: code)
    }

    private func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private func parseDate(_ value: String) throws -> Date {
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }
        throw ProofPublisherError.invalidExpiry
    }
}

public enum ProofPublisherError: LocalizedError, Sendable, Equatable {
    case registrationUnavailable(details: String)
    case registrationRejected(code: String, message: String)
    case installationNotFound
    case publicationUnavailable(details: String)
    case publicationRejected(code: String, message: String)
    case invalidExpiry
    case invalidReservation
    case invalidReceipt
    case uploadFailed

    public var errorDescription: String? {
        switch self {
        case .registrationUnavailable:
            "The Hush verification service is currently unavailable. Try again later."
        case let .registrationRejected(_, message):
            "Hush could not register this Mac. \(message)"
        case .installationNotFound:
            "This Mac is not registered with the Hush verification service."
        case .publicationUnavailable:
            "The Hush verification service is currently unavailable. Try again later."
        case let .publicationRejected(_, message):
            "Hush could not secure this message. \(message)"
        case .invalidExpiry: "The proof expiry is invalid."
        case .invalidReservation: "The proof reservation did not match the signed message."
        case .invalidReceipt: "The Hush receipt did not match the encrypted proof."
        case .uploadFailed: "The encrypted proof could not be uploaded."
        }
    }
}

private func canonicalEnrollmentRequest(
    challengeId: String,
    publicKey: String,
    nonce: String
) -> String {
    ["hush-enroll-v1", challengeId, nonce, publicKey].joined(separator: "\n")
}

func canonicalProofRequest(
    proof: PreparedProof,
    challengeID: String,
    challengeNonce: String,
    installationID: String,
    expiry: Date
) throws -> String {
    let dateTranscoder: any DateTranscoder = .iso8601WithFractionalSeconds
    return try [
        "hush-proof-v1",
        proof.proofId,
        challengeID,
        challengeNonce,
        installationID,
        proof.commitment,
        proof.ciphertextSha256,
        String(proof.ciphertextSize),
        dateTranscoder.encode(expiry),
        String(proof.assuranceLevel),
    ].joined(separator: "\n")
}

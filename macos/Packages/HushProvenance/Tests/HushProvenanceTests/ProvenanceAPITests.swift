import Foundation
@testable import HushProvenance
import Testing
import CryptoKit
import OpenAPIRuntime

private let integrationServiceURL = ProcessInfo.processInfo.environment["HUSH_PROVENANCE_E2E_BASE_URL"]
    .flatMap(URL.init(string:))

@Suite("Hush provenance API")
struct ProvenanceAPITests {
    @Test("constructs the generated client for HTTPS origins")
    func constructsClient() throws {
        let origin = try #require(URL(string: "https://proof.hush.app"))

        _ = ProvenanceAPI.client(baseURL: origin)
    }

    @Test("prepares a browser-compatible encrypted proof")
    func preparesProof() throws {
        let key = try #require(Data(base64Encoded: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
        let signer = try SoftwareP256Signer(
            rawRepresentation: Data(repeating: 1, count: 32)
        )
        let manifest = fixtureManifest()
        let prepared = try ProofPreparer.prepare(
            manifest: manifest,
            signer: signer,
            assuranceLevel: 2,
            encryptionKey: SymmetricKey(data: key),
            nonce: try AES.GCM.Nonce(data: Data(repeating: 2, count: 12))
        )

        #expect(prepared.proofId == manifest.proofId)
        #expect(prepared.decryptionKey.count == 43)
        #expect(prepared.commitment.count == 43)
        #expect(prepared.ciphertextSha256.count == 43)
        #expect(prepared.ciphertextSize > prepared.manifest.count)

        let sealed = try AES.GCM.SealedBox(combined: prepared.ciphertext)
        let packageData = try AES.GCM.open(sealed, using: SymmetricKey(data: key))
        let package = try #require(
            JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        )
        let manifestData = try decodeBase64URL(try #require(package["manifest"] as? String))
        let signatureData = try decodeBase64URL(
            try #require(package["manifestSignature"] as? String)
        )
        let publicKeyData = try decodeBase64URL(
            try #require(package["installationPublicKey"] as? String)
        )
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)

        #expect(manifestData == prepared.manifest)
        #expect(publicKey.isValidSignature(signature, for: manifestData))
        #expect(package["signatureAlgorithm"] as? String == "ES256")
    }

    @Test(
        "calculates deterministic AI edit share",
        arguments: [
            ("hello world", "hello world", 0.0),
            ("hello world", "hello there", 0.5),
            ("one two", "one two three four", 0.5),
            ("one two", "different words", 1.0),
        ]
    )
    func editShare(original: String, refined: String, expected: Double) {
        #expect(AIEditShare.calculate(original: original, refined: refined) == expected)
    }

    @Test("audio hashing is versioned and deterministic")
    func audioHash() {
        let first = ProofAudioHasher.hash(samples: [0, 0.25, -0.25], sampleRate: 16_000)
        let second = ProofAudioHasher.hash(samples: [0, 0.25, -0.25], sampleRate: 16_000)

        #expect(first == second)
        #expect(first.count == 43)
        #expect(first != ProofAudioHasher.hash(samples: [0, 0.25], sampleRate: 16_000))
    }

    @Test("round trips immutable revisions with ordered composer voice sections")
    func revisionAndVoiceSections() throws {
        let segment = ProofManifest.VoiceSegment(
            id: "018f47a6-84d2-7a10-9c2d-2f2c29ba7c45",
            capturedAt: "2026-08-02T20:00:00.000Z",
            durationMs: 1_500,
            sampleRate: 16_000,
            audioSha256: String(repeating: "B", count: 43),
            transcript: "Add this section here.",
            modelId: "large-v3",
            modelDisplayName: "Large v3",
            language: "en"
        )
        let manifest = ProofManifest(
            proofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7d56",
            commitmentNonce: String(repeating: "C", count: 43),
            createdAt: "2026-08-02T20:01:00.000Z",
            expiresAt: "2026-09-01T20:01:00.000Z",
            author: nil,
            capture: .init(
                source: .hushHistory,
                durationMs: nil,
                sampleRate: nil,
                audioSha256: nil
            ),
            transcription: nil,
            sourceText: "Original Hush message.",
            voiceSegments: [segment],
            revision: .init(
                parentProofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
                parentCommitment: String(repeating: "A", count: 43)
            ),
            provenanceEvents: [
                .init(
                    occurredAt: "2026-08-02T19:58:00.000Z",
                    kind: .messageStarted
                ),
                .init(
                    occurredAt: segment.capturedAt,
                    kind: .voiceSectionAdded,
                    voiceSegmentId: segment.id,
                    durationMs: segment.durationMs,
                    modelDisplayName: segment.modelDisplayName
                ),
                .init(
                    occurredAt: "2026-08-02T20:00:02.000Z",
                    kind: .cleanupApplied
                ),
                .init(
                    occurredAt: "2026-08-02T20:01:00.000Z",
                    kind: .revisionCreated,
                    parentProofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
                    parentCommitment: String(repeating: "A", count: 43)
                ),
            ],
            transformations: [.init(kind: .cleanup, algorithmVersion: "basic-v1")],
            finalText: "Original Hush message. Add this section here.",
            aiEditShare: nil,
            activitySnapshot: nil
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ProofManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(decoded.voiceSegments?.map(\.transcript) == ["Add this section here."])
        #expect(decoded.revision?.parentProofId == "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34")
        #expect(decoded.provenanceEvents?.map(\.kind) == [
            .messageStarted,
            .voiceSectionAdded,
            .cleanupApplied,
            .revisionCreated,
        ])
    }

    @Test("carries an initial voice recording through a manually edited revision")
    func completeVoiceRevisionChronology() {
        let original = ProofChronology.build(
            initialVoiceCapture: .init(
                capturedAt: "2026-08-02T19:58:00.000Z",
                durationMs: 12_400,
                modelDisplayName: "Large v3"
            ),
            cleanupAppliedAt: "2026-08-02T19:58:13.000Z"
        )
        let segment = ProofManifest.VoiceSegment(
            id: "018f47a6-84d2-7a10-9c2d-2f2c29ba7c45",
            capturedAt: "2026-08-02T20:00:00.000Z",
            durationMs: 1_500,
            sampleRate: 16_000,
            audioSha256: String(repeating: "B", count: 43),
            transcript: "Add this section here.",
            modelId: "large-v3",
            modelDisplayName: "Large v3",
            language: "en"
        )
        let revision = ProofChronology.build(
            inheriting: original,
            voiceSegments: [segment],
            cleanupAppliedAt: "2026-08-02T20:00:02.000Z",
            manualEditAt: "2026-08-02T20:01:00.000Z",
            revision: .init(
                createdAt: "2026-08-02T20:01:00.000Z",
                parentProofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
                parentCommitment: String(repeating: "A", count: 43)
            )
        )

        #expect(revision.map(\.kind) == [
            .voiceCapture,
            .cleanupApplied,
            .voiceSectionAdded,
            .cleanupApplied,
            .manualEdit,
            .revisionCreated,
        ])
        #expect(revision.first?.durationMs == 12_400)
        #expect(revision.first?.modelDisplayName == "Large v3")
        #expect(revision[2].voiceSegmentId == segment.id)
    }

    @Test("appends the private proof link after the message")
    func appendsSignatureLink() throws {
        let url = try #require(URL(
            string: "https://hush.app/p/example#k=private-decryption-key"
        ))

        let signed = ProofSignatureFormatter.append(
            to: "Perfect, let's lock in Thursday at 10.",
            proofURL: url
        )

        #expect(signed == """
        Perfect, let's lock in Thursday at 10.

        -typed with hush: https://hush.app/p/example#k=private-decryption-key
        """)
    }

    @Test("creates a rich signature with the private proof URL as its link")
    func createsRichSignatureLink() throws {
        let url = try #require(URL(
            string: "https://behu.sh/A7k2Qx#k=private-decryption-key"
        ))
        let content = ProofSignatureFormatter.content(
            for: "Perfect, let's lock in Thursday at 10.",
            proofURL: url
        )
        let linkRange = (content.richText.string as NSString).range(of: "typed with hush")

        #expect(content.richText.string == """
        Perfect, let's lock in Thursday at 10.

        -typed with hush
        """)
        #expect(content.richText.attribute(.link, at: linkRange.location - 1, effectiveRange: nil) == nil)
        #expect(content.richText.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == url)
        #expect(content.plainText.hasSuffix("-typed with hush: \(url.absoluteString)"))

        let fullRange = NSRange(location: 0, length: content.richText.length)
        let htmlData = try content.richText.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        let rtfData = try content.richText.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let html = try #require(String(data: htmlData, encoding: .utf8))
        #expect(html.contains(url.absoluteString))
        #expect(rtfData.isEmpty == false)
    }

    @Test("uses visible URLs when a destination may sanitize rich links")
    func avoidsRichLinksInUnverifiedDestinations() {
        #expect(ProofSignatureFormatter.supportsDurableLinkPaste(
            destinationBundleIdentifier: "com.apple.Safari"
        ) == false)
        #expect(ProofSignatureFormatter.supportsDurableLinkPaste(
            destinationBundleIdentifier: "com.google.Chrome"
        ) == false)
        #expect(ProofSignatureFormatter.supportsDurableLinkPaste(
            destinationBundleIdentifier: nil
        ) == false)
        #expect(ProofSignatureFormatter.supportsDurableLinkPaste(
            destinationBundleIdentifier: "com.apple.mail"
        ))
    }

    @Test("canonicalizes proof expiry as RFC 3339 UTC")
    func canonicalizesProofExpiry() throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let expiry = try Date("2026-08-31T12:00:00.000Z", strategy: .iso8601)
        let canonical = try canonicalProofRequest(
            proof: proof,
            challengeID: "challenge-id",
            challengeNonce: "challenge-nonce",
            installationID: "installation-id",
            expiry: expiry
        )

        #expect(canonical.split(separator: "\n")[8] == "2026-08-31T12:00:00.000Z")
    }

    @Test("signs the exact fractional expiry encoded by OpenAPI")
    func signsOpenAPIExpiryAtRoundingBoundary() throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let expiry = try Date("2026-09-01T00:39:17.002Z", strategy: .iso8601)
        let dateTranscoder: any DateTranscoder = .iso8601WithFractionalSeconds
        let wireExpiry = try dateTranscoder.encode(expiry)
        let canonical = try canonicalProofRequest(
            proof: proof,
            challengeID: "challenge-id",
            challengeNonce: "challenge-nonce",
            installationID: "installation-id",
            expiry: expiry
        )

        #expect(wireExpiry == "2026-09-01T00:39:17.002Z")
        #expect(canonical.split(separator: "\n")[8] == Substring(wireExpiry))
    }

    @Test("publishes through the generated API and scoped upload")
    func publishesProof() async throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let api = MockProofAPI(proof: proof)
        let uploader = MockProofUploader()
        let publisher = ProofPublisher(
            api: api,
            proofURLBaseURL: URL(string: "https://hush.app/s/")!,
            uploader: uploader
        )

        let published = try await publisher.publish(
            proof,
            installationID: "018f47a6-84d2-7a10-9c2d-2f2c29ba7000",
            signer: signer
        )

        #expect(published.id == proof.proofId)
        #expect(published.slug == MockProofAPI.slug)
        #expect(published.privateURL.fragment == "k=\(proof.decryptionKey)")
        #expect(await uploader.uploadedData == proof.ciphertext)
        let reservation = await api.reservation
        #expect(reservation?.commitment == proof.commitment)
        #expect(reservation?.signature.isEmpty == false)
    }

    @Test("rejects a proof link outside the configured first-party origin")
    func rejectsUntrustedProofURL() async throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let publisher = ProofPublisher(
            api: MockProofAPI(
                proof: proof,
                proofURL: "https://lookalike.example/s/Ab3dE7"
            ),
            proofURLBaseURL: URL(string: "https://hush.app/s/")!,
            uploader: MockProofUploader()
        )

        await #expect(throws: ProofPublisherError.invalidReceipt) {
            try await publisher.publish(
                proof,
                installationID: "018f47a6-84d2-7a10-9c2d-2f2c29ba7000",
                signer: signer
            )
        }
    }

    @Test("rejects a proof link without an exact six-character alias")
    func rejectsInvalidProofAliasLength() async throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let publisher = ProofPublisher(
            api: MockProofAPI(
                proof: proof,
                proofURL: "https://hush.app/s/Ab3dE7x"
            ),
            proofURLBaseURL: URL(string: "https://hush.app/s/")!,
            uploader: MockProofUploader()
        )

        await #expect(throws: ProofPublisherError.invalidReceipt) {
            try await publisher.publish(
                proof,
                installationID: "018f47a6-84d2-7a10-9c2d-2f2c29ba7000",
                signer: signer
            )
        }
    }

    @Test("reports an unavailable registration service")
    func unavailableRegistrationService() async throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let publisher = ProofPublisher(
            api: UnavailableEnrollmentAPI(),
            proofURLBaseURL: URL(string: "https://hush.app/s/")!
        )

        await #expect(throws: ProofPublisherError.self) {
            try await publisher.enroll(
                signer: signer,
                keyKind: .keychain,
                appVersion: "0.1.0-alpha.1",
                platformVersion: "macOS test"
            )
        }
    }

    @Test("reports when a cached installation is missing from the service")
    func missingPublicationInstallation() async throws {
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 1, count: 32))
        let proof = try ProofPreparer.prepare(
            manifest: fixtureManifest(),
            signer: signer,
            assuranceLevel: 2
        )
        let publisher = ProofPublisher(
            api: MockProofAPI(
                proof: proof,
                publicationChallengeErrorCode: "installation_not_found"
            ),
            proofURLBaseURL: URL(string: "https://hush.app/s/")!,
            uploader: MockProofUploader()
        )

        await #expect(throws: ProofPublisherError.installationNotFound) {
            try await publisher.publish(
                proof,
                installationID: "018f47a6-84d2-7a10-9c2d-2f2c29ba7000",
                signer: signer
            )
        }
    }

    @Test(
        "enrolls and publishes with the Hono service over HTTP",
        .enabled(if: integrationServiceURL != nil)
    )
    func enrollsAndPublishesWithHonoService() async throws {
        let baseURL = try #require(integrationServiceURL)
        let signer = try SoftwareP256Signer(rawRepresentation: Data(repeating: 7, count: 32))
        let publisher = ProofPublisher(
            api: ProvenanceAPI.client(baseURL: baseURL),
            proofURLBaseURL: baseURL.appending(path: "s")
        )

        let registration = try await publisher.enroll(
            signer: signer,
            keyKind: .keychain,
            appVersion: "0.1.0-alpha.1-e2e",
            platformVersion: "macOS Swift E2E"
        )

        #expect(UUID(uuidString: registration.id) != nil)
        #expect(registration.fingerprint.count == 43)

        let now = Date()
        let createdAt = now.formatted(.iso8601)
        let proof = try ProofPreparer.prepare(
            manifest: ProofManifest(
                proofId: UUID().uuidString.lowercased(),
                commitmentNonce: String(repeating: "A", count: 43),
                createdAt: createdAt,
                expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60).formatted(.iso8601),
                author: .init(displayName: "E2E", identityKind: .selfDeclared),
                capture: .init(
                    durationMs: 1_000,
                    sampleRate: 16_000,
                    audioSha256: ProofAudioHasher.hash(samples: [0, 0.1], sampleRate: 16_000)
                ),
                transcription: .init(
                    rawText: "Testing the complete proof journey",
                    modelId: "e2e",
                    modelDisplayName: "E2E",
                    language: "en"
                ),
                provenanceEvents: ProofChronology.build(
                    initialVoiceCapture: .init(
                        capturedAt: createdAt,
                        durationMs: 1_000,
                        modelDisplayName: "E2E"
                    ),
                    cleanupAppliedAt: createdAt
                ),
                transformations: [.init(kind: .cleanup, algorithmVersion: "e2e-v1")],
                finalText: "Testing the complete proof journey.",
                aiEditShare: nil,
                activitySnapshot: nil
            ),
            signer: signer,
            assuranceLevel: 2
        )
        let published = try await publisher.publish(
            proof,
            installationID: registration.id,
            signer: signer
        )
        let signedText = ProofSignatureFormatter.append(
            to: "Testing the complete proof journey.",
            proofURL: published.privateURL
        )

        #expect(published.privateURL.host == baseURL.host)
        #expect(published.privateURL.path.hasPrefix("/s/"))
        #expect(published.privateURL.lastPathComponent.count == 6)
        #expect(published.privateURL.fragment == "k=\(proof.decryptionKey)")
        #expect(signedText.hasSuffix(published.privateURL.absoluteString))
        #expect(signedText.contains("\n\n-typed with hush: "))
    }

    private func fixtureManifest() -> ProofManifest {
        ProofManifest(
            proofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
            commitmentNonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            createdAt: "2026-08-01T12:00:00.000Z",
            expiresAt: "2026-08-31T12:00:00.000Z",
            author: .init(displayName: "Alex", identityKind: .selfDeclared),
            capture: .init(
                durationMs: 3_200,
                sampleRate: 16_000,
                audioSha256: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
            ),
            transcription: .init(
                rawText: "Perfect lets lock in Thursday at ten",
                modelId: "large-v3",
                modelDisplayName: "Large v3",
                language: "en"
            ),
            provenanceEvents: ProofChronology.build(
                initialVoiceCapture: .init(
                    capturedAt: "2026-08-01T11:59:55.000Z",
                    durationMs: 3_200,
                    modelDisplayName: "Large v3"
                ),
                cleanupAppliedAt: "2026-08-01T11:59:59.000Z",
                localAIRefinement: .init(
                    refinedAt: "2026-08-01T12:00:00.000Z",
                    modelDisplayName: "Apple Intelligence",
                    persona: "Business"
                )
            ),
            transformations: [
                .init(kind: .cleanup, algorithmVersion: "basic-v1"),
                .init(
                    kind: .localAI,
                    provider: "Apple Intelligence",
                    model: "System model",
                    persona: "Business",
                    algorithmVersion: "persona-v1"
                ),
            ],
            finalText: "Perfect, let's lock in Thursday at 10.",
            aiEditShare: 0.28,
            activitySnapshot: nil
        )
    }

    private func decodeBase64URL(_ value: String) throws -> Data {
        let base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((value.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        return try #require(Data(base64Encoded: base64))
    }
}

private actor MockProofUploader: ProofUploading {
    private(set) var uploadedData: Data?

    func upload(_ data: Data, to url: URL, headers: [String: String]) async throws {
        uploadedData = data
    }
}

private actor MockProofAPI: APIProtocol {
    static let slug = "mock-proof-slug-4gJ8qA2pN7wK"

    private let proof: PreparedProof
    private let proofURL: String
    private let publicationChallengeErrorCode: String?
    private(set) var reservation: Operations.reserveProof.Input.Body.jsonPayload?

    init(
        proof: PreparedProof,
        proofURL: String = "https://hush.app/s/Ab3dE7",
        publicationChallengeErrorCode: String? = nil
    ) {
        self.proof = proof
        self.proofURL = proofURL
        self.publicationChallengeErrorCode = publicationChallengeErrorCode
    }

    func createPublicationChallenge(
        _ input: Operations.createPublicationChallenge.Input
    ) async throws -> Operations.createPublicationChallenge.Output {
        if let publicationChallengeErrorCode {
            return .notFound(.init(body: .json(.init(error: .init(
                code: publicationChallengeErrorCode,
                message: "Installation not found.",
                requestId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7222"
            )))))
        }
        return .ok(.init(body: .json(.init(
            id: "018f47a6-84d2-7a10-9c2d-2f2c29ba7111",
            nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: Date(timeIntervalSince1970: 1_775_212_300)
        ))))
    }

    func reserveProof(
        _ input: Operations.reserveProof.Input
    ) async throws -> Operations.reserveProof.Output {
        guard case let .json(body)? = input.body else { throw MockError.missingBody }
        reservation = body
        return .created(.init(body: .json(.init(
            id: proof.proofId,
            slug: Self.slug,
            uploadUrl: "https://upload.hush.app/proof",
            uploadHeaders: .init(additionalProperties: [
                "content-type": "application/vnd.hush.proof+encrypted",
            ]),
            completionToken: "completion-token",
            revocationSecret: "revocation-secret"
        ))))
    }

    func completeProof(
        _ input: Operations.completeProof.Input
    ) async throws -> Operations.completeProof.Output {
        .ok(.init(body: .json(.init(
            proofUrl: proofURL,
            receipt: .init(
                version: 1,
                keyId: "service-key",
                proofId: proof.proofId,
                slug: Self.slug,
                commitment: proof.commitment,
                ciphertextSha256: proof.ciphertextSha256,
                ciphertextSize: proof.ciphertextSize,
                assuranceLevel: proof.assuranceLevel,
                createdAt: Date(timeIntervalSince1970: 1_775_212_000),
                expiresAt: Date(timeIntervalSince1970: 1_777_804_800)
            ),
            receiptSignature: "receipt-signature"
        ))))
    }

    func createEnrollmentChallenge(
        _ input: Operations.createEnrollmentChallenge.Input
    ) async throws -> Operations.createEnrollmentChallenge.Output { fatalError() }

    func enrollInstallation(
        _ input: Operations.enrollInstallation.Input
    ) async throws -> Operations.enrollInstallation.Output { fatalError() }

    func getPublicProof(
        _ input: Operations.getPublicProof.Input
    ) async throws -> Operations.getPublicProof.Output { fatalError() }

    func revokeProof(
        _ input: Operations.revokeProof.Input
    ) async throws -> Operations.revokeProof.Output { fatalError() }

    func resolveProofAlias(
        _ input: Operations.resolveProofAlias.Input
    ) async throws -> Operations.resolveProofAlias.Output { fatalError() }

    private enum MockError: Error { case missingBody }
}

private actor UnavailableEnrollmentAPI: APIProtocol {
    func createEnrollmentChallenge(
        _ input: Operations.createEnrollmentChallenge.Input
    ) async throws -> Operations.createEnrollmentChallenge.Output {
        throw URLError(.cannotConnectToHost)
    }

    func enrollInstallation(
        _ input: Operations.enrollInstallation.Input
    ) async throws -> Operations.enrollInstallation.Output { fatalError() }

    func createPublicationChallenge(
        _ input: Operations.createPublicationChallenge.Input
    ) async throws -> Operations.createPublicationChallenge.Output { fatalError() }

    func reserveProof(
        _ input: Operations.reserveProof.Input
    ) async throws -> Operations.reserveProof.Output { fatalError() }

    func completeProof(
        _ input: Operations.completeProof.Input
    ) async throws -> Operations.completeProof.Output { fatalError() }

    func getPublicProof(
        _ input: Operations.getPublicProof.Input
    ) async throws -> Operations.getPublicProof.Output { fatalError() }

    func revokeProof(
        _ input: Operations.revokeProof.Input
    ) async throws -> Operations.revokeProof.Output { fatalError() }

    func resolveProofAlias(
        _ input: Operations.resolveProofAlias.Input
    ) async throws -> Operations.resolveProofAlias.Output { fatalError() }
}

import CryptoKit
import Foundation
import HushProvenance
import OSLog

struct VerifiedMessageDraft: Sendable {
    enum Origin: Equatable, Sendable {
        case voice
        case newDraft
        case recentHushOutput
    }

    let origin: Origin
    let samples: [Float]
    let rawText: String
    let finalText: String
    let language: String
    let modelID: String
    let modelName: String
    let personaName: String?
    let providerName: String?
    let destinationBundleIdentifier: String?
    var destinationApplicationName: String? = nil
    var destinationIsSecureField: Bool = false
    var destinationWebsiteHost: String? = nil
    var destinationIsBrowserAddressOrSearchField: Bool = false
    let containsManualEdits: Bool
    var captureStartedAt: Date? = nil
    var voiceSegments: [ProofManifest.VoiceSegment] = []
    var parentProofId: String? = nil
    var parentProofCommitment: String? = nil
    var parentProvenanceEvents: [ProofManifest.ProvenanceEvent] = []
    var composerStartedAt: Date? = nil
    var refinedAt: Date? = nil
}

struct VerifiedMessageText {
    let text: String
    let richText: NSAttributedString?
    let isVerified: Bool
    let publicationWarning: String?
    var destinationSuppression: VerifiedMessageDestinationSuppression? = nil
    var proofId: String? = nil
    var proofCommitment: String? = nil
    var provenanceEvents: [ProofManifest.ProvenanceEvent] = []

    var insertionContent: TextInsertionContent {
        TextInsertionContent(plainText: text, richText: richText)
    }
}

@MainActor
final class VerifiedMessageCoordinator {
    private static let log = Logger(
        subsystem: "com.decentralfreedom.hush",
        category: "VerifiedMessages"
    )
    private static let configuration = ProofServiceConfiguration.current
    private let keyStore = InstallationKeyStore()
    private let publisher = ProofPublisher(
        api: ProvenanceAPI.client(baseURL: configuration.serviceURL),
        proofURLBaseURL: configuration.proofURLBaseURL
    )

    func prepareRegistration() async throws {
        let identity = try keyStore.loadOrCreate()
        _ = try await registration(for: identity)
    }

    func textWithProof(for draft: VerifiedMessageDraft) async -> VerifiedMessageText {
        guard Settings.shared.verifiedMessagesEnabled else {
            return VerifiedMessageText(
                text: draft.finalText,
                richText: nil,
                isVerified: false,
                publicationWarning: nil
            )
        }
        let destinationDecision = VerifiedMessageDestinationPolicy.decision(
            mode: Settings.shared.verifiedMessagesDestinationMode,
            exceptions: Settings.shared.verifiedMessagesAppExceptions,
            websiteExceptions: Settings.shared.verifiedMessagesWebsiteExceptions,
            bundleIdentifier: draft.destinationBundleIdentifier,
            applicationName: draft.destinationApplicationName,
            isSecureField: draft.destinationIsSecureField,
            websiteHost: draft.destinationWebsiteHost,
            isBrowserAddressOrSearchField: draft.destinationIsBrowserAddressOrSearchField
        )
        guard destinationDecision.allowsProof else {
            Self.log.info(
                "Proof skipped by destination policy for \(draft.destinationBundleIdentifier ?? "secure field", privacy: .public)"
            )
            return VerifiedMessageText(
                text: draft.finalText,
                richText: nil,
                isVerified: false,
                publicationWarning: nil,
                destinationSuppression: destinationDecision.suppression
            )
        }
        do {
            let publication = try await publish(draft)
            return VerifiedMessageText(
                content: publication.content,
                destinationBundleIdentifier: draft.destinationBundleIdentifier,
                isVerified: true,
                publicationWarning: nil,
                proofId: publication.proofId,
                proofCommitment: publication.commitment,
                provenanceEvents: publication.provenanceEvents
            )
        } catch {
            Self.log.notice("Proof unavailable: \(error.localizedDescription, privacy: .public)")
            return VerifiedMessageText(
                text: draft.finalText,
                richText: nil,
                isVerified: false,
                publicationWarning: "Inserted without Typed with hush link"
            )
        }
    }

    private func publish(_ draft: VerifiedMessageDraft) async throws -> PublishedSignature {
        let identity = try keyStore.loadOrCreate()
        let registration = try await registration(for: identity)
        let now = Date()
        let expiry = now.addingTimeInterval(30 * 24 * 60 * 60)
        let proofID = UUID().uuidString.lowercased()
        let llmUsed = draft.providerName != nil
        let capture: ProofManifest.Capture
        let transcription: ProofManifest.Transcription?
        var transformations: [ProofManifest.Transformation] = []
        switch draft.origin {
        case .voice:
            capture = .init(
                durationMs: Int(Double(draft.samples.count) / AudioRecorder.targetSampleRate * 1_000),
                sampleRate: Int(AudioRecorder.targetSampleRate),
                audioSha256: ProofAudioHasher.hash(
                    samples: draft.samples,
                    sampleRate: Int(AudioRecorder.targetSampleRate)
                )
            )
            transcription = .init(
                rawText: draft.rawText,
                modelId: draft.modelID,
                modelDisplayName: draft.modelName,
                language: draft.language
            )
            transformations.append(.init(kind: .cleanup, algorithmVersion: "basic-v1"))
        case .newDraft:
            capture = .init(
                source: .keyboard,
                durationMs: nil,
                sampleRate: nil,
                audioSha256: nil
            )
            transcription = nil
        case .recentHushOutput:
            capture = .init(
                source: .hushHistory,
                durationMs: nil,
                sampleRate: nil,
                audioSha256: nil
            )
            transcription = nil
        }
        if llmUsed {
            transformations.append(.init(
                kind: .localAI,
                provider: draft.providerName,
                model: draft.providerName,
                persona: draft.personaName,
                algorithmVersion: "persona-v1"
            ))
        }
        if !draft.voiceSegments.isEmpty,
           !transformations.contains(where: { $0.kind == .cleanup }) {
            transformations.append(.init(kind: .cleanup, algorithmVersion: "basic-v1"))
        }
        if draft.containsManualEdits {
            transformations.append(.init(kind: .manualHushEdit, algorithmVersion: "editor-v1"))
        }
        let revision: ProofManifest.Revision?
        if let parentProofId = draft.parentProofId,
           let parentProofCommitment = draft.parentProofCommitment {
            revision = .init(
                parentProofId: parentProofId,
                parentCommitment: parentProofCommitment
            )
        } else {
            revision = nil
        }
        let authorName = Settings.shared.verifiedMessagesAuthorName
        let eventTimestamp = timestamp(now)
        let initialVoiceCapture: ProofChronology.InitialVoiceCapture? = if draft.origin == .voice {
            .init(
                capturedAt: timestamp(draft.captureStartedAt ?? now),
                durationMs: capture.durationMs ?? 1,
                modelDisplayName: draft.modelName
            )
        } else {
            nil
        }
        let localAIRefinement: ProofChronology.LocalAIRefinement? = if let providerName = draft.providerName {
            .init(
                refinedAt: timestamp(draft.refinedAt ?? now),
                modelDisplayName: providerName,
                persona: draft.personaName
            )
        } else {
            nil
        }
        let revisionEvent: ProofChronology.Revision? = if let parentProofId = draft.parentProofId,
                                                          let parentProofCommitment = draft.parentProofCommitment {
            .init(
                createdAt: eventTimestamp,
                parentProofId: parentProofId,
                parentCommitment: parentProofCommitment
            )
        } else {
            nil
        }
        let provenanceEvents = ProofChronology.build(
            inheriting: draft.parentProvenanceEvents,
            messageStartedAt: draft.origin == .newDraft
                ? timestamp(draft.composerStartedAt ?? now)
                : nil,
            initialVoiceCapture: initialVoiceCapture,
            voiceSegments: draft.voiceSegments,
            cleanupAppliedAt: transformations.contains(where: { $0.kind == .cleanup })
                ? eventTimestamp
                : nil,
            localAIRefinement: localAIRefinement,
            manualEditAt: draft.containsManualEdits ? eventTimestamp : nil,
            revision: revisionEvent
        )
        let manifest = ProofManifest(
            proofId: proofID,
            commitmentNonce: randomBytes(count: 32).base64URLString,
            createdAt: timestamp(now),
            expiresAt: timestamp(expiry),
            author: .init(
                displayName: authorName.isEmpty ? nil : authorName,
                identityKind: authorName.isEmpty ? .anonymous : .selfDeclared
            ),
            capture: capture,
            transcription: transcription,
            sourceText: draft.origin == .voice ? nil : draft.rawText,
            voiceSegments: draft.voiceSegments.isEmpty ? nil : draft.voiceSegments,
            revision: revision,
            provenanceEvents: provenanceEvents.isEmpty ? nil : provenanceEvents,
            transformations: transformations,
            finalText: draft.finalText,
            aiEditShare: llmUsed
                ? AIEditShare.calculate(original: draft.rawText, refined: draft.finalText)
                : nil,
            activitySnapshot: nil
        )
        let proof = try ProofPreparer.prepare(
            manifest: manifest,
            signer: identity.signer,
            assuranceLevel: 2
        )
        let published: PublishedProof
        do {
            published = try await publisher.publish(
                proof,
                installationID: registration.id,
                signer: identity.signer
            )
        } catch ProofPublisherError.installationNotFound {
            Self.log.info("Cached proof registration is stale; enrolling this Mac again")
            clearCachedRegistration(matching: registration.id)
            let refreshedRegistration = try await enroll(identity)
            published = try await publisher.publish(
                proof,
                installationID: refreshedRegistration.id,
                signer: identity.signer
            )
        }
        return PublishedSignature(
            content: ProofSignatureFormatter.content(
                for: draft.finalText,
                proofURL: published.privateURL
            ),
            proofId: proof.proofId,
            commitment: proof.commitment,
            provenanceEvents: provenanceEvents
        )
    }

    private func registration(
        for identity: InstallationSigningIdentity
    ) async throws -> InstallationRegistration {
        if Settings.shared.verifiedMessagesInstallationFingerprint == identity.fingerprint,
           Settings.shared.verifiedMessagesInstallationServiceURL
            == Self.configuration.serviceURL.absoluteString,
           let id = Settings.shared.verifiedMessagesInstallationID {
            return InstallationRegistration(id: id, fingerprint: identity.fingerprint)
        }
        return try await enroll(identity)
    }

    private func enroll(
        _ identity: InstallationSigningIdentity
    ) async throws -> InstallationRegistration {
        let registration = try await publisher.enroll(
            signer: identity.signer,
            keyKind: identity.keyKind,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            platformVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        Settings.shared.verifiedMessagesInstallationID = registration.id
        Settings.shared.verifiedMessagesInstallationFingerprint = registration.fingerprint
        Settings.shared.verifiedMessagesInstallationServiceURL
            = Self.configuration.serviceURL.absoluteString
        return registration
    }

    private func clearCachedRegistration(matching installationID: String) {
        guard Settings.shared.verifiedMessagesInstallationID == installationID else { return }
        Settings.shared.verifiedMessagesInstallationID = nil
        Settings.shared.verifiedMessagesInstallationFingerprint = nil
        Settings.shared.verifiedMessagesInstallationServiceURL = nil
    }

    private func randomBytes(count: Int) -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0.prefix(count)) }
    }

    private func timestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }
}

private extension VerifiedMessageText {
    @MainActor
    init(
        content: ProofSignatureContent,
        destinationBundleIdentifier: String?,
        isVerified: Bool,
        publicationWarning: String?,
        proofId: String?,
        proofCommitment: String?,
        provenanceEvents: [ProofManifest.ProvenanceEvent]
    ) {
        let richText: NSAttributedString? = switch Settings.shared.verifiedMessagesLinkPresentation {
        case .automatic:
            ProofSignatureFormatter.supportsDurableLinkPaste(
                destinationBundleIdentifier: destinationBundleIdentifier
            ) ? content.richText : nil
        case .linkedSignature:
            content.richText
        case .visibleURL:
            nil
        }
        self.init(
            text: content.plainText,
            richText: richText,
            isVerified: isVerified,
            publicationWarning: publicationWarning,
            proofId: proofId,
            proofCommitment: proofCommitment,
            provenanceEvents: provenanceEvents
        )
    }
}

private struct PublishedSignature {
    let content: ProofSignatureContent
    let proofId: String
    let commitment: String
    let provenanceEvents: [ProofManifest.ProvenanceEvent]
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

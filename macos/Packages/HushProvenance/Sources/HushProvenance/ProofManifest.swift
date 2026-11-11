import Foundation

public struct ProofManifest: Codable, Equatable, Sendable {
    public let version: Int
    public let proofId: String
    public let commitmentNonce: String
    public let createdAt: String
    public let expiresAt: String
    public let author: Author?
    public let capture: Capture
    public let transcription: Transcription?
    public let sourceText: String?
    public let voiceSegments: [VoiceSegment]?
    public let revision: Revision?
    public let provenanceEvents: [ProvenanceEvent]?
    public let transformations: [Transformation]
    public let finalText: String
    public let aiEditShare: Double?
    public let activitySnapshot: ActivitySnapshot?

    public init(
        proofId: String,
        commitmentNonce: String,
        createdAt: String,
        expiresAt: String,
        author: Author?,
        capture: Capture,
        transcription: Transcription?,
        sourceText: String? = nil,
        voiceSegments: [VoiceSegment]? = nil,
        revision: Revision? = nil,
        provenanceEvents: [ProvenanceEvent]? = nil,
        transformations: [Transformation],
        finalText: String,
        aiEditShare: Double?,
        activitySnapshot: ActivitySnapshot?
    ) {
        self.version = 2
        self.proofId = proofId
        self.commitmentNonce = commitmentNonce
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.author = author
        self.capture = capture
        self.transcription = transcription
        self.sourceText = sourceText
        self.voiceSegments = voiceSegments
        self.revision = revision
        self.provenanceEvents = provenanceEvents
        self.transformations = transformations
        self.finalText = finalText
        self.aiEditShare = aiEditShare
        self.activitySnapshot = activitySnapshot
    }

    public struct Author: Codable, Equatable, Sendable {
        public enum IdentityKind: String, Codable, Sendable {
            case anonymous
            case selfDeclared = "self_declared"
        }

        public let displayName: String?
        public let identityKind: IdentityKind

        public init(displayName: String?, identityKind: IdentityKind) {
            self.displayName = displayName
            self.identityKind = identityKind
        }
    }

    public struct Capture: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable {
            case microphone
            case keyboard
            case hushHistory = "hush_history"
        }

        public let source: Source
        public let durationMs: Int?
        public let sampleRate: Int?
        public let audioSha256: String?
        public let audio: Audio?

        public init(
            source: Source = .microphone,
            durationMs: Int?,
            sampleRate: Int?,
            audioSha256: String?,
            audio: Audio? = nil
        ) {
            self.source = source
            self.durationMs = durationMs
            self.sampleRate = sampleRate
            self.audioSha256 = audioSha256
            self.audio = audio
        }
    }

    public struct Audio: Codable, Equatable, Sendable {
        public enum MIMEType: String, Codable, Sendable {
            case mp4 = "audio/mp4"
            case aac = "audio/aac"
            case wav = "audio/wav"
        }

        public let mimeType: MIMEType
        public let base64: String
        public let durationMs: Int

        public init(mimeType: MIMEType, base64: String, durationMs: Int) {
            self.mimeType = mimeType
            self.base64 = base64
            self.durationMs = durationMs
        }
    }

    public struct Transcription: Codable, Equatable, Sendable {
        public let rawText: String
        public let modelId: String
        public let modelDisplayName: String
        public let language: String

        public init(
            rawText: String,
            modelId: String,
            modelDisplayName: String,
            language: String
        ) {
            self.rawText = rawText
            self.modelId = modelId
            self.modelDisplayName = modelDisplayName
            self.language = language
        }
    }

    /// One microphone capture inserted into a Hush composer session. The
    /// signed hash proves which audio produced this section without retaining
    /// or uploading the recording itself.
    public struct VoiceSegment: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let capturedAt: String
        public let durationMs: Int
        public let sampleRate: Int
        public let audioSha256: String
        public let transcript: String
        public let modelId: String
        public let modelDisplayName: String
        public let language: String

        public init(
            id: String,
            capturedAt: String,
            durationMs: Int,
            sampleRate: Int,
            audioSha256: String,
            transcript: String,
            modelId: String,
            modelDisplayName: String,
            language: String
        ) {
            self.id = id
            self.capturedAt = capturedAt
            self.durationMs = durationMs
            self.sampleRate = sampleRate
            self.audioSha256 = audioSha256
            self.transcript = transcript
            self.modelId = modelId
            self.modelDisplayName = modelDisplayName
            self.language = language
        }
    }

    /// An immutable reference to the proof this message revises. The previous
    /// private decryption key is deliberately not copied into the new proof.
    public struct Revision: Codable, Equatable, Sendable {
        public let parentProofId: String
        public let parentCommitment: String

        public init(parentProofId: String, parentCommitment: String) {
            self.parentProofId = parentProofId
            self.parentCommitment = parentCommitment
        }
    }

    /// Privacy-minimized, signed chronology carried forward into later
    /// revisions. It records what happened and when without exposing previous
    /// message text or private proof keys.
    public struct ProvenanceEvent: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case messageStarted = "message_started"
            case voiceCapture = "voice_capture"
            case voiceSectionAdded = "voice_section_added"
            case cleanupApplied = "cleanup_applied"
            case localAIRefined = "local_ai_refined"
            case manualEdit = "manual_edit"
            case revisionCreated = "revision_created"
        }

        public let id: String
        public let occurredAt: String
        public let kind: Kind
        public let voiceSegmentId: String?
        public let durationMs: Int?
        public let modelDisplayName: String?
        public let persona: String?
        public let parentProofId: String?
        public let parentCommitment: String?

        public init(
            id: String = UUID().uuidString.lowercased(),
            occurredAt: String,
            kind: Kind,
            voiceSegmentId: String? = nil,
            durationMs: Int? = nil,
            modelDisplayName: String? = nil,
            persona: String? = nil,
            parentProofId: String? = nil,
            parentCommitment: String? = nil
        ) {
            self.id = id
            self.occurredAt = occurredAt
            self.kind = kind
            self.voiceSegmentId = voiceSegmentId
            self.durationMs = durationMs
            self.modelDisplayName = modelDisplayName
            self.persona = persona
            self.parentProofId = parentProofId
            self.parentCommitment = parentCommitment
        }
    }

    public struct Transformation: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case cleanup
            case localAI = "local_ai"
            case manualHushEdit = "manual_hush_edit"
        }

        public let kind: Kind
        public let provider: String?
        public let model: String?
        public let persona: String?
        public let algorithmVersion: String

        public init(
            kind: Kind,
            provider: String? = nil,
            model: String? = nil,
            persona: String? = nil,
            algorithmVersion: String
        ) {
            self.kind = kind
            self.provider = provider
            self.model = model
            self.persona = persona
            self.algorithmVersion = algorithmVersion
        }
    }

    public struct ActivitySnapshot: Codable, Equatable, Sendable {
        public let estimatedTimeSavedSeconds: Double
        public let totalWordsSpoken: Int
        public let capturedAt: String

        public init(
            estimatedTimeSavedSeconds: Double,
            totalWordsSpoken: Int,
            capturedAt: String
        ) {
            self.estimatedTimeSavedSeconds = estimatedTimeSavedSeconds
            self.totalWordsSpoken = totalWordsSpoken
            self.capturedAt = capturedAt
        }
    }
}

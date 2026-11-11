import Foundation

public enum ProofChronology {
    public struct InitialVoiceCapture: Equatable, Sendable {
        public let capturedAt: String
        public let durationMs: Int
        public let modelDisplayName: String

        public init(capturedAt: String, durationMs: Int, modelDisplayName: String) {
            self.capturedAt = capturedAt
            self.durationMs = durationMs
            self.modelDisplayName = modelDisplayName
        }
    }

    public struct LocalAIRefinement: Equatable, Sendable {
        public let refinedAt: String
        public let modelDisplayName: String
        public let persona: String?

        public init(refinedAt: String, modelDisplayName: String, persona: String?) {
            self.refinedAt = refinedAt
            self.modelDisplayName = modelDisplayName
            self.persona = persona
        }
    }

    public struct Revision: Equatable, Sendable {
        public let createdAt: String
        public let parentProofId: String
        public let parentCommitment: String

        public init(createdAt: String, parentProofId: String, parentCommitment: String) {
            self.createdAt = createdAt
            self.parentProofId = parentProofId
            self.parentCommitment = parentCommitment
        }
    }

    public static func build(
        inheriting inheritedEvents: [ProofManifest.ProvenanceEvent] = [],
        messageStartedAt: String? = nil,
        initialVoiceCapture: InitialVoiceCapture? = nil,
        voiceSegments: [ProofManifest.VoiceSegment] = [],
        cleanupAppliedAt: String? = nil,
        localAIRefinement: LocalAIRefinement? = nil,
        manualEditAt: String? = nil,
        revision: Revision? = nil
    ) -> [ProofManifest.ProvenanceEvent] {
        var events = inheritedEvents

        if let messageStartedAt {
            events.append(.init(occurredAt: messageStartedAt, kind: .messageStarted))
        }
        if let initialVoiceCapture,
           !events.contains(where: { $0.kind == .voiceCapture }) {
            events.append(.init(
                occurredAt: initialVoiceCapture.capturedAt,
                kind: .voiceCapture,
                durationMs: initialVoiceCapture.durationMs,
                modelDisplayName: initialVoiceCapture.modelDisplayName
            ))
        }

        let knownVoiceSegmentIDs = Set(events.compactMap(\.voiceSegmentId))
        events.append(contentsOf: voiceSegments.compactMap { segment in
            guard !knownVoiceSegmentIDs.contains(segment.id) else { return nil }
            return .init(
                occurredAt: segment.capturedAt,
                kind: .voiceSectionAdded,
                voiceSegmentId: segment.id,
                durationMs: segment.durationMs,
                modelDisplayName: segment.modelDisplayName
            )
        })

        if let cleanupAppliedAt {
            events.append(.init(occurredAt: cleanupAppliedAt, kind: .cleanupApplied))
        }
        if let localAIRefinement {
            events.append(.init(
                occurredAt: localAIRefinement.refinedAt,
                kind: .localAIRefined,
                modelDisplayName: localAIRefinement.modelDisplayName,
                persona: localAIRefinement.persona
            ))
        }
        if let manualEditAt {
            events.append(.init(occurredAt: manualEditAt, kind: .manualEdit))
        }
        if let revision {
            events.append(.init(
                occurredAt: revision.createdAt,
                kind: .revisionCreated,
                parentProofId: revision.parentProofId,
                parentCommitment: revision.parentCommitment
            ))
        }

        return events.enumerated().sorted { left, right in
            if left.element.occurredAt != right.element.occurredAt {
                return left.element.occurredAt < right.element.occurredAt
            }
            let leftRank = rank(left.element.kind)
            let rightRank = rank(right.element.kind)
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
    }

    private static func rank(_ kind: ProofManifest.ProvenanceEvent.Kind) -> Int {
        switch kind {
        case .messageStarted: 0
        case .voiceCapture: 1
        case .voiceSectionAdded: 2
        case .cleanupApplied: 3
        case .localAIRefined: 4
        case .manualEdit: 5
        case .revisionCreated: 6
        }
    }
}

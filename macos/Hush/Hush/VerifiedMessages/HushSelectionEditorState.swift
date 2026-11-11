import Foundation

enum HushThinkingPresentation {
    enum LiveStage: String, Sendable, Equatable {
        case reviewingContext = "Reviewing context"
        case planningResponse = "Planning response"
        case writingResponse = "Writing response"
        case checkingResult = "Checking result"
    }

    static func liveStage(
        elapsed: TimeInterval,
        hasAssistantOutput: Bool,
        hasArtifactOutput: Bool
    ) -> LiveStage {
        if hasArtifactOutput { return .checkingResult }
        if hasAssistantOutput { return .writingResponse }
        return elapsed < 1.2 ? .reviewingContext : .planningResponse
    }

    static func completedSummary(instruction: String, createdArtifact: Bool) -> String {
        let request = requestExcerpt(instruction)
        if createdArtifact {
            return "Reviewed “\(request)” against the current text, applied the requested change, and checked the new version for completeness."
        }
        return "Considered “\(request)” in the context of the current text and conversation before answering."
    }

    private static func requestExcerpt(_ instruction: String) -> String {
        let compact = instruction
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard compact.count > 96 else { return compact }
        return String(compact.prefix(93)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

@MainActor
final class HushSelectionEditorState {
    enum Mode: Int, Sendable {
        case compose
        case editWithAI
    }

    struct Revision: Identifiable, Sendable, Equatable {
        let id: UUID
        let number: Int
        let instruction: String
        let assistantMessage: String
        let inputText: String
        let text: String
        let persona: Profile?
        let providerName: String
        let outputTokenCount: Int?
        let generationDuration: TimeInterval?
        let createdAt: Date
    }

    struct ConversationTurn: Identifiable, Sendable, Equatable {
        let id: UUID
        let instruction: String
        let assistantMessage: String
        let revisionID: UUID?
        let outputTokenCount: Int?
        let generationDuration: TimeInterval?
        let createdAt: Date
    }

    let originalText: String
    private(set) var mode: Mode = .compose
    private(set) var currentText: String
    private(set) var revisions: [Revision] = []
    private(set) var conversationTurns: [ConversationTurn] = []
    private(set) var activeRevisionID: UUID?
    private(set) var containsManualEdits = false

    init(originalText: String) {
        self.originalText = originalText
        self.currentText = originalText
    }

    func selectMode(_ mode: Mode) {
        self.mode = mode
    }

    func setManualText(_ text: String) {
        currentText = text
        containsManualEdits = true
    }

    func setProgrammaticText(_ text: String) {
        currentText = text
    }

    @discardableResult
    func appendRevision(
        text: String,
        instruction: String,
        assistantMessage: String = "I updated the text.",
        inputText: String,
        persona: Profile?,
        providerName: String,
        outputTokenCount: Int? = nil,
        generationDuration: TimeInterval? = nil,
        createdAt: Date = Date()
    ) -> Revision {
        let revision = Revision(
            id: UUID(),
            number: revisions.count + 1,
            instruction: instruction,
            assistantMessage: assistantMessage,
            inputText: inputText,
            text: text,
            persona: persona,
            providerName: providerName,
            outputTokenCount: outputTokenCount,
            generationDuration: generationDuration,
            createdAt: createdAt
        )
        revisions.append(revision)
        conversationTurns.append(ConversationTurn(
            id: UUID(),
            instruction: instruction,
            assistantMessage: assistantMessage,
            revisionID: revision.id,
            outputTokenCount: outputTokenCount,
            generationDuration: generationDuration,
            createdAt: createdAt
        ))
        currentText = text
        activeRevisionID = revision.id
        return revision
    }

    @discardableResult
    func appendConversationResponse(
        instruction: String,
        assistantMessage: String,
        outputTokenCount: Int? = nil,
        generationDuration: TimeInterval? = nil,
        createdAt: Date = Date()
    ) -> ConversationTurn {
        let turn = ConversationTurn(
            id: UUID(),
            instruction: instruction,
            assistantMessage: assistantMessage,
            revisionID: nil,
            outputTokenCount: outputTokenCount,
            generationDuration: generationDuration,
            createdAt: createdAt
        )
        conversationTurns.append(turn)
        return turn
    }

    func revision(id: UUID) -> Revision? {
        revisions.first(where: { $0.id == id })
    }

    func useRevision(id: UUID) {
        guard let revision = revisions.first(where: { $0.id == id }) else { return }
        currentText = revision.text
        activeRevisionID = revision.id
    }

    func restoreOriginal(to text: String? = nil) {
        currentText = text ?? originalText
        revisions.removeAll()
        conversationTurns.removeAll()
        activeRevisionID = nil
        containsManualEdits = false
    }

    var activeRevision: Revision? {
        guard let activeRevisionID else { return nil }
        return revisions.first(where: { $0.id == activeRevisionID })
    }

    var usedLocalAI: Bool { activeRevision != nil }

    var totalOutputTokenCount: Int? {
        let counts = revisions.compactMap(\.outputTokenCount)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    func replaceWithVoiceEditedText(_ text: String) {
        currentText = text
        revisions.removeAll()
        conversationTurns.removeAll()
        activeRevisionID = nil
    }
}

import Foundation
import Testing
@testable import Hush

@MainActor
@Suite("Hush selection editor state")
struct HushSelectionEditorStateTests {
    @Test("Safe progress stages follow observable generation state")
    func safeProgressStages() {
        #expect(HushThinkingPresentation.liveStage(
            elapsed: 0.4,
            hasAssistantOutput: false,
            hasArtifactOutput: false
        ) == .reviewingContext)
        #expect(HushThinkingPresentation.liveStage(
            elapsed: 1.5,
            hasAssistantOutput: false,
            hasArtifactOutput: false
        ) == .planningResponse)
        #expect(HushThinkingPresentation.liveStage(
            elapsed: 1.5,
            hasAssistantOutput: true,
            hasArtifactOutput: false
        ) == .writingResponse)
        #expect(HushThinkingPresentation.liveStage(
            elapsed: 1.5,
            hasAssistantOutput: true,
            hasArtifactOutput: true
        ) == .checkingResult)
    }

    @Test("Completed thinking summaries are contextual without private reasoning")
    func contextualThinkingSummary() {
        #expect(HushThinkingPresentation.completedSummary(
            instruction: "Make it shorter",
            createdArtifact: true
        ) == "Reviewed “Make it shorter” against the current text, applied the requested change, and checked the new version for completeness.")
        #expect(HushThinkingPresentation.completedSummary(
            instruction: "What would you improve?",
            createdArtifact: false
        ) == "Considered “What would you improve?” in the context of the current text and conversation before answering.")
    }

    @Test("AI revisions are versioned and only the chosen version is current")
    func versionsRemainSelectable() {
        let state = HushSelectionEditorState(originalText: "Original")
        let first = state.appendRevision(
            text: "First",
            instruction: "Make it clear",
            inputText: "Original",
            persona: nil,
            providerName: "Apple Intelligence",
            outputTokenCount: 12
        )
        _ = state.appendRevision(
            text: "Second",
            instruction: "Make it shorter",
            inputText: "First",
            persona: nil,
            providerName: "Apple Intelligence",
            outputTokenCount: 8,
            generationDuration: 1.25
        )

        #expect(state.currentText == "Second")
        #expect(state.revisions.map(\.number) == [1, 2])
        state.useRevision(id: first.id)
        #expect(state.currentText == "First")
        #expect(state.activeRevisionID == first.id)
        #expect(state.totalOutputTokenCount == 20)
        #expect(state.revisions.last?.generationDuration == 1.25)
    }

    @Test("Manual editing preserves truthful AI origin metadata")
    func manualTextPreservesRevisionOrigin() {
        let state = HushSelectionEditorState(originalText: "Original")
        _ = state.appendRevision(
            text: "AI text",
            instruction: "Polish",
            inputText: "Original",
            persona: nil,
            providerName: "Local model"
        )
        state.setManualText("My own edit")

        #expect(state.currentText == "My own edit")
        #expect(state.activeRevision?.text == "AI text")
        #expect(state.usedLocalAI)
        #expect(state.containsManualEdits)
    }

    @Test("Restore original removes generated revision state")
    func restoreIsTruthful() {
        let state = HushSelectionEditorState(originalText: "Original")
        _ = state.appendRevision(
            text: "Changed",
            instruction: "Rewrite",
            inputText: "Original",
            persona: nil,
            providerName: "Local model"
        )
        state.restoreOriginal()

        #expect(state.currentText == "Original")
        #expect(state.revisions.isEmpty)
        #expect(!state.usedLocalAI)
        #expect(!state.containsManualEdits)
    }

    @Test("Conversation replies do not create or replace text artifacts")
    func conversationalReplyKeepsCurrentArtifact() {
        let state = HushSelectionEditorState(originalText: "Original")
        state.appendConversationResponse(
            instruction: "What would you improve?",
            assistantMessage: "I would tighten the opening.",
            outputTokenCount: 9,
            generationDuration: 0.8
        )

        #expect(state.currentText == "Original")
        #expect(state.revisions.isEmpty)
        #expect(state.conversationTurns.count == 1)
        #expect(state.conversationTurns[0].revisionID == nil)
        #expect(!state.usedLocalAI)
    }
}

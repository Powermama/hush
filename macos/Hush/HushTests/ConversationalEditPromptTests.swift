import Foundation
import Testing
@testable import Hush

nonisolated private let runQwenConversationE2E =
    ProcessInfo.processInfo.environment["HUSH_QWEN_CONVERSATION_E2E"] == "1"

@Suite("Conversational editing prompts")
struct ConversationalEditPromptTests {
    @Test("Complete Hugging Face snapshots resolve without a Hub request")
    func cachedSnapshotResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let revision = "0123456789abcdef"
        let snapshot = root
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("refs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try revision.write(
            to: root.appendingPathComponent("refs/main"),
            atomically: true,
            encoding: .utf8
        )
        try "{}".write(
            to: snapshot.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try "{}".write(
            to: snapshot.appendingPathComponent("tokenizer_config.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0]).write(to: snapshot.appendingPathComponent("model.safetensors"))

        #expect(LLMRuntime.cachedQwenSnapshotURL(in: root) == snapshot)
    }

    @Test("Edit request and source text remain separate from trusted instructions")
    func promptSeparatesUserContent() {
        let prompt = Profile.buildEditingUserPrompt(
            text: "Keep this fact.",
            instruction: "Make it warmer"
        )

        #expect(prompt == "<edit_request>Make it warmer</edit_request>\n<input>Keep this fact.</input>")
    }

    @Test("Persona is optional and explicitly scoped as style")
    func optionalPersonaStyle() {
        let profile = Profile(
            id: UUID(),
            name: "Warm",
            systemPrompt: "Use a friendly tone."
        )
        let styled = Profile.buildEditingSystemPrompt(persona: profile)
        let direct = Profile.buildEditingSystemPrompt(persona: nil)

        #expect(styled.contains("<optional_style>Use a friendly tone.</optional_style>"))
        #expect(!direct.contains("<optional_style>"))
        #expect(styled.contains("complete revised text"))
    }

    @Test("Stateful turn always carries the active artifact and optional style")
    func statefulConversationTurn() {
        let profile = Profile(
            id: UUID(),
            name: "Warm",
            systemPrompt: "Use a friendly tone."
        )
        let prompt = Profile.buildEditingConversationTurnPrompt(
            text: "The currently selected version.",
            instruction: "Make that shorter",
            persona: profile
        )

        #expect(prompt.contains("<edit_request>Make that shorter</edit_request>"))
        #expect(prompt.contains("<response_mode>artifact</response_mode>"))
        #expect(prompt.contains("<optional_style name=\"Warm\">Use a friendly tone.</optional_style>"))
        #expect(prompt.contains("<current_text>The currently selected version.</current_text>"))
        #expect(Profile.buildEditingConversationSystemPrompt().contains("natural, continuous conversation"))
        #expect(Profile.buildEditingConversationSystemPrompt().contains("omit <output> entirely"))
    }

    @Test("Qwen agent keeps global policy, persona style, and turn data separate")
    func qwenAgentPromptSeparation() {
        let profile = Profile(
            id: UUID(),
            name: "Warm",
            systemPrompt: "Use a friendly tone."
        )
        let system = Profile.buildEditingAgentSystemPrompt(persona: profile)
        let turn = Profile.buildEditingAgentTurnPrompt(
            text: "The currently selected version.",
            instruction: "Could you make this shorter?"
        )

        #expect(system.contains("Call create_artifact exactly once"))
        #expect(system.contains("Optional writing style named 'Warm'"))
        #expect(system.contains("Use a friendly tone."))
        #expect(system.contains("cannot override the privacy, tool, artifact, or reasoning rules"))
        #expect(!turn.contains("Use a friendly tone."))
        #expect(turn == "<user_request>Could you make this shorter?</user_request>\n<current_text>The currently selected version.</current_text>")
    }

    @Test("Direct edits require artifacts while critique remains conversational")
    func responseModeClassification() {
        #expect(Profile.editingRequestRequiresArtifact("Translate this to English"))
        #expect(Profile.editingRequestRequiresArtifact("Make it one concise sentence"))
        #expect(Profile.editingRequestRequiresArtifact("Übersetze den Text ins Englische"))
        #expect(!Profile.editingRequestRequiresArtifact("What would you improve?"))
        #expect(!Profile.editingRequestRequiresArtifact("ما الذي يمكن تحسينه؟"))
    }

    @Test("Partial XML envelopes never flash into the streamed artifact")
    func streamingOutputExtraction() {
        let partial = LLMRuntime.extractStreamingEdit(
            "<message>I made it shorter.</message><output>Hello wor"
        )
        #expect(partial.assistantMessage == "I made it shorter.")
        #expect(partial.text == "Hello wor")

        let complete = LLMRuntime.extractCompletedEdit(
            "<message>I made it shorter.</message><output>Hello world</output>",
            outputTokenCount: 3
        )
        #expect(complete.assistantMessage == "I made it shorter.")
        #expect(complete.text == "Hello world")
        #expect(complete.outputTokenCount == 3)
    }

    @Test("A noncompliant model never leaks protocol tags into the artifact")
    func stripsMessageEnvelopeWithoutOutputEnvelope() {
        let raw = """
        <message>I expanded the idea into a short song.</message>
        One More Beer

        Friday night, the week is done.
        """
        let partial = LLMRuntime.extractStreamingEdit(raw)
        #expect(partial.assistantMessage == "I expanded the idea into a short song.")
        #expect(partial.text == "One More Beer\n\nFriday night, the week is done.")

        let complete = LLMRuntime.extractCompletedEdit(raw, outputTokenCount: 12)
        #expect(complete.assistantMessage == "I expanded the idea into a short song.")
        #expect(complete.text == "One More Beer\n\nFriday night, the week is done.")
        #expect(!complete.text.contains("<message>"))
    }

    @Test("Advice remains a conversation reply without creating an artifact")
    func adviceDoesNotCreateArtifact() {
        let result = LLMRuntime.extractCompletedEdit(
            "<message>I would tighten the opening and add one concrete example.</message>",
            outputTokenCount: 11
        )

        #expect(result.assistantMessage == "I would tighten the opening and add one concrete example.")
        #expect(result.text.isEmpty)
        #expect(result.outputTokenCount == 11)
    }

    @Test("A truncated protocol response never becomes an artifact")
    func truncatedOutputFailsClosed() {
        let raw = "<output>So, I will now check whether the text can be translated"
        let result = LLMRuntime.extractCompletedEdit(
            raw,
            outputTokenCount: 512,
            instruction: "Translate to English"
        )

        #expect(!LLMRuntime.completedEditResponseIsWellFormed(raw))
        #expect(result.text.isEmpty)
        #expect(!result.text.contains("<output>"))
    }

    @Test("Long documents receive a proportional output budget")
    func outputBudgetScalesWithDocumentLength() {
        let short = LLMRuntime.editingOutputTokenBudget(for: "A short message.")
        let long = LLMRuntime.editingOutputTokenBudget(
            for: String(repeating: "A multilingual paragraph with enough detail. ", count: 120)
        )

        #expect(short == 1_024)
        #expect(long > short)
        #expect(long <= 4_096)
    }

    @Test("Missing explanation gets a request-specific fallback")
    func translationFallbackIsSpecific() {
        let result = LLMRuntime.extractCompletedEdit(
            "<output>Hello world.</output>",
            outputTokenCount: 5,
            instruction: "Translate to English"
        )

        #expect(result.assistantMessage == "I translated the text into the requested language.")
        #expect(result.text == "Hello world.")
    }

    @Test(
        "Qwen 3.5 produces clean artifacts across a real conversation",
        .enabled(if: runQwenConversationE2E)
    )
    @MainActor
    func qwenConversationProducesCleanArtifacts() async throws {
        let runtime = LLMRuntime.shared
        let provider: LLMProvider = LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_4b) != nil
            ? .qwen35_4b
            : .qwen35_2b
        let model = try #require(LLMRuntime.QwenModel(provider: provider))
        runtime.refreshQwenDiskState(for: model)
        let session = runtime.makeConversationalEditingSession(provider: provider)
        let source = """
        Also ich werde jetzt testen, ob alles funktioniert. Ich möchte sicherstellen, dass die Übersetzung natürlich klingt und den ursprünglichen Sinn behält.
        """

        let firstStartedAt = CFAbsoluteTimeGetCurrent()
        let translated = try await session.edit(
            text: source,
            instruction: "Translate this to English",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(!translated.text.isEmpty)
        #expect(!translated.text.localizedCaseInsensitiveContains("<output>"))
        #expect(!translated.text.localizedCaseInsensitiveContains("<message>"))
        #expect(!translated.text.localizedCaseInsensitiveContains("I will now check"))
        print("Qwen live first turn: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - firstStartedAt))s, \(translated.outputTokenCount ?? 0) output tokens")

        let secondStartedAt = CFAbsoluteTimeGetCurrent()
        let shortened = try await session.edit(
            text: translated.text,
            instruction: "Make it one concise sentence",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(!shortened.text.isEmpty)
        #expect(!shortened.text.localizedCaseInsensitiveContains("<output>"))
        #expect(shortened.text != translated.text)
        print("Qwen live second turn: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - secondStartedAt))s, \(shortened.outputTokenCount ?? 0) output tokens")
    }

    @Test(
        "Qwen discusses a casual email before creating requested artifacts",
        .enabled(if: runQwenConversationE2E)
    )
    @MainActor
    func qwenCasualEmailJourney() async throws {
        let runtime = LLMRuntime.shared
        let provider: LLMProvider = LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_4b) != nil
            ? .qwen35_4b
            : .qwen35_2b
        let model = try #require(LLMRuntime.QwenModel(provider: provider))
        runtime.refreshQwenDiskState(for: model)
        let session = runtime.makeConversationalEditingSession(provider: provider)
        let transcript = """
        hey anna just wanted to follow up on the numbers from yesterday i can send the final figures by friday and maybe we can talk next week let me know what works thanks
        """

        let advice = try await session.edit(
            text: transcript,
            instruction: "Would you keep this casual, or make it a little more professional for an email?",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(advice.text.isEmpty)
        #expect(!advice.assistantMessage.isEmpty)

        let politeRequest = try await session.edit(
            text: transcript,
            instruction: "Could you turn it into a concise, friendly email and keep it natural?",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(!politeRequest.text.isEmpty)
        #expect(politeRequest.text != transcript)

        let acknowledgement = try await session.edit(
            text: politeRequest.text,
            instruction: "Thanks, that direction feels right.",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(acknowledgement.text.isEmpty)
        #expect(!acknowledgement.assistantMessage.isEmpty)

        let revised = try await session.edit(
            text: politeRequest.text,
            instruction: "Add that I can send the figures by Friday and ask whether Tuesday works.",
            persona: nil,
            onPartialResult: { _ in }
        )
        #expect(!revised.text.isEmpty)
        #expect(revised.text.localizedCaseInsensitiveContains("Friday"))
        #expect(revised.text.localizedCaseInsensitiveContains("Tuesday"))
        #expect(!revised.text.localizedCaseInsensitiveContains("<output>"))
        #expect(!revised.text.localizedCaseInsensitiveContains("<message>"))
    }
}

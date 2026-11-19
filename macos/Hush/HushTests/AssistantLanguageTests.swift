import Testing
@testable import Hush

/// Owner decision 2026-11-19 (PRD R27): the assistant talks in English, because its voice
/// speaks English; text it writes into the user's apps keeps the language the user asks for.
@Suite("Assistant language")
struct AssistantLanguageTests {
    private let mail = CoworkerObservation(application: "Mail", window: "Draft", selectedText: "", visibleText: "",
                                           elements: [], editable: true, limitation: nil,
                                           mailDraft: .init(subject: "Termin", body: "Hallo Tom,"))

    @Test("Every assistant prompt tells the model to talk in English")
    func talksInEnglish() {
        for prompt in [CoworkerReply.instructions, CoworkerReply.operationInstructions, CoworkerReply.instructions(for: mail)] {
            #expect(prompt.contains("in English"))
            #expect(!prompt.contains("in the user's language"))
        }
    }

    @Test("Written text keeps the user's language")
    func contentKeepsLanguage() {
        #expect(CoworkerReply.instructions.contains("keeps the language the user asks"))
        #expect(CoworkerReply.instructions(for: mail).contains("keeps the language of the draft"))
    }
}

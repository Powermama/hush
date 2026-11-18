import Foundation
import Testing
@testable import Hush

@Suite("Dictation prompts and answers")
struct DictationPromptTests {
    let persona = Profile(
        id: UUID(),
        name: "Strukturierung",
        systemPrompt: "Erkenne die Absicht hinter dem gesprochenen Text und führe die Anweisung direkt aus.",
        creativity: 0.3,
        mode: .compose
    )

    @Test("Only the answer reaches the user, after reasoning and restated rules")
    func extractsTheFinalAnswer() {
        // As a tester saw it from Qwen 3.5 4B: restated rules naming the tags, plain-text reasoning, then the answer.
        let raw = """
        Write only the finished text inside <output>...</output>.
        6. No explanations, introductions, or questions

        Let me analyze the input text:
        "Ich schreib eine Meeting-Einladung an meine Chefin"
        </thinking>

        <output>Liebe Corinda, ich lade dich morgen um 10:30 Uhr zum Brunch ein.
        """
        #expect(LLMRuntime.extractOutput(raw) == "Liebe Corinda, ich lade dich morgen um 10:30 Uhr zum Brunch ein.")
    }

    @Test("Reasoning blocks are removed, closed or imitated")
    func dropsReasoning() {
        #expect(LLMRuntime.extractOutput("<think>\nplan\n</think>\n\n<output>Hallo</output>") == "Hallo")
        #expect(LLMRuntime.extractOutput("<thinking>plan</thinking>\nHallo") == "Hallo")
        #expect(LLMRuntime.extractOutput("Hallo <thinking>an unfinished plan") == "Hallo")
        #expect(LLMRuntime.extractOutput("<output>Hallo</output> trailing remark") == "Hallo")
        #expect(LLMRuntime.extractOutput("Plain answer") == "Plain answer")
        #expect(LLMRuntime.stripAnswerLabel("Answer: Hallo") == "Hallo")
    }

    @Test("Each mode is one clear task")
    func modeRules() {
        let correct = Profile.dictationRules(for: .correct)
        let compose = Profile.dictationRules(for: .compose)
        #expect(correct.contains("never something for you to do"))
        #expect(!correct.lowercased().contains("message"), "A correcting persona must not be nudged to write a message")
        #expect(compose.contains("Write that text itself"))
        for rules in [correct, compose] {
            #expect(rules.contains("DO NOT add dates, weekdays, times, names"))
            #expect(rules.contains("one item per line"))
            #expect(!rules.contains("You rewrite text"))
        }
    }

    @Test("A correcting persona never sees an example that writes a message")
    func examplesMatchTheMode() {
        for example in Profile.dictationExamples(for: .correct) {
            #expect(!example.output.contains("Hi ") && !example.output.contains("Hallo "))
        }
        #expect(Profile.dictationExamples(for: .compose).contains { $0.output.hasPrefix("- ") }, "Compose shows a list")
    }

    @Test("Qwen gets the mode's rules as the system message, its examples as turns, and the persona with the dictation")
    func qwenMessages() {
        let messages = LLMRuntime.qwenDictationMessages(transcript: "Bitte schreib eine kurze Nachricht an das Team.", profile: persona)
        let examples = Profile.dictationExamples(for: .compose)
        #expect(messages.count == 2 + 2 * examples.count)
        #expect(messages.first?.role == .system)
        #expect(messages.first?.content == Profile.qwenDictationSystemPrompt(for: .compose))
        #expect(!(messages.first?.content.contains(persona.systemPrompt) ?? true))
        for (index, example) in examples.enumerated() {
            #expect(messages[1 + 2 * index].role == .user)
            #expect(messages[2 + 2 * index].content == "<output>\(example.output)</output>")
        }
        #expect(messages.last?.role == .user)
        #expect(messages.last?.content == "<persona>\(persona.systemPrompt)</persona>\n<creativity>\(persona.creativityHint)</creativity>\n<language>German</language>\n<dictation>Bitte schreib eine kurze Nachricht an das Team.</dictation>")
    }

    @Test("Apple's instructions hold only hush's rules and the mode's examples")
    func appleInstructions() {
        let instructions = Profile.appleDictationInstructions(for: .compose)
        #expect(instructions.hasPrefix(Profile.dictationRules(for: .compose)))
        #expect(!instructions.contains(persona.systemPrompt))
        for example in Profile.dictationExamples(for: .compose) { #expect(instructions.contains("Answer: " + example.output)) }
        #expect(!Profile.appleDictationInstructions(for: .compose, examples: false).contains("Answer:"))
    }

    @Test("The dictation's language is named for the model, and left open when unclear")
    func language() {
        #expect(Profile.dictationLanguage(of: "um so I think we should uh move the meeting to monday because john is out") == "English")
        #expect(Profile.dictationLanguage(of: "also ich hab gestern mit dem Team gesprochen und wir verschieben das Release") == "German")
        #expect(Profile.dictationLanguage(of: "ok") == "the language of the dictation")
    }

    @Test("Personas saved before modes keep correcting; a mode survives saving")
    func modeCoding() throws {
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Old","systemPrompt":"Fix it.","creativity":0.3}"#
        #expect(try JSONDecoder().decode(Profile.self, from: Data(legacy.utf8)).mode == .correct)
        let saved = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(persona))
        #expect(saved.mode == .compose)
        #expect(Profile.seededProfiles.allSatisfy { $0.mode == .correct }, "Writing is Live Write's own behaviour, not a library persona")
        #expect(Profile.liveWrite.mode == .compose)
    }

    @Test("An empty persona falls back to its mode's plain task")
    func emptyPersonaByMode() {
        #expect(Profile(id: UUID(), name: "", systemPrompt: "", mode: .compose).personaTask == "Write the text I describe, clear and ready to send.")
    }

    @Test("A persona without instructions only corrects")
    func emptyPersona() {
        let empty = Profile(id: UUID(), name: "Empty", systemPrompt: "  ", creativity: 0.3)
        #expect(empty.personaTask == "Fix grammar and punctuation. Keep the wording.")
    }

    @Test("Each Qwen model samples with its model card's non-thinking settings")
    func qwenSampling() {
        let small = LLMRuntime.QwenModel.qwen35_2b.sampling
        let large = LLMRuntime.QwenModel.qwen35_4b.sampling
        // No presence penalty: MLX applies it to the prompt too, which penalised the user's own words.
        #expect(small == QwenSampling(temperature: 1.0, topP: 1.0, topK: 20, presencePenalty: 0))
        #expect(large == QwenSampling(temperature: 0.7, topP: 0.8, topK: 20, presencePenalty: 0))
        #expect(large.temperature(creativity: 1) == 0.7)
        #expect(large.temperature(creativity: 0) == 0)
        #expect(abs(large.temperature(creativity: 0.3) - 0.21) < 0.0001)
    }
}

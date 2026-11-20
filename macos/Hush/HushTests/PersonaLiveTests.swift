import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers
import Testing
@testable import Hush

/// Opt-in evaluation with the installed models: a persona decides what hush does
/// with a dictation. Run with HUSH_PERSONA_LIVE=1 (and TEST_RUNNER_HUSH_PERSONA_LIVE=1).
/// Sampling varies, so each case runs several times and reports how many runs pass.
@Suite("Personas on the installed models", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_PERSONA_LIVE"] == "1"))
@MainActor
struct PersonaLiveTests {
    nonisolated static let providers: [LLMProvider] = [.qwen35_4b, .qwen35_2b, .appleIntelligence]
    /// Runs per case: HUSH_PERSONA_RUNS, 3 by default; more to tell close variants apart.
    static let runs = Int(ProcessInfo.processInfo.environment["HUSH_PERSONA_RUNS"] ?? "") ?? 3

    /// A tester's persona that writes what is dictated, in German.
    static let assistant = Profile(
        id: UUID(),
        name: "Strukturierung",
        systemPrompt: """
        Du bist ein intelligenter deutscher Schreibassistent für Spracheingaben.

        Erkenne die Absicht hinter dem gesprochenen Text und führe die Anweisung direkt aus. Schreibe, korrigiere, strukturiere oder formatiere wie gewünscht. Entferne Füllwörter und Wiederholungen, ohne Informationen zu verlieren.

        Ohne Anweisung: Verbessere nur Grammatik und Lesbarkeit.
        """,
        creativity: 0.3,
        mode: .compose
    )
    static let slack = Profile(
        id: UUID(),
        name: "Slack writer",
        systemPrompt: "Write the Slack message I describe. Casual, no greeting, at most two sentences.",
        creativity: 0.3,
        mode: .compose
    )
    static let writer = Profile(id: UUID(), name: "Write for me", systemPrompt: "Write what I describe, clear and ready to send.", creativity: 0.3, mode: .compose)
    static var polish: Profile { Profile.seededProfiles[0] }

    struct Case: Sendable {
        let name: String
        let profile: Profile
        let dictation: String
        /// Problems with one output; empty when it passes.
        let check: @Sendable (String) -> [String]
    }

    nonisolated static func lacks(_ output: String, _ words: [String]) -> [String] {
        words.filter { !output.lowercased().contains($0.lowercased()) }.map { "lost \"\($0)\"" }
    }

    nonisolated static func has(_ output: String, _ pattern: String, _ problem: String) -> [String] {
        output.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil ? [] : [problem]
    }

    /// No reasoning, protocol markup, preamble or formatting the user did not ask for.
    nonisolated static func clean(_ output: String) -> [String] {
        var problems: [String] = []
        if output.isEmpty { problems.append("empty") }
        problems += has(output, #"</?(output|think|thinking|persona|dictation|creativity)>"#, "markup, reasoning or an echoed prompt")
        problems += has(output, #"^(hier ist|here is|here's|gerne|sure|okay)"#, "preamble")
        problems += has(output, #"\*\*|<h\d|<p>|^#"#, "Markdown or HTML")
        return problems
    }

    nonisolated static let weekdays = #"\b(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b"#

    static let cases: [Case] = [
        Case(name: "writes the described invitation", profile: assistant,
             dictation: "Ich schreib eine Meeting-Einladung an meine Chefin für morgen 10.30 Uhr zum Brunchen, wo wir das neuen Sales Pitch besprechen. Meine Chefin heißt Corinda und genau, mach nicht sie, sondern du kannst sie duzen.") { output in
            var problems = clean(output) + lacks(output, ["Corinda", "morgen", "Sales Pitch"])
            if !(output.contains("10:30") || output.contains("10.30")) { problems.append("lost the time") }
            problems += has(output, #"^ich schreib|du schreibst|einladung an (meine|deine) chefin|chefin heißt|heißt corinda"#, "rewrote the request instead of writing the invitation")
            problems += has(output, #"\["#, "placeholder")
            problems += has(output, weekdays, "invented a weekday")
            if output.range(of: #"\b(du|dich|dir|dein|deine)\b"#, options: [.regularExpression, .caseInsensitive]) == nil { problems.append("not addressed with du") }
            if output.range(of: #"\bSie\b"#, options: .regularExpression) != nil { problems.append("used Sie") }
            return problems
        },
        Case(name: "only corrects a plain dictation", profile: assistant,
             dictation: "also ich hab gestern mit dem Team gesprochen und wir haben beschlossen dass wir das Release auf Freitag verschieben") { output in
            var problems = clean(output) + lacks(output, ["gestern", "Team", "Release", "Freitag"])
            problems += has(output, #"\bheute\b"#, "changed the day")
            return problems
        },
        Case(name: "Polish keeps a request as corrected text", profile: polish,
             dictation: "schreib eine kurze Mail an Tom dass ich heute später komme") { output in
            var problems = clean(output) + lacks(output, ["schreib", "Tom", "heute", "später"])
            problems += has(output, #"^(hallo|liebe|lieber|hi)\b|betreff"#, "wrote the mail")
            if !output.contains(", dass") { problems.append("no comma before dass") }
            return problems
        },
        Case(name: "writes the described Slack message", profile: slack,
             dictation: "tell the team in slack that the deploy is moved to thursday at 3pm because QA found a bug in the login flow") { output in
            var problems = clean(output) + lacks(output, ["Thursday", "3", "login"])
            problems += has(output, #"^tell the team"#, "rewrote the request instead of writing the message")
            problems += has(output, #"^(hi|hey|hello)\b"#, "added a greeting")
            return problems
        },
        Case(name: "writes the described to-do list", profile: writer,
             dictation: "make me a to-do list for tomorrow call the bank about the card finish the slides for Friday and uh buy a present for Lisa") { output in
            var problems = clean(output) + lacks(output, ["bank", "slides", "Friday", "Lisa"])
            let items = output.split(separator: "\n").filter { $0.range(of: #"^\s*(- |\d+\.)"#, options: .regularExpression) != nil }
            if items.count != 3 { problems.append("\(items.count) list items, not 3") }
            problems += has(output, #"\b(uh|um)\b|^make me"#, "kept the request or filler")
            return problems
        },
        Case(name: "structures the described steps in order", profile: writer,
             dictation: "schreib das als Schritte erst die Daten exportieren dann die Summen prüfen und danach das Ganze an die Buchhaltung schicken") { output in
            var problems = clean(output) + lacks(output, ["export", "Summen", "Buchhaltung"])
            let steps = output.split(separator: "\n").filter { $0.range(of: #"^\s*(\d+\.|- )"#, options: .regularExpression) != nil }
            if steps.count != 3 { problems.append("\(steps.count) steps, not 3") }
            let order = ["export", "Summen", "Buchhaltung"].compactMap { output.range(of: $0, options: .caseInsensitive)?.lowerBound }
            if order.count == 3 && order != order.sorted() { problems.append("changed the order") }
            return problems
        },
        Case(name: "writes the described formal email", profile: writer,
             dictation: "write a formal email to Mr Becker that the contract is ready to sign and we can send it on Monday") { output in
            var problems = clean(output) + lacks(output, ["Becker", "contract", "Monday"])
            problems += has(output, #"^write a formal"#, "rewrote the request instead of writing the email")
            problems += has(output, #"\bhey\b|\bcheers\b"#, "not formal")
            return problems
        },
        Case(name: "turns loose context into a structured email", profile: writer,
             dictation: "okay I need an email to Steffi she's our CEO um she's preparing the board meeting and wants an update from my team so tell her the beta launched last week we have 40 pilot customers and the main risk is the hiring for two engineers and I need bullet points for those three things and keep it short and professional") { output in
            var problems = clean(output) + lacks(output, ["Steffi", "beta", "40", "pilot", "hiring", "board"])
            problems += has(output, #"^(okay|i need an email)"#, "rewrote the request instead of writing the email")
            let bullets = output.split(separator: "\n").filter { $0.range(of: #"^\s*(- |\d+\.|• )"#, options: .regularExpression) != nil }
            if bullets.count != 3 { problems.append("\(bullets.count) bullet points, not 3") }
            if output.range(of: #"^(hi|hello|dear|good (morning|afternoon))\b[^\n]*steffi"#, options: [.regularExpression, .caseInsensitive]) == nil { problems.append("no greeting to Steffi on the first line") }
            problems += has(output, #"\[|\b(monday|tuesday|wednesday|thursday|friday)\b"#, "invented a date or placeholder")
            problems += has(output, #"\b(um|uh)\b"#, "kept filler words")
            return problems
        },
        // Languages hush has no special code for: the model decides and writes in them.
        Case(name: "writes the described email in French", profile: writer,
             dictation: "écris un mail à Paul pour lui dire que je serai en retard demain matin et que la réunion peut commencer sans moi") { output in
            var problems = clean(output) + lacks(output, ["Paul", "demain", "retard", "réunion"])
            problems += has(output, #"^écris"#, "rewrote the request instead of writing the email")
            if output.range(of: #"^(bonjour|salut|cher|coucou)\b[^\n]*paul"#, options: [.regularExpression, .caseInsensitive]) == nil { problems.append("no French greeting to Paul") }
            problems += has(output, #"\b(dear|tomorrow|meeting|regards)\b"#, "switched to English")
            return problems
        },
        Case(name: "cleans a Spanish dictation without acting", profile: polish,
             dictation: "eh bueno creo que deberíamos mover la reunión al lunes porque Juan no está") { output in
            var problems = clean(output) + lacks(output, ["reunión", "lunes", "Juan"])
            problems += has(output, #"^eh\b"#, "kept the hesitation")
            problems += has(output, #"\b(meeting|monday|because)\b"#, "switched to English")
            return problems
        },
        Case(name: "removes French hesitations", profile: polish,
             dictation: "euh donc je pense que euh on devrait déplacer la réunion à lundi") { output in
            var problems = clean(output) + lacks(output, ["réunion", "lundi"])
            problems += has(output, #"\beuh\b"#, "kept the hesitation")
            problems += has(output, #"\b(meeting|monday|think)\b"#, "switched to English")
            return problems
        },
        Case(name: "Polish only cleans an English dictation", profile: polish,
             dictation: "um so I think we should uh move the meeting to monday because john is out") { output in
            var problems = clean(output) + lacks(output, ["meeting", "Monday", "John"])
            problems += has(output, #"\b(um|uh)\b"#, "kept filler words")
            return problems
        },
    ]

    /// Models that are not set up on this Mac are reported and skipped, never silently passed.
    private func available(_ provider: LLMProvider) -> Bool {
        let ready = switch provider {
        case .qwen35_2b: LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_2b) != nil
        case .qwen35_4b: LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_4b) != nil
        default: true
        }
        if !ready { print("[persona-live] SKIPPED \(provider.rawValue): not downloaded on this Mac") }
        return ready
    }

    private func evaluate(_ label: String, _ generate: (Case) async throws -> String) async throws {
        var summary: [String] = []
        for item in Self.cases {
            var passed = 0
            for run in 1...Self.runs {
                let output = try await generate(item)
                let problems = item.check(output)
                if problems.isEmpty { passed += 1 }
                print("[persona-live] \(label) | \(item.name) | run \(run) | \(problems.isEmpty ? "PASS" : "FAIL " + problems.joined(separator: ", "))\n\(output)\n")
            }
            summary.append("\(passed)/\(Self.runs)  \(item.name)")
            #expect(passed == Self.runs, "\(label): \(item.name) passed \(passed)/\(Self.runs)")
        }
        print("[persona-live] SUMMARY \(label)\n" + summary.joined(separator: "\n"))
    }

    @Test("Each persona does its task on each model", arguments: providers)
    func personas(provider: LLMProvider) async throws {
        guard available(provider) else { return }
        try await evaluate(provider.rawValue) { item in
            try await LLMRuntime.shared.generate(transcript: item.dictation, profile: item.profile, provider: provider)
        }
    }

    /// The choice between ways of reaching Apple's model rests on this comparison.
    @Test("Apple Intelligence, each way of passing the persona", arguments: LLMRuntime.AppleDictationStyle.allCases)
    func appleStyles(style: LLMRuntime.AppleDictationStyle) async throws {
        try await evaluate("appleIntelligence/\(style)") { item in
            // Through the same deterministic cleanup as the app, so the variants compare fairly.
            let spoken = item.dictation.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try await LLMRuntime.shared.generateAppleDictation(transcript: spoken, profile: item.profile, style: style)
            return DictationCleanup.finishing(output, dictation: spoken)
        }
    }

    /// The prompt Qwen actually receives: with thinking off, Qwen 3.5's chat template opens the
    /// reply with an empty think block, so the model answers instead of reasoning in plain text.
    @Test("hush's Qwen prompt reaches the model with thinking switched off")
    func qwenPromptHasThinkingOff() async throws {
        let snapshot = try #require(LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_4b))
        let container = try await VLMModelFactory.shared.loadContainer(from: snapshot, using: #huggingFaceTokenizerLoader())
        let profile = Self.assistant
        let rendered = try await container.perform { context in
            // Chat messages are not Sendable: build them where they are used.
            let messages = LLMRuntime.qwenDictationMessages(transcript: "Test", profile: profile)
            let input = try await context.processor.prepare(input: UserInput(
                chat: messages,
                additionalContext: ["enable_thinking": false]
            ))
            return context.tokenizer.decode(tokenIds: input.text.tokens.asArray(Int.self))
        }
        print("[persona-live] rendered Qwen prompt:\n\(rendered)")
        #expect(rendered.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
        #expect(rendered.contains("<|im_start|>system\nYou are the writing step of hush"))
    }
}

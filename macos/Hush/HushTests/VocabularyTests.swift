import Foundation
import Testing
@testable import Hush

/// PRD R13: the user's names and terms are written their way in every dictation.
@Suite("Vocabulary")
struct VocabularyTests {
    private let terms = [
        VocabularyTerm(term: "hush", soundsLike: ["hash", "husch"]),
        VocabularyTerm(term: "Kubernetes", soundsLike: ["cuba netties", "kuber nets"]),
        VocabularyTerm(term: "C++", soundsLike: ["c plus plus"]),
        VocabularyTerm(term: "Müller GmbH", soundsLike: ["müller gmbh", "mueller"]),
    ]

    @Test("Aliases become the term, ignoring case, whole words only")
    func wholeWords() {
        #expect(Vocabulary.apply(terms, to: "Open Hash and type") == "Open hush and type")
        #expect(Vocabulary.apply(terms, to: "a hashtag and #hash") == "a hashtag and #hush")
        #expect(Vocabulary.apply(terms, to: "husch, hash.") == "hush, hush.")
    }

    @Test("Multi-word aliases match across any spacing")
    func multiWord() {
        #expect(Vocabulary.apply(terms, to: "deploy to cuba  netties now") == "deploy to Kubernetes now")
        #expect(Vocabulary.apply(terms, to: "I write C plus plus") == "I write C++")
    }

    @Test("Letters in any script count as part of a word")
    func unicode() {
        #expect(Vocabulary.apply(terms, to: "Brief an mueller") == "Brief an Müller GmbH")
        #expect(Vocabulary.apply(terms, to: "Muellers") == "Muellers")
    }

    @Test("A term is never replaced again by another alias")
    func singlePass() {
        let chained = [
            VocabularyTerm(term: "beta", soundsLike: ["alpha"]),
            VocabularyTerm(term: "gamma", soundsLike: ["beta"]),
        ]
        #expect(Vocabulary.apply(chained, to: "alpha beta") == "beta gamma")
    }

    @Test("No aliases leave the text unchanged")
    func noAliases() {
        let plain = [VocabularyTerm(term: "Qwen")]
        #expect(Vocabulary.apply(plain, to: "  qwen (test) $1 ") == "  qwen (test) $1 ")
        #expect(Vocabulary.apply([], to: "hash") == "hash")
    }

    @Test("Terms are trimmed, unique and sorted; an alias equal to the term is dropped")
    func normalized() {
        let list = Vocabulary.normalized([
            VocabularyTerm(term: " zeta ", soundsLike: ["Zeta", " zita ", ""]),
            VocabularyTerm(term: "Alpha"),
            VocabularyTerm(term: "alpha"),
            VocabularyTerm(term: "  "),
        ])
        #expect(list.map(\.term) == ["Alpha", "zeta"])
        #expect(list[1].soundsLike == ["zita"])
    }

    @Test("Every dictation path applies the vocabulary")
    func postProcessor() async throws {
        let processed = try await BasicPostProcessor(vocabulary: terms).process("  open  hash ", language: "en")
        #expect(processed == "open hush")
    }

    @Test("Live Write's prompt lists the terms")
    func prompt() {
        let profile = Profile(id: UUID(), name: "", systemPrompt: "", creativity: 0.3)
        let turn = Profile.buildDictationTurn(transcript: "Test", profile: profile, vocabulary: ["hush", "Kubernetes"])
        #expect(turn.hasSuffix("<vocabulary>hush, Kubernetes</vocabulary>"))
        #expect(!Profile.buildDictationTurn(transcript: "Test", profile: profile).contains("<vocabulary>"))
    }

    @Test("The list persists through Settings")
    @MainActor
    func persists() {
        let suite = "hush.tests.vocabulary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        #expect(settings.vocabulary.isEmpty)
        settings.vocabulary = [VocabularyTerm(term: "hush", soundsLike: ["hash"]), VocabularyTerm(term: "Hush")]
        #expect(Settings(defaults: defaults).vocabulary == [VocabularyTerm(term: "hush", soundsLike: ["hash"])])
    }
}

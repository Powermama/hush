import Foundation
import NaturalLanguage
import Testing
@testable import Hush

/// PRD R13: the pieces of the engine boosts that need no model.
@Suite("Vocabulary boost")
struct VocabularyBoostTests {
    #if canImport(FluidAudio)
    @Test("Timed words become one word token each, ending where the next starts")
    func timings() {
        let words = [TimedWord(text: "call", start: 0.2), TimedWord(text: "at", start: 0.6), TimedWord(text: "3.", start: 0.8)]
        let timings = ParakeetVocabularyBoost.timings(for: words, end: 1.0)
        #expect(timings.map(\.token) == ["\u{2581}call", "\u{2581}at", "\u{2581}3."])
        #expect(timings.map(\.endTime) == [0.6, 0.8, 1.0])
        let long = ParakeetVocabularyBoost.timings(for: [TimedWord(text: "pause", start: 1)], end: 9)
        #expect(long[0].endTime == 2.5, "a word before a long pause does not span the silence")
    }

    @Test("A word that only drops letters from what was said is not a fix")
    func parts() {
        #expect(ParakeetVocabularyBoost.isPart("Java", of: "XJava"))
        #expect(ParakeetVocabularyBoost.isPart("Java", of: "X-Java"))
        #expect(!ParakeetVocabularyBoost.isPart("Ollama", of: "Olima"))
        #expect(!ParakeetVocabularyBoost.isPart("Qwen", of: "Quen"))
    }
    #endif

    @Test("Real words are protected, in English and German; misheard names are not")
    func everydayWords() {
        let languages: [NLLanguage] = [.english, .german]
        for word in ["going", "April", "call at", "making", "selling", "Bahnhof", "morgen"] {
            #expect(EverydayWords.containsAny(of: word, languages: languages), "\(word)")
        }
        for word in ["Cressman", "Zyintrava", "Olima", "Quen", "Villorix"] {
            #expect(!EverydayWords.containsAny(of: word, languages: languages), "\(word)")
        }
    }
}

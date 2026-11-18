import Foundation
import NaturalLanguage
import os

/// Whether a word is an ordinary word of the user's languages (PRD R13). The user's
/// vocabulary may replace misheard non-words, never real words.
///
/// Uses the on-device word lists behind Natural Language's word embeddings, which are safe
/// off the main thread. `NSSpellChecker` was the first choice, but it starts the system
/// spelling service on the main thread and stalled the app on first use.
nonisolated enum EverydayWords {
    private static let cache = OSAllocatedUnfairLock<[NLLanguage: NLEmbedding]>(initialState: [:])

    /// English plus the dictation language and the user's preferred languages.
    static func languages(dictationLanguage: String) -> [NLLanguage] {
        var codes = ["en"] + Locale.preferredLanguages.map { String($0.prefix(2)) }
        if dictationLanguage != "auto" { codes.append(dictationLanguage) }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }.map { NLLanguage(rawValue: $0) }
    }

    static func containsAny(of phrase: String, languages: [NLLanguage]) -> Bool {
        let words = phrase.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 }
        guard !words.isEmpty else { return false }
        let embeddings = languages.compactMap(embedding(for:))
        // The lists keep each word's usual case: "going", "April", German "Bahnhof".
        return words.contains { word in
            let forms = Set([word, word.lowercased(), word.lowercased().capitalized])
            return embeddings.contains { embedding in forms.contains { embedding.contains($0) } }
        }
    }

    private static func embedding(for language: NLLanguage) -> NLEmbedding? {
        if let cached = cache.withLock({ $0[language] }) { return cached }
        guard let loaded = NLEmbedding.wordEmbedding(for: language) else { return nil }
        cache.withLock { $0[language] = loaded }
        return loaded
    }
}

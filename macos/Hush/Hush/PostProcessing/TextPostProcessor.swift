import Foundation

/// Hook point for iteration 2 (LLM cleanup: remove fillers, fix punctuation, capitalize, etc.).
///
/// MVP behavior: identity — return the input unchanged. The wiring is ready so we can plug in
/// a real implementation later (local MLX model or remote API) without touching the call sites.
protocol TextPostProcessor: Sendable {
    func process(_ text: String, language: String) async throws -> String
}

struct IdentityPostProcessor: TextPostProcessor {
    func process(_ text: String, language: String) async throws -> String { text }
}

/// Light-touch local cleanup that doesn't need an LLM: trims whitespace, collapses repeats.
struct BasicPostProcessor: TextPostProcessor {
    /// The user's terms (PRD R13); every dictation path runs through here, so each one,
    /// with or without Live Write, writes them the user's way.
    var vocabulary: [VocabularyTerm]

    init(vocabulary: [VocabularyTerm]) {
        self.vocabulary = vocabulary
    }

    @MainActor init() {
        self.init(vocabulary: Settings.shared.vocabulary)
    }

    func process(_ text: String, language: String) async throws -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse runs of >2 spaces (Whisper occasionally emits extras between segments).
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return Vocabulary.apply(vocabulary, to: s)
    }
}

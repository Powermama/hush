import Foundation

/// A name, brand or term the user wants written their way (PRD R13), with what the speech
/// model tends to hear instead, such as "Spazzz Hotel" for "space hotel".
nonisolated struct VocabularyTerm: Codable, Equatable, Hashable, Sendable {
    var term: String
    var soundsLike: [String]

    init(term: String, soundsLike: [String] = []) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.term = term
        self.soundsLike = soundsLike
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(term) != .orderedSame }
    }
}

/// The user's vocabulary at work. After recognition every "sounds like" spelling becomes the
/// user's term, exactly and on word boundaries, so the guarantee does not depend on a model;
/// Live Write additionally receives the terms so it spells them as listed.
nonisolated enum Vocabulary {
    /// Replaces each alias with its term, case-insensitively, whole words only (letters and
    /// digits in any script count as word characters). One pass over all aliases, longest
    /// first, so "new york city" wins over "new york" and an inserted term is never replaced
    /// again.
    static func apply(_ terms: [VocabularyTerm], to text: String) -> String {
        var termByAlias: [String: String] = [:]
        for term in terms {
            for alias in term.soundsLike where termByAlias[key(alias)] == nil {
                termByAlias[key(alias)] = term.term
            }
        }
        guard !termByAlias.isEmpty else { return text }
        let alternatives = termByAlias.keys.sorted { $0.count > $1.count }.map {
            NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+")
        }
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let term = termByAlias[key(String(text[range]))] else { continue }
            result += text[last..<range.lowerBound] + term
            last = range.upperBound
        }
        return result + text[last...]
    }

    /// Aliases compare without case and with any whitespace as one space.
    private static func key(_ alias: String) -> String {
        alias.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Unique by term, sorted, without empty entries, as the user sees the list.
    static func normalized(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        var seen = Set<String>()
        return terms.filter { !$0.term.isEmpty && seen.insert($0.term.lowercased()).inserted }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }
}

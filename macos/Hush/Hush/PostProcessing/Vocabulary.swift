import Foundation

/// A name, brand or term the user wants written their way (PRD R13), with the spellings
/// the speech model produces instead, such as "hash" for "hush".
nonisolated struct VocabularyTerm: Codable, Equatable, Hashable, Sendable {
    /// A spelling to replace. `modelID` names the speech model that produced it when the
    /// user said the word; nil when the user typed it.
    struct Spelling: Codable, Equatable, Hashable, Sendable {
        var text: String
        var modelID: String?
    }

    var term: String
    var spellings: [Spelling]

    var soundsLike: [String] { spellings.map(\.text) }

    init(term: String, spellings: [Spelling] = []) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.term = term
        var seen = Set<String>()
        self.spellings = spellings
            .map { Spelling(text: Vocabulary.cleanHeard($0.text), modelID: $0.modelID) }
            .filter { !$0.text.isEmpty && !Vocabulary.matches($0.text, term) && seen.insert($0.text.lowercased()).inserted }
    }

    init(term: String, soundsLike: [String]) {
        self.init(term: term, spellings: soundsLike.map { Spelling(text: $0) })
    }

    /// Whether the user taught this word by voice with a model other than `modelID`,
    /// so its heard spellings may not fit the model now in use.
    func needsPractice(with modelID: String?) -> Bool {
        guard let modelID else { return false }
        let heardBy = Set(spellings.compactMap(\.modelID))
        return !heardBy.isEmpty && !heardBy.contains(modelID)
    }
}

/// The user's vocabulary at work. After recognition every heard spelling becomes the
/// user's word, exactly and on word boundaries, so the guarantee does not depend on a
/// model; Live Write additionally receives the words so it spells them as listed.
nonisolated enum Vocabulary {
    /// Replaces each spelling with its word, case-insensitively, whole words only (letters
    /// and digits in any script count as word characters). One pass over all spellings,
    /// longest first, so "new york city" wins over "new york" and an inserted word is
    /// never replaced again.
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

    /// What the model heard for a single word, without the sentence punctuation it adds.
    static func cleanHeard(_ heard: String) -> String {
        heard.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether a heard spelling is already the word, ignoring case and punctuation.
    static func matches(_ heard: String, _ term: String) -> Bool {
        key(cleanHeard(heard)) == key(cleanHeard(term))
    }

    /// Whether a dictated sentence contains the word.
    static func contains(_ text: String, term: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Spellings compare without case and with any whitespace as one space.
    private static func key(_ alias: String) -> String {
        alias.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Unique by word, sorted, without empty entries, as the user sees the list.
    static func normalized(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        var seen = Set<String>()
        return terms.filter { !$0.term.isEmpty && seen.insert($0.term.lowercased()).inserted }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
    }
}

/// Decides, from the microphone level, when the user has finished saying something, so
/// teaching a word needs no button: speech starts the clock, a pause ends the clip.
nonisolated struct SpeechEndpoint: Sendable {
    enum Decision: Equatable { case listening, finished, noSpeech }

    var speechLevel: Float = 0.08
    var silenceLevel: Float = 0.04
    var minimumSpeech: TimeInterval = 0.12
    var trailingSilence: TimeInterval = 0.7
    var maximumDuration: TimeInterval = 4
    var noSpeechTimeout: TimeInterval = 6

    private var start: Date?
    private var speechSince: Date?
    private var heardSpeech = false
    private var quietSince: Date?

    /// A word: stop soon after a short pause.
    static let word = SpeechEndpoint()
    /// A sentence to test a word: longer pauses, longer clips.
    static let sentence = SpeechEndpoint(trailingSilence: 1.2, maximumDuration: 12, noSpeechTimeout: 8)

    init(trailingSilence: TimeInterval = 0.7, maximumDuration: TimeInterval = 4, noSpeechTimeout: TimeInterval = 6) {
        self.trailingSilence = trailingSilence
        self.maximumDuration = maximumDuration
        self.noSpeechTimeout = noSpeechTimeout
    }

    mutating func feed(level: Float, at now: Date) -> Decision {
        if start == nil { start = now }
        let elapsed = now.timeIntervalSince(start ?? now)
        if !heardSpeech {
            if level >= speechLevel {
                if speechSince == nil { speechSince = now }
                if now.timeIntervalSince(speechSince ?? now) >= minimumSpeech { heardSpeech = true }
            } else {
                speechSince = nil
            }
            return elapsed >= noSpeechTimeout ? .noSpeech : .listening
        }
        if elapsed >= maximumDuration { return .finished }
        if level < silenceLevel {
            if quietSince == nil { quietSince = now }
            return now.timeIntervalSince(quietSince ?? now) >= trailingSilence ? .finished : .listening
        }
        quietSince = nil
        return .listening
    }
}

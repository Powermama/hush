import Foundation

/// A word and when it starts in the recording, from the speech model's token timings.
nonisolated struct TimedWord: Equatable, Sendable {
    var text: String
    var start: TimeInterval
}

nonisolated extension TimedWord {
    /// Groups tokens into words: a token that starts with a space or SentencePiece's "▁"
    /// begins a new word. `offset` places a window's times in the whole recording.
    static func words(from tokens: [(text: String, start: TimeInterval)], offset: TimeInterval = 0) -> [TimedWord] {
        var words: [TimedWord] = []
        // Parakeet writes some words as a lone "▁" token followed by the word's pieces,
        // such as "▁", "3" for the "3" in "at 3": the boundary carries over to them.
        var boundaryPending = false
        for token in tokens {
            let startsWord = boundaryPending || token.text.hasPrefix(" ") || token.text.hasPrefix("\u{2581}")
            let text = token.text.replacingOccurrences(of: "\u{2581}", with: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                boundaryPending = boundaryPending || startsWord
                continue
            }
            boundaryPending = false
            if startsWord || words.isEmpty {
                words.append(TimedWord(text: text, start: offset + token.start))
            } else {
                words[words.count - 1].text += text
            }
        }
        return words
    }
}

/// Recognition while the user speaks (PRD R9, stage 2), on phonon's measured design:
/// every 0.4 s once speech is heard, a round transcribes the recording so far in batch
/// mode. At release only the last stretch is transcribed: words that start before the
/// cut come from the last round, which heard them with at least 2 s of right context,
/// the rest from the release pass. Words are partitioned by start time, so none can
/// appear twice. phonon measured +0.0009 WER against whole-file recognition on 1,351
/// public clips. Pure logic: the caller runs the speech model.
struct SpeechRounds: Sendable {
    struct Plan: Sendable {
        /// Time between rounds.
        var interval: TimeInterval = 0.4
        /// Right context a round's words need before they are trusted at release.
        var releaseOverlap: TimeInterval = 2
        /// Left context of the release pass before the cut.
        var releaseBefore: TimeInterval = 8
        /// Past this much uncommitted audio, a round commits its settled words.
        var softMax: TimeInterval = 60
        /// Left context of every window once words are committed.
        var before: TimeInterval = 20
        /// Shorter windows are not worth a pass.
        var minimum: TimeInterval = 0.5
        /// Two passes may disagree this much on where one word starts.
        var duplicateTolerance: TimeInterval = 0.5
    }

    /// What to transcribe now, in seconds of the recording.
    struct Window: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
    }

    let plan: Plan
    private(set) var committed: [TimedWord] = []
    /// Where uncommitted audio begins.
    private(set) var pending: TimeInterval = 0
    private(set) var lastRound: (end: TimeInterval, words: [TimedWord])?

    init(plan: Plan = Plan()) { self.plan = plan }

    /// The window for a round once `heard` seconds are recorded, or nil while too short.
    func roundWindow(heard: TimeInterval) -> Window? {
        guard heard - pending >= plan.minimum else { return nil }
        return Window(start: max(0, pending - plan.before), end: heard)
    }

    /// Keeps a finished round. Past `softMax` of uncommitted audio its settled words are
    /// committed, so later rounds stay bounded instead of growing with the recording.
    mutating func accept(round words: [TimedWord], window: Window) {
        lastRound = (window.end, words.filter { $0.start >= pending })
        guard window.end - pending > plan.softMax else { return }
        let settled = window.end - plan.releaseOverlap
        committed += words.filter { $0.start >= pending && $0.start < settled }
        pending = settled
        lastRound = (window.end, words.filter { $0.start >= pending })
    }

    /// What release still has to transcribe. With a usable round, only the last stretch;
    /// otherwise everything uncommitted, as hush did before rounds.
    func releaseWindow(end: TimeInterval) -> Window {
        if let cut = cut {
            return Window(start: max(0, cut - plan.releaseBefore), end: end)
        }
        return Window(start: max(0, pending - plan.before), end: end)
    }

    /// The final transcript from the release pass's words (times in the recording).
    func transcript(release words: [TimedWord], end: TimeInterval) -> String {
        var result = committed
        // A release pass that starts at the beginning heard everything with full context:
        // it decides every word, exactly as whole-file recognition would.
        if let cut, let lastRound, releaseWindow(end: end).start > 0 || pending > 0 {
            let before = lastRound.words.filter { $0.start >= pending && $0.start < cut }
            var after = words.filter { $0.start >= cut }
            // The two passes can place one word on both sides of the cut; keep it once.
            if let last = before.last, let first = after.first, Self.sameWord(last, first),
               first.start - last.start < plan.duplicateTolerance {
                after.removeFirst()
            }
            result += before + after
        } else {
            result += words.filter { $0.start >= pending }
        }
        return result.map(\.text).joined(separator: " ")
    }

    static func sameWord(_ a: TimedWord, _ b: TimedWord) -> Bool {
        func bare(_ word: TimedWord) -> String { word.text.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        return bare(a) == bare(b)
    }

    /// The release cut: the last round's end minus the right context its words need.
    private var cut: TimeInterval? {
        guard let lastRound else { return nil }
        let cut = lastRound.end - plan.releaseOverlap
        return cut - pending >= plan.minimum ? cut : nil
    }
}

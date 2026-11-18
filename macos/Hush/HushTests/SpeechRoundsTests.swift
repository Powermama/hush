import Foundation
import Testing
@testable import Hush

/// R9 stage 2: the join of round and release words, on phonon's design.
@Suite("Speech rounds")
struct SpeechRoundsTests {
    private func words(_ pairs: [(String, Double)]) -> [TimedWord] { pairs.map { TimedWord(text: $0.0, start: $0.1) } }

    @Test("Tokens become words at each word-start marker, with recording times")
    func tokensToWords() {
        let tokens: [(text: String, start: TimeInterval)] = [("\u{2581}Hal", 0.1), ("lo", 0.3), ("\u{2581}Welt", 0.6), (" und", 1.0), (".", 1.2)]
        #expect(TimedWord.words(from: tokens, offset: 10) == words([("Hallo", 10.1), ("Welt", 10.6), ("und.", 11.0)]))
    }

    @Test("A lone word-start marker starts the next word: \"at 3\" stays two words")
    func loneMarker() {
        let words = TimedWord.words(from: [("\u{2581}call", 0.0), ("\u{2581}at", 0.4), ("\u{2581}", 0.6), ("3", 0.6), (".", 0.7)])
        #expect(words.map(\.text) == ["call", "at", "3."])
        #expect(words[2].start == 0.6)
    }

    @Test("No round yet: release transcribes everything and keeps all of it")
    func noRound() {
        let rounds = SpeechRounds()
        #expect(rounds.releaseWindow(end: 5) == .init(start: 0, end: 5))
        #expect(rounds.transcript(release: words([("a", 0.2), ("b", 4)]), end: 5) == "a b")
    }

    @Test("Release transcribes only the last stretch and joins at the cut by start time")
    func joinAtCut() {
        var rounds = SpeechRounds()
        let window = rounds.roundWindow(heard: 20)!
        #expect(window == .init(start: 0, end: 20))
        // The round heard words up to 19.5 s; the cut is 18 s.
        rounds.accept(round: words([("one", 1), ("two", 10), ("three", 17.9), ("four", 18.2), ("fivv", 19.5)]), window: window)
        #expect(rounds.releaseWindow(end: 21) == .init(start: 10, end: 21))
        // The release pass corrects the words after the cut and adds the new ones.
        let release = words([("two", 10), ("three", 17.95), ("four", 18.1), ("five", 19.4), ("six", 20.5)])
        #expect(rounds.transcript(release: release, end: 21) == "one two three four five six")
    }

    @Test("Rounds start only with enough audio")
    func minimum() {
        #expect(SpeechRounds().roundWindow(heard: 0.3) == nil)
    }

    @Test("A long recording commits settled words and keeps rounds bounded")
    func softCommit() {
        var rounds = SpeechRounds()
        let window = rounds.roundWindow(heard: 61)!
        rounds.accept(round: words([("early", 5), ("middle", 40), ("late", 59.5)]), window: window)
        #expect(rounds.committed.map(\.text) == ["early", "middle"])
        #expect(rounds.pending == 59)
        #expect(rounds.roundWindow(heard: 70) == .init(start: 39, end: 70), "20 s of left context, not the whole recording")
        let next = rounds.roundWindow(heard: 70)!
        rounds.accept(round: words([("middle", 40), ("late", 59.5), ("end", 68)]), window: next)
        #expect(rounds.transcript(release: words([("end", 68), ("done", 69.5)]), end: 70) == "early middle late end done")
    }

    @Test("A short recording is decided by the release pass alone")
    func shortRecording() {
        var rounds = SpeechRounds()
        let window = rounds.roundWindow(heard: 3)!
        rounds.accept(round: words([("Lim,", 0.1), ("das", 0.4), ("Meeting", 0.8)]), window: window)
        #expect(rounds.releaseWindow(end: 3.4).start == 0)
        #expect(rounds.transcript(release: words([("Das", 0.4), ("Meeting", 0.8), ("ist", 1.5)]), end: 3.4) == "Das Meeting ist")
    }

    @Test("A word both passes place at the cut appears once")
    func duplicateAtCut() {
        var rounds = SpeechRounds()
        let window = rounds.roundWindow(heard: 30)!
        rounds.accept(round: words([("great.", 26), ("Uh,", 27.9)]), window: window)
        let release = words([("great.", 26), ("Uh,", 28.1), ("yes,", 28.6), ("fine.", 29.5)])
        #expect(rounds.transcript(release: release, end: 30) == "great. Uh, yes, fine.")
    }
}

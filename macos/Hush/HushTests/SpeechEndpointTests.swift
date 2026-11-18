import Foundation
import Testing
@testable import Hush

/// Teaching a word needs no button: speech starts the clip, a pause ends it.
@Suite("Speech endpoint")
struct SpeechEndpointTests {
    /// Feeds levels at 20 per second and returns the first decision that is not `listening`.
    private func run(_ endpoint: SpeechEndpoint, _ levels: [Float]) -> (SpeechEndpoint.Decision, seconds: Double) {
        var endpoint = endpoint
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for (index, level) in levels.enumerated() {
            let time = Double(index) * 0.05
            let decision = endpoint.feed(level: level, at: start.addingTimeInterval(time))
            if decision != .listening { return (decision, time) }
        }
        return (.listening, Double(levels.count) * 0.05)
    }

    private func repeated(_ level: Float, seconds: Double) -> [Float] { Array(repeating: level, count: Int(seconds * 20)) }

    @Test("A word followed by a pause finishes after the pause")
    func wordThenPause() {
        let (decision, seconds) = run(.word, repeated(0.01, seconds: 0.5) + repeated(0.3, seconds: 0.5) + repeated(0.01, seconds: 2))
        #expect(decision == .finished)
        #expect(seconds > 1.6 && seconds < 1.8)
    }

    @Test("Silence ends as nothing heard")
    func silence() {
        let (decision, seconds) = run(.word, repeated(0.01, seconds: 8))
        #expect(decision == .noSpeech)
        #expect(seconds >= 6 && seconds < 6.1)
    }

    @Test("A click is not speech")
    func click() {
        let (decision, _) = run(.word, [0.9] + repeated(0.01, seconds: 7))
        #expect(decision == .noSpeech)
    }

    @Test("Short gaps inside a word do not end it")
    func gaps() {
        let levels = repeated(0.3, seconds: 0.3) + repeated(0.02, seconds: 0.4) + repeated(0.3, seconds: 0.3) + repeated(0.01, seconds: 2)
        let (decision, seconds) = run(.word, levels)
        #expect(decision == .finished)
        #expect(seconds > 1.6)
    }

    @Test("Talking without a pause stops at the limit")
    func limit() {
        let (decision, seconds) = run(.word, repeated(0.3, seconds: 10))
        #expect(decision == .finished)
        #expect(seconds >= 4 && seconds < 4.1)
    }

    @Test("A sentence allows longer pauses")
    func sentence() {
        let levels = repeated(0.3, seconds: 1) + repeated(0.01, seconds: 0.9) + repeated(0.3, seconds: 1) + repeated(0.01, seconds: 2)
        let (decision, seconds) = run(.sentence, levels)
        #expect(decision == .finished)
        #expect(seconds > 3.9)
    }
}

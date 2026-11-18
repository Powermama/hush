import Foundation
import Testing
@testable import Hush

/// R1: no dictation is lost at the recording limit. A recording that reaches the cap keeps
/// everything said until then; only audio after the cap is dropped.
@Suite("Recording limit")
struct RecordingLimitTests {
    private let rate = 16_000.0

    private func second(_ value: Float) -> [Float] { Array(repeating: value, count: 16_000) }

    @Test("Reaching the limit keeps every sample recorded until then")
    func keepsAudioAtLimit() {
        var buffer = RecordingBuffer(maxDuration: 3, sampleRate: rate)
        let first = buffer.append(second(0.1))
        let second2 = buffer.append(second(0.2))
        let third = buffer.append(second(0.3))
        #expect(!first && !second2)
        #expect(third, "The third second reaches the 3-second cap")
        let samples = buffer.take()
        #expect(samples.count == 48_000)
        #expect(samples.first == 0.1 && samples.last == 0.3)
    }

    @Test("Audio after the limit is dropped, and the limit is reported once")
    func dropsOnlyLaterAudio() {
        var buffer = RecordingBuffer(maxDuration: 1, sampleRate: rate)
        let reached = buffer.append(second(0.1) + [0.9, 0.9])
        let again = buffer.append(second(0.5))
        #expect(reached, "Frames past the cap are cut at the cap")
        #expect(!again, "Already at the cap: no second report")
        #expect(buffer.reachedLimit)
        #expect(buffer.take() == second(0.1))
    }

    @Test("Taking the samples starts the next recording empty")
    func takeResets() {
        var buffer = RecordingBuffer(maxDuration: 1, sampleRate: rate)
        buffer.append(second(0.1))
        _ = buffer.take()
        #expect(!buffer.reachedLimit)
        #expect(buffer.take().isEmpty)
        let reached = buffer.append([0.2])
        #expect(!reached)
    }

    @Test("The limit is two minutes and is named in words")
    func twoMinutes() {
        #expect(AudioRecorder.maxDurationSeconds == 120)
        #expect(AudioRecorder.limitDescription.contains("2"))
    }
}

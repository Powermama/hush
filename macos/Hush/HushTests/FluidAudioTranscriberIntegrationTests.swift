import AVFoundation
import Foundation
import Testing
@testable import Hush

/// Real-model checks for the Parakeet path: download, compile, warm-up and
/// transcription of recorded speech, compared against the bundled Whisper model.
///
/// Opt-in because the first run downloads ~800 MB:
///   TEST_RUNNER_HUSH_PARAKEET_E2E=1 xcodebuild test -project Hush/Hush.xcodeproj -scheme Hush \
///     -only-testing:HushTests/FluidAudioTranscriberIntegrationTests
///
/// The fixtures are synthetic `say` voices (en_US, en_GB, de_DE). They prove the
/// pipeline end to end and cover short clips; they are not the real-voice accuracy
/// benchmark from PRD-parakeet-fluidaudio section 9.2.
@Suite(
    "FluidAudio transcriber integration",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["HUSH_PARAKEET_E2E"] == "1")
)
struct FluidAudioTranscriberIntegrationTests {
    struct Clip: Sendable, CustomTestStringConvertible {
        let file: String
        let language: String
        let reference: String
        var testDescription: String { file }
    }

    static let clips: [Clip] = [
        Clip(file: "en-yes", language: "en", reference: "Yes."),
        Clip(file: "en-short", language: "en", reference: "Send it now."),
        Clip(file: "en-sentence", language: "en", reference: "Please schedule the design review with Clara for Thursday at three thirty."),
        Clip(file: "en-long", language: "en", reference: "Hush is a dictation app for the Mac. You hold a shortcut, speak naturally, and the text appears wherever your cursor is. Everything runs on this computer, so your voice never leaves the device, and it keeps working when you are offline on a plane or in a train."),
        Clip(file: "de-short", language: "de", reference: "Ja, gerne."),
        Clip(file: "de-sentence", language: "de", reference: "Bitte schick mir die Unterlagen bis Freitag, damit wir das Angebot rechtzeitig fertigstellen können."),
    ]

    #if canImport(FluidAudio)
    @Test("Parakeet transcribes every clip", arguments: ParakeetModel.allCases)
    func parakeetTranscribes(model: ParakeetModel) async throws {
        let transcriber = FluidAudioTranscriber()
        let start = CFAbsoluteTimeGetCurrent()
        try await transcriber.prepare(modelID: model.id) { _ in }
        let prepareSeconds = CFAbsoluteTimeGetCurrent() - start
        #expect(ModelManager.isInCache(model.id))
        print("[parakeet] \(model.id) prepare \(String(format: "%.2f", prepareSeconds))s")

        for clip in Self.clips {
            let samples = try Self.samples(for: clip)
            let (text, seconds) = try await Self.timed {
                try await transcriber.transcribe(samples: samples, language: clip.language, fallbackCount: 0)
            }
            let wer = Self.wordErrorRate(reference: clip.reference, hypothesis: text ?? "")
            print("[parakeet] \(model.id) \(clip.file) \(String(format: "%.0f", seconds * 1000))ms WER \(String(format: "%.2f", wer)) \"\(text ?? "<nil>")\"")
            #expect(text != nil, "Empty transcript for \(clip.file)")
            #expect(wer <= 0.25, "WER \(wer) for \(clip.file): \(text ?? "<nil>")")
        }
        await transcriber.unload()
    }
    #endif

    #if canImport(WhisperKit)
    @Test("Bundled Whisper baseline on the same clips")
    func whisperBaseline() async throws {
        let whisper = WhisperKitTranscriber()
        try await whisper.prepare(modelID: "base") { _ in }
        for clip in Self.clips {
            let samples = try Self.samples(for: clip)
            let (text, seconds) = try await Self.timed {
                try await whisper.transcribe(samples: samples, language: clip.language, fallbackCount: 1)
            }
            let wer = Self.wordErrorRate(reference: clip.reference, hypothesis: text ?? "")
            print("[whisper] base \(clip.file) \(String(format: "%.0f", seconds * 1000))ms WER \(String(format: "%.2f", wer)) \"\(text ?? "<nil>")\"")
        }
        await whisper.unload()
    }
    #endif

    // MARK: - Helpers

    static func timed<T>(_ work: () async throws -> T) async rethrows -> (T, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let value = try await work()
        return (value, CFAbsoluteTimeGetCurrent() - start)
    }

    static func samples(for clip: Clip) throws -> [Float] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Speech/\(clip.file).wav")
        let file = try AVAudioFile(forReading: url)
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// Word-level edit distance over normalised words (lowercase, no punctuation).
    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let ref = words(reference)
        let hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var previous = Array(0...hyp.count)
        for (i, r) in ref.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: hyp.count)
            for (j, h) in hyp.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (r == h ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }
}

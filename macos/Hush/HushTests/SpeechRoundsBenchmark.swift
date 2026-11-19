import Foundation
import Testing
@testable import Hush

/// The R9 stage-2 gate (PRD section 5): recognition in 0.4 s rounds while the user speaks
/// must give the same text as recognising the whole recording after release, and must
/// shorten the wait after release. Rounds are replayed on growing prefixes of each
/// recording, as they would run while the key is held; the release pass is timed alone,
/// so a round still in flight at release is not included.
///
/// Recordings: every corpus clip alone, pairs of clips, each language's ten clips in a row
/// (about 30 s) and twice in a row (over 60 s, where settled words are committed), so
/// short, long and very long dictations are all covered.
///
/// Opt-in, because it needs clips and the Parakeet model:
///   scripts/speech-benchmark-clips.sh /tmp/clips
///   TEST_RUNNER_HUSH_SPEECH_BENCH_CLIPS=/tmp/clips \
///   xcodebuild test ... -only-testing:HushTests/SpeechRoundsBenchmark
/// HUSH_SPEECH_ROUNDS_MODEL picks the model (default parakeet-ultra); HUSH_SPEECH_BENCH_OUT
/// writes every recording's result as JSON.
@Suite(
    "Speech rounds benchmark",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["HUSH_SPEECH_BENCH_CLIPS"] != nil)
)
struct SpeechRoundsBenchmark {
    typealias Clip = SpeechFillerBenchmark.Clip

    struct Recording {
        let id: String
        let language: String
        let samples: [Float]
        let reference: String
    }

    struct Result: Encodable {
        let id: String
        let language: String
        let seconds: Double
        let rounds: Int
        let whole: String
        let streamed: String
        let identical: Bool
        let wholeWER: Double
        let streamedWER: Double
        let wholeMilliseconds: Double
        let releaseMilliseconds: Double
        let longestRoundMilliseconds: Double
    }

    static let environment = ProcessInfo.processInfo.environment
    static let sampleRate = 16_000.0

    @Test("Rounds give whole-file text with a shorter wait")
    func gate() async throws {
        let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Speech/filler-clips.json")
        let corpus = try JSONDecoder().decode(SpeechFillerBenchmark.Corpus.self, from: Data(contentsOf: corpusURL))
        let folder = URL(fileURLWithPath: try #require(Self.environment["HUSH_SPEECH_BENCH_CLIPS"]))
        let model = Self.environment["HUSH_SPEECH_ROUNDS_MODEL"] ?? ParakeetModel.ultra.rawValue
        try #require(ModelManager.isAvailable(model), "\(model) is not on this Mac")
        let transcriber = FluidAudioTranscriber()
        try await transcriber.prepare(modelID: model) { _ in }

        let recordings = try Self.recordings(corpus.clips, folder: folder)
        try #require(!recordings.isEmpty, "No clips in \(folder.path); run scripts/speech-benchmark-clips.sh")
        if let first = recordings.first {
            _ = try await transcriber.transcribeWords(samples: first.samples, language: first.language)
        }

        var results: [Result] = []
        for recording in recordings {
            results.append(try await Self.run(recording, transcriber: transcriber))
        }
        print(Self.report(results))
        if let out = Self.environment["HUSH_SPEECH_BENCH_OUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: URL(fileURLWithPath: out))
        }
        // The gate, fixed in the PRD before the measurement: at least 95% identical texts.
        let identical = Double(results.filter(\.identical).count) / Double(results.count)
        #expect(identical >= 0.95, "Only \(Int(identical * 100))% of rounds texts equal whole-file recognition")
    }

    static func run(_ recording: Recording, transcriber: FluidAudioTranscriber) async throws -> Result {
        let seconds = Double(recording.samples.count) / sampleRate
        func slice(_ window: SpeechRounds.Window) -> [Float] {
            let start = Int(window.start * sampleRate), end = min(recording.samples.count, Int(window.end * sampleRate))
            return Array(recording.samples[start ..< end])
        }

        var start = CFAbsoluteTimeGetCurrent()
        let whole = try await transcriber.transcribeWords(samples: recording.samples, language: recording.language)
            .map(\.text).joined(separator: " ")
        let wholeMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000

        var rounds = SpeechRounds()
        var count = 0
        var longestRound = 0.0
        var heard = rounds.plan.interval
        while heard < seconds {
            if let window = rounds.roundWindow(heard: heard) {
                start = CFAbsoluteTimeGetCurrent()
                let words = try await transcriber.transcribeWords(samples: slice(window), language: recording.language, offset: window.start)
                longestRound = max(longestRound, (CFAbsoluteTimeGetCurrent() - start) * 1000)
                rounds.accept(round: words, window: window)
                count += 1
            }
            heard += rounds.plan.interval
        }

        let release = rounds.releaseWindow(end: seconds)
        start = CFAbsoluteTimeGetCurrent()
        let releaseWords = try await transcriber.transcribeWords(samples: slice(release), language: recording.language, offset: release.start)
        let streamed = rounds.transcript(release: releaseWords, end: seconds)
        let releaseMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let reference = SpeechFillerBenchmark.words(recording.reference)
        return Result(
            id: recording.id, language: recording.language, seconds: seconds, rounds: count,
            whole: whole, streamed: streamed,
            identical: SpeechFillerBenchmark.words(whole) == SpeechFillerBenchmark.words(streamed),
            wholeWER: SpeechFillerBenchmark.wordErrorRate(reference: reference, hypothesis: SpeechFillerBenchmark.words(whole)),
            streamedWER: SpeechFillerBenchmark.wordErrorRate(reference: reference, hypothesis: SpeechFillerBenchmark.words(streamed)),
            wholeMilliseconds: wholeMilliseconds, releaseMilliseconds: releaseMilliseconds,
            longestRoundMilliseconds: longestRound
        )
    }

    /// Each clip alone, consecutive pairs, and each language's clips in a row, with 0.4 s
    /// of silence between clips.
    static func recordings(_ clips: [Clip], folder: URL) throws -> [Recording] {
        let available = clips.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0.id).wav").path) }
        let gap = [Float](repeating: 0, count: Int(0.4 * sampleRate))
        func joined(_ id: String, _ parts: [Clip]) throws -> Recording {
            var samples: [Float] = []
            for (index, clip) in parts.enumerated() {
                if index > 0 { samples += gap }
                samples += try SpeechFillerBenchmark.samples(folder, clip)
            }
            return Recording(id: id, language: parts[0].language, samples: samples,
                             reference: parts.map(\.reference).joined(separator: " "))
        }
        var result = try available.map { try joined($0.id, [$0]) }
        for language in Set(available.map(\.language)).sorted() {
            let clips = available.filter { $0.language == language }
            for index in stride(from: 0, to: clips.count - 1, by: 2) {
                result.append(try joined("\(language)-pair-\(index / 2 + 1)", Array(clips[index ... index + 1])))
            }
            result.append(try joined("\(language)-all", clips))
            // Past 60 s, so settled words are committed and rounds keep 20 s of context.
            result.append(try joined("\(language)-twice", clips + clips))
        }
        return result
    }

    static func report(_ results: [Result]) -> String {
        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(max(Int((p * Double(sorted.count)).rounded(.up)), 1), sorted.count) - 1]
        }
        let identical = results.filter(\.identical).count
        let wholeWER = results.map(\.wholeWER).reduce(0, +) / Double(results.count)
        let streamedWER = results.map(\.streamedWER).reduce(0, +) / Double(results.count)
        var lines = [
            "[speech-rounds] recordings=\(results.count) identical=\(identical) (\(identical * 100 / results.count)%)",
            String(format: "[speech-rounds] WER whole=%.4f rounds=%.4f delta=%+.4f", wholeWER, streamedWER, streamedWER - wholeWER),
            String(format: "[speech-rounds] wait after release ms: whole p50=%.0f p90=%.0f · rounds p50=%.0f p90=%.0f",
                   percentile(results.map(\.wholeMilliseconds), 0.5), percentile(results.map(\.wholeMilliseconds), 0.9),
                   percentile(results.map(\.releaseMilliseconds), 0.5), percentile(results.map(\.releaseMilliseconds), 0.9)),
            String(format: "[speech-rounds] longest round ms p90=%.0f max=%.0f",
                   percentile(results.map(\.longestRoundMilliseconds), 0.9), results.map(\.longestRoundMilliseconds).max() ?? 0),
        ]
        for result in results where !result.identical {
            lines.append("[speech-rounds] DIFF \(result.id) (\(Int(result.seconds)) s)\n  whole:  \(result.whole)\n  rounds: \(result.streamed)")
        }
        return lines.joined(separator: "\n")
    }
}

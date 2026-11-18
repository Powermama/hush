import AVFoundation
import Foundation
import Testing
@testable import Hush
#if canImport(FluidAudio)
import FluidAudio
#endif

/// How each speech engine handles hesitation sounds, on the corpus in
/// Fixtures/Speech/filler-clips.json: fillers left, reference words lost, word error
/// rate against the clean reference and time per clip, per engine and language.
/// The engines run as hush runs them; Bark 3.0 Clean runs through FluidAudio directly.
///
/// Opt-in, because it needs clips and downloaded models:
///   scripts/speech-benchmark-clips.sh /tmp/clips
///   TEST_RUNNER_HUSH_SPEECH_BENCH_CLIPS=/tmp/clips \
///   TEST_RUNNER_HUSH_SPEECH_BENCH_ENGINES=parakeet-ultra,base,large-v3-v20240930_turbo_632MB,bark-clean \
///   TEST_RUNNER_HUSH_SPEECH_BENCH_MODELS=/tmp/bench-models \
///   xcodebuild test ... -only-testing:HushTests/SpeechFillerBenchmark
/// Engines that are not on this Mac are skipped, never downloaded, except Bark, which
/// downloads into HUSH_SPEECH_BENCH_MODELS. HUSH_SPEECH_BENCH_OUT writes the results as JSON.
@Suite(
    "Speech filler benchmark",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["HUSH_SPEECH_BENCH_CLIPS"] != nil)
)
struct SpeechFillerBenchmark {

    struct Corpus: Decodable {
        let version: Int
        let clips: [Clip]
    }

    struct Clip: Decodable {
        let id: String
        let language: String
        let spoken: String
        let reference: String
        let fillers: [String]
    }

    struct Measurement: Encodable {
        let engine: String
        let clip: String
        let language: String
        let output: String
        let fillersSpoken: Int
        let fillersLeft: Int
        let wordsLost: Int
        let wordErrorRate: Double
        let milliseconds: Double
    }

    static let environment = ProcessInfo.processInfo.environment

    @Test("Every engine on every clip")
    func benchmark() async throws {
        let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Speech/filler-clips.json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
        let clipsFolder = URL(fileURLWithPath: try #require(Self.environment["HUSH_SPEECH_BENCH_CLIPS"]))
        let clips = corpus.clips.filter { FileManager.default.fileExists(atPath: clipsFolder.appendingPathComponent("\($0.id).wav").path) }
        #expect(!clips.isEmpty, "No clips in \(clipsFolder.path); run scripts/speech-benchmark-clips.sh")

        let engines = (Self.environment["HUSH_SPEECH_BENCH_ENGINES"] ?? "parakeet-ultra,base")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var measurements: [Measurement] = []
        for engine in engines {
            guard let transcribe = try await Self.engine(engine) else {
                print("[speech-bench] SKIPPED \(engine): not on this Mac")
                continue
            }
            // One warm-up, so the first clip does not carry the load time.
            if let first = clips.first { _ = try? await transcribe(try Self.samples(clipsFolder, first), first.language) }
            for clip in clips {
                let samples = try Self.samples(clipsFolder, clip)
                let start = CFAbsoluteTimeGetCurrent()
                let output = try await transcribe(samples, clip.language) ?? ""
                let measurement = Self.measure(engine: engine, clip: clip, output: output,
                                               milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
                measurements.append(measurement)
                print("[speech-bench] \(engine) | \(clip.id) | fillers left \(measurement.fillersLeft)/\(measurement.fillersSpoken) | lost \(measurement.wordsLost) | \(String(format: "%.0f", measurement.milliseconds)) ms | \(output)")
            }
        }

        print(Self.report(measurements))
        if let path = Self.environment["HUSH_SPEECH_BENCH_OUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(["corpusVersion": corpus.version]).write(to: URL(fileURLWithPath: path + ".meta.json"))
            try encoder.encode(measurements).write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Engines

    typealias Transcribe = ([Float], String) async throws -> String?

    static func engine(_ name: String) async throws -> Transcribe? {
        #if canImport(FluidAudio)
        if name == "bark-clean" {
            let folder = URL(fileURLWithPath: environment["HUSH_SPEECH_BENCH_MODELS"] ?? NSTemporaryDirectory())
            let models = try await AsrModels.downloadAndLoad(to: folder, version: .bark3Clean, progressHandler: { _ in })
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            return { samples, _ in
                var state = TdtDecoderState.make()
                return try await asr.transcribe(samples, decoderState: &state).text
            }
        }
        #endif
        guard ModelManager.isAvailable(name) else { return nil }
        let transcriber: Transcriber = ParakeetModel(rawValue: name) != nil ? FluidAudioTranscriber() : WhisperKitTranscriber()
        try await transcriber.prepare(modelID: name) { _ in }
        return { samples, language in
            try await transcriber.transcribe(samples: samples, language: language, fallbackCount: 1)
        }
    }

    // MARK: - Metrics

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }

    /// "ummm" counts as "umm" counts as "um": runs of one letter collapsed.
    static func squeezed(_ word: String) -> String {
        var result = ""
        for character in word where character != result.last { result.append(character) }
        return result
    }

    static func measure(engine: String, clip: Clip, output: String, milliseconds: Double) -> Measurement {
        let fillers = Set(clip.fillers.map { squeezed($0.lowercased()) })
        let spokenWords = words(clip.spoken)
        let outputWords = words(output)
        var remaining = outputWords
        var lost = 0
        for word in words(clip.reference) {
            if let index = remaining.firstIndex(of: word) { remaining.remove(at: index) } else { lost += 1 }
        }
        return Measurement(
            engine: engine, clip: clip.id, language: clip.language, output: output,
            fillersSpoken: spokenWords.filter { fillers.contains(squeezed($0)) }.count,
            fillersLeft: outputWords.filter { fillers.contains(squeezed($0)) }.count,
            wordsLost: lost,
            wordErrorRate: wordErrorRate(reference: words(clip.reference), hypothesis: outputWords),
            milliseconds: milliseconds
        )
    }

    static func wordErrorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (i, word) in reference.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: hypothesis.count)
            for (j, other) in hypothesis.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (word == other ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[hypothesis.count]) / Double(reference.count)
    }

    static func report(_ measurements: [Measurement]) -> String {
        var lines = ["[speech-bench] engine | language | fillers left | reference words lost | mean WER | median ms"]
        for engine in measurements.map(\.engine).uniqued() {
            for language in measurements.map(\.language).uniqued() {
                let rows = measurements.filter { $0.engine == engine && $0.language == language }
                guard !rows.isEmpty else { continue }
                let times = rows.map(\.milliseconds).sorted()
                lines.append(String(
                    format: "[speech-bench] %@ | %@ | %d/%d | %d | %.2f | %.0f",
                    engine, language,
                    rows.map(\.fillersLeft).reduce(0, +), rows.map(\.fillersSpoken).reduce(0, +),
                    rows.map(\.wordsLost).reduce(0, +),
                    rows.map(\.wordErrorRate).reduce(0, +) / Double(rows.count),
                    times[times.count / 2]
                ))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func samples(_ folder: URL, _ clip: Clip) throws -> [Float] {
        let file = try AVAudioFile(forReading: folder.appendingPathComponent("\(clip.id).wav"))
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: try #require(buffer.floatChannelData)[0], count: Int(buffer.frameLength)))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

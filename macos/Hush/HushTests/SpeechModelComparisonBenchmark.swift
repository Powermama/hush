import Foundation
import Testing
@testable import Hush

#if canImport(FluidAudio)
import FluidAudio

/// Compares a candidate Parakeet-family model with Parakeet Ultra on real speech, through
/// hush's own FluidAudio path. Opt-in: `HUSH_VOCAB_BENCH_DIR` holds the earnings22 clips
/// (see `VocabularyBoostBenchmark`), `HUSH_MODEL_BENCH_DIR` a Core ML package in a folder
/// named `parakeet-ultra` (FluidAudio's folder name for `.ultra`), with the joint model as
/// `JointDecisionv3.mlmodelc`. Under any other name FluidAudio silently downloads Ultra next
/// to it and the "candidate" is Ultra again. Nothing is written to the user's models.
///
/// 2026-11-18, Fluid Speech Pro (FluidVoice-Labs/fluid-speech-pro-coreml) through the official
/// FluidAudio 0.18.0: WER 73.1% against Ultra's 16.9%, with transcripts cut off. Its card's
/// Swift path needs FluidVoice's FluidAudio fork, so hush stays on Ultra until FluidAudio
/// supports it.
@Suite("Speech model comparison", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_MODEL_BENCH_DIR"] != nil
                && ProcessInfo.processInfo.environment["HUSH_VOCAB_BENCH_DIR"] != nil))
struct SpeechModelComparisonBenchmark {
    @Test("Candidate against Parakeet Ultra: word errors, names and time")
    func compare() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["HUSH_VOCAB_BENCH_DIR"]!)
        let clips = try JSONDecoder().decode([VocabularyBoostBenchmark.Clip].self,
                                             from: Data(contentsOf: root.appendingPathComponent("clips.json")))
        let audio = try clips.map { try VocabularyBoostIntegrationTests.load(root.appendingPathComponent($0.file)) }

        // FluidAudio keeps loaded models per repository folder, so each model is measured in
        // its own test process: `HUSH_MODEL_BENCH_RUN` is `ultra` or `candidate`.
        let run = environment["HUSH_MODEL_BENCH_RUN"] ?? "candidate"
        if run == "ultra" {
            let ultra = FluidAudioTranscriber()
            try await ultra.prepare(modelID: ParakeetModel.ultra.id) { _ in }
            let result = try await Self.run(clips: clips, audio: audio) {
                try await ultra.transcribeUnaided(samples: $0, language: "en", fallbackCount: 0) ?? ""
            }
            await ultra.unload()
            Self.report("ultra", result)
            return
        }

        let loadStart = CFAbsoluteTimeGetCurrent()
        let models = try await AsrModels.load(from: URL(fileURLWithPath: environment["HUSH_MODEL_BENCH_DIR"]!), version: .ultra)
        let candidate = AsrManager(config: .default)
        try await candidate.loadModels(models)
        print("[models] candidate load \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStart))s")
        let candidateResult = try await Self.run(clips: clips, audio: audio) { samples in
            var state = TdtDecoderState.make()
            return try await candidate.transcribe(samples, decoderState: &state, language: .english).text
        }
        await candidate.cleanup()

        Self.report("candidate", candidateResult)
    }

    static func report(_ name: String, _ result: Result) {
        print("[models] \(name): WER \(String(format: "%.2f%%", result.wer * 100)), names \(String(format: "%.1f%%", result.recall * 100)), median \(result.median) ms, p90 \(result.p90) ms")
        print("[models] \(name) errors per clip: \(result.errors.map(String.init).joined(separator: ","))")
    }

    struct Result {
        var errors: [Int] = []
        var wer: Double = 0
        var recall: Double = 0
        var median = 0, p90 = 0
    }

    static func run(clips: [VocabularyBoostBenchmark.Clip], audio: [[Float]],
                    transcribe: ([Float]) async throws -> String) async throws -> Result {
        var result = Result()
        var references = 0, spoken = 0, hits = 0
        var times: [Double] = []
        _ = try await transcribe(audio[0])  // warm-up, not measured
        for (clip, samples) in zip(clips, audio) {
            let start = CFAbsoluteTimeGetCurrent()
            let text = try await transcribe(samples)
            times.append(CFAbsoluteTimeGetCurrent() - start)
            if result.errors.count < 3 { print("[models] text \(clip.file): \(text)") }  // spot-check the model
            let errors = VocabularyBoostIntegrationTests.wordErrors(reference: clip.text, hypothesis: text)
            result.errors.append(errors)
            references += VocabularyBoostBenchmark.normalized(clip.text).count
            for keyword in clip.keywords where Vocabulary.contains(clip.text, term: keyword) {
                spoken += 1
                if Vocabulary.contains(text, term: keyword) { hits += 1 }
            }
        }
        let sorted = times.sorted()
        result.wer = Double(result.errors.reduce(0, +)) / Double(max(references, 1))
        result.recall = Double(hits) / Double(max(spoken, 1))
        result.median = Int(sorted[sorted.count / 2] * 1000)
        result.p90 = Int(sorted[Int(Double(sorted.count) * 0.9)] * 1000)
        return result
    }
}
#endif

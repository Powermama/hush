import AVFoundation
import Foundation
import Testing
@testable import Hush

#if canImport(FluidAudio)
/// PRD R13: the Parakeet boost on real speech. Reads earnings22 keyword clips (Argmax's
/// `contextual-earnings22`, dev split, CC BY-SA 4.0) exported as `clip-NNN.wav` plus
/// `clips.json` into `HUSH_VOCAB_BENCH_DIR`; the data never enters the repository.
/// Each clip's vocabulary is its call's keyword list, so names that are not said in the
/// clip are natural decoys. It runs the production path: timed words, then the boost.
@Suite("Vocabulary boost benchmark", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_VOCAB_BENCH_DIR"] != nil))
struct VocabularyBoostBenchmark {
    struct Clip: Decodable {
        let file: String
        let text: String
        let keywords: [String]
    }

    @Test("Recall, false insertions, word errors and time on real speech")
    func benchmark() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HUSH_VOCAB_BENCH_DIR"]!)
        let clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: root.appendingPathComponent("clips.json")))
        let directory = root.appendingPathComponent("ctc").appendingPathComponent(ParakeetVocabularyBoost.variant.repo.folderName)
        if !ParakeetVocabularyBoost.isInstalled(at: directory) { try await ParakeetVocabularyBoost.install(at: directory) }

        let transcriber = FluidAudioTranscriber()
        try await transcriber.prepare(modelID: ParakeetModel.ultra.id) { _ in }
        let boost = ParakeetVocabularyBoost(directory: directory)

        var spoken = 0, plainHits = 0, boostedHits = 0
        var plainFalse = 0, boostedFalse = 0
        var plainErrors = 0, boostedErrors = 0, referenceWords = 0
        var times: [Double] = [], skipped = 0, worse = 0
        for clip in clips {
            let samples = try VocabularyBoostIntegrationTests.load(root.appendingPathComponent(clip.file))
            try await boost.configure(clip.keywords.map { VocabularyTerm(term: $0) })
            let words = try await transcriber.transcribeWords(samples: samples, language: "en")
            let plain = words.map(\.text).joined(separator: " ")
            let start = CFAbsoluteTimeGetCurrent()
            let rescored = await boost.rescore(
                text: plain, timings: ParakeetVocabularyBoost.timings(for: words, end: Double(samples.count) / 16_000),
                samples: samples)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            times.append(elapsed)
            if elapsed < 0.02 { skipped += 1 }
            let boosted = rescored ?? plain
            for keyword in clip.keywords {
                let said = Vocabulary.contains(clip.text, term: keyword)
                let inPlain = Vocabulary.contains(plain, term: keyword)
                let inBoosted = Vocabulary.contains(boosted, term: keyword)
                if said {
                    spoken += 1
                    if inPlain { plainHits += 1 }
                    if inBoosted { boostedHits += 1 }
                } else {
                    if inPlain { plainFalse += 1 }
                    if inBoosted { boostedFalse += 1 }
                }
            }
            let reference = Self.normalized(clip.text)
            referenceWords += reference.count
            let plainWER = VocabularyBoostIntegrationTests.wordErrors(reference: clip.text, hypothesis: plain)
            let boostedWER = VocabularyBoostIntegrationTests.wordErrors(reference: clip.text, hypothesis: boosted)
            plainErrors += plainWER
            boostedErrors += boostedWER
            if boostedWER > plainWER {
                worse += 1
                print("[bench] worse \(clip.file): \"\(plain)\" -> \"\(boosted)\"")
            }
        }
        let sorted = times.sorted()
        func percent(_ a: Int, _ b: Int) -> String { String(format: "%.1f%%", b == 0 ? 0 : Double(a) / Double(b) * 100) }
        print("[bench] \(clips.count) clips, \(spoken) spoken keywords")
        print("[bench] keyword recall: plain \(percent(plainHits, spoken)) -> boosted \(percent(boostedHits, spoken))")
        print("[bench] keywords written but not said: plain \(plainFalse) -> boosted \(boostedFalse)")
        print("[bench] WER: plain \(percent(plainErrors, referenceWords)) -> boosted \(percent(boostedErrors, referenceWords)); clips worse \(worse)")
        print("[bench] boost time: median \(Int(sorted[sorted.count / 2] * 1000)) ms, p90 \(Int(sorted[Int(Double(sorted.count) * 0.9)] * 1000)) ms, skipped by the text check \(skipped)")
        #expect(boostedHits >= plainHits)
        #expect(boostedErrors <= plainErrors)
        await transcriber.unload()
    }

    /// Reference text without the annotation marks earnings22 uses.
    static func normalized(_ text: String) -> [String] {
        text.replacingOccurrences(of: "<unk>", with: " ").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
#endif

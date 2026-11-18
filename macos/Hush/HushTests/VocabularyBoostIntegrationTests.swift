import AVFoundation
import Foundation
import Testing
@testable import Hush

#if canImport(FluidAudio)
/// PRD R13: proves on real audio that the Parakeet boost writes the user's words, and how
/// long it takes. Opt-in like `FluidAudioTranscriberIntegrationTests`: it needs Parakeet
/// Ultra on this Mac and downloads the 97.5 MB CTC model into a temporary folder.
@Suite(
    "Vocabulary boost on real audio",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["HUSH_PARAKEET_E2E"] == "1")
)
struct VocabularyBoostIntegrationTests {
    struct Case: Sendable {
        let term: String
        let sentence: String
    }

    /// Made-up and uncommon names a general model cannot know, said in a sentence.
    static let cases = [
        Case(term: "Zyntrava", sentence: "Please send the Zyntrava report to the whole team by Friday."),
        Case(term: "Qwen", sentence: "We tested Qwen against the other local models yesterday."),
        Case(term: "Kressmann", sentence: "Clemens Kressmann will join the call at three."),
        Case(term: "Velorix", sentence: "The Velorix dashboard shows every open ticket."),
        Case(term: "Ollama", sentence: "Run the model with Ollama on your laptop."),
    ]

    /// Ordinary sentences with none of the words: the boost must leave them alone.
    static let distractors = [
        "Can you call me back at three after the meeting?",
        "The quick brown fox jumps over the lazy dog.",
        "I will send the report and the slides tomorrow morning.",
        "Let's run the numbers again before we decide.",
    ]

    @Test("The boost writes words Parakeet misses, quickly")
    func boostWritesTheWords() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("hush-ctc-\(UUID().uuidString)")
        let directory = parent.appendingPathComponent(ParakeetVocabularyBoost.variant.repo.folderName)
        defer { try? FileManager.default.removeItem(at: parent) }
        let downloadStart = CFAbsoluteTimeGetCurrent()
        try await ParakeetVocabularyBoost.install(at: directory)
        print("[boost] download \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - downloadStart))s")

        let transcriber = FluidAudioTranscriber()
        try await transcriber.prepare(modelID: ParakeetModel.ultra.id) { _ in }
        let boost = ParakeetVocabularyBoost(directory: directory)
        try await boost.configure(Self.cases.map { VocabularyTerm(term: $0.term) })

        var fixed = 0, broken = 0
        var boostTimes: [Double] = []
        for item in Self.cases {
            let samples = try Self.speak(item.sentence)
            let plain = try await transcriber.transcribeUnaided(samples: samples, language: "en", fallbackCount: 0) ?? ""
            let words = try await transcriber.transcribeWords(samples: samples, language: "en")
            let start = CFAbsoluteTimeGetCurrent()
            let boosted = await boost.rescore(
                text: words.map(\.text).joined(separator: " "),
                timings: ParakeetVocabularyBoost.timings(for: words, end: Double(samples.count) / 16_000),
                samples: samples) ?? plain
            boostTimes.append(CFAbsoluteTimeGetCurrent() - start)
            let before = Vocabulary.contains(plain, term: item.term)
            let after = Vocabulary.contains(boosted, term: item.term)
            if !before && after { fixed += 1 }
            // Writing the word is not enough: the rest of the sentence must stay as good.
            let plainErrors = Self.wordErrors(reference: item.sentence, hypothesis: plain)
            let boostedErrors = Self.wordErrors(reference: item.sentence, hypothesis: boosted)
            if (before && !after) || boostedErrors > plainErrors { broken += 1 }
            print("[boost] \(item.term): plain \"\(plain)\" | boosted \"\(boosted)\" | \(String(format: "%.0f", boostTimes.last! * 1000))ms")
        }
        var falsePositives = 0
        for sentence in Self.distractors {
            let samples = try Self.speak(sentence)
            let words = try await transcriber.transcribeWords(samples: samples, language: "en")
            let start = CFAbsoluteTimeGetCurrent()
            let boosted = await boost.rescore(
                text: words.map(\.text).joined(separator: " "),
                timings: ParakeetVocabularyBoost.timings(for: words, end: Double(samples.count) / 16_000),
                samples: samples)
            let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if let boosted { falsePositives += 1 }
            print("[boost] distractor \"\(sentence)\" -> \(boosted.map { "\"\($0)\"" } ?? "unchanged") | \(String(format: "%.1f", milliseconds))ms")
        }
        print("[boost] false positives \(falsePositives) of \(Self.distractors.count)")
        #expect(falsePositives == 0)

        let longSamples = try Self.speak(Array(repeating: Self.cases[0].sentence, count: 8).joined(separator: " "))
        let longWords = try await transcriber.transcribeWords(samples: longSamples, language: "en")
        let longStart = CFAbsoluteTimeGetCurrent()
        _ = await boost.rescore(text: longWords.map(\.text).joined(separator: " "),
                                timings: ParakeetVocabularyBoost.timings(for: longWords, end: Double(longSamples.count) / 16_000),
                                samples: longSamples)
        print("[boost] long clip \(String(format: "%.1f", Double(longSamples.count) / 16_000))s audio: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - longStart) * 1000))ms")
        print("[boost] fixed \(fixed), broke \(broken), of \(Self.cases.count)")
        #expect(broken == 0)
        #expect(fixed > 0, "The boost changed no transcript; it is not wired")
        await transcriber.unload()
    }

    /// Word-level edit distance, ignoring case and punctuation.
    static func wordErrors(reference: String, hypothesis: String) -> Int {
        func words(_ text: String) -> [String] {
            text.replacingOccurrences(of: "<unk>", with: " ").lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let r = words(reference), h = words(hypothesis)
        var row = Array(0...h.count)
        for i in 1...max(1, r.count) where !r.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: h.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (r[i - 1] == h[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return r.isEmpty ? h.count : row[h.count]
    }

    /// A sentence spoken by macOS' default voice, as 16 kHz mono samples.
    static func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hush-say-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        return try load(url)
    }

    /// An audio file as 16 kHz mono samples.
    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
#endif

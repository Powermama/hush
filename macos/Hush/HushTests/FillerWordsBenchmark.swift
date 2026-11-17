import Foundation
import Testing
@testable import Hush

/// Quality and speed of hesitation removal on Fixtures/Cleanup/filler-words.json, printed
/// as one report per run so changes to the lists or the code are compared on numbers.
/// Gate: every case without `knownGap` passes, no real word is ever removed, and a
/// known gap that starts passing must be promoted, so quality only moves up.
@Suite("Filler words benchmark")
struct FillerWordsBenchmark {

    struct Corpus: Decodable {
        let version: Int
        let cases: [Case]
    }

    struct Case: Decodable {
        let id: String
        let language: String
        let input: String
        let expected: String
        let knownGap: String?
    }

    struct Result {
        let item: Case
        let output: String
        var passed: Bool { output == item.expected }
        /// Words of the expected text that are missing: real words wrongly removed.
        var wordsLost: Int { Self.difference(item.expected, output) }
        /// Words left that the expected text does not have: sounds not removed.
        var soundsLeft: Int { Self.difference(output, item.expected) }

        static func words(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "'" }.map(String.init)
        }

        static func difference(_ text: String, _ other: String) -> Int {
            var remaining = words(other)
            var missing = 0
            for word in words(text) {
                if let index = remaining.firstIndex(of: word) { remaining.remove(at: index) } else { missing += 1 }
            }
            return missing
        }
    }

    static func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Cleanup/filler-words.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    @Test("Benchmark: quality and speed against the corpus")
    func benchmark() throws {
        let corpus = try Self.corpus()
        let results = corpus.cases.map { Result(item: $0, output: FillerWords.removing(from: $0.input, language: $0.language)) }

        // Speed: every case 200 times, so the median and slowest dictation are stable.
        var timings: [Double] = []
        for item in corpus.cases {
            for _ in 0..<200 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = FillerWords.removing(from: item.input, language: item.language)
                timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            }
        }
        timings.sort()
        let median = timings[timings.count / 2]
        let p95 = timings[timings.count * 95 / 100]

        let gated = results.filter { $0.item.knownGap == nil }
        let gaps = results.filter { $0.item.knownGap != nil }
        var report = [
            "[filler-benchmark] corpus v\(corpus.version): \(results.filter(\.passed).count)/\(results.count) exact",
            "required \(gated.filter(\.passed).count)/\(gated.count), known gaps solved \(gaps.filter(\.passed).count)/\(gaps.count)",
            "real words removed \(results.map(\.wordsLost).reduce(0, +)), sounds left \(results.map(\.soundsLeft).reduce(0, +))",
            String(format: "median %.1f µs, p95 %.1f µs per dictation", median, p95),
        ].joined(separator: " | ")
        for language in Set(results.map(\.item.language)).sorted() {
            let own = results.filter { $0.item.language == language }
            report += "\n[filler-benchmark]   \(language): \(own.filter(\.passed).count)/\(own.count)"
        }
        for result in results where !result.passed {
            report += "\n[filler-benchmark]   \(result.item.knownGap == nil ? "FAIL" : "gap ") \(result.item.id): \"\(result.output)\""
        }
        print(report)

        for result in gated {
            #expect(result.passed, "\(result.item.id): got \"\(result.output)\", expected \"\(result.item.expected)\"")
        }
        for result in results {
            #expect(result.wordsLost == 0, "\(result.item.id) removed a real word: \"\(result.output)\"")
        }
        for result in gaps where result.passed {
            Issue.record("\(result.item.id) now passes: remove its knownGap so it is required from now on")
        }
        // Generous for a debug build on a CI runner; the report carries the real number.
        #expect(p95 < 2_000, "hesitation removal must stay instant; p95 was \(p95) µs")
    }
}

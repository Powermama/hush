import Foundation
import os

/// How long one dictation made the user wait: from key release to inserted text, split
/// into its steps (PRD R7). Numbers and engine names only, never text, so it is kept
/// whatever the history setting. phonon measures the same span ("key-up to pasted text").
struct DictationTiming: Codable, Equatable, Sendable {
    var date: Date
    /// Seconds of speech.
    var audio: Double
    var transcribe: Double
    /// Live Write or a persona; zero when no AI wrote.
    var write: Double
    var insert: Double
    /// Key release to inserted text.
    var wait: Double
    var speechModel: String
    /// The writing engine, or nil for plain dictation.
    var writingEngine: String?
}

/// The wait users feel, as a median and a 90th percentile. The R9 gate is p90 < 0.3 s.
struct DictationWaitSummary: Equatable, Sendable {
    let count: Int
    let median: Double
    let p90: Double

    init?(_ waits: [Double]) {
        guard !waits.isEmpty else { return nil }
        let sorted = waits.sorted()
        count = sorted.count
        median = Self.percentile(0.5, of: sorted)
        p90 = Self.percentile(0.9, of: sorted)
    }

    /// Nearest-rank percentile, so a reported value is a wait that really happened.
    static func percentile(_ p: Double, of sorted: [Double]) -> Double {
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// The last dictation timings on this Mac, in a small JSON file beside hush's models.
@MainActor
final class DictationTimingStore {
    static let shared = DictationTimingStore()
    static let capacity = 500

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "Timing")
    private let url: URL
    private(set) var timings: [DictationTiming]

    /// Tests and previews run inside the app; they never write into the user's own timings.
    static var defaultURL: URL {
        let environment = ProcessInfo.processInfo.environment
        if environment["HUSH_TEST_HOST"] == "1" || environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--preview-") }) {
            return FileManager.default.temporaryDirectory.appendingPathComponent("hush-dictation-timings-\(ProcessInfo.processInfo.processIdentifier).json")
        }
        return AIModelStorage.root.deletingLastPathComponent().appendingPathComponent("dictation-timings.json")
    }

    init(url: URL = DictationTimingStore.defaultURL) {
        self.url = url
        timings = (try? JSONDecoder().decode([DictationTiming].self, from: Data(contentsOf: url))) ?? []
    }

    func record(_ timing: DictationTiming) {
        timings.append(timing)
        if timings.count > Self.capacity { timings.removeFirst(timings.count - Self.capacity) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(timings).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Could not save dictation timings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The recent waits, separately for plain dictation and for AI writing, which differ by
    /// an order of magnitude and must not be averaged together.
    func summary(writing: Bool, recent: Int = 50) -> DictationWaitSummary? {
        DictationWaitSummary(timings.filter { ($0.writingEngine != nil) == writing }.suffix(recent).map(\.wait))
    }
}

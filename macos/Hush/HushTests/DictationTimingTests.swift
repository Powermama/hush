import Foundation
import Testing
@testable import Hush

/// R7: the wait from key release to inserted text is measured, kept and summarised.
@Suite("Dictation timing")
@MainActor
struct DictationTimingTests {
    private func timing(_ wait: Double, writing: String? = nil) -> DictationTiming {
        DictationTiming(date: Date(), audio: 4, transcribe: 0.1, write: writing == nil ? 0 : wait - 0.15, insert: 0.05,
                        wait: wait, speechModel: "parakeet", writingEngine: writing)
    }

    private func store() -> DictationTimingStore {
        DictationTimingStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("timings-\(UUID().uuidString).json"))
    }

    @Test("Median and p90 are waits that really happened (nearest rank)")
    func percentiles() throws {
        let summary = try #require(DictationWaitSummary((1...10).map { Double($0) / 10 }))
        #expect(summary.count == 10)
        #expect(summary.median == 0.5)
        #expect(summary.p90 == 0.9)
        #expect(DictationWaitSummary([]) == nil)
        #expect(DictationWaitSummary([0.4])?.p90 == 0.4)
    }

    @Test("Plain dictation and AI writing are summarised apart")
    func splitByWriting() throws {
        let store = store()
        for wait in [0.2, 0.3, 0.25] { store.record(timing(wait)) }
        for wait in [1.6, 1.9] { store.record(timing(wait, writing: "Qwen 3.5 4B")) }
        #expect(try #require(store.summary(writing: false)).median == 0.25)
        #expect(try #require(store.summary(writing: true)).p90 == 1.9)
    }

    @Test("Timings survive a restart and keep only the newest")
    func persistsAndCaps() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("timings-\(UUID().uuidString).json")
        let first = DictationTimingStore(url: url)
        for index in 0 ..< DictationTimingStore.capacity + 3 { first.record(timing(Double(index))) }
        let reopened = DictationTimingStore(url: url)
        #expect(reopened.timings.count == DictationTimingStore.capacity)
        #expect(reopened.timings.first?.wait == 3)
    }

    @Test("Only the recent dictations count")
    func recentOnly() throws {
        let store = store()
        for _ in 0 ..< 60 { store.record(timing(5)) }
        for _ in 0 ..< 50 { store.record(timing(0.2)) }
        #expect(try #require(store.summary(writing: false)).p90 == 0.2)
    }
}

@Suite("Dictation timing storage")
@MainActor
struct DictationTimingStorageTests {
    @Test("Inside tests the shared store never points at the user's file")
    func testsUseTemporaryFile() {
        #expect(DictationTimingStore.defaultURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}

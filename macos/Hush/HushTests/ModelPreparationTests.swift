import Foundation
import Testing
@testable import Hush

private actor ModelPreparationProbe {
    private(set) var started: [String] = []
    private(set) var completed: [String] = []

    func markStarted(_ id: String) { started.append(id) }
    func markCompleted(_ id: String) { completed.append(id) }
}

private final class ProbeTranscriber: Transcriber, @unchecked Sendable {
    let probe: ModelPreparationProbe

    init(probe: ModelPreparationProbe) {
        self.probe = probe
    }

    func prepare(
        modelID: String,
        progress: @Sendable @MainActor @escaping (Double) -> Void
    ) async throws {
        await probe.markStarted(modelID)
        progress(0.25)
        try await Task.sleep(for: .milliseconds(120))
        try Task.checkCancellation()
        await probe.markCompleted(modelID)
        progress(1)
    }

    func transcribe(samples: [Float], language: String, fallbackCount: Int) async throws -> String? {
        "probe"
    }

    func unload() async {}
}

@MainActor
@Suite("Model preparation", .serialized)
struct ModelPreparationTests {
    @Test("Concurrent requests for the same model share one preparation")
    func coalescesDuplicatePreparation() async {
        let oldModelID = Settings.shared.modelID
        defer { Settings.shared.modelID = oldModelID }
        Settings.shared.modelID = "base"

        let probe = ModelPreparationProbe()
        let coordinator = DictationCoordinator { _ in
            ProbeTranscriber(probe: probe)
        }

        let first = Task { await coordinator.prepareModelInBackground() }
        await Task.yield()
        let duplicate = Task { await coordinator.prepareModelInBackground() }
        await first.value
        await duplicate.value

        #expect(await probe.started == ["base"])
        #expect(await probe.completed == ["base"])
        #expect(coordinator.isModelReady)
        #expect(coordinator.loadedModelID == "base")
        #expect(coordinator.phase.value == .idle)
    }

    @Test("Switching models cancels stale work before loading the new selection")
    func cancelsStalePreparationWhenSwitching() async {
        let oldModelID = Settings.shared.modelID
        defer { Settings.shared.modelID = oldModelID }

        let probe = ModelPreparationProbe()
        let coordinator = DictationCoordinator { _ in
            ProbeTranscriber(probe: probe)
        }

        Settings.shared.modelID = "base"
        let base = Task { await coordinator.prepareModelInBackground() }
        try? await Task.sleep(for: .milliseconds(25))

        Settings.shared.modelID = "tiny.en"
        let tiny = Task { await coordinator.prepareModelInBackground() }
        await base.value
        await tiny.value

        #expect(await probe.started == ["base", "tiny.en"])
        #expect(await probe.completed == ["tiny.en"])
        #expect(coordinator.isModelReady)
        #expect(coordinator.loadedModelID == "tiny.en")
        #expect(coordinator.phase.value == .idle)
    }
}

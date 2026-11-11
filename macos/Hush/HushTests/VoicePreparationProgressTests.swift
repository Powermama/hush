import AppKit
import Testing
@testable import Hush

@MainActor
struct VoicePreparationProgressTests {
    @Test func unknownLengthsAndPreparationNeverInventPercentages() {
        #expect(VoicePreparationProgress.percentage(received: 300, expected: -1) == nil)
        #expect(VoicePreparationProgress.percentage(received: 600, expected: 1000) == 60)
        #expect(VoicePreparationProgress.percentage(received: 1200, expected: 1000) == 100)
        #expect(VoicePreparationProgress.file(3, 62).label == "Downloading voice file 3 · 62%")
        #expect(VoicePreparationProgress.loading.fraction == nil)
        #expect(VoicePreparationProgress.warming.fraction == nil)
        #expect(!VoicePreparationProgress.file(3, nil).label.contains("%"))
    }

    @Test func progressCannotComeFromOtherModelsOrWebsites() throws {
        #expect(VoicePreparationProgress.isVoiceAsset(URL(string: "https://huggingface.co/FluidInference/kokoro-82m-coreml/resolve/pinned/file.bin")))
        #expect(!VoicePreparationProgress.isVoiceAsset(URL(string: "https://huggingface.co/FluidInference/parakeet/resolve/main/file.bin")))
        #expect(!VoicePreparationProgress.isVoiceAsset(URL(string: "https://example.com/FluidInference/kokoro-82m-coreml/resolve/main/file.bin")))
        #expect(!VoicePreparationProgress.isVoiceAsset(URL(string: "https://huggingface.co/api/models/FluidInference/kokoro-82m-coreml")))
    }

    @Test func nativeMenuNoLongerContainsAssistantEntry() {
        let panel = MenuBarPanelView(onSettings: {}, onPermissions: {}, onPersona: {}, onCheckForUpdates: {}, onQuit: {}, onRecent: { _ in })
        panel.setRecentItems([])
        panel.layoutSubtreeIfNeeded()
        func labels(_ view: NSView) -> [String] {
            (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(labels)
        }
        #expect(!labels(panel).contains("Hey Hush"))
        #expect(labels(panel).contains("Settings..."))
        #expect(labels(panel).contains("Quit hush"))
        #expect(panel.subviews.allSatisfy { $0.frame.maxY <= panel.bounds.height })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUSH_PROGRESS_FIXTURE"] != nil))
    func actualURLSessionTransferReportsIntermediatePercentage() async throws {
        let url = URL(string: "http://127.0.0.1:3017/voice.bin")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var reports: [VoicePreparationProgress] = []
        let observer = Task {
            await VoiceTransferObserver.observe(session: session, matching: { $0 == url }) { reports.append($0) }
        }
        defer { observer.cancel() }
        let (data, response) = try await session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data.count == 8 * 1024 * 1024)
        observer.cancel()
        await observer.value
        #expect(reports.contains { if case .file(1, let value) = $0, let value { return value > 0 && value < 100 }; return false })
    }
}

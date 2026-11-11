import Foundation
import Testing
@testable import Hush

@MainActor
struct AssistantSetupFlowTests {
    private typealias Step = AssistantSetupFlow.Step

    private func finish(_ flow: AssistantSetupFlow) async throws {
        for _ in 0..<200 where flow.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!flow.isRunning)
    }

    @Test func skipsInstalledComponentsAndResumesAfterFailure() async throws {
        var ready: Set<Step> = [.microphone, .intelligence]
        var performed: [Step] = []
        var failScreen = true
        let flow = AssistantSetupFlow(dependencies: .init(ready: { ready.contains($0) }, perform: { step in
            performed.append(step)
            if step == .screen && failScreen { throw CocoaError(.fileReadUnknown) }
            ready.insert(step)
        }))
        flow.start()
        try await finish(flow)
        #expect(performed == [.accessibility, .screen])
        #expect(!flow.isReady)
        guard case .failed = flow.state else { Issue.record("Failure must stay visible"); return }
        failScreen = false
        flow.start()
        try await finish(flow)
        #expect(performed == [.accessibility, .screen, .screen, .transcription, .voice])
        #expect(flow.state == .complete)
        #expect(flow.isReady)
        flow.start()
        try await finish(flow)
        #expect(performed.count == 5)
    }

    @Test func permissionRequestAloneNeverCountsAsGranted() async throws {
        var performed: [Step] = []
        let flow = AssistantSetupFlow(dependencies: .init(ready: { _ in false }, perform: { performed.append($0) }))
        flow.start()
        try await finish(flow)
        #expect(performed == [.microphone])
        #expect(!flow.isReady)
        guard case .failed = flow.state else { Issue.record("Ungrantable permission must stop setup"); return }
    }

    @Test func cancellationStopsRemainingStepsAndCanResume() async throws {
        var ready = Set<Step>()
        var performed: [Step] = []
        var waitForPermission = true
        let flow = AssistantSetupFlow(dependencies: .init(ready: { ready.contains($0) }, perform: { step in
            performed.append(step)
            if step == .accessibility && waitForPermission { try await Task.sleep(for: .seconds(60)) }
            ready.insert(step)
        }))
        flow.start()
        for _ in 0..<200 where flow.state != .working(.accessibility) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(flow.state == .working(.accessibility))
        flow.start() // Double-click must not create a second sequence.
        flow.cancel()
        try await finish(flow)
        #expect(flow.state == .cancelled)
        #expect(performed == [.microphone, .accessibility])
        #expect(ready == [.microphone])
        waitForPermission = false
        flow.start()
        try await finish(flow)
        #expect(flow.isReady)
        #expect(performed.filter { $0 == .microphone }.count == 1)
    }

    @Test func removalOnlyTouchesOwnedVoiceFilesAndAllowsReinstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-voice-removal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = VoiceModelFiles.folders + ["parakeet", "unrelated"]
        for folder in folders {
            let directory = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent("fixture.bin"))
        }
        #expect(VoiceModelFiles.bytes(in: root) == 6)
        try VoiceModelFiles.remove(in: root)
        try VoiceModelFiles.remove(in: root) // Repeated removal is harmless.
        #expect(VoiceModelFiles.bytes(in: root) == 0)
        for folder in ["parakeet", "unrelated"] {
            #expect(try Data(contentsOf: root.appendingPathComponent(folder + "/fixture.bin")) == Data([1, 2, 3]))
        }
        let voice = VoiceModelFiles.urls(in: root)[0]
        try FileManager.default.createDirectory(at: voice, withIntermediateDirectories: true)
        try Data([4, 5]).write(to: voice.appendingPathComponent("fixture.bin"))
        #expect(VoiceModelFiles.bytes(in: root) == 2)
    }
}

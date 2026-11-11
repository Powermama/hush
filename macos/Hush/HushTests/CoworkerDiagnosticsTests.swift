#if DEBUG
import AppKit
import Testing
@testable import Hush

@Suite("Development-only coworker diagnostics", .serialized)
@MainActor
struct CoworkerDiagnosticsTests {
    @Test("Each sequence step preserves its own inputs under the same storage limit")
    func stepEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-trace-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let trace = CoworkerTrace(id: UUID(), root: root)
        trace.artifact(.context, text: "first observation")
        trace.beginStep(1)
        trace.artifact(.context, text: "second observation")
        await trace.flush()
        #expect(try String(contentsOf: trace.directory.appendingPathComponent("context.json"), encoding: .utf8) == "first observation")
        #expect(try String(contentsOf: trace.directory.appendingPathComponent("step-2-context.json"), encoding: .utf8) == "second observation")
    }

    @Test("Disabled diagnostics create no trace")
    func disabled() {
        let recorder = CoworkerDiagnostics()
        recorder.enabled = false
        #expect(recorder.begin(id: UUID(), application: nil) == nil)
    }

    @Test("A trace preserves inputs, exact failure, event order, and restrictive file permissions")
    func failureEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-trace-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let trace = CoworkerTrace(id: UUID(), root: root)
        trace.event("turn.started")
        trace.artifact(.transcript, text: "Write an email to my mother.")
        trace.failure("action.failed", CoworkerError.changedContext)
        trace.finish("failed")
        await trace.flush()
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: trace.directory.appendingPathComponent("trace.json"))) as! [String: Any]
        let events = report["events"] as! [[String: Any]]
        #expect(events.map { $0["stage"] as! String } == ["turn.started", "action.failed", "turn.finished"])
        let failure = events[1]["fields"] as! [String: String]
        #expect(failure["error"] == "changedContext")
        #expect(failure["description"] == CoworkerError.changedContext.localizedDescription)
        #expect(try String(contentsOf: trace.directory.appendingPathComponent("transcript.txt"), encoding: .utf8) == "Write an email to my mother.")
        let attributes = try FileManager.default.attributesOfItem(atPath: trace.directory.appendingPathComponent("trace.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trace.directory.path).allSatisfy { !$0.hasSuffix("wav") })
    }

    @Test("Retention bounds turn count and oversized artifacts are explicitly omitted")
    func retention() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-trace-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for _ in 0..<7 {
            let trace = CoworkerTrace(id: UUID(), root: root)
            trace.event("turn.started"); trace.finish("answered"); await trace.flush()
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == CoworkerTrace.maximumTurns)
        let trace = CoworkerTrace(id: UUID(), root: root)
        trace.artifact(.screenshot, Data(repeating: 0, count: 3 * 1_024 * 1_024))
        await trace.flush()
        #expect(!FileManager.default.fileExists(atPath: trace.directory.appendingPathComponent("model-screen.png").path))
        let report = try String(contentsOf: trace.directory.appendingPathComponent("trace.json"), encoding: .utf8)
        #expect(report.contains("artifact.omitted"))
    }

    @Test("Turning diagnostics off rejects late model output")
    func disabling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hush-trace-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let trace = CoworkerTrace(id: UUID(), root: root)
        trace.event("turn.started")
        trace.disable()
        trace.artifact(.rawReply, text: "Late output must not be stored")
        trace.event("should.not.exist")
        await trace.flush()
        #expect(!FileManager.default.fileExists(atPath: trace.directory.appendingPathComponent("model-output.txt").path))
        #expect(try !String(contentsOf: trace.directory.appendingPathComponent("trace.json"), encoding: .utf8).contains("should.not.exist"))
    }

    @Test("Replay retains the actual model input and rejects a missing image")
    func replay() throws {
        let request = CoworkerRequest(text: "Write a short email to my mother saying I will visit tomorrow.",
            observation: .init(application: "Mail", window: "New message", selectedText: "", visibleText: "",
                               elements: [], editable: true, limitation: nil), history: [],
            now: Date(timeIntervalSince1970: 1_793_570_000), timeZone: TimeZone(secondsFromGMT: -10_800)!)
        let original = CoworkerReplaySnapshot(request, provider: .qwen35_4b)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CoworkerReplaySnapshot.self, from: encoder.encode(original))
        #expect(try decoded.input(screenshot: nil).prompt == request.prompt)
        var imageRequest = request; imageRequest.screenshot = Data([1, 2, 3])
        let imageReplay = CoworkerReplaySnapshot(imageRequest, provider: .qwen35_4b)
        #expect(throws: (any Error).self) { try imageReplay.input(screenshot: nil) }
    }
}

/// Explicit developer command only. Regenerates a response, never applies it.
@Suite("Recorded coworker model replay", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_REPLAY_DIRECTORY"] != nil))
@MainActor
struct CoworkerReplayTests {
    @Test("Replay a recorded model request without any desktop action")
    func modelOnly() async throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUSH_REPLAY_DIRECTORY"]))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CoworkerReplaySnapshot.self, from: Data(contentsOf: root.appendingPathComponent("replay.json")))
        let image = snapshot.hasScreenshot ? try Data(contentsOf: root.appendingPathComponent("model-screen.png")) : nil
        let provider = try #require(LLMProvider(rawValue: snapshot.provider))
        let reply = try await LLMRuntime.shared.generateCoworkerReply(snapshot.input(screenshot: image), provider: provider)
        print("[model-only-replay] \(reply)")
    }
}
#endif

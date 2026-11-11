import AppKit
import Testing
@testable import Hush

@Suite("Checked coworker sequences", .serialized)
@MainActor
struct CoworkerSequenceTests {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Sequence did not settle within five seconds")
    }

    @Test("One goal advances using new observations, new IDs and verified checkpoints")
    func freshObservations() async throws {
        let fixture = SequenceFixture()
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Open the first music video after searching")
        try await wait { fixture.actions.count == 2 }
        #expect(fixture.actions == [10, 11])
        #expect(fixture.requests.count == 2)
        #expect(fixture.requests[0].text == fixture.requests[1].text)
        #expect(fixture.requests[1].observation.visibleText == "Page 1")
        #expect(fixture.requests[1].checkpoints.map(\.result) == ["Verified page 1"])
        #expect(controller.history.count == 1)
        #expect(controller.history[0].outcome.contains("Verified page 2"))
    }

    @Test("An uncertain mutation stops and is never automatically replayed")
    func uncertainResult() async throws {
        let fixture = SequenceFixture()
        fixture.verification = .unverified
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Find and open a video")
        try await wait { controller.waitingForInput }
        #expect(fixture.actions.count == 1)
        #expect(fixture.requests.count == 1)
        #expect(controller.status == "Please check the result")
    }

    @Test("Terminal model prose cannot claim an unperformed action after a checkpoint")
    func unsupportedCompletionClaim() async throws {
        let fixture = SequenceFixture()
        fixture.claimAfterFirstAction = true
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Find and open a video")
        try await wait { controller.waitingForInput }
        #expect(fixture.actions.count == 1)
        #expect(controller.response.contains("Verified page 1"))
        #expect(!controller.response.contains("The video is playing"))
        #expect(controller.history.last?.response == controller.response)
    }

    @Test("Escape during a subsequent decision cancels all later actions")
    func cancelContinuation() async throws {
        let fixture = SequenceFixture()
        fixture.delaySecondDecision = true
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Find and open a video")
        try await wait { fixture.requests.count == 2 }
        #expect(controller.progressCaption(at: controller.stageStartedAt.addingTimeInterval(4)).contains("Step 2 · 4s"))
        controller.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.actions.count == 1)
        #expect(controller.phase == .stopped)
        #expect(!controller.progressCaption(at: .now).contains("Step"))
    }

    @Test("The same action against unchanged evidence is rejected before another mutation")
    func repeatedAction() async throws {
        let fixture = SequenceFixture()
        fixture.advanceObservation = false
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Continue until the destination is open")
        try await wait { controller.waitingForInput }
        #expect(fixture.actions.count == 1)
        #expect(controller.response == CoworkerProgressError.noProgress.localizedDescription)
    }

    @Test("Bounded runs never dispatch a ninth action")
    func boundedRun() async throws {
        let fixture = SequenceFixture()
        fixture.maximumActions = 20
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Keep navigating")
        try await wait { controller.waitingForInput }
        #expect(fixture.actions.count == 8)
        #expect(fixture.requests.count == 8)
        #expect(controller.response == CoworkerProgressError.limit.localizedDescription)
    }

    @Test("Every model adapter crosses the same contract validation before execution")
    func invalidAdapterReply() async throws {
        let fixture = SequenceFixture()
        fixture.invalidReply = true
        let controller = fixture.controller()
        defer { controller.dismiss() }
        controller.submit("Open the result")
        try await wait { controller.waitingForInput }
        #expect(fixture.actions.isEmpty)
        #expect(controller.response == CoworkerError.invalidResponse.localizedDescription)
    }

    @Test("URL normalization allows root slash and TLS upgrades, not invented destinations")
    func groundedURLs() throws {
        func url(_ value: String) -> URL { URL(string: value)! }
        #expect(CoworkerLinkPolicy.equivalent(url("http://youtube.com"), url("https://youtube.com/")))
        #expect(!CoworkerLinkPolicy.equivalent(url("https://youtube.com"), url("http://youtube.com")))
        #expect(CoworkerLinkPolicy.arrived(at: url("https://youtube.com"), actual: url("https://www.youtube.com/")))
        #expect(!CoworkerLinkPolicy.arrived(at: url("https://youtube.com/watch?v=1"), actual: url("https://www.youtube.com/watch?v=2")))
        #expect(!CoworkerLinkPolicy.arrived(at: url("https://youtube.com"), actual: url("https://youtube.com.evil.example/")))
        #expect(CoworkerDirectCommand.reply(to: "Search for David Guetta and open the first video") == nil)
    }

    @Test("Native capabilities narrow the grammar independently of the task wording")
    func capabilitySchema() throws {
        let observation = CoworkerObservation(application: "Any app", window: "", selectedText: "", visibleText: "",
            elements: [], editable: false, limitation: nil, availableActions: [.answer, .press])
        let request = CoworkerRequest(text: "Do the next step", observation: observation, history: [], now: .now, timeZone: .current)
        let schema = try #require(JSONSerialization.jsonObject(with: Data(CoworkerReply.schema(for: request).utf8)) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(properties["action"]?["enum"] as? [String] == ["answer", "press"])
        let shorter = CoworkerRequest(text: "Make it shorter", observation: observation,
            history: [.init(request: "Write", response: "Draft", artifact: String(repeating: "x", count: 500), outcome: "Verified")],
            now: .now, timeZone: .current)
        #expect(shorter.maximumDraftCharacters == 400)
        #expect(CoworkerReply.schema(for: shorter) == CoworkerReply.schema(for: request))
    }

    @Test("Safari sibling tabs count, unrelated radio buttons do not")
    func nativeTabSemantics() {
        #expect(CoworkerBrowserState.isTab(role: "AXRadioButton", subrole: "AXTabButton", insideTabGroup: false))
        #expect(CoworkerBrowserState.isTab(role: "AXRadioButton", subrole: nil, insideTabGroup: true))
        #expect(!CoworkerBrowserState.isTab(role: "AXRadioButton", subrole: nil, insideTabGroup: false))
        #expect(!CoworkerBrowserState.isTab(role: "AXButton", subrole: nil, insideTabGroup: true))
    }

    @Test("A destination URL alone cannot certify a usable page after navigation")
    func browserDocumentReadiness() {
        let url = URL(string: "https://example.com/")!
        let page = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        #expect(!CoworkerBrowserState(url: url, tabCount: 1).documentReady)
        #expect(!CoworkerBrowserState(url: url, tabCount: 1, page: page, loaded: false, hasPageContents: true).documentReady)
        #expect(!CoworkerBrowserState(url: url, tabCount: 1, page: page, loaded: true, hasPageContents: false).documentReady)
        #expect(CoworkerBrowserState(url: url, tabCount: 1, page: page, loaded: true, hasPageContents: true).documentReady)
    }

    @Test("Contextual searches cannot bypass the observed page")
    func contextualSearchRouting() {
        for request in ["Can you search for other David Gatter videos on YouTube on this tab, please?",
                        "Search for invoices in this app", "Look up the next result here",
                        "Search Google for Swift and open the first result"] {
            #expect(CoworkerDirectCommand.reply(to: request) == nil)
        }
    }

    @Test("Observed links avoid image prefill; visual explanations retain it")
    func contextualVision() {
        let page = CoworkerObservation(application: "Browser", window: "", selectedText: "", visibleText: "Video result",
            elements: [.init(id: 1, role: "AXLink", label: "First music video", url: "https://example.com/video")],
            editable: false, limitation: nil, pageURL: "https://example.com/")
        #expect(!CoworkerScreenObserver.isUseful(request: "Open the first video here", observation: page))
        #expect(CoworkerScreenObserver.isUseful(request: "Explain what this video shows", observation: page))
        #expect(CoworkerScreenObserver.isUseful(request: "What is in this image?", observation: page))
    }
}

@MainActor
private final class SequenceFixture: CoworkerGenerating, CoworkerDesktopControlling {
    var requests: [CoworkerRequest] = []
    var actions: [Int] = []
    var verification: CoworkerActionResult.Verification = .verified
    var advanceObservation = true
    var delaySecondDecision = false
    var invalidReply = false
    var claimAfterFirstAction = false
    var maximumActions = 2
    private var page = 0

    func controller() -> AssistantCompanionController {
        AssistantCompanionController(generator: self, capture: { [self] _ in
            CoworkerContext(application: nil, observation: .init(application: "Browser fixture", window: "Sequence",
                selectedText: "", visibleText: "Page \(page)",
                elements: [.init(id: page + 10, role: "AXLink", label: "Next", url: nil)], editable: false, limitation: nil), desktop: self)
        }, voiceEnabled: false)
    }
    func respond(to request: CoworkerRequest) async throws -> CoworkerReply {
        requests.append(request)
        request.onStage?(.choosingAction)
        if claimAfterFirstAction && requests.count == 2 {
            return .init(message: "The video is playing.", action: .answer, content: "", target: 0, start: "", minutes: 0)
        }
        if delaySecondDecision && requests.count == 2 { try await Task.sleep(for: .seconds(10)) }
        return .init(message: invalidReply ? "" : "I'll open the next page.", action: .press, content: "",
            target: request.observation.elements[0].id, start: "", minutes: 0, more: actions.count + 1 < maximumActions)
    }
    func frame(for reply: CoworkerReply) -> CGRect? { nil }
    func perform(_ reply: CoworkerReply, request: String) async throws -> CoworkerActionResult {
        actions.append(reply.target)
        if advanceObservation { page += 1 }
        return .init(message: "Verified page \(page)", verification: verification)
    }
}

import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import Hush

@Suite("Coworker conversation", .serialized)
@MainActor
struct CoworkerTests {
    private let observation = CoworkerObservation(application: "Browser", window: "Test", selectedText: "", visibleText: "",
        elements: [.init(id: 1, role: "AXLink", label: "Example", url: "https://example.com/docs")], editable: false, limitation: nil)

    @Test("Links must be grounded in the current screen or explicit user input")
    func links() throws {
        func reply(_ url: String, id: Int = 0) -> CoworkerReply {
            .init(message: "Open it", action: .openLink, content: url, target: id, start: "", minutes: 0)
        }
        #expect(throws: (any Error).self) { try CoworkerLinkPolicy.resolve(reply("file:///etc/passwd"), request: "Open it", observation: observation) }
        #expect(throws: (any Error).self) { try CoworkerLinkPolicy.resolve(reply("https://invented.example"), request: "Open it", observation: observation) }
        #expect(try CoworkerLinkPolicy.resolve(reply("https://example.com/docs", id: 1), request: "Open it", observation: observation).host == "example.com")
        #expect(try CoworkerLinkPolicy.resolve(reply("https://example.org/"), request: "Open https://example.org/", observation: observation).host == "example.org")
    }

    @Test("Calendar drafts escape content and keep timezone-resolved instants")
    func calendarDraft() throws {
        let reply = CoworkerReply(message: "Review it", action: .meeting,
            content: "Tom, review\r\nATTENDEE:mailto:wrong@example.com", target: 0,
            start: "2026-11-02T10:00:00-03:00", minutes: 30)
        let ics = try CoworkerCalendarDraft.contents(reply)
        #expect(ics.contains("DTSTART:20261102T130000Z\r\n"))
        #expect(ics.contains("DTEND:20261102T133000Z\r\n"))
        #expect(!ics.contains("\r\nATTENDEE:"))
        #expect(!ics.contains("METHOD:REQUEST"))
    }

    @Test("Incomplete or unknown actions cannot become executable replies")
    func schema() throws {
        #expect(throws: (any Error).self) { try CoworkerReply.decode(#"{"action":"write"}"#) }
        #expect(throws: (any Error).self) { try CoworkerReply.decode(#"{"message":"done","action":"send","content":"x","target":0,"start":"","minutes":0}"#) }
        #expect(throws: (any Error).self) { try CoworkerReply.decode(#"{"message":"done","action":"meeting","content":"Tom","target":0,"start":"tomorrow","minutes":30}"#) }
    }

    @Test("Native validation still rejects oversized text without character-count grammar states")
    func textLimits() throws {
        func decode(content: String = "Hi", subject: String = "") throws -> CoworkerReply {
            let reply = CoworkerReply(message: "Here's a draft.", action: .write, content: content,
                target: 0, start: "", minutes: 0, subject: subject)
            return try CoworkerReply.decode(String(decoding: JSONEncoder().encode(reply), as: UTF8.self))
        }
        #expect(try decode(subject: String(repeating: "é", count: 300)).subject.count == 300)
        #expect(throws: (any Error).self) { try decode(subject: String(repeating: "é", count: 301)) }
        #expect(throws: (any Error).self) { try decode(content: String(repeating: "x", count: 6_001)) }
    }

    @Test("A cancelled request never starts model preparation")
    func cancelledBeforePreparation() async throws {
        var stages: [CoworkerStage] = []
        var request = CoworkerRequest(text: "Hello", observation: observation, history: [], now: .now, timeZone: .current)
        request.onStage = { stages.append($0) }
        let task = Task { try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(stages.isEmpty)
    }

    @Test("Cancelled and stale voice turns cannot update the conversation")
    func cancelledTurn() async throws {
        let controller = AssistantCompanionController(generator: SlowCoworkerGenerator(), voice: SilentCoworkerVoice(),
            capture: { _ in CoworkerContext(application: nil, observation: observation) }, voiceEnabled: false)
        defer { controller.dismiss() }
        let id = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Wrong turn", sessionID: UUID())
        #expect(controller.history.isEmpty)
        controller.receiveTranscript("Hello", sessionID: id)
        controller.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.history.isEmpty)
        #expect(controller.pending == nil)
        #expect(controller.phase == .stopped)
    }

    @Test("Clarification and follow-up stay in the spoken conversation")
    func spokenClarification() async throws {
        let voice = RecordingCoworkerVoice()
        let generator = ConversationCoworkerGenerator()
        let controller = AssistantCompanionController(generator: generator, voice: voice,
            capture: { _ in CoworkerContext(application: nil, observation: observation) }, voiceEnabled: true)
        defer { controller.dismiss() }
        let first = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Help me reply", sessionID: first)
        try await eventually { controller.waitingForInput }
        #expect(voice.spoken == ["What tone would you like?"])
        #expect(!controller.expanded)
        let second = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Warm and brief", sessionID: second)
        try await eventually { controller.history.count == 2 }
        #expect(generator.requests.last?.history.first?.response == "What tone would you like?")
        #expect(generator.requests.last?.text == "Warm and brief")
        #expect(voice.spoken.last == "Understood. Warm and brief.")
    }

    @Test("Escape clears conversation state and the next voice turn starts with fresh context")
    func escapeStartsFresh() async throws {
        let generator = ConversationCoworkerGenerator()
        var screen = observation
        let controller = AssistantCompanionController(generator: generator, voice: SilentCoworkerVoice(),
            capture: { _ in CoworkerContext(application: nil, observation: screen) }, voiceEnabled: false)
        defer { controller.dismiss() }
        let first = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Help with the first document", sessionID: first)
        try await eventually { controller.history.count == 1 }
        controller.stop()
        #expect(controller.history.isEmpty)
        #expect(controller.pending == nil)
        #expect(controller.response.isEmpty)
        controller.stop()
        screen = CoworkerObservation(application: "Browser", window: "Second", selectedText: "",
            visibleText: "A different document", elements: [], editable: false, limitation: nil)
        let next = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Late old transcript", sessionID: first)
        #expect(controller.history.isEmpty)
        await Task.yield()
        controller.receiveTranscript("Help with this document", sessionID: next)
        try await eventually { generator.requests.count == 2 }
        #expect(generator.requests.last?.history.isEmpty == true)
        #expect(generator.requests.last?.checkpoints.isEmpty == true)
        #expect(generator.requests.last?.observation.visibleText == "A different document")
        #expect(controller.history.map(\.request) == ["Help with this document"])
    }

    @Test("An outside-input interruption keeps the conversation for a spoken follow-up")
    func interruptedActionKeepsConversation() async throws {
        let generator = ConversationCoworkerGenerator()
        let controller = AssistantCompanionController(generator: generator, voice: SilentCoworkerVoice(),
            capture: { _ in CoworkerContext(application: nil, observation: observation) }, voiceEnabled: false)
        defer { controller.dismiss() }
        let first = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Help with this document", sessionID: first)
        try await eventually { controller.history.count == 1 }
        controller.stop(endingConversation: false)
        let next = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Make it warmer", sessionID: next)
        try await eventually { generator.requests.count == 2 }
        #expect(generator.requests.last?.history.first?.request == "Help with this document")
    }

    @Test("Escape during the target cue prevents the edit and its spoken success")
    func cancelBeforeEdit() async throws {
        let target = SlowCoworkerDestination()
        let voice = RecordingCoworkerVoice()
        let controller = AssistantCompanionController(generator: WritingCoworkerGenerator(), voice: voice,
            capture: { _ in CoworkerContext(application: nil, observation: observation, textTarget: target) }, voiceEnabled: true)
        defer { controller.dismiss() }
        let id = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Write a reply", sessionID: id)
        try await eventually { controller.phase == .acting }
        controller.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(target.dispatched == 0)
        #expect(voice.spoken.isEmpty)
        #expect(controller.phase == .stopped)
    }

    @Test("Escape after dispatch finishes verification without repeating or claiming no edit")
    func cancelAfterDispatch() async throws {
        let target = SlowCoworkerDestination()
        let voice = RecordingCoworkerVoice()
        let controller = AssistantCompanionController(generator: WritingCoworkerGenerator(), voice: voice,
            capture: { _ in CoworkerContext(application: nil, observation: observation, textTarget: target) }, voiceEnabled: true)
        defer { controller.dismiss() }
        let id = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Write a reply", sessionID: id)
        try await eventually { target.dispatched == 1 }
        controller.stop()
        #expect(controller.history.isEmpty)
        #expect(!controller.canRecordRequest)
        #expect(controller.beginListening(from: nil) == nil)
        try await eventually { controller.canRecordRequest }
        #expect(target.dispatched == 1)
        #expect(controller.response.contains("checked the text"))
        #expect(controller.phase == .stopped)
        #expect(voice.spoken.isEmpty)
        #expect(controller.history.isEmpty)
        let next = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Write a new draft", sessionID: next)
        try await eventually { target.dispatched == 2 }
        #expect(target.revisionAttempts == 0)
        try await eventually { controller.canRecordRequest }
        #expect(controller.history.map(\.request) == ["Write a new draft"])
    }

    @Test("An error returned after Escape cannot restart speech or restore conversation state")
    func cancelledVerificationFailure() async throws {
        let target = SlowCoworkerDestination()
        target.failVerification = true
        let voice = RecordingCoworkerVoice()
        let controller = AssistantCompanionController(generator: WritingCoworkerGenerator(), voice: voice,
            capture: { _ in CoworkerContext(application: nil, observation: observation, textTarget: target) }, voiceEnabled: true)
        defer { controller.dismiss() }
        let turn = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Write a reply", sessionID: turn)
        try await eventually { target.dispatched == 1 }
        controller.stop()
        try await eventually { controller.canRecordRequest }
        #expect(controller.phase == .stopped)
        #expect(controller.history.isEmpty)
        #expect(voice.spoken.isEmpty)
        #expect(controller.response.contains("may already have completed"))
    }

    @Test("An unsupported editor reports the real cause aloud instead of claiming the destination moved")
    func unavailableEditor() async throws {
        let voice = RecordingCoworkerVoice()
        let controller = AssistantCompanionController(generator: WritingCoworkerGenerator(), voice: voice,
            capture: { _ in CoworkerContext(application: nil, observation: observation, textTargetFailure: .unsupportedEditor) },
            voiceEnabled: true)
        defer { controller.dismiss() }
        let id = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Write a reply", sessionID: id)
        try await eventually { !voice.spoken.isEmpty }
        #expect(voice.spoken == [CoworkerError.unsupportedEditor.localizedDescription])
        #expect(!controller.response.contains("destination changed"))
        #expect(!controller.response.contains("updated"))
    }

    @Test("Text ranges preserve emoji and reject split surrogate pairs and out-of-bounds offsets")
    func unicodeEditorRanges() throws {
        let text = "Grüße 🧪\nCafé"
        let emoji = (text as NSString).range(of: "🧪")
        #expect(try CoworkerTextSnapshot(text: text, selection: emoji).selection.length == 2)
        #expect(throws: (any Error).self) { try CoworkerTextSnapshot(text: text, selection: NSRange(location: emoji.location + 1, length: 0)) }
        #expect(throws: (any Error).self) { try CoworkerTextSnapshot(text: text, selection: NSRange(location: 0, length: Int.max)) }
        #expect(try CoworkerTextSnapshot(text: "", selection: NSRange(location: 0, length: 0)).text.isEmpty)
    }

    @Test("An omitted native value is writable only with independent proof that it is empty")
    func emptyNativeEditor() throws {
        for status in [AXError.success, .noValue] {
            let text = try CoworkerNativeTextAccess.readText(value: nil, status: status) { NSNumber(value: 0) }
            #expect(try CoworkerTextSnapshot(text: text, selection: NSRange(location: 0, length: 0)).text.isEmpty)
            #expect(throws: (any Error).self) {
                try CoworkerTextSnapshot(text: text, selection: NSRange(location: 1, length: 0))
            }
            for count: CFTypeRef? in [nil, NSNumber(value: 1), NSNumber(value: -1), NSNumber(value: 0.5), kCFBooleanFalse, "0" as CFString] {
                #expect(throws: (any Error).self) {
                    try CoworkerNativeTextAccess.readText(value: nil, status: status) { count }
                }
            }
        }
        for status in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .attributeUnsupported] {
            #expect(throws: (any Error).self) {
                try CoworkerNativeTextAccess.readText(value: nil, status: status) { NSNumber(value: 0) }
            }
        }
        #expect(throws: (any Error).self) {
            try CoworkerNativeTextAccess.readText(value: NSNumber(value: 0), status: .success) { NSNumber(value: 0) }
        }
        let existing = "Existing groceries 🥨"
        #expect(try CoworkerNativeTextAccess.readText(value: existing as CFString, status: .success) {
            Issue.record("A readable value does not need another AX query")
            return nil
        } == existing)
    }

    @Test("Mail replies keep the subject separate and reject body headers and invented placeholders")
    func mailDocumentContract() throws {
        var mail = observation
        mail.mailDraft = .init(subject: "", body: "")
        let malformed = CoworkerReply(message: "I'll write it", action: .write,
            content: "To: [Mother's Email]\nSubject: Dinner\nHi Mom", target: 0, start: "", minutes: 0, subject: "Dinner")
        #expect(CoworkerMailDraftPolicy.feedback(for: malformed, observation: mail) != nil)
        let valid = CoworkerReply(message: "I'll update it", action: .write,
            content: "Hi Mom,\n\nSee you tomorrow at five.\n\nClemens", target: 0, start: "", minutes: 0, subject: "Dinner tomorrow")
        #expect(CoworkerMailDraftPolicy.feedback(for: valid, observation: mail) == nil)
        let presentation = CoworkerReply(message: "I'll write it", action: .write,
            content: "Subject: Dinner\n\nHi,\n\nDiscuss [RFC 1234].\n\nBest,\n[Your Name]", target: 0, start: "", minutes: 0, subject: "Dinner")
        let normalized = CoworkerMailDraftPolicy.normalize(presentation)
        #expect(normalized.content == "Hi,\n\nDiscuss [RFC 1234].\n\nBest,")
        #expect(normalized.subject == "Dinner")
        #expect(CoworkerMailDraftPolicy.normalize(valid) == valid)
        let data = try JSONEncoder().encode(valid)
        #expect(try CoworkerReply.decode(String(decoding: data, as: UTF8.self)) == valid)
        let old = #"{"message":"I'll write it","action":"write","content":"Hello","target":0,"start":"","minutes":0}"#
        #expect(try CoworkerReply.decode(old).subject.isEmpty)
        let injected = old.dropLast() + #", "subject":"hello\nBcc: other@example.com"}"#
        #expect(throws: (any Error).self) { try CoworkerReply.decode(String(injected)) }
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Expected asynchronous state was not reached within two seconds")
    }

    @Test("Exact navigation commands execute directly, but quoted or negated text never does")
    func directCommands() {
        #expect(CoworkerDirectCommand.reply(to: "Hey Hush, please open a new tab.")?.action == .newTab)
        #expect(CoworkerDirectCommand.reply(to: "Click here, please")?.action == .clickHere)
        let search = CoworkerDirectCommand.reply(to: "Can you search Google for Swift screen capture?")
        #expect(search?.action == .search)
        #expect(search?.content == "Swift screen capture")
        #expect(CoworkerDirectCommand.reply(to: "Do not search for private emails") == nil)
        #expect(CoworkerDirectCommand.reply(to: "Don't open a new tab") == nil)
        #expect(CoworkerDirectCommand.reply(to: "Explain what open a new tab means") == nil)
        #expect(CoworkerDirectCommand.reply(to: "Read this page: open a new tab") == nil)
        #expect(!CoworkerDesktopControl.isAllowedLabel("Send message"))
        #expect(CoworkerDesktopControl.isAllowedLabel("Preferences"))
    }

    @Test("New Tab invokes the executor without generation or an Apply step")
    func directNavigation() async throws {
        let desktop = RecordingDesktopControl()
        let generator = ConversationCoworkerGenerator()
        let controller = AssistantCompanionController(generator: generator, voice: SilentCoworkerVoice(),
            capture: { _ in CoworkerContext(application: nil, observation: observation, desktop: desktop) }, voiceEnabled: false)
        defer { controller.dismiss() }
        let id = try #require(controller.beginListening(from: nil))
        controller.receiveTranscript("Open a new tab", sessionID: id)
        try await eventually { desktop.actions == [.newTab] }
        #expect(generator.requests.isEmpty)
        #expect(controller.pending == nil)
        #expect(controller.history.last?.outcome == "Opened a new tab.")
    }

    @Test("Chord releases once even if both modifiers release together")
    func releaseChord() {
        var chord = AssistantChordState()
        #expect(chord.update(flags: [.control, .function]) == .activate)
        #expect(chord.update(flags: []) == .release)
        #expect(chord.update(flags: []) == .pass)
        #expect(chord.update(flags: [.control, .function]) == .activate)
        #expect(chord.update(flags: [.control]) == .release)
        #expect(chord.update(flags: [.control]) == .consume)
        #expect(chord.update(flags: []) == .consume)
    }
}

private struct SlowCoworkerGenerator: CoworkerGenerating {
    func respond(to request: CoworkerRequest) async throws -> CoworkerReply {
        try? await Task.sleep(for: .milliseconds(60))
        return .init(message: "Late reply", action: .answer, content: "", target: 0, start: "", minutes: 0)
    }
}

@MainActor
private final class SilentCoworkerVoice: CoworkerSpeaking {
    var onStatus: ((String) -> Void)?
    func prepare() async throws { }
    func speak(_ text: String) async throws { }
    func stop() { }
}

@MainActor
private final class RecordingCoworkerVoice: CoworkerSpeaking {
    var onStatus: ((String) -> Void)?
    var spoken: [String] = []
    func prepare() async throws { }
    func speak(_ text: String) async throws { spoken.append(text) }
    func stop() { }
}

@MainActor
private final class ConversationCoworkerGenerator: CoworkerGenerating {
    var requests: [CoworkerRequest] = []
    func respond(to request: CoworkerRequest) async throws -> CoworkerReply {
        requests.append(request)
        return .init(message: requests.count == 1 ? "What tone would you like?" : "Understood. Warm and brief.",
                     action: .answer, content: "", target: 0, start: "", minutes: 0)
    }
}

private struct WritingCoworkerGenerator: CoworkerGenerating {
    func respond(to request: CoworkerRequest) async throws -> CoworkerReply {
        .init(message: "I'll write it.", action: .write, content: "Hello Tom", target: 0, start: "", minutes: 0)
    }
}

@MainActor
private final class SlowCoworkerDestination: CoworkerRevisionDestination {
    let context = AssistantContext(id: UUID(), applicationName: "Test", destinationName: "Reply", selectedText: "")
    var targetFrame: CGRect? { nil }
    var dispatched = 0
    var revisionAttempts = 0
    var failVerification = false
    func sharesEditor(with current: any AssistantDestination) -> Bool { current as? SlowCoworkerDestination === self }
    func revisionTarget(current: any AssistantDestination) throws -> any AssistantDestination {
        revisionAttempts += 1
        throw CoworkerError.changedContext
    }
    func validate() throws { }
    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        try Task.checkCancellation()
        dispatched += 1
        let result = await Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            return AssistantInsertionResult.verified
        }.value
        if failVerification { throw CoworkerError.changedContext }
        return result
    }
}

@MainActor
private final class RecordingDesktopControl: CoworkerDesktopControlling {
    var actions: [CoworkerReply.Action] = []
    func frame(for reply: CoworkerReply) -> CGRect? { nil }
    func perform(_ reply: CoworkerReply, request: String) async throws -> CoworkerActionResult {
        try Task.checkCancellation()
        actions.append(reply.action)
        return .init(message: "Opened a new tab.", verification: .verified)
    }
}

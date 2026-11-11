#if DEBUG
import AppKit

extension AppDelegate {
    func showAssistantJourneyIfRequested() -> Bool {
        if CoworkerNativeEditorDebugCheck.runIfRequested() { return true }
        if CoworkerMailDebugCheck.runIfRequested() { return true }
        if CoworkerBrowserDebugCheck.runIfRequested() { return true }
        if ProcessInfo.processInfo.arguments.contains("--preview-assistant-global") {
            let fixture = CoworkerDebugJourney()
            objc_setAssociatedObject(self, &AssistantDebugJourney.retentionKey, fixture, .OBJC_ASSOCIATION_RETAIN)
            fixture.show()
            return true
        }
        guard ProcessInfo.processInfo.arguments.contains("--preview-assistant") else { return false }
        if ProcessInfo.processInfo.arguments.contains("--preview-dark-appearance") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if ProcessInfo.processInfo.arguments.contains("--preview-light-appearance") { NSApp.appearance = NSAppearance(named: .aqua) }
        let fixture = AssistantDebugJourney()
        objc_setAssociatedObject(self, &AssistantDebugJourney.retentionKey, fixture, .OBJC_ASSOCIATION_RETAIN)
        fixture.show()
        return true
    }
}

@MainActor
private final class CoworkerDebugJourney: NSObject {
    private let destination = AssistantDebugDestination()
    private let window = NSWindow(contentRect: NSRect(x: 90, y: 220, width: 500, height: 400),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var controller: AssistantCompanionController!
    private var spokenTurn = 0
    override init() {
        super.init()
        controller = AssistantCompanionController(generator: CoworkerDebugGenerator(), voice: CoworkerDebugVoice(),
            capture: { [destination] app in
                if ProcessInfo.processInfo.arguments.contains("--preview-assistant-sequence") {
                    return CoworkerContext(application: app, observation: .init(application: "Browser fixture", window: "Sequence",
                        selectedText: "", visibleText: destination.textView.string,
                        elements: [.init(id: 1, role: "AXLink", label: "First music video", url: nil)], editable: false, limitation: nil),
                        desktop: CoworkerDebugDesktop(textView: destination.textView))
                }
                let unavailable = ProcessInfo.processInfo.arguments.contains("--preview-assistant-missing-target")
                return CoworkerContext(application: app, observation: .init(application: "Safari fixture", window: "Conversation with Tom",
                    selectedText: "", visibleText: "Tom: Can we meet tomorrow at 10 for 30 minutes?", elements: [], editable: !unavailable, limitation: nil),
                    textTarget: unavailable ? nil : CoworkerDebugDestination(textView: destination.textView))
            }, voiceEnabled: true)
        window.title = "Working app fixture"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 50, width: 460, height: 330))
        scroll.hasVerticalScroller = true
        destination.textView.frame = scroll.bounds
        destination.textView.autoresizingMask = [.width, .height]
        scroll.documentView = destination.textView
        root.addSubview(scroll)
        if ProcessInfo.processInfo.arguments.contains("--preview-assistant-reset") {
            let note = NSButton(title: "New note", target: self, action: #selector(newNote))
            note.frame = NSRect(x: 20, y: 10, width: 120, height: 28)
            note.setAccessibilityIdentifier("hush.fixture.new-note")
            root.addSubview(note)
            let talk = NSButton(title: "Simulate voice turn", target: self, action: #selector(talk))
            talk.frame = NSRect(x: 160, y: 10, width: 180, height: 28)
            talk.setAccessibilityIdentifier("hush.fixture.voice")
            root.addSubview(talk)
        }
        window.contentView = root
        controller.onMicrophone = { [weak self] in
            guard let self, let id = self.controller.beginListening(from: nil) else { return }
            self.controller.updateLevel(0.7)
            let turn = self.spokenTurn
            self.spokenTurn += 1
            let arguments = ProcessInfo.processInfo.arguments
            let request: String
            if arguments.contains("--preview-assistant-sequence") { request = "Open a new tab and open the first music video" }
            else if arguments.contains("--preview-assistant-reset") { request = "Write a reply to Tom" }
            else if arguments.contains("--preview-assistant-slow") { request = "Write a slow reply" }
            else if arguments.contains("--preview-assistant-speaking") { request = "explain" }
            else if arguments.contains("--preview-assistant-question"), turn == 0 { request = "ask me" }
            else { request = turn == 0 ? "Write a reply to Tom" : "Make it warmer" }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self.controller.captureState("transcribing", turnID: id)
                try? await Task.sleep(for: .milliseconds(200))
                self.controller.receiveTranscript(request, sessionID: id)
            }
        }
    }
    @objc private func newNote() {
        destination.textView.string = ""
        destination.textView.setSelectedRange(NSRange(location: 0, length: 0))
        window.makeFirstResponder(destination.textView)
    }
    @objc private func talk() { controller.onMicrophone?() }
    func show() {
        // This fixture represents the working app. Give it ordinary foreground
        // activation so UI automation cannot type into another application.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--preview-assistant-sequence") { destination.textView.string = "Browser start" }
        if ProcessInfo.processInfo.arguments.contains("--preview-dark-appearance") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        else { NSApp.appearance = NSAppearance(named: .aqua) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(destination.textView)
        controller.open(from: nil)
    }
}

private struct CoworkerDebugGenerator: CoworkerGenerating {
    func respond(to request: CoworkerRequest) async throws -> CoworkerReply {
        request.onStage?(.choosingAction)
        if ProcessInfo.processInfo.arguments.contains("--preview-assistant-progress"), !request.checkpoints.isEmpty {
            try await Task.sleep(for: .seconds(10))
        }
        try await Task.sleep(for: .milliseconds(request.text.contains("slow") ? 4_000 : 150))
        if ProcessInfo.processInfo.arguments.contains("--preview-assistant-sequence") {
            if request.observation.visibleText == "Browser start" {
                return .init(message: "I'll open a tab.", action: .newTab, content: "", target: 0, start: "", minutes: 0, more: true)
            }
            return .init(message: "I'll open the first music video.", action: .press, content: "", target: 1, start: "", minutes: 0)
        }
        if request.text == "invalid" { throw CoworkerError.invalidResponse }
        if request.text == "explain" {
            return .init(message: "I'm here with you. We can take this one step at a time.", action: .answer, content: "", target: 0, start: "", minutes: 0)
        }
        if request.text == "ask me" {
            return .init(message: "What tone would you like for Tom?", action: .answer, content: "", target: 0, start: "", minutes: 0)
        }
        let followUp = request.history.contains { $0.outcome.contains("checked the text") }
        return .init(message: followUp ? "I'll make the reply warmer." : "I'll write a reply to Tom.",
                     action: followUp && !ProcessInfo.processInfo.arguments.contains("--preview-assistant-write-followup") ? .revise : .write, content: followUp ? "Hi Tom,\n\nThat sounds lovely. Tomorrow at 10 works for me!" : "Hi Tom,\n\nTomorrow at 10 works for me.",
                     target: 0, start: "", minutes: 0)
    }
}

@MainActor
private final class CoworkerDebugDesktop: CoworkerDesktopControlling {
    let textView: NSTextView
    init(textView: NSTextView) { self.textView = textView }
    func frame(for reply: CoworkerReply) -> CGRect? { nil }
    func perform(_ reply: CoworkerReply, request: String) async throws -> CoworkerActionResult {
        try Task.checkCancellation()
        if reply.action == .newTab, textView.string == "Browser start" {
            textView.string = "Search results: First music video"
            return .init(message: "Opened the fixture tab.", verification: .verified)
        }
        guard reply.action == .press, reply.target == 1, textView.string == "Search results: First music video" else {
            throw CoworkerError.changedContext
        }
        textView.string = "Video opened"
        return .init(message: "Opened the fixture video.", verification: .verified)
    }
}

/// Fresh bindings exercise direct insertion and exact-range revision in a native editor.
@MainActor
private final class CoworkerDebugDestination: CoworkerRevisionDestination {
    let context = AssistantContext(id: UUID(), applicationName: "Safari fixture", destinationName: "Reply", selectedText: "")
    let textView: NSTextView
    private let original: String
    private let selection: NSRange
    private var replacement: NSRange?
    private var verifiedValue: String?
    private var verifiedRange: NSRange?
    private var dispatched = false
    init(textView: NSTextView) {
        self.textView = textView
        original = textView.string
        selection = textView.selectedRange()
    }
    var targetFrame: CGRect? {
        guard let window = textView.window, let screen = NSScreen.screens.first else { return nil }
        let rect = window.convertToScreen(textView.convert(textView.bounds, to: nil))
        return CGRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
    func validate() throws {
        guard !dispatched, textView.string == original, textView.selectedRange() == selection else { throw CoworkerError.changedContext }
    }
    func sharesEditor(with current: any AssistantDestination) -> Bool {
        (current as? CoworkerDebugDestination)?.textView === textView
    }
    func revisionTarget(current: any AssistantDestination) throws -> any AssistantDestination {
        guard let current = current as? CoworkerDebugDestination,
              current.textView === textView, let verifiedValue, let verifiedRange,
              current.original == verifiedValue,
              current.selection.location >= verifiedRange.location,
              NSMaxRange(current.selection) <= NSMaxRange(verifiedRange) else { throw CoworkerError.changedContext }
        try current.validate()
        current.replacement = verifiedRange
        return current
    }
    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        try Task.checkCancellation()
        try validate()
        let range = replacement ?? selection
        let lease = try AssistantClipboardLease(proposal: proposal)
        textView.window?.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        dispatched = true
        textView.paste(nil)
        let expected = (original as NSString).replacingCharacters(in: range, with: proposal.plainText)
        guard textView.string == expected else { return .unverified }
        verifiedValue = expected
        verifiedRange = NSRange(location: range.location, length: proposal.plainText.utf16.count)
        lease.restoreIfUnchanged()
        return .verified
    }
}

@MainActor
private final class CoworkerDebugVoice: CoworkerSpeaking {
    var onStatus: ((String) -> Void)?
    var onUtterance: ((String?) -> Void)?
    private var playback = UUID()
    func prepare() async throws { }
    func speak(_ text: String) async throws {
        let id = playback
        onUtterance?(text)
        defer { if id == playback { onUtterance?(nil) } }
        let arguments = ProcessInfo.processInfo.arguments
        try await Task.sleep(for: .milliseconds(arguments.contains("--preview-assistant-speaking") || arguments.contains("--preview-assistant-reset") ? 4_000 : 150))
    }
    func stop() { playback = UUID(); onUtterance?(nil) }
}

@MainActor
private final class AssistantDebugJourney {
    static var retentionKey: UInt8 = 0
    let destination = AssistantDebugDestination()
    let controller = AssistantWindowController()
    let window: NSWindow

    init() {
        window = NSWindow(contentRect: NSRect(x: 80, y: 200, width: 500, height: 460),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Assistant destination fixture"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 460))
        let label = NSTextField(labelWithString: "Native email body fixture")
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.frame = NSRect(x: 22, y: 414, width: 400, height: 26)
        content.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 22, y: 72, width: 456, height: 325))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        destination.textView.frame = scroll.bounds
        destination.textView.autoresizingMask = [.width, .height]
        destination.textView.textContainer?.widthTracksTextView = true
        scroll.documentView = destination.textView
        content.addSubview(scroll)
        let change = NSButton(title: "Change destination", target: self, action: #selector(changeDestination))
        change.bezelStyle = .rounded
        change.frame = NSRect(x: 22, y: 23, width: 160, height: 32)
        change.setAccessibilityIdentifier("hush.assistant.fixture.change")
        content.addSubview(change)
        window.contentView = content
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        controller.present(destination: destination, generator: AssistantDebugGenerator(), modelName: "Fixture model")
    }

    @objc private func changeDestination() {
        destination.textView.string = "A newer draft typed by the user."
    }
}

@MainActor
private final class AssistantDebugDestination: AssistantDestination {
    let context = AssistantContext(id: UUID(), applicationName: "Mail fixture",
                                   destinationName: "Email body at your caret", selectedText: "")
    let textView = NSTextView()
    private let initial = "\n\nKind regards,\nAlex"
    private var dispatched = false
    var targetFrame: CGRect? {
        guard let window = textView.window, let screen = NSScreen.screens.first else { return nil }
        let rect = window.convertToScreen(textView.convert(textView.bounds, to: nil))
        return CGRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    init() {
        textView.string = initial
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setAccessibilityIdentifier("hush.assistant.fixture.body")
    }

    func validate() throws {
        guard !dispatched, textView.string == initial,
              textView.selectedRange() == NSRange(location: 0, length: 0) else { throw AssistantFailure.contextChanged }
    }

    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        try Task.checkCancellation()
        try validate()
        let lease = try AssistantClipboardLease(proposal: proposal)
        dispatched = true
        textView.paste(nil)
        let verified = textView.string == proposal.plainText + initial
        if verified { lease.restoreIfUnchanged() }
        return verified ? .verified : .unverified
    }
}

private struct AssistantDebugGenerator: AssistantGenerating {
    func generate(_ brief: AssistantBrief) async throws -> AssistantProposal {
        try await Task.sleep(for: .milliseconds(brief.request.contains("slow") ? 3_000 : 150))
        if brief.request.contains("invalid") {
            return try AssistantProposal.decode("{\"decision\":\"draft\"", completed: false)
        }
        return AssistantProposal(decision: .draft, message: "", blocks: [
            .init(kind: .paragraph, text: "Hello Sam,"),
            .init(kind: .paragraph, text: "Thanks for your message. Here is the plan:"),
            .init(kind: .bullet, text: "Review the proposal together."),
            .init(kind: .bullet, text: "Confirm the next steps.")
        ])
    }
}
#endif

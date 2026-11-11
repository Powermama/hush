import AppKit

/// A compose window is a document with separate subject and body fields. Its
/// identity survives caret movement between headers and body, and every voice
/// turn binds a fresh snapshot. Recipients and Send are never mutation targets.
@MainActor
final class CoworkerMailDraftTarget: CoworkerRevisionDestination, CoworkerDocumentDestination {
    let context: AssistantContext
    let capturedBody: String
    let capturedSubject: String
    private let application: NSRunningApplication
    private let app: AXUIElement
    private let window: AXUIElement
    private let body: AXUIElement
    private let subject: AXUIElement
    private let initialFocus: AXUIElement
    private let access: CoworkerWebTextAccess
    private let paste = CoworkerPaste()
    #if DEBUG
    var diagnosticTrace: CoworkerTrace? {
        didSet { paste.diagnosticTrace = diagnosticTrace }
    }
    #endif

    init(application: NSRunningApplication) throws {
        guard AXIsProcessTrusted() else { throw CoworkerError.missingContext }
        guard application.bundleIdentifier == "com.apple.mail" else { throw CoworkerError.unsupportedEditor }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let window = CoworkerAX.element(kAXFocusedWindowAttribute, app),
              let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app),
              CoworkerAX.string(kAXSubroleAttribute, focused) != kAXSecureTextFieldSubrole else { throw CoworkerError.unsupportedEditor }
        let fields = Self.fields(in: window)
        guard fields.bodies.count == 1, fields.subjects.count == 1,
              let body = fields.bodies.first, let subject = fields.subjects.first,
              CoworkerMailCompose.containsBody(body, window: window),
              let subjectValue = CoworkerAX.string(kAXValueAttribute, subject), subjectValue.count <= 300 else {
            throw CoworkerError.unsupportedEditor
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(subject, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else { throw CoworkerError.unsupportedEditor }
        let access = CoworkerWebTextAccess(field: body)
        let text = try access.text()
        // A document replacement must include all existing text in model context.
        guard text.count <= 6_000 else { throw CoworkerError.unsupportedEditor }
        self.application = application; self.app = app; self.window = window
        self.body = body; self.subject = subject; self.initialFocus = focused; self.access = access
        capturedBody = text; capturedSubject = subjectValue
        let selected = try? access.snapshot()
        let selectedText = selected.map { ($0.text as NSString).substring(with: $0.selection) } ?? ""
        context = .init(id: UUID(), applicationName: "Mail", destinationName: "Current email draft", selectedText: selectedText)
    }

    static func fields(in window: AXUIElement) -> (bodies: [AXUIElement], subjects: [AXUIElement]) {
        var queue = [window], index = 0
        var bodies: [AXUIElement] = [], subjects: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(0.4)
        while index < queue.count, index < 220, Date() < deadline {
            let node = queue[index]; index += 1
            let role = CoworkerAX.string(kAXRoleAttribute, node)
            if role == "AXWebArea" { bodies.append(node); continue }
            if role == kAXTextFieldRole {
                let titleElement = CoworkerAX.element(kAXTitleUIElementAttribute, node)
                let label = titleElement.map { CoworkerAX.string(kAXValueAttribute, $0) ?? CoworkerAX.label($0) } ?? CoworkerAX.label(node)
                if ["subject", "betreff"].contains(label.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":"))).lowercased()) {
                    subjects.append(node)
                }
            }
            if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 220 - queue.count)))
            }
        }
        return (bodies, subjects)
    }

    var targetFrame: CGRect? { CoworkerAX.frame(body) }

    func validate() throws {
        try validateWindow()
        guard let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app), CFEqual(focused, initialFocus),
              try access.text() == capturedBody,
              CoworkerAX.string(kAXValueAttribute, subject) == capturedSubject else { throw CoworkerError.changedContext }
    }

    private func validateWindow() throws {
        guard !application.isTerminated,
              let current = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(current, window),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw CoworkerError.changedContext
        }
    }

    func revisionTarget(current: any AssistantDestination) throws -> any AssistantDestination {
        guard let current = current as? CoworkerMailDraftTarget, CFEqual(current.window, window), CFEqual(current.body, body) else {
            throw CoworkerError.changedContext
        }
        try current.validate()
        return current
    }

    func sharesEditor(with current: any AssistantDestination) -> Bool {
        guard let current = current as? CoworkerMailDraftTarget else { return false }
        return CFEqual(current.window, window) && CFEqual(current.body, body)
    }

    func update(_ edit: CoworkerDocumentEdit) async throws -> AssistantInsertionResult {
        try await insert(edit.body, subject: edit.fields[.title] ?? "")
    }

    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        try await insert(proposal, subject: "")
    }

    func insert(_ proposal: AssistantProposal, subject newSubject: String) async throws -> AssistantInsertionResult {
        try Task.checkCancellation()
        try validate()
        guard newSubject.count <= 300, !newSubject.contains(where: \.isNewline) else { throw CoworkerError.invalidResponse }
        guard AXUIElementSetAttributeValue(body, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw CoworkerError.unsupportedEditor
        }
        // Preserve WebKit's trailing paragraph boundary while replacing the document text.
        let range = NSRange(location: 0, length: capturedBody.utf16.count - (capturedBody.hasSuffix("\n") ? 1 : 0))
        try access.select(range)
        let expectedSnapshot = try CoworkerTextSnapshot(text: capturedBody, selection: range)
        for _ in 0..<10 {
            if (try? access.snapshot()) == expectedSnapshot { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let result = try await paste.perform(proposal, application: application, access: access, original: capturedBody, range: range) {
            try validateWindow()
            guard let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app), CFEqual(focused, body),
                  CoworkerAX.string(kAXValueAttribute, subject) == capturedSubject else { throw CoworkerError.changedContext }
        }
        guard result == .verified else { return result }
        // Escape after a body paste prevents the next mutation. No retry of the body.
        try Task.checkCancellation()
        if !newSubject.isEmpty, newSubject != capturedSubject {
            do {
                try validateWindow()
                guard CoworkerAX.string(kAXValueAttribute, subject) == capturedSubject,
                      AXUIElementSetAttributeValue(subject, kAXValueAttribute as CFString, newSubject as CFString) == .success else {
                    throw CoworkerError.subjectUpdateFailed
                }
                for _ in 0..<10 {
                    if CoworkerAX.string(kAXValueAttribute, subject) == newSubject { break }
                    try await Task.sleep(for: .milliseconds(30))
                }
                guard CoworkerAX.string(kAXValueAttribute, subject) == newSubject else { throw CoworkerError.subjectUpdateFailed }
                #if DEBUG
                diagnosticTrace?.event("mail.subject_verified")
                #endif
            } catch { throw CoworkerError.subjectUpdateFailed }
        }
        return .verified
    }
}

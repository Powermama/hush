import AppKit
import ApplicationServices

@MainActor
enum CoworkerAX {
    static func attribute(_ name: String, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func string(_ name: String, _ element: AXUIElement) -> String? { attribute(name, element) as? String }
    static func label(_ element: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"] {
            if let value = string(key, element), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return ""
    }
    static func element(_ name: String, _ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func range(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ax, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(kAXPositionAttribute, element), let s = attribute(kAXSizeAttribute, element),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        let position = p as! AXValue, size = s as! AXValue
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

@MainActor
final class CoworkerContext {
    let observation: CoworkerObservation
    let textTarget: (any AssistantDestination)?
    let application: NSRunningApplication?
    let targetFrames: [Int: CGRect]
    let desktop: (any CoworkerDesktopControlling)?
    let windowFrame: CGRect?
    let textTargetFailure: CoworkerError

    init(application: NSRunningApplication?, observation: CoworkerObservation,
         textTarget: (any AssistantDestination)? = nil, targetFrames: [Int: CGRect] = [:],
         desktop: (any CoworkerDesktopControlling)? = nil, windowFrame: CGRect? = nil,
         textTargetFailure: CoworkerError = .unsupportedEditor) {
        self.application = application
        self.observation = observation
        self.textTarget = textTarget
        self.targetFrames = targetFrames
        self.desktop = desktop
        self.windowFrame = windowFrame
        self.textTargetFailure = textTargetFailure
    }

    static func capture(from application: NSRunningApplication?) -> CoworkerContext {
        let name = application?.localizedName ?? "Your Mac"
        func empty(_ limitation: String) -> CoworkerContext {
            CoworkerContext(application: application, observation: .init(application: name, window: "",
                selectedText: "", visibleText: "", elements: [], editable: false, limitation: limitation),
                textTargetFailure: AXIsProcessTrusted() ? .unsupportedEditor : .missingContext)
        }
        guard AXIsProcessTrusted() else { return empty(CoworkerError.missingContext.localizedDescription) }
        guard let application, !application.isTerminated else { return empty("No source app is selected.") }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let window = CoworkerAX.element(kAXFocusedWindowAttribute, app) else {
            return empty("This app has not exposed a readable window.")
        }
        let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app)
        if let focused, CoworkerAX.string(kAXSubroleAttribute, focused) == kAXSecureTextFieldSubrole {
            return empty("A secure field is focused. Its contents are unavailable.")
        }
        let target: (any AssistantDestination)?
        let targetFailure: CoworkerError
        do {
            target = application.bundleIdentifier == "com.apple.mail"
                ? try CoworkerMailDraftTarget(application: application)
                : try CoworkerTextTarget(application: application)
            targetFailure = .unsupportedEditor
        }
        catch { target = nil; targetFailure = (error as? CoworkerError) ?? .unsupportedEditor }
        let selected = target?.context.selectedText ?? focused.flatMap { CoworkerAX.string(kAXSelectedTextAttribute, $0) } ?? ""
        let windowFrame = CoworkerAX.frame(window)
        let browserState = CoworkerBrowserState.read(window)
        let deadline = Date().addingTimeInterval(0.65)
        var queue: [(AXUIElement, Int)] = []
        // The active document gets the control budget before browser chrome.
        // A focused toolbar or many open tabs must not hide the page's search field.
        if let page = browserState.page { queue.append((page, 0)) }
        if let focused {
            queue.append((focused, 0))
            var ancestor = CoworkerAX.element(kAXParentAttribute, focused)
            for _ in 0..<20 {
                guard let node = ancestor else { break }
                if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { queue.append((node, 0)); break }
                ancestor = CoworkerAX.element(kAXParentAttribute, node)
            }
        }
        if browserState.page == nil { queue.append((window, 0)) }
        var visited = Set<CFHashCode>()
        var index = 0, text: [String] = [], seen = Set<String>(), count = 0
        var elements: [CoworkerObservation.Element] = [], frames: [Int: CGRect] = [:]
        var controls: [Int: AXUIElement] = [:], labels: [Int: String] = [:]
        while index < queue.count, index < 220, Date() < deadline {
            let (node, depth) = queue[index]
            index += 1
            guard visited.insert(CFHash(node)).inserted else { continue }
            if CoworkerAX.string(kAXSubroleAttribute, node) == kAXSecureTextFieldSubrole { continue }
            if (CoworkerAX.attribute("AXHidden", node) as? Bool) == true { continue }
            let role = CoworkerAX.string(kAXRoleAttribute, node) ?? ""
            let frame = CoworkerAX.frame(node)
            if let frame, let windowFrame, !frame.isEmpty, !frame.intersects(windowFrame) { continue }
            let title = CoworkerAX.label(node)
            let value = CoworkerAX.string(kAXValueAttribute, node) ?? ""
            for candidate in [title, value] where !candidate.isEmpty {
                let bounded = String(candidate.prefix(min(2_000, max(0, 7_000 - count))))
                if !bounded.isEmpty, seen.insert(bounded).inserted { text.append(bounded); count += bounded.count }
            }
            if elements.count < 48, ["AXLink", kAXButtonRole, kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXMenuItemRole].contains(role) {
                let id = elements.count + 1
                let url = (CoworkerAX.attribute(kAXURLAttribute, node) as? URL)?.absoluteString
                elements.append(.init(id: id, role: role, label: String(title.prefix(160)), url: url,
                    value: [kAXTextFieldRole, kAXComboBoxRole].contains(role) ? String(value.prefix(250)) : nil,
                    subrole: CoworkerAX.string(kAXSubroleAttribute, node)))
                if let frame { frames[id] = frame }
                controls[id] = node
                labels[id] = title
            }
            if depth < 16, let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                // Walk each visible subtree in document order. Breadth-first queue
                // allocation let broad sidebars consume the budget before nested
                // header inputs (the observed search field was node 453 vs 16).
                // Processing remains bounded by 220 nodes, depth 16 and 650 ms.
                let descendants = children.prefix(220).map { ($0, depth + 1) }
                if browserState.page != nil,
                   CoworkerAX.string(kAXSubroleAttribute, node) == "AXLandmarkNavigation" {
                    // Keep global navigation available, but give the page's main
                    // content a chance before a long sidebar exhausts the budget.
                    queue.append(contentsOf: descendants)
                } else {
                    queue.insert(contentsOf: descendants, at: index)
                }
            }
        }
        let capturedText = (target as? CoworkerMailDraftTarget)?.capturedBody ?? (target as? CoworkerTextTarget)?.capturedText
        if let capturedText, !capturedText.isEmpty { text.insert(String(capturedText.prefix(7_000)), at: 0) }
        let mail = target as? CoworkerMailDraftTarget
        let desktop = try? CoworkerDesktopControl(application: application, window: window, targets: controls, labels: labels,
                                                  pointer: CGEvent(source: nil)?.location ?? .zero)
        var available: [CoworkerReply.Action] = [.answer, .diagram, .meeting, .search, .openLink]
        if target != nil { available += [.write, .revise] }
        available += desktop?.availableActions ?? []
        // One URL-opening operation per surface. Native navigation verifies the active
        // tab; the external-browser alias would bypass that verification.
        if available.contains(.navigate) {
            available.removeAll { $0 == .openLink || $0 == .search }
            if desktop?.availableActions.contains(.search) == true { available.append(.search) }
        }
        return CoworkerContext(application: application, observation: .init(application: name,
            window: String((CoworkerAX.string(kAXTitleAttribute, window) ?? "").prefix(240)),
            selectedText: String(selected.prefix(3_000)), visibleText: String(text.joined(separator: "\n").prefix(7_000)),
            elements: elements, editable: target != nil,
            limitation: text.isEmpty ? "No readable page content. Images and hidden content are unavailable." : "Accessibility text only; images and hidden content are unavailable.",
            mailDraft: mail.map { .init(subject: $0.capturedSubject, body: $0.capturedBody) },
            pageURL: browserState.url?.absoluteString, availableActions: available),
            textTarget: target, targetFrames: frames,
            desktop: desktop, windowFrame: windowFrame, textTargetFailure: targetFailure)
    }
}

/// A bound native text range, independent of the app's brand or window title.
@MainActor
protocol CoworkerRevisionDestination: AssistantDestination {
    /// Rebind only a previously verified insertion in the same unchanged editor.
    func revisionTarget(current: any AssistantDestination) throws -> any AssistantDestination
    func sharesEditor(with current: any AssistantDestination) -> Bool
}

@MainActor
final class CoworkerTextTarget: CoworkerRevisionDestination {
    let context: AssistantContext
    private let application: NSRunningApplication
    private let app: AXUIElement
    private let field: AXUIElement
    private let window: AXUIElement
    private let access: any CoworkerTextAccess
    private let original: String
    var capturedText: String { original }
    var textAccessKind: String { access.kind }
    private let selection: NSRange
    private var dispatched = false
    private let paste = CoworkerPaste()
    private var replacementRange: NSRange?
    private var verifiedValue: String?
    private var verifiedRange: NSRange?
    #if DEBUG
    var diagnosticTrace: CoworkerTrace?
    #endif

    init(application: NSRunningApplication) throws {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let policy = VerifiedMessageDestinationPolicy.decision(mode: .smart, exceptions: [],
            bundleIdentifier: application.bundleIdentifier, applicationName: application.localizedName, isSecureField: false)
        if case .hidden(.terminal) = policy { throw CoworkerError.unsupportedEditor }
        guard AXIsProcessTrusted() else { throw CoworkerError.missingContext }
        guard let field = CoworkerAX.element(kAXFocusedUIElementAttribute, app),
              CoworkerAX.string(kAXSubroleAttribute, field) != kAXSecureTextFieldSubrole,
              let window = CoworkerAX.element(kAXFocusedWindowAttribute, app) else { throw CoworkerError.unsupportedEditor }
        let role = CoworkerAX.string(kAXRoleAttribute, field) ?? ""
        let access: any CoworkerTextAccess
        if [kAXTextAreaRole, kAXTextFieldRole].contains(role) {
            access = CoworkerNativeTextAccess(field: field)
        } else if role == "AXWebArea", application.bundleIdentifier == "com.apple.mail",
                  CoworkerMailCompose.containsBody(field, window: window) {
            access = CoworkerWebTextAccess(field: field)
        } else {
            throw CoworkerError.unsupportedEditor
        }
        let snapshot = try access.snapshot()
        let original = snapshot.text, selection = snapshot.selection
        let browsers = ["com.apple.safari", "com.google.chrome", "com.google.chrome.canary", "com.brave.browser",
                        "com.microsoft.edgemac", "company.thebrowser.browser", "org.mozilla.firefox", "com.operasoftware.opera"]
        if browsers.contains(application.bundleIdentifier?.lowercased() ?? "") {
            var ancestor: AXUIElement? = field
            var insidePage = false
            for _ in 0..<24 {
                guard let node = ancestor else { break }
                if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { insidePage = true; break }
                ancestor = CoworkerAX.element(kAXParentAttribute, node)
            }
            guard insidePage else { throw CoworkerError.unsupportedEditor }
        }
        self.access = access
        self.application = application; self.app = app; self.field = field; self.window = window
        self.original = original; self.selection = selection
        context = .init(id: UUID(), applicationName: application.localizedName ?? "App",
                        destinationName: selection.length > 0 ? "Selected text" : "Current text field",
                        selectedText: String((original as NSString).substring(with: selection).prefix(3_000)))
    }

    var targetFrame: CGRect? { CoworkerAX.frame(field) }

    func sharesEditor(with current: any AssistantDestination) -> Bool {
        guard let current = current as? CoworkerTextTarget else { return false }
        return current.application.processIdentifier == application.processIdentifier && CFEqual(current.field, field) && CFEqual(current.window, window)
    }

    func revisionTarget(current: any AssistantDestination) throws -> any AssistantDestination {
        guard let current = current as? CoworkerTextTarget,
              let verifiedValue, let verifiedRange,
              current.application.processIdentifier == application.processIdentifier,
              CFEqual(current.field, field), CFEqual(current.window, window),
              current.original == verifiedValue,
              current.selection.location >= verifiedRange.location,
              NSMaxRange(current.selection) <= NSMaxRange(verifiedRange) else {
            throw CoworkerError.changedContext
        }
        try current.validate()
        current.replacementRange = verifiedRange
        return current
    }

    func validate() throws {
        let currentSnapshot = try? access.snapshot()
        #if DEBUG
        if let diagnosticTrace {
            var fields = CoworkerDiagnostics.binding(application)
            fields["same_field"] = String(CoworkerAX.element(kAXFocusedUIElementAttribute, app).map { CFEqual($0, field) } ?? false)
            fields["same_window"] = String(CoworkerAX.element(kAXFocusedWindowAttribute, app).map { CFEqual($0, window) } ?? false)
            fields["same_text"] = String(currentSnapshot?.text == original)
            fields["same_selection"] = String(currentSnapshot?.selection == selection)
            fields["text_access"] = access.kind
            diagnosticTrace.event("destination.validation", fields)
        }
        #endif
        guard !application.isTerminated,
              let current = CoworkerAX.element(kAXFocusedUIElementAttribute, app), CFEqual(current, field),
              let currentWindow = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(currentWindow, window),
              currentSnapshot?.text == original, currentSnapshot?.selection == selection,
              CoworkerAX.string(kAXSubroleAttribute, field) != kAXSecureTextFieldSubrole else {
            throw CoworkerError.changedContext
        }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard pid == application.processIdentifier || pid == ProcessInfo.processInfo.processIdentifier else {
            throw CoworkerError.changedContext
        }
    }

    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        guard !dispatched else { throw CoworkerError.changedContext }
        try validate()
        application.activate()
        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        try validate()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw CoworkerError.changedContext
        }
        let range = replacementRange ?? selection
        if replacementRange != nil {
            try access.select(range)
            // WebKit applies marker selections asynchronously. Never paste before read-back agrees.
            for _ in 0..<10 {
                if (try? access.snapshot()) == (try? CoworkerTextSnapshot(text: original, selection: range)) { break }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        try Task.checkCancellation()
        guard let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app), CFEqual(focused, field),
              let focusedWindow = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(focusedWindow, window),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
              let current = try? access.snapshot(), current.text == original, current.selection == range else {
            throw CoworkerError.changedContext
        }
        dispatched = true
        #if DEBUG
        paste.diagnosticTrace = diagnosticTrace
        #endif
        let result = try await paste.perform(proposal, application: application, access: access, original: original, range: range) {
            guard let focused = CoworkerAX.element(kAXFocusedUIElementAttribute, app), CFEqual(focused, field),
                  let currentWindow = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(currentWindow, window),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
                throw CoworkerError.changedContext
            }
        }
        if result == .verified {
            verifiedValue = (original as NSString).replacingCharacters(in: range, with: proposal.plainText)
            verifiedRange = NSRange(location: range.location, length: proposal.plainText.utf16.count)
        }
        return result
    }
}

enum CoworkerLinkPolicy {
    static func resolve(_ reply: CoworkerReply, request: String, observation: CoworkerObservation) throws -> URL {
        // An element reference is the complete link selection. Resolve its URL
        // natively instead of asking the model to reproduce a second, redundant
        // copy (which commonly loses tracking/query parameters).
        let destination: String
        if reply.target > 0 {
            guard let link = observation.elements.first(where: { $0.id == reply.target }),
                  let url = link.url else { throw CoworkerError.invalidLink }
            destination = url
        } else { destination = reply.content }
        guard let url = URL(string: destination), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { throw CoworkerError.invalidLink }
        if reply.target > 0 { return url }
        // Navigation accepts a destination, whereas an element reference must still
        // resolve to the captured link. Requiring a visible link for target=0 made
        // ordinary requests such as opening a named website impossible.
        if [.navigate, .openPage].contains(reply.action) {
            return url
        }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let supplied = detector.matches(in: request, range: NSRange(request.startIndex..., in: request))
            .contains { $0.url.map { equivalent($0, url) } == true }
        guard supplied else { throw CoworkerError.invalidLink }
        return url
    }

    /// An omitted root slash and an HTTP-to-HTTPS upgrade preserve the supplied destination.
    /// Hosts, ports, paths, fragments, and query values otherwise remain exact.
    static func equivalent(_ source: URL, _ destination: URL) -> Bool {
        guard let a = URLComponents(url: source, resolvingAgainstBaseURL: false),
              let b = URLComponents(url: destination, resolvingAgainstBaseURL: false),
              a.host?.lowercased() == b.host?.lowercased(), a.port == b.port,
              a.user == nil, b.user == nil, a.password == nil, b.password == nil,
              a.query == b.query, a.fragment == b.fragment,
              (a.path.isEmpty ? "/" : a.path) == (b.path.isEmpty ? "/" : b.path) else { return false }
        return a.scheme == b.scheme || (a.scheme == "http" && b.scheme == "https")
    }

    /// Recognize a site's conventional www redirect only during post-action read-back.
    /// This does not authorize the planner to invent a different destination.
    static func arrived(at requested: URL, actual: URL) -> Bool {
        if equivalent(requested, actual) { return true }
        guard var redirected = URLComponents(url: requested, resolvingAgainstBaseURL: false),
              let host = redirected.host, !host.hasPrefix("www."), actual.host == "www." + host else { return false }
        redirected.host = "www." + host
        return redirected.url.map { equivalent($0, actual) } == true
    }

    /// The web-search tool owns this endpoint and query. Safari may add client
    /// metadata and encode spaces as '+'. Do not relax arbitrary link matching.
    static func arrivedAtWebSearch(query: String, actual: URL) -> Bool {
        guard let components = URLComponents(url: actual, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              ["google.com", "www.google.com"].contains(components.host?.lowercased() ?? ""),
              components.port == nil || components.port == 443,
              components.user == nil, components.password == nil,
              components.path == "/search" else { return false }
        // Decode form encoding in the raw query so %2B stays a literal plus.
        var form = URLComponents()
        form.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        let queries = form.queryItems?.filter { $0.name == "q" } ?? []
        return queries.count == 1 && queries[0].value == query
    }
}

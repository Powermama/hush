import AppKit
import ApplicationServices

@MainActor
protocol CoworkerDesktopControlling {
    var availableActions: [CoworkerReply.Action] { get }
    func frame(for reply: CoworkerReply) -> CGRect?
    func perform(_ reply: CoworkerReply, request: String) async throws -> CoworkerActionResult
    func perform(_ reply: CoworkerReply, request: String, onVerification: @escaping @MainActor () -> Void) async throws -> CoworkerActionResult
}

extension CoworkerDesktopControlling {
    var availableActions: [CoworkerReply.Action] { [.newTab, .press, .clickHere, .navigate, .fill, .submitSearch] }
    func perform(_ reply: CoworkerReply, request: String, onVerification: @escaping @MainActor () -> Void) async throws -> CoworkerActionResult {
        try await perform(reply, request: request)
    }
}

/// Exact voice commands do not need model inference or a preview/confirmation UI.
enum CoworkerDirectCommand {
    static func reply(to request: String) -> CoworkerReply? {
        // Only an explicit web provider is an unambiguous shortcut. Generic
        // 'search for ... on this tab' needs the current page and conversation.
        let pattern = #"(?i)^\s*(?:hey\s+hush[,!]?\s*)?(?:(?:please|can you|could you)\s+)?(?:search\s+(?:google|the web|the internet)\s+for|google)\s+(.+?)\s*[.!?]?\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
           let range = Range(match.range(at: 1), in: request) {
            let query = String(request[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Compound requests need the observation loop, not a whole sentence in Google.
            let sequence = query.range(of: #"(?i)\b(?:then|and\s+(?:open|click|play|select|visit|go|search))\b"#, options: .regularExpression)
            let contextual = query.range(of: #"(?i)\b(?:this|here|current|then|within|inside)\b"#, options: .regularExpression)
            if !query.isEmpty, sequence == nil, contextual == nil {
                return .init(message: "I'll search for that.", action: .search, content: query, target: 0, start: "", minutes: 0)
            }
        }
        var words = request.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.first == "hey" { words.removeFirst() }
        if words.first == "hush" { words.removeFirst() }
        if words.starts(with: ["can", "you"]) || words.starts(with: ["could", "you"]) { words.removeFirst(2) }
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        let command = words.joined(separator: " ")
        let action: CoworkerReply.Action
        switch command {
        case "open a new tab", "open new tab", "open a new browser tab", "new tab", "öffne einen neuen tab": action = .newTab
        case "click here", "click right here", "click where i am pointing", "klick hier": action = .clickHere
        default: return nil
        }
        return .init(message: action == .newTab ? "I'll open a new tab." : "I'll click where you pointed.",
                     action: action, content: "", target: 0, start: "", minutes: 0)
    }
}

/// Binds native actions to an observed process/window/control. No model-supplied code,
/// shortcut, or pixel coordinate is executed. Pixel clicking requires a user-pointed location.
@MainActor
final class CoworkerDesktopControl: CoworkerDesktopControlling {
    private let application: NSRunningApplication
    private let window: AXUIElement
    private let targets: [Int: AXUIElement]
    private let labels: [Int: String]
    private let pointer: CGPoint
    private let windowFrame: CGRect
    private let values: [Int: String]
    private let urls: [Int: URL]
    private let sourcePage: URL?
    private let sourceContent: [String]
    private static let browsers = Set(["com.apple.safari", "com.google.chrome", "com.google.chrome.canary",
        "com.brave.browser", "com.microsoft.edgemac", "company.thebrowser.browser", "org.mozilla.firefox", "com.operasoftware.opera"])

    init(application: NSRunningApplication, window: AXUIElement, targets: [Int: AXUIElement], labels: [Int: String], pointer: CGPoint) throws {
        guard let frame = CoworkerAX.frame(window) else { throw CoworkerError.changedContext }
        self.application = application; self.window = window; self.targets = targets; self.labels = labels
        self.pointer = pointer; self.windowFrame = frame
        self.values = targets.compactMapValues { CoworkerAX.string(kAXValueAttribute, $0) }
        self.urls = targets.compactMapValues { CoworkerAX.attribute(kAXURLAttribute, $0) as? URL }
        let state = CoworkerBrowserState.read(window)
        self.sourcePage = state.url
        self.sourceContent = state.contentFingerprint()
    }

    func frame(for reply: CoworkerReply) -> CGRect? {
        if reply.action == .clickHere { return CGRect(x: pointer.x - 10, y: pointer.y - 10, width: 20, height: 20) }
        return targets[reply.target].flatMap { CoworkerAX.frame($0) }
    }

    var availableActions: [CoworkerReply.Action] {
        var actions: [CoworkerReply.Action] = [.newTab, .clickHere]
        if Self.browsers.contains(application.bundleIdentifier?.lowercased() ?? "") {
            actions += [.navigate, .search]
            if CoworkerReply.bundledBrowserOperationsEnabled { actions.append(.openPage) }
        }
        if targets.contains(where: { id, target in
            guard let label = labels[id], !label.isEmpty, Self.isAllowedLabel(label) else { return false }
            var names: CFArray?
            return AXUIElementCopyActionNames(target, &names) == .success && (names as? [String])?.contains(kAXPressAction) == true
        }) { actions.append(.press) }
        let fields = targets.keys.compactMap { id -> (Int, AXUIElement)? in
            guard let field = try? boundField(id) else { return nil }
            return (id, field)
        }
        if fields.contains(where: { id, field in isSearchField(field, id: id) }) {
            // On a searchable page, use its bound field. An unrelated web search
            // must not silently replace a site-specific request.
            actions.removeAll { $0 == .search }
            if CoworkerReply.bundledBrowserOperationsEnabled { actions.append(.searchPage) }
        }
        if fields.contains(where: { _, field in
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        }) { actions.append(.fill) }
        if fields.contains(where: { id, field in isSearchField(field, id: id) && !(values[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            actions.append(.submitSearch)
        }
        return actions
    }

    private func validate() throws {
        guard AXIsProcessTrusted(), !application.isTerminated,
              let current = CoworkerAX.element(kAXFocusedWindowAttribute, AXUIElementCreateApplication(application.processIdentifier)),
              CFEqual(current, window), CoworkerAX.frame(window) == windowFrame else { throw CoworkerError.changedContext }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard pid == application.processIdentifier || pid == ProcessInfo.processInfo.processIdentifier else {
            throw CoworkerError.changedContext
        }
        if let sourcePage, CoworkerBrowserState.read(window).url != sourcePage { throw CoworkerError.changedContext }
    }

    private func activate(_ app: NSRunningApplication) async throws {
        app.activate()
        for _ in 0..<40 {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CoworkerError.changedContext
    }

    func perform(_ reply: CoworkerReply, request: String) async throws -> CoworkerActionResult {
        try await perform(reply, request: request, onVerification: {})
    }

    func perform(_ reply: CoworkerReply, request: String, onVerification: @escaping @MainActor () -> Void) async throws -> CoworkerActionResult {
        try validate()
        switch reply.action {
        case .openPage:
            guard Self.browsers.contains(application.bundleIdentifier?.lowercased() ?? "") else { throw DesktopError.browserUnavailable }
            // Authorize against the ORIGINAL observation, before any mutation. After
            // tab creation only the resolved URL crosses the boundary, never old IDs.
            let url = try resolveURL(reply, request: request)
            let tab = try await perform(.init(message: "", action: .newTab, content: "", target: 0, start: "", minutes: 0),
                                        request: request, onVerification: onVerification)
            guard tab.canContinue else { return tab }
            try Task.checkCancellation()
            let app = AXUIElementCreateApplication(application.processIdentifier)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
                  let current = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(current, window),
                  CoworkerAX.frame(current) == windowFrame else { throw CoworkerError.changedContext }
            let fresh = try CoworkerDesktopControl(application: application, window: current,
                targets: [:], labels: [:], pointer: pointer)
            // The native-resolved URL is now the authorized input for navigation.
            return try await fresh.perform(.init(message: "", action: .navigate, content: url.absoluteString,
                target: 0, start: "", minutes: 0), request: url.absoluteString, onVerification: onVerification)

        case .newTab:
            let browser: NSRunningApplication
            if Self.browsers.contains(application.bundleIdentifier?.lowercased() ?? "") { browser = application }
            else {
                guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
                      let id = Bundle(url: url)?.bundleIdentifier,
                      Self.browsers.contains(id.lowercased()) else { throw DesktopError.browserUnavailable }
                browser = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            try await activate(browser)
            let app = AXUIElementCreateApplication(browser.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.1)
            let beforeWindow = CoworkerAX.element(kAXFocusedWindowAttribute, app)
            let beforeTabs = beforeWindow.flatMap { CoworkerBrowserState.read($0).tabCount }
            try Task.checkCancellation()
            try Self.key(17, flags: .maskCommand, to: browser.processIdentifier)
            onVerification()
            return await Task { @MainActor in
                for _ in 0..<15 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if let current = CoworkerAX.element(kAXFocusedWindowAttribute, app),
                       let beforeWindow, CFEqual(current, beforeWindow), let beforeTabs,
                       CoworkerBrowserState.read(current).tabCount == beforeTabs + 1 {
                        return CoworkerActionResult(message: "Opened a new tab in \(browser.localizedName ?? "your browser").", verification: .verified, applicationPID: browser.processIdentifier)
                    }
                }
                return CoworkerActionResult(message: "I used your browser's New Tab shortcut. Please check that the tab opened.", verification: .unverified)
            }.value

        case .navigate, .search:
            guard Self.browsers.contains(application.bundleIdentifier?.lowercased() ?? "") else { throw DesktopError.browserUnavailable }
            let url: URL
            if reply.action == .search {
                var components = URLComponents(string: "https://www.google.com/search")!
                components.queryItems = [.init(name: "q", value: reply.content)]
                guard let searchURL = components.url else { throw CoworkerError.invalidLink }
                url = searchURL
            } else {
                url = try resolveURL(reply, request: request)
            }
            try await activate(application)
            try validate()
            try Task.checkCancellation()
            try Self.key(37, flags: .maskCommand, to: application.processIdentifier) // Native address bar.
            try await Task.sleep(for: .milliseconds(100))
            let app = AXUIElementCreateApplication(application.processIdentifier)
            guard let field = CoworkerAX.element(kAXFocusedUIElementAttribute, app),
                  CoworkerAX.element(kAXWindowAttribute, field).map({ CFEqual($0, window) }) == true,
                  !CoworkerBrowserState.insidePage(field, window: window),
                  [kAXTextFieldRole, kAXComboBoxRole].contains(CoworkerAX.string(kAXRoleAttribute, field) ?? "") else {
                throw DesktopError.unavailableControl
            }
            guard try await setField(field, text: url.absoluteString) else {
                return .init(message: "I couldn't verify the address field. Please check the browser.", verification: .unverified)
            }
            try validate()
            try Task.checkCancellation()
            guard CoworkerAX.element(kAXFocusedUIElementAttribute, app).map({ CFEqual($0, field) }) == true else { throw CoworkerError.changedContext }
            try Self.key(36, flags: [], to: application.processIdentifier)
            onVerification()
            return await verifyPage {
                reply.action == .search
                    ? CoworkerLinkPolicy.arrivedAtWebSearch(query: reply.content, actual: $0)
                    : CoworkerLinkPolicy.arrived(at: url, actual: $0)
            }

        case .fill, .submitSearch, .searchPage:
            try await activate(application)
            try validate()
            let field = try boundField(reply.target)
            if reply.action == .fill {
                let verified = try await fillPageField(field, text: reply.content)
                return .init(message: verified ? "Filled the field and checked its value." : "The field change couldn't be verified. Please check it.",
                             verification: verified ? .verified : .unverified)
            }
            guard isSearchField(field, id: reply.target), CoworkerBrowserState.insidePage(field, window: window) else { throw DesktopError.unavailableControl }
            let value: String
            if reply.action == .searchPage {
                guard try await fillPageField(field, text: reply.content) else {
                    return .init(message: "I couldn't verify the search text, so I haven't submitted it.", verification: .unverified)
                }
                try Task.checkCancellation()
                // Same observed field, fresh value. A page change or user edit must
                // stop the bundle before Return can submit a different destination.
                try validate()
                value = reply.content
            } else {
                guard let original = values[reply.target] else { throw DesktopError.unavailableControl }
                value = original
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  CoworkerAX.string(kAXValueAttribute, field) == value else { throw CoworkerError.changedContext }
            try await focusField(field)
            let app = AXUIElementCreateApplication(application.processIdentifier)
            guard CoworkerAX.element(kAXFocusedUIElementAttribute, app).map({ CFEqual($0, field) }) == true else { throw CoworkerError.changedContext }
            try validate()
            try Task.checkCancellation()
            try Self.key(36, flags: [], to: application.processIdentifier)
            onVerification()
            return await verifyPage { CoworkerSiteSearch.arrived(from: self.sourcePage, query: value, at: $0) }

        case .press:
            guard let target = targets[reply.target], let label = labels[reply.target], !label.isEmpty,
                  Self.isAllowedLabel(label),
                  CoworkerAX.label(target) == label,
                  CoworkerAX.attribute(kAXEnabledAttribute, target) as? Bool != false,
                  let frame = CoworkerAX.frame(target), frame.intersects(windowFrame) else { throw DesktopError.unavailableControl }
            try await activate(application)
            try validate()
            try Task.checkCancellation()
            // A search button and Return in its field have the same postcondition.
            // Bind the query before dispatch; never send a second event as a retry.
            let searchQuery = queryForSearchButton(target, label: label)
            var actions: CFArray?
            guard AXUIElementCopyActionNames(target, &actions) == .success,
                  (actions as? [String])?.contains(kAXPressAction) == true,
                  AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else { throw DesktopError.unavailableControl }
            onVerification()
            if let url = urls[reply.target] { return await verifyPage { CoworkerLinkPolicy.arrived(at: url, actual: $0) } }
            if let searchQuery {
                return await verifyPage { CoworkerSiteSearch.arrived(from: self.sourcePage, query: searchQuery, at: $0) }
            }
            if [kAXCheckBoxRole, kAXRadioButtonRole].contains(CoworkerAX.string(kAXRoleAttribute, target) ?? ""),
               let before = values[reply.target], let after = CoworkerAX.string(kAXValueAttribute, target), before != after {
                return .init(message: "Changed \(label) and checked its value.", verification: .verified)
            }
            return .init(message: "The press was sent to \(label), but I couldn't verify its result.", verification: .unverified)

        case .clickHere:
            guard CoworkerDirectCommand.reply(to: request)?.action == .clickHere,
                  windowFrame.contains(pointer), let now = CGEvent(source: nil)?.location,
                  hypot(now.x - pointer.x, now.y - pointer.y) < 6 else { throw CoworkerError.changedContext }
            try await activate(application)
            try validate()
            try Task.checkCancellation()
            var element: AXUIElement?
            let app = AXUIElementCreateApplication(application.processIdentifier)
            if AXUIElementCopyElementAtPosition(app, Float(pointer.x), Float(pointer.y), &element) == .success, let element {
                let label = CoworkerAX.label(element)
                guard Self.isAllowedLabel(label), CoworkerAX.string(kAXSubroleAttribute, element) != kAXSecureTextFieldSubrole else {
                    throw DesktopError.unavailableControl
                }
            }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: pointer, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: pointer, mouseButton: .left) else {
                throw DesktopError.unavailableControl
            }
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: MailAssistantDestination.pasteEventMarker)
                event.post(tap: .cghidEventTap)
            }
            return .init(message: "Clicked where you pointed. Please check the result.", verification: .unverified)
        default: throw DesktopError.unavailableControl
        }
    }

    private func resolveURL(_ reply: CoworkerReply, request: String) throws -> URL {
        let links = urls.map { CoworkerObservation.Element(id: $0.key, role: "AXLink", label: labels[$0.key] ?? "", url: $0.value.absoluteString) }
        let observation = CoworkerObservation(application: "", window: "", selectedText: "", visibleText: "", elements: links, editable: false, limitation: nil)
        return try CoworkerLinkPolicy.resolve(reply, request: request, observation: observation)
    }

    private func boundField(_ id: Int) throws -> AXUIElement {
        guard let field = targets[id], let label = labels[id], CoworkerAX.label(field) == label,
              CoworkerAX.string(kAXValueAttribute, field) == values[id],
              [kAXTextFieldRole, kAXComboBoxRole].contains(CoworkerAX.string(kAXRoleAttribute, field) ?? ""),
              CoworkerAX.string(kAXSubroleAttribute, field) != kAXSecureTextFieldSubrole,
              CoworkerBrowserState.insidePage(field, window: window),
              CoworkerAX.attribute(kAXEnabledAttribute, field) as? Bool != false else { throw DesktopError.unavailableControl }
        return field
    }

    private func isSearchField(_ field: AXUIElement, id: Int) -> Bool {
        let label = (labels[id] ?? "").lowercased()
        return CoworkerAX.string(kAXSubroleAttribute, field) == "AXSearchField" ||
            !Set(label.components(separatedBy: CharacterSet.letters.inverted)).isDisjoint(with: ["search", "suche", "suchen"])
    }

    private func focusField(_ field: AXUIElement) async throws {
        try validate()
        try Task.checkCancellation()
        guard AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw DesktopError.unavailableControl
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        for _ in 0..<20 {
            try Task.checkCancellation()
            try validate()
            if CoworkerAX.element(kAXFocusedUIElementAttribute, app).map({ CFEqual($0, field) }) == true { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw DesktopError.unavailableControl
    }

    private func queryForSearchButton(_ button: AXUIElement, label: String) -> String? {
        guard CoworkerSiteSearch.isSubmitButton(role: CoworkerAX.string(kAXRoleAttribute, button) ?? "", label: label),
              CoworkerBrowserState.insidePage(button, window: window) else { return nil }
        let queries = targets.keys.compactMap { id -> String? in
            guard let field = try? boundField(id), isSearchField(field, id: id),
                  let query = values[id], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return query
        }
        return queries.count == 1 ? queries.first : nil
    }

    /// Web inputs need ordinary text input events. A reported AXValue setter can
    /// succeed without updating a controlled HTML input. Use the shared, verified
    /// native paste transaction up front, never as a retry after an uncertain write.
    private func fillPageField(_ field: AXUIElement, text: String) async throws -> Bool {
        let access = CoworkerNativeTextAccess(field: field)
        let original = try access.text()
        let selection = NSRange(location: 0, length: original.utf16.count)
        try await focusField(field)
        guard try access.text() == original else { throw CoworkerError.changedContext }
        try access.select(selection)
        let expected = try CoworkerTextSnapshot(text: original, selection: selection)
        for _ in 0..<20 {
            try Task.checkCancellation()
            if (try? access.snapshot()) == expected { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        let proposal = AssistantProposal(decision: .draft, message: "", blocks: [.init(kind: .paragraph, text: text)])
        let result = try await CoworkerPaste().perform(proposal, application: application, access: access,
            original: original, range: selection) {
                try self.validate()
                guard CoworkerAX.element(kAXFocusedUIElementAttribute, app).map({ CFEqual($0, field) }) == true else {
                    throw CoworkerError.changedContext
                }
            }
        return result == .verified
    }

    private func setField(_ field: AXUIElement, text: String) async throws -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else { throw DesktopError.unavailableControl }
        try validate()
        try Task.checkCancellation()
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString)
        guard result == .success else { return false }
        // WebKit applies AX setters across a process boundary. A successful dispatch
        // is not synchronous read-back. Observe once-dispatched work; never retype it.
        return await Task { @MainActor in
            for _ in 0..<20 {
                if CoworkerAX.string(kAXValueAttribute, field) == text { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }.value
    }

    /// Verification outlives cancellation after dispatch. The caller cannot start another
    /// mutation until it settles, and cancellation never causes a second key/click.
    private func verifyPage(_ predicate: @escaping @MainActor (URL) -> Bool) async -> CoworkerActionResult {
        await Task { @MainActor in
            let started = ContinuousClock.now
            let deadline = started.advanced(by: .seconds(12))
            var readiness = CoworkerPageReadiness(previous: sourceContent)
            var reason = "deadline"
            var lastState: CoworkerBrowserState?
            var lastContent: [String] = []
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                let app = AXUIElementCreateApplication(application.processIdentifier)
                guard let current = CoworkerAX.element(kAXFocusedWindowAttribute, app), CFEqual(current, window),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
                    reason = "focused_window_changed"; break
                }
                let state = CoworkerBrowserState.read(window)
                lastState = state
                let matches = state.url.map(predicate) ?? false
                // Search suggestions and updated page titles are not new results.
                lastContent = matches && state.documentReady ? state.contentFingerprint() : []
                if readiness.observe(documentReady: state.documentReady, urlMatches: matches,
                                     content: lastContent, elapsed: started.duration(to: .now),
                                     requiresContentChange: state.url != sourcePage) {
                    return .init(message: "The requested page is open in this tab.", verification: .verified)
                }
            }
            var result = CoworkerActionResult(message: "The browser action was sent, but I couldn't verify the destination. Please check the page.", verification: .unverified)
            #if DEBUG
            result.diagnostics = ["reason": reason, "observed_url": lastState?.url?.absoluteString ?? "missing",
                "document_ready": String(lastState?.documentReady ?? false),
                "document_loaded": lastState?.loaded.map(String.init) ?? "unknown",
                "url_matches": String(lastState?.url.map(predicate) ?? false),
                "content_changed": String(lastContent != sourceContent),
                "content_items": String(lastContent.count)]
            #endif
            return result
        }.value
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags, to pid: pid_t) throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { throw DesktopError.unavailableControl }
        for event in [down, up] {
            event.flags = event.type == .keyDown ? flags : []
            event.setIntegerValueField(.eventSourceUserData, value: MailAssistantDestination.pasteEventMarker)
            event.postToPid(pid)
        }
    }

    static func isAllowedLabel(_ label: String) -> Bool {
        let words = Set(label.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        return words.isDisjoint(with: ["send", "senden", "delete", "löschen", "trash", "purchase", "pay", "buy", "publish", "erase"])
    }
}

enum CoworkerSiteSearch {
    static func isSubmitButton(role: String, label: String) -> Bool {
        role == kAXButtonRole && ["search", "suche", "suchen"].contains(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// A site-owned search must remain on the bound origin and expose the submitted
    /// query in a changed destination. Form decoding preserves literal %2B values.
    static func arrived(from source: URL?, query: String, at actual: URL) -> Bool {
        guard let source, let before = URLComponents(url: source, resolvingAgainstBaseURL: false),
              let after = URLComponents(url: actual, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(after.scheme?.lowercased() ?? ""),
              after.scheme == before.scheme, after.host?.lowercased() == before.host?.lowercased(),
              after.port == before.port, after.user == nil, after.password == nil,
              before.path != after.path || before.percentEncodedQuery != after.percentEncodedQuery else { return false }
        var form = URLComponents()
        form.percentEncodedQuery = after.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        let items = form.queryItems ?? []
        return items.contains { item in
            item.value == query && items.filter { $0.name == item.name }.count == 1
        }
    }
}

private enum DesktopError: LocalizedError {
    case unavailableControl, browserUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailableControl: "I can't safely press that control. Point at the control and tell me what you want to change."
        case .browserUnavailable: "I couldn't find a supported browser. Open Safari or Chrome and ask me again."
        }
    }
}

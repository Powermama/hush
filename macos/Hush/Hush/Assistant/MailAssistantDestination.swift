import AppKit
import ApplicationServices

/// Initial adapter: a focused, readable Apple Mail text area in a compose window.
/// Unrecognized Mail layouts fail closed. No coordinates are used to select a field.
@MainActor
final class MailAssistantDestination: AssistantDestination {
    nonisolated static let pasteEventMarker: Int64 = 0x4855534841535354
    let context: AssistantContext
    private let application: NSRunningApplication
    private let appElement: AXUIElement
    private let window: AXUIElement
    private let body: AXUIElement
    private let originalValue: String
    private let originalRange: NSRange
    private var dispatched = false

    static func capture(from application: NSRunningApplication?) throws -> MailAssistantDestination {
        guard AXIsProcessTrusted() else { throw AssistantFailure.permissionRequired }
        guard let application, application.bundleIdentifier == "com.apple.mail" else {
            throw AssistantFailure.unsupportedDestination
        }
        return try MailAssistantDestination(application: application)
    }

    private init(application: NSRunningApplication) throws {
        self.application = application
        appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        guard let body = Self.element(kAXFocusedUIElementAttribute, appElement),
              Self.string(kAXRoleAttribute, body) == kAXTextAreaRole,
              Self.string(kAXSubroleAttribute, body) != kAXSecureTextFieldSubrole,
              let window = Self.element(kAXWindowAttribute, body),
              let focusedWindow = Self.element(kAXFocusedWindowAttribute, appElement),
              CFEqual(window, focusedWindow), Self.isComposeWindow(window),
              let value = Self.string(kAXValueAttribute, body), value.utf16.count <= 50_000,
              let range = Self.range(body), range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= value.utf16.count,
              Self.isSettable(kAXSelectedTextRangeAttribute, body) else {
            throw AssistantFailure.unsupportedDestination
        }
        self.body = body
        self.window = window
        originalValue = value
        originalRange = range
        let selection = (value as NSString).substring(with: range)
        guard selection.utf8.count <= 6_000 else { throw AssistantFailure.contextTooLarge }
        context = AssistantContext(id: UUID(), applicationName: "Mail",
                                   destinationName: range.length == 0 ? "Email body at your caret" : "Selected text in email body",
                                   selectedText: selection)
    }

    var targetFrame: CGRect? {
        guard let position = Self.value(kAXPositionAttribute, body),
              let size = Self.value(kAXSizeAttribute, body),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func validate() throws {
        guard !application.isTerminated,
              let currentWindow = Self.element(kAXFocusedWindowAttribute, appElement), CFEqual(currentWindow, window),
              let currentBody = Self.element(kAXFocusedUIElementAttribute, appElement), CFEqual(currentBody, body),
              Self.string(kAXRoleAttribute, body) == kAXTextAreaRole,
              Self.string(kAXSubroleAttribute, body) != kAXSecureTextFieldSubrole,
              Self.isSettable(kAXSelectedTextRangeAttribute, body),
              Self.string(kAXValueAttribute, body) == originalValue,
              Self.range(body) == originalRange else { throw AssistantFailure.contextChanged }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           frontmost.processIdentifier != application.processIdentifier {
            throw AssistantFailure.contextChanged
        }
    }

    func insert(_ proposal: AssistantProposal) async throws -> AssistantInsertionResult {
        guard !dispatched else { throw AssistantFailure.contextChanged }
        try Task.checkCancellation()
        try validate()
        application.activate()
        // Activation is asynchronous. Recheck the actual frontmost app, field,
        // document contents, and selection before creating or posting any events.
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier { break }
        }
        try Task.checkCancellation()
        try validate()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AssistantFailure.contextChanged
        }
        let lease = try AssistantClipboardLease(proposal: proposal)
        let expected = (originalValue as NSString).replacingCharacters(in: originalRange, with: proposal.plainText)
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: Self.pasteEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.pasteEventMarker)
        dispatched = true
        down.postToPid(application.processIdentifier)
        up.postToPid(application.processIdentifier)

        // A separate task finishes verification even if Escape cancels the caller.
        // A dispatched paste is never repeated, including after an uncertain result.
        return await Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(50))
                if Self.string(kAXValueAttribute, body) == expected {
                    lease.restoreIfUnchanged()
                    return .verified
                }
            }
            // Leave the draft on the clipboard if consumption is uncertain.
            // Restoring early could make a delayed paste consume unrelated data.
            return .unverified
        }.value
    }

    private static func isComposeWindow(_ window: AXUIElement) -> Bool {
        // Positive compose evidence, bounded traversal. No send action is exposed.
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 180 {
            let element = queue.removeFirst()
            visited += 1
            if string(kAXRoleAttribute, element) == kAXButtonRole {
                let name = string(kAXTitleAttribute, element) ?? string(kAXDescriptionAttribute, element) ?? ""
                let identifier = string(kAXIdentifierAttribute, element) ?? ""
                if ["Send", "Send message", "Senden", "Nachricht senden"].contains(name)
                    || identifier == "sendMessage:" { return true }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let elements = children as? [AXUIElement] {
                queue.append(contentsOf: elements.prefix(max(0, 180 - visited - queue.count)))
            }
        }
        return false
    }

    private static func string(_ name: String, _ element: AXUIElement) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? String
    }

    private static func element(_ name: String, _ element: AXUIElement) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(result, to: AXUIElement.self)
    }

    private static func value(_ name: String, _ element: AXUIElement) -> AXValue? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(result, to: AXValue.self)
    }

    private static func range(_ element: AXUIElement) -> NSRange? {
        guard let value = value(kAXSelectedTextRangeAttribute, element), AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func isSettable(_ name: String, _ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
}

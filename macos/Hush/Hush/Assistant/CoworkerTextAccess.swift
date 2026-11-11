import AppKit
import ApplicationServices

/// Editors expose either native UTF-16 ranges or WebKit text markers. Keep their
/// representation here; identity, cancellation, paste and verification stay shared.
@MainActor
protocol CoworkerTextAccess {
    var kind: String { get }
    func text() throws -> String
    func snapshot() throws -> CoworkerTextSnapshot
    func select(_ range: NSRange) throws
}

struct CoworkerTextSnapshot: Equatable {
    let text: String
    let selection: NSRange

    init(text: String, selection: NSRange) throws {
        guard text.utf16.count <= 50_000, selection.location >= 0, selection.length >= 0,
              selection.location <= text.utf16.count,
              selection.length <= text.utf16.count - selection.location,
              Range(selection, in: text) != nil else { throw CoworkerError.unsupportedEditor }
        let units = Array(text.utf16)
        for boundary in [selection.location, selection.location + selection.length] {
            if boundary > 0, boundary < units.count,
               (0xD800...0xDBFF).contains(units[boundary - 1]), (0xDC00...0xDFFF).contains(units[boundary]) {
                throw CoworkerError.unsupportedEditor
            }
        }
        self.text = text
        self.selection = selection
    }
}

@MainActor
struct CoworkerNativeTextAccess: CoworkerTextAccess {
    let field: AXUIElement
    let kind = "native_range"
    func text() throws -> String {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value)
        return try Self.readText(value: value, status: status) {
            CoworkerAX.attribute(kAXNumberOfCharactersAttribute, field)
        }
    }

    static func readText(value: CFTypeRef?, status: AXError,
                         characterCount: () -> CFTypeRef?) throws -> String {
        if status == .success, let text = value as? String {
            guard text.utf16.count <= 50_000 else { throw CoworkerError.unsupportedEditor }
            return text
        }
        // Some native editors omit AXValue while empty. A missing value alone
        // never proves emptiness; require an independent, numeric zero length.
        // Failed AX reads and unexpected value types must still fail closed.
        guard [.success, .noValue].contains(status), value == nil,
              let count = characterCount(), CFGetTypeID(count) == CFNumberGetTypeID(),
              let number = count as? NSNumber, number == NSNumber(value: 0) else {
            throw CoworkerError.unsupportedEditor
        }
        return ""
    }
    func snapshot() throws -> CoworkerTextSnapshot {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue, let range = CoworkerAX.range(field) else { throw CoworkerError.unsupportedEditor }
        return try .init(text: text(), selection: range)
    }
    func select(_ range: NSRange) throws {
        _ = try CoworkerTextSnapshot(text: text(), selection: range)
        var native = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &native),
              AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw CoworkerError.changedContext
        }
    }
}

/// Only constructed for a positively identified Mail compose body. A selectable
/// AXWebArea alone is not evidence that a page is editable.
@MainActor
struct CoworkerWebTextAccess: CoworkerTextAccess {
    let field: AXUIElement
    let kind = "webkit_markers"

    private func parameter(_ name: String, _ value: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(field, name as CFString, value, &result) == .success else { return nil }
        return result
    }
    private func marker(_ value: CFTypeRef?) throws -> AXTextMarker {
        guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID(),
              (parameter(kAXTextMarkerIsValidParameterizedAttribute, value) as? Bool) == true else {
            throw CoworkerError.unsupportedEditor
        }
        return value as! AXTextMarker
    }
    private func bounds() throws -> (AXTextMarker, AXTextMarker) {
        try (marker(CoworkerAX.attribute(kAXStartTextMarkerAttribute as String, field)),
             marker(CoworkerAX.attribute(kAXEndTextMarkerAttribute as String, field)))
    }
    private func string(from start: AXTextMarker, to end: AXTextMarker) throws -> String {
        let range = AXTextMarkerRangeCreate(kCFAllocatorDefault, start, end)
        guard let length = parameter(kAXLengthForTextMarkerRangeParameterizedAttribute, range) as? NSNumber,
              length.intValue >= 0, length.intValue <= 50_000 else { throw CoworkerError.unsupportedEditor }
        let result = parameter(kAXStringForTextMarkerRangeParameterizedAttribute, range) as? String
        // WebKit may return nil for an empty marker range. The length must independently be zero.
        guard let text = result ?? (length.intValue == 0 ? "" : nil), text.utf16.count == length.intValue else {
            throw CoworkerError.unsupportedEditor
        }
        return text
    }
    func text() throws -> String {
        let (start, end) = try bounds()
        return try string(from: start, to: end)
    }
    func snapshot() throws -> CoworkerTextSnapshot {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXSelectedTextMarkerRangeAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let value = CoworkerAX.attribute(kAXSelectedTextMarkerRangeAttribute as String, field),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { throw CoworkerError.unsupportedEditor }
        let selection = value as! AXTextMarkerRange
        let a = try marker(AXTextMarkerRangeCopyStartMarker(selection))
        let b = try marker(AXTextMarkerRangeCopyEndMarker(selection))
        let (start, end) = try bounds()
        let text = try string(from: start, to: end)
        let prefix = try string(from: start, to: a)
        let selected = try string(from: a, to: b)
        let suffix = try string(from: b, to: end)
        // Reject stale/cross-document markers and inconsistent AX snapshots.
        guard prefix + selected + suffix == text else { throw CoworkerError.unsupportedEditor }
        return try .init(text: text, selection: NSRange(location: prefix.utf16.count, length: selected.utf16.count))
    }
    func select(_ range: NSRange) throws {
        let before = try text()
        _ = try CoworkerTextSnapshot(text: before, selection: range)
        let (start, _) = try bounds()
        guard let base = parameter(kAXIndexForTextMarkerParameterizedAttribute, start) as? NSNumber,
              base.intValue >= 0, base.intValue <= Int.max - 50_000 else { throw CoworkerError.unsupportedEditor }
        let a = try marker(parameter(kAXTextMarkerForIndexParameterizedAttribute, NSNumber(value: base.intValue + range.location)))
        let b = try marker(parameter(kAXTextMarkerForIndexParameterizedAttribute, NSNumber(value: base.intValue + NSMaxRange(range))))
        // Do not assume a provider's index units. Confirm the exact UTF-16 boundaries before changing selection.
        guard try string(from: start, to: a) == (before as NSString).substring(to: range.location),
              try string(from: a, to: b) == (before as NSString).substring(with: range),
              try text() == before else { throw CoworkerError.changedContext }
        let selection = AXTextMarkerRangeCreate(kCFAllocatorDefault, a, b)
        guard AXUIElementSetAttributeValue(field, kAXSelectedTextMarkerRangeAttribute as CFString, selection) == .success else {
            throw CoworkerError.changedContext
        }
    }
}

@MainActor
enum CoworkerMailCompose {
    static func containsBody(_ field: AXUIElement, window: AXUIElement) -> Bool {
        // Prove that this body belongs to this window, independently of its title or position.
        var parent: AXUIElement? = field
        var belongs = false
        for _ in 0..<24 {
            guard let node = parent else { break }
            if CFEqual(node, window) { belongs = true; break }
            parent = CoworkerAX.element(kAXParentAttribute, node)
        }
        guard belongs else { return false }
        var queue = [window], index = 0
        let deadline = Date().addingTimeInterval(0.3)
        while index < queue.count, index < 180, Date() < deadline {
            let node = queue[index]; index += 1
            // Body HTML cannot supply the compose-window evidence.
            if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { continue }
            if CoworkerAX.string(kAXRoleAttribute, node) == kAXButtonRole {
                let identifier = CoworkerAX.string(kAXIdentifierAttribute, node) ?? ""
                if identifier == "sendMessage:" || ["Send", "Send message", "Senden", "Nachricht senden"].contains(CoworkerAX.label(node)) {
                    return true
                }
            }
            if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 180 - queue.count)))
            }
        }
        return false
    }
}

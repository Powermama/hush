import AppKit
import Carbon.HIToolbox
import OSLog

struct TextInsertionContent {
    let plainText: String
    let richText: NSAttributedString?

    init(plainText: String, richText: NSAttributedString? = nil) {
        self.plainText = plainText
        self.richText = richText
    }
}

/// Inserts the recognized text into whatever app is currently focused.
///
/// MVP path: clipboard + simulated ⌘V via `CGEvent`.
/// Posting `CGEvent`s into other apps requires the user to grant **Accessibility** to Hush
/// in System Settings → Privacy & Security → Accessibility. Without it, we still copy to the
/// clipboard and let the user paste manually (or surface the text in the HUD).
///
/// In `APP_STORE` builds the auto-paste path is compiled out: the App Store version is
/// clipboard-only to avoid review friction around Accessibility entitlements.
@MainActor
final class TextInserter {

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "TextInsert")

    enum Outcome: Equatable {
        case insertedAutomatically
        case copiedToClipboard
        case missingAccessibilityPermission
    }

    func insert(_ text: String) -> Outcome {
        insert(TextInsertionContent(plainText: text))
    }

    func insert(_ content: TextInsertionContent, automatically: Bool = true) -> Outcome {
        guard !content.plainText.isEmpty else { return .copiedToClipboard }

        let pasteboard = NSPasteboard.general
        let savedItems: [(NSPasteboard.PasteboardType, Data)]? = Settings.shared.restoreClipboard
            ? snapshot(pasteboard: pasteboard)
            : nil

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(content.plainText, forType: .string)
        if let richText = content.richText {
            let fullRange = NSRange(location: 0, length: richText.length)
            if let html = try? richText.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            ) {
                item.setData(html, forType: .html)
            }
            if let rtf = try? richText.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                item.setData(rtf, forType: .rtf)
            }
        }
        pasteboard.writeObjects([item])

        if !automatically || !Settings.shared.autoInsert {
            return .copiedToClipboard
        }

        #if APP_STORE
        // App Store build: never simulate paste. User pastes manually.
        return .copiedToClipboard
        #else
        guard PermissionsChecker.isAccessibilityGranted else {
            Self.log.notice("Accessibility not granted - leaving text in clipboard.")
            return .missingAccessibilityPermission
        }

        guard simulateCommandV() else {
            return .copiedToClipboard
        }

        if let savedItems {
            // Wait long enough for the focused app to consume our paste before restoring.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.restore(items: savedItems, on: pasteboard)
            }
        }

        return .insertedAutomatically
        #endif
    }

    private func snapshot(pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        guard let types = pasteboard.types else { return [] }
        return types.compactMap { type in
            pasteboard.data(forType: type).map { (type, $0) }
        }
    }

    private func restore(items: [(NSPasteboard.PasteboardType, Data)], on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }

    private func simulateCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

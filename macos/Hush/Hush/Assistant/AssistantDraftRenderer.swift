import AppKit

enum AssistantDraftRenderer {
    static func attributedText(_ proposal: AssistantProposal) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return NSAttributedString(string: proposal.plainText, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph
        ])
    }

    static func pasteboardItem(_ proposal: AssistantProposal) throws -> NSPasteboardItem {
        let text = attributedText(proposal)
        let range = NSRange(location: 0, length: text.length)
        let item = NSPasteboardItem()
        item.setString(text.string, forType: .string)
        item.setData(try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        item.setData(try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]), forType: .html)
        return item
    }
}

/// A clipboard lease preserves item boundaries and never overwrites a newer copy.
@MainActor
final class AssistantClipboardLease {
    private let pasteboard: NSPasteboard
    private let original: [[NSPasteboard.PasteboardType: Data]]
    private let ownedChangeCount: Int

    init(proposal: AssistantProposal, pasteboard: NSPasteboard = .general) throws {
        let item = try AssistantDraftRenderer.pasteboardItem(proposal)
        self.pasteboard = pasteboard
        original = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw AssistantFailure.contextChanged }
        ownedChangeCount = pasteboard.changeCount
    }

    var stillOwnsClipboard: Bool { pasteboard.changeCount == ownedChangeCount }

    func restoreIfUnchanged() {
        guard stillOwnsClipboard else { return }
        let items = original.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

import AppKit

public struct ProofSignatureContent {
    public let plainText: String
    public let richText: NSAttributedString
}

public enum ProofSignatureFormatter {
    private static let durableLinkDestinations: Set<String> = [
        "com.apple.iwork.pages",
        "com.apple.mail",
        "com.apple.notes",
        "com.apple.textedit",
        "com.microsoft.word",
    ]

    public static func append(to text: String, proofURL: URL) -> String {
        content(for: text, proofURL: proofURL).plainText
    }

    public static func content(for text: String, proofURL: URL) -> ProofSignatureContent {
        let plainText = "\(text)\n\n-typed with hush: \(proofURL.absoluteString)"
        let richText = NSMutableAttributedString(string: "\(text)\n\n-")
        richText.append(NSAttributedString(
            string: "typed with hush",
            attributes: [.link: proofURL]
        ))
        return ProofSignatureContent(plainText: plainText, richText: richText)
    }

    public static func supportsDurableLinkPaste(
        destinationBundleIdentifier: String?
    ) -> Bool {
        guard let destinationBundleIdentifier else { return false }
        return durableLinkDestinations.contains(destinationBundleIdentifier.lowercased())
    }
}

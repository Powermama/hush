import AppKit
import HushProvenance
import OSLog

struct HushSelectionContext: Sendable {
    enum Origin: String, Sendable {
        case newDraft = "new_draft"
        case recentHushOutput = "recent_hush_output"
    }

    enum Destination: Sendable {
        case exactRange(location: Int, length: Int, expectedText: String)
        case insertionPoint
        case clipboard
    }

    let originalText: String
    let applicationName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let isSecureField: Bool
    let websiteHost: String?
    let isBrowserAddressOrSearchField: Bool
    let destination: Destination
    let origin: Origin
    let parentProofId: String?
    let parentProofCommitment: String?
    let parentProvenanceEvents: [ProofManifest.ProvenanceEvent]
    let refinementSourceText: String?

    init(
        originalText: String,
        applicationName: String,
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        isSecureField: Bool = false,
        websiteHost: String? = nil,
        isBrowserAddressOrSearchField: Bool = false,
        destination: Destination,
        origin: Origin,
        parentProofId: String? = nil,
        parentProofCommitment: String? = nil,
        parentProvenanceEvents: [ProofManifest.ProvenanceEvent] = [],
        refinementSourceText: String? = nil
    ) {
        self.originalText = originalText
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isSecureField = isSecureField
        self.websiteHost = websiteHost
        self.isBrowserAddressOrSearchField = isBrowserAddressOrSearchField
        self.destination = destination
        self.origin = origin
        self.parentProofId = parentProofId
        self.parentProofCommitment = parentProofCommitment
        self.parentProvenanceEvents = parentProvenanceEvents
        self.refinementSourceText = refinementSourceText
    }
}

@MainActor
final class SelectionCapture {
    private static let log = Logger(
        subsystem: "com.decentralfreedom.hush",
        category: "SelectionCapture"
    )

    /// Resolves the most useful editor context without retaining the surrounding
    /// contents of the focused field. A retained Hush message enclosing the
    /// selection or caret wins. Otherwise the editor opens blank and never
    /// treats arbitrary selected text as Hush-authored source.
    func resolveEditorContext(
        recentActivities: [DictationActivity],
        sourceApplication: NSRunningApplication? = nil
    ) -> HushSelectionContext {
        guard let application = sourceApplication ?? NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return HushSelectionContext(
                originalText: "",
                applicationName: "Clipboard",
                bundleIdentifier: nil,
                processIdentifier: 0,
                destination: .clipboard,
                origin: .newDraft
            )
        }

        let destinationContext = FocusedDestinationInspector.context(for: application)
        let base = HushSelectionContext(
            originalText: "",
            applicationName: application.localizedName ?? "App",
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            isSecureField: destinationContext.isSecureField,
            websiteHost: destinationContext.websiteHost,
            isBrowserAddressOrSearchField: destinationContext.isBrowserAddressOrSearchField,
            destination: .insertionPoint,
            origin: .newDraft
        )
        guard PermissionsChecker.isAccessibilityGranted,
              let focusedElement = focusedTextElement() else {
            return base
        }

        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: focusedElement)
        let selectedRange = rangeAttribute(kAXSelectedTextRangeAttribute, from: focusedElement)
        if let selectedRange,
           selectedRange.length > 0,
           let fieldValue = stringAttribute(kAXValueAttribute, from: focusedElement),
           let bundleIdentifier = application.bundleIdentifier,
           let match = TextContextMatcher.match(
                fieldValue: fieldValue,
                bundleIdentifier: bundleIdentifier,
                candidates: recentActivities.compactMap { activity in
                    guard let bundleIdentifier = activity.appBundleIdentifier else { return nil }
                    return RecentTextCandidate(
                        text: activity.text,
                        bundleIdentifier: bundleIdentifier,
                        copiedToClipboard: activity.copiedToClipboard,
                        proofId: activity.proofId,
                        proofCommitment: activity.proofCommitment,
                        provenanceEvents: activity.provenanceEvents,
                        sourceText: activity.sourceText
                    )
                },
                selectionLocation: selectedRange.location,
                selectedRange: selectedRange
           ) {
            return HushSelectionContext(
                originalText: match.message,
                applicationName: base.applicationName,
                bundleIdentifier: base.bundleIdentifier,
                processIdentifier: base.processIdentifier,
                isSecureField: base.isSecureField,
                websiteHost: base.websiteHost,
                isBrowserAddressOrSearchField: base.isBrowserAddressOrSearchField,
                destination: .exactRange(
                    location: match.replacementRange.location,
                    length: match.replacementRange.length,
                    expectedText: match.expectedText
                ),
                origin: .recentHushOutput,
                parentProofId: match.proofId,
                parentProofCommitment: match.proofCommitment,
                parentProvenanceEvents: match.provenanceEvents,
                refinementSourceText: match.sourceText
            )
        }

        guard let selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        let destination: HushSelectionContext.Destination = if let selectedRange {
            .exactRange(
                location: selectedRange.location,
                length: selectedRange.length,
                expectedText: selectedText
            )
        } else {
            .clipboard
        }
        return HushSelectionContext(
            originalText: "",
            applicationName: base.applicationName,
            bundleIdentifier: base.bundleIdentifier,
            processIdentifier: base.processIdentifier,
            isSecureField: base.isSecureField,
            websiteHost: base.websiteHost,
            isBrowserAddressOrSearchField: base.isBrowserAddressOrSearchField,
            destination: destination,
            origin: .newDraft
        )
    }

    func reactivateSource(_ context: HushSelectionContext) async {
        guard let application = NSRunningApplication(processIdentifier: context.processIdentifier) else {
            return
        }
        application.activate()
        try? await Task.sleep(for: .milliseconds(160))
    }

    /// Revalidates an exact target after the editor closes. If the source changed
    /// while Hush was open, this fails closed instead of replacing unrelated text.
    func prepareDestination(_ context: HushSelectionContext) async -> Bool {
        switch context.destination {
        case .clipboard:
            return false
        case .insertionPoint:
            await reactivateSource(context)
            return context.processIdentifier != 0
        case .exactRange(let location, let length, let expectedText):
            await reactivateSource(context)
            guard let element = focusedTextElement(),
                  let currentValue = stringAttribute(kAXValueAttribute, from: element) else {
                return false
            }
            let range = NSRange(location: location, length: length)
            guard TextContextMatcher.isValid(
                range: range,
                expectedText: expectedText,
                in: currentValue
            ) else {
                return false
            }
            var cfRange = CFRange(location: range.location, length: range.length)
            guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
            return AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                value
            ) == .success
        }
    }

    private func focusedTextElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func rangeAttribute(_ name: String, from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue: AXValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}

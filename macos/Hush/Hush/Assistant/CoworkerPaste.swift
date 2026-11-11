import AppKit

/// Single-use paste transaction shared by field and document adapters.
@MainActor
final class CoworkerPaste {
    private var dispatched = false
    #if DEBUG
    var diagnosticTrace: CoworkerTrace?
    #endif

    func perform(_ proposal: AssistantProposal, application: NSRunningApplication,
                 access: any CoworkerTextAccess, original: String, range: NSRange,
                 validate: () throws -> Void) async throws -> AssistantInsertionResult {
        guard !dispatched else { throw CoworkerError.changedContext }
        try Task.checkCancellation()
        let snapshot = try CoworkerTextSnapshot(text: original, selection: range)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw CoworkerError.changedContext
        }
        try validate()
        guard try access.snapshot() == snapshot else { throw CoworkerError.changedContext }
        let lease = try AssistantClipboardLease(proposal: proposal)
        let expected = (original as NSString).replacingCharacters(in: range, with: proposal.plainText)
        dispatched = true
        #if DEBUG
        diagnosticTrace?.event("paste.dispatched", ["replacement_location": String(range.location),
            "replacement_length": String(range.length), "inserted_utf16": String(proposal.plainText.utf16.count)])
        #endif
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: MailAssistantDestination.pasteEventMarker)
            event.postToPid(application.processIdentifier)
        }
        // Finish verification even if Escape cancels the calling turn. Never retry a dispatched paste.
        return await Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(50))
                if (try? access.text()) == expected {
                    lease.restoreIfUnchanged()
                    #if DEBUG
                    diagnosticTrace?.event("paste.verified")
                    #endif
                    return .verified
                }
            }
            #if DEBUG
            diagnosticTrace?.event("paste.unverified", ["expected_utf16": String(expected.utf16.count),
                "observed_utf16": String((try? access.text())?.utf16.count ?? -1)])
            #endif
            return .unverified
        }.value
    }
}

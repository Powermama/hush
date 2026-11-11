import AppKit
import Testing
@testable import Hush

/// Explicit opt-in: reads only the currently focused Mail compose window.
/// Never resolves recipients, sends mail, or writes into the user's draft.
@Suite("Coworker real Mail diagnostics", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_MAIL_LIVE"] == "1"))
@MainActor
struct CoworkerMailLiveTests {
    @Test("The actual focused Mail body can be bound as a writing destination")
    func focusedMailBody() async throws {
        #expect(AXIsProcessTrusted(), "The test host needs Accessibility permission; no editor conclusion can be drawn without it.")
        guard AXIsProcessTrusted() else { return }
        let mail = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first)
        mail.activate()
        try await Task.sleep(for: .milliseconds(300))
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        let focused = try #require(CoworkerAX.element(kAXFocusedUIElementAttribute, app))
        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(focused, kAXSelectedTextRangeAttribute as CFString, &settable)
        print("[mail-live] focusedRole=\(CoworkerAX.string(kAXRoleAttribute, focused) ?? "nil") subrole=\(CoworkerAX.string(kAXSubroleAttribute, focused) ?? "nil") valuePresent=\(CoworkerAX.string(kAXValueAttribute, focused) != nil) range=\(String(describing: CoworkerAX.range(focused))) selectionSettable=\(settable.boolValue) status=\(settableStatus.rawValue)")
        let context = CoworkerContext.capture(from: mail)
        print("[mail-live] editable=\(context.observation.editable) limitation=\(context.observation.limitation ?? "none") controls=\(context.observation.elements.count)")
        #expect(context.textTarget != nil, "A caret in the real Mail compose body must be recognized before generation.")
    }
}

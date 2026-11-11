#if DEBUG
import AppKit

/// Explicit developer launch only. Uses the installed app's normal TCC identity.
/// Read-only by default; the write check creates its own recipient-free draft.
@MainActor
enum CoworkerMailDebugCheck {
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--inspect-mail-editor") || arguments.contains("--test-mail-editor") else { return false }
        Task { @MainActor in
            var report: [String: Any] = ["accessibility": AXIsProcessTrusted()]
            do {
                guard AXIsProcessTrusted() else { throw CoworkerError.missingContext }
                guard let mail = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first else {
                    throw CoworkerError.unsupportedEditor
                }
                mail.activate()
                try await Task.sleep(for: .milliseconds(400))
                let app = AXUIElementCreateApplication(mail.processIdentifier)
                if arguments.contains("--test-mail-editor") {
                    let previousWindow = CoworkerAX.element(kAXFocusedWindowAttribute, app)
                    let source = CGEventSource(stateID: .privateState)
                    for down in [true, false] {
                        let event = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: down)
                        event?.flags = .maskCommand
                        event?.postToPid(mail.processIdentifier)
                    }
                    try await Task.sleep(for: .milliseconds(700))
                    guard let window = CoworkerAX.element(kAXFocusedWindowAttribute, app),
                          previousWindow.map({ !CFEqual($0, window) }) ?? true else { throw CoworkerError.changedContext }
                    // Move from the new draft's recipient field to its body using its AX tree.
                    var queue = [window], index = 0
                    var body: AXUIElement?
                    while index < queue.count, index < 180 {
                        let node = queue[index]; index += 1
                        if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { body = node; break }
                        if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                            queue.append(contentsOf: children.prefix(max(0, 180 - queue.count)))
                        }
                    }
                    guard let body, CoworkerMailCompose.containsBody(body, window: window),
                          AXUIElementSetAttributeValue(body, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
                        throw CoworkerError.unsupportedEditor
                    }
                    try await Task.sleep(for: .milliseconds(150))
                }
                report["binding"] = CoworkerDiagnostics.binding(mail)
                if let field = CoworkerAX.element(kAXFocusedUIElementAttribute, app) {
                    var names: CFArray?
                    AXUIElementCopyParameterizedAttributeNames(field, &names)
                    report["parameterized_attributes"] = names
                    var attributes: CFArray?
                    AXUIElementCopyAttributeNames(field, &attributes)
                    report["attributes"] = attributes
                    var settable = DarwinBoolean(false)
                    let status = AXUIElementIsAttributeSettable(field, kAXSelectedTextMarkerRangeAttribute as CFString, &settable)
                    report["marker_selection_settable"] = settable.boolValue
                    report["marker_selection_status"] = status.rawValue
                    for key in [kAXStartTextMarkerAttribute, kAXEndTextMarkerAttribute, kAXSelectedTextMarkerRangeAttribute] {
                        report[key as String] = CoworkerAX.attribute(key as String, field).map { String(describing: CFGetTypeID($0)) } ?? "missing"
                    }
                    if let window = CoworkerAX.element(kAXFocusedWindowAttribute, app) {
                        report["mail_compose"] = CoworkerMailCompose.containsBody(field, window: window)
                    }
                }
                if let window = CoworkerAX.element(kAXFocusedWindowAttribute, app) {
                    let fields = CoworkerMailDraftTarget.fields(in: window)
                    report["mail_body_count"] = fields.bodies.count
                    report["mail_subject_count"] = fields.subjects.count
                    var queue = [window], index = 0, labels: [[String: String]] = []
                    while index < queue.count, index < 220 {
                        let node = queue[index]; index += 1
                        if CoworkerAX.string(kAXRoleAttribute, node) == "AXWebArea" { continue }
                        if CoworkerAX.string(kAXRoleAttribute, node) == kAXTextFieldRole {
                            let title = CoworkerAX.element(kAXTitleUIElementAttribute, node)
                            labels.append(["label": CoworkerAX.label(node), "identifier": CoworkerAX.string(kAXIdentifierAttribute, node) ?? "",
                                           "title_label": title.map { CoworkerAX.label($0) } ?? "",
                                           "title_value": title.flatMap { CoworkerAX.string(kAXValueAttribute, $0) } ?? ""])
                        }
                        if let children = CoworkerAX.attribute(kAXChildrenAttribute, node) as? [AXUIElement] {
                            queue.append(contentsOf: children.prefix(max(0, 220 - queue.count)))
                        }
                    }
                    report["native_field_labels"] = labels
                }
                let destination = try CoworkerMailDraftTarget(application: mail)
                report["adapter"] = "mail_document"
                report["text_utf16"] = destination.capturedBody.utf16.count
                try destination.validate()
                report["binding_valid"] = true
                if arguments.contains("--test-mail-editor") {
                    // Refuse to overwrite even an automatically inserted signature.
                    guard destination.capturedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CoworkerError.changedContext
                    }
                    let first = AssistantCompanionController.draft("Hush development check 🧪\n\nGuten Morgen, Grüße aus München.\n\nThis is an unsent editor test.")
                    let result = try await destination.insert(first, subject: "Hush editor validation")
                    report["insert_result"] = String(describing: result)
                    guard result == .verified else { throw CoworkerError.changedContext }
                    let current = try CoworkerMailDraftTarget(application: mail)
                    let revision = try destination.revisionTarget(current: current) as! CoworkerMailDraftTarget
                    let revised = AssistantCompanionController.draft("Hush development check 🧪\n\nThe follow-up edit is verified. Grüße!\n\nThis is an unsent editor test.")
                    report["revision_result"] = String(describing: try await revision.insert(revised, subject: "Hush follow-up verified"))
                    let after = try CoworkerMailDraftTarget(application: mail)
                    report["subject_verified"] = after.capturedSubject == "Hush follow-up verified"
                    report["no_duplicate"] = after.capturedBody.components(separatedBy: "Hush development check").count == 2
                    report["body_verified"] = after.capturedBody.trimmingCharacters(in: .whitespacesAndNewlines) == revised.plainText
                    do { try current.validate(); report["stale_snapshot_rejected"] = false }
                    catch { report["stale_snapshot_rejected"] = true }
                    // A second write (the original model's mistaken action) must still replace the document.
                    report["repeat_write_result"] = String(describing: try await after.insert(revised, subject: "Hush follow-up verified"))
                    let final = try CoworkerMailDraftTarget(application: mail)
                    report["repeat_write_no_duplicate"] = final.capturedBody.components(separatedBy: "Hush development check").count == 2
                }
            } catch { report["error"] = String(describing: error); report["description"] = error.localizedDescription }
            let path = ProcessInfo.processInfo.environment["HUSH_MAIL_PROBE_PATH"] ?? "/private/tmp/hush-mail-editor-check.json"
            if JSONSerialization.isValidJSONObject(report), let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
#endif

#if DEBUG
import AppKit

/// Explicit local development check. Inspection is read-only. The opt-in Notes
/// mutation check creates a separate empty note and leaves it visible for review.
@MainActor
enum CoworkerNativeEditorDebugCheck {
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let writes = arguments.contains("--test-notes-editor")
        guard writes || arguments.contains("--inspect-notes-editor") else { return false }
        Task { @MainActor in
            var report: [String: Any] = ["accessibility": AXIsProcessTrusted()]
            do {
                guard AXIsProcessTrusted(),
                      let notes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first else {
                    throw CoworkerError.missingContext
                }
                notes.activate()
                try await Task.sleep(for: .milliseconds(400))
                let app = AXUIElementCreateApplication(notes.processIdentifier)
                AXUIElementSetMessagingTimeout(app, 0.2)
                if writes {
                    // Create an owned fixture through the observed native New Note control.
                    let context = CoworkerContext.capture(from: notes)
                    guard let button = context.observation.elements.first(where: {
                        $0.role == kAXButtonRole && ["New Note", "Neue Notiz"].contains($0.label)
                    }), let desktop = context.desktop else { throw CoworkerError.unsupportedEditor }
                    let reply = CoworkerReply(message: "Create a test note", action: .press, content: "",
                        target: button.id, start: "", minutes: 0)
                    _ = try await desktop.perform(reply, request: "Create a new test note")
                    try await Task.sleep(for: .milliseconds(500))
                }
                report["binding"] = CoworkerDiagnostics.binding(notes)
                let context = CoworkerContext.capture(from: notes)
                report["editable"] = context.observation.editable
                report["available_actions"] = context.observation.availableActions?.map(\.rawValue)
                let destination = try CoworkerTextTarget(application: notes)
                try destination.validate()
                report["binding_valid"] = true
                if writes {
                    guard let field = CoworkerAX.element(kAXFocusedUIElementAttribute, app),
                          try CoworkerNativeTextAccess(field: field).text().isEmpty else {
                        throw CoworkerError.changedContext
                    }
                    let first = AssistantCompanionController.draft("Hush editor test\n\nGerman breakfast\nBrötchen\nEier\nKäse 🧀")
                    let result = try await destination.insert(first)
                    report["insert_result"] = String(describing: result)
                    guard result == .verified else { throw CoworkerError.changedContext }
                    let current = try CoworkerTextTarget(application: notes)
                    let revision = try destination.revisionTarget(current: current)
                    let revised = AssistantCompanionController.draft("Hush editor test\n\nGerman breakfast\nBrötchen\nEier\nKäse 🧀\nKaffee")
                    report["revision_result"] = String(describing: try await revision.insert(revised))
                    guard let finalField = CoworkerAX.element(kAXFocusedUIElementAttribute, app) else {
                        throw CoworkerError.changedContext
                    }
                    let text = try CoworkerNativeTextAccess(field: finalField).text()
                    report["exact_text_verified"] = text == revised.plainText
                    report["no_duplicate"] = text.components(separatedBy: "Hush editor test").count == 2
                    do { try current.validate(); report["stale_snapshot_rejected"] = false }
                    catch { report["stale_snapshot_rejected"] = true }
                }
            } catch {
                report["error"] = String(describing: error)
                report["description"] = error.localizedDescription
            }
            let url = URL(fileURLWithPath: "/private/tmp/hush-notes-editor-check.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
#endif

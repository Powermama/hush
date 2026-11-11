#if DEBUG
import AppKit

/// Explicit local development checks using Hush's normal permission identity.
/// No messages, files or accounts are changed. Browser tests leave their new tab open.
@MainActor
enum CoworkerBrowserDebugCheck {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--inspect-browser") || args.contains("--test-browser-controls") || args.contains("--test-browser-agent") else { return false }
        Task { @MainActor in
            var report: [String: Any] = ["accessibility": AXIsProcessTrusted()]
            let started = ContinuousClock.now
            do {
                guard AXIsProcessTrusted(), let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
                    throw CoworkerError.missingContext
                }
                let app = AXUIElementCreateApplication(safari.processIdentifier)
                guard let window = CoworkerAX.element(kAXFocusedWindowAttribute, app) else { throw CoworkerError.missingContext }
                let state = CoworkerBrowserState.read(window)
                report["tabs_before"] = state.tabCount
                report["page_found"] = state.page != nil
                report["document_ready"] = state.documentReady
                report["document_loaded"] = state.loaded
                let observed = CoworkerContext.capture(from: safari).observation
                report["fields"] = observed.elements.filter { ["AXTextField", "AXComboBox"].contains($0.role) }.map {
                    ["role": $0.role, "subrole": $0.subrole ?? "", "label": $0.label]
                }
                if !args.contains("--inspect-browser") {
                    safari.activate()
                    try await Task.sleep(for: .milliseconds(400))
                    let goal = ProcessInfo.processInfo.environment["HUSH_BROWSER_GOAL"] ?? "Open a new tab, go to https://www.youtube.com/, search for David Guetta and open the first music video."
                    if args.contains("--test-browser-agent") {
                        CoworkerDiagnostics.shared.enabled = true
                        let controller = AssistantCompanionController(voiceEnabled: false)
                        defer { controller.dismiss() }
                        guard let turn = controller.beginListening(from: safari) else { throw CoworkerError.missingContext }
                        report["turn_id"] = turn.uuidString
                        controller.receiveTranscript(goal, sessionID: turn)
                        for _ in 0..<1200 {
                            try await Task.sleep(for: .milliseconds(200))
                            if [.ready, .stopped].contains(controller.phase) { break }
                        }
                        report["status"] = controller.status
                        report["response"] = controller.response
                        report["outcome"] = controller.history.last?.outcome
                    } else {
                        var steps: [[String: Any]] = []
                        @MainActor func perform(_ action: CoworkerReply.Action, content: String = "", target: Int = 0, context: CoworkerContext? = nil) async throws {
                            let context = context ?? CoworkerContext.capture(from: safari)
                            guard let desktop = context.desktop else { throw CoworkerError.missingContext }
                            let start = ContinuousClock.now
                            let result = try await desktop.perform(.init(message: "Development check", action: action,
                                content: content, target: target, start: "", minutes: 0), request: goal)
                            steps.append(["action": action.rawValue, "verified": result.canContinue,
                                          "duration": String(describing: start.duration(to: .now)), "result": result.message,
                                          "diagnostics": result.diagnostics])
                            report["steps"] = steps
                            if !result.canContinue {
                                report["context_after_unverified_action"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CoworkerContext.capture(from: safari).observation))
                            }
                            guard result.canContinue else { throw CoworkerError.changedContext }
                        }
                        try await perform(.openPage, content: "https://www.youtube.com/")
                        // Wait for actual exposed controls, not a guessed page-load delay.
                        @MainActor func searchField() async throws -> (CoworkerContext, CoworkerObservation.Element) {
                            for _ in 0..<30 {
                                let context = CoworkerContext.capture(from: safari)
                                if let field = context.observation.elements.first(where: {
                                    ["AXTextField", "AXComboBox"].contains($0.role) &&
                                        ($0.subrole == "AXSearchField" || ["search", "suche", "suchen"].contains($0.label.lowercased()))
                                }) { return (context, field) }
                                try await Task.sleep(for: .milliseconds(100))
                            }
                            throw CoworkerError.missingContext
                        }
                        let (searchContext, field) = try await searchField()
                        try await perform(.searchPage, content: "David Guetta", target: field.id, context: searchContext)
                        var result: (CoworkerContext, CoworkerObservation.Element)?
                        for _ in 0..<30 {
                            let context = CoworkerContext.capture(from: safari)
                            if let element = context.observation.elements.first(where: {
                                $0.url.flatMap(URL.init(string:))?.path == "/watch" && !$0.label.isEmpty
                            }) { result = (context, element) }
                            if result != nil { break }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        guard let result, let url = result.1.url else { throw CoworkerError.missingContext }
                        try await perform(.navigate, content: url, target: result.1.id, context: result.0)
                    }
                    if let current = CoworkerAX.element(kAXFocusedWindowAttribute, app) {
                        let after = CoworkerBrowserState.read(current)
                        report["tabs_after"] = after.tabCount
                        report["final_page_url"] = after.url?.absoluteString
                        report["video_page_verified"] = ["youtube.com", "www.youtube.com"].contains(after.url?.host ?? "") && after.url?.path == "/watch"
                        let finalContext = CoworkerContext.capture(from: safari).observation
                        report["final_window_title"] = finalContext.window
                        report["player_pause_controls"] = finalContext.elements.filter {
                            $0.role == "AXButton" && $0.label.lowercased().hasPrefix("pause")
                        }.map(\.label)
                    }
                }
            } catch { report["error"] = String(describing: error); report["description"] = error.localizedDescription }
            report["duration"] = String(describing: started.duration(to: .now))
            let path = ProcessInfo.processInfo.environment["HUSH_BROWSER_PROBE_PATH"] ?? "/private/tmp/hush-browser-check.json"
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
#endif

#if DEBUG
import Foundation
import Testing
@testable import Hush

/// Small, synthetic navigation regression set. No UI actions or microphone input.
@Suite("Native navigation decisions", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_NAVIGATION_EVAL"] == "1"))
@MainActor
struct CoworkerNavigationEvaluation {
    @Test("Named sites, supplied URLs, unknown destinations and observed results")
    func navigation() async throws {
        struct Case {
            let id: String
            let request: String
            let host: String?
            var more = false
            var target = 0
            var elements: [CoworkerObservation.Element] = []
        }
        // Expectations declared before running the model. These are not a
        // browser-task accuracy benchmark or a substitute for a live run.
        let cases: [Case] = [
            .init(id: "named-youtube", request: "Open YouTube, search for David Guetta, and open the first video.", host: "youtube.com", more: true),
            .init(id: "named-wikipedia", request: "Open Wikipedia.", host: "wikipedia.org"),
            .init(id: "named-apple-de", request: "Öffne die Apple Webseite.", host: "apple.com"),
            .init(id: "supplied-docs", request: "Open https://example.org/docs/", host: "example.org"),
            .init(id: "unknown", request: "Open my team's private dashboard. I have not given you its address.", host: nil),
            .init(id: "observed-result", request: "Open the first result.", host: "example.org", target: 42,
                  elements: [.init(id: 42, role: "AXLink", label: "First result", url: "https://example.org/item/42")])
        ]
        var rows: [[String: Any]] = []
        for test in cases {
            let observation = CoworkerObservation(application: "Safari", window: "Start Page", selectedText: "",
                visibleText: test.elements.isEmpty ? "Start Page. No website is loaded." : "First result is visible.",
                elements: test.elements, editable: false, limitation: nil,
                availableActions: [.answer, .newTab, .navigate, .search])
            let request = CoworkerRequest(text: test.request, observation: observation, history: [],
                now: Date(timeIntervalSince1970: 1_793_635_200), timeZone: TimeZone(secondsFromGMT: 0)!)
            let start = ContinuousClock.now
            do {
                let reply = try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b)
                let url = URL(string: reply.content)
                let host = url?.host?.lowercased().replacingOccurrences(of: "www.", with: "")
                let passed = test.host == nil
                    ? reply.action == .answer && !reply.more
                    : reply.action == .navigate && host == test.host && reply.target == test.target && reply.more == test.more
                rows.append(["id": test.id, "passed": passed, "seconds": String(describing: start.duration(to: .now)),
                             "reply": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))])
            } catch {
                rows.append(["id": test.id, "passed": false, "error": error.localizedDescription])
            }
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/private/tmp/hush-navigation-evaluation.json"), options: .atomic)
        }
        #expect(rows.count == cases.count)
        // Record honest model results, including failures; do not rewrite expectations.
        let passedCount = rows.filter { $0["passed"] as? Bool == true }.count
        print("[navigation-evaluation] \(passedCount)/\(rows.count)")
    }
}
#endif

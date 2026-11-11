#if DEBUG
import Foundation
import Testing
@testable import Hush

/// Paired decision evaluation, not a desktop success-rate benchmark. All data is synthetic.
@Suite("Sequence contract A/B", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_SEQUENCE_AB"] == "1"))
@MainActor
struct CoworkerSequenceEvaluation {
    struct Case {
        let id: String
        let split: String
        let request: CoworkerRequest
        let actions: [CoworkerReply.Action]
        var target: Int? = nil
        var content: String? = nil
        var more = false
        var question = false
        var subject = false
    }
    struct Result: Codable {
        let id: String
        let split: String
        let variant: String
        let seconds: Double
        let passed: Bool
        let failures: [String]
        let reply: CoworkerReply?
        let error: String?
    }

    @Test("Frozen baseline and standard action contract on identical synthetic task states")
    func pairedDecisions() async throws {
        let cases = Self.cases()
        #expect(cases.count == 36)
        // Warm once separately; do not bury initial model preparation inside steady-state latency.
        let coldStart = ContinuousClock.now
        _ = try await LLMRuntime.shared.generateCoworkerReply(cases[0].request, provider: .qwen35_4b)
        let preparation = coldStart.duration(to: .now)
        var results: [Result] = []
        for (index, test) in cases.enumerated() {
            for variant in (index.isMultiple(of: 2) ? ["baseline", "standard"] : ["standard", "baseline"]) {
                var request = test.request
                if variant == "baseline" {
                    request.evaluationInstructions = request.observation.mailDraft == nil
                        ? CoworkerSequenceBaseline.instructions : CoworkerReply.instructions(for: request.observation)
                    request.evaluationSchema = CoworkerSequenceBaseline.schema
                }
                let start = ContinuousClock.now
                var reply: CoworkerReply?
                var error: String?
                do { reply = try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b) }
                catch let failure { error = failure.localizedDescription }
                let duration = start.duration(to: .now).components
                var failures: [String] = []
                if let reply {
                    if !test.actions.contains(reply.action) { failures.append("action") }
                    if let target = test.target, reply.target != target { failures.append("target") }
                    if let content = test.content, !reply.content.localizedCaseInsensitiveContains(content) { failures.append("arguments") }
                    if reply.more != test.more { failures.append("continuation") }
                    if test.question && !reply.message.contains("?") { failures.append("clarification") }
                    if test.subject && (reply.subject.isEmpty || reply.content.contains("Subject:")) { failures.append("document_fields") }
                    if let allowed = request.observation.availableActions, !allowed.contains(reply.action) { failures.append("unavailable_action") }
                } else { failures.append("generation") }
                results.append(.init(id: test.id, split: test.split, variant: variant,
                    seconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                    passed: failures.isEmpty, failures: failures, reply: reply, error: error))
                // Preserve partial results if a later evaluation is interrupted.
                try Self.save(results, preparation: String(describing: preparation))
            }
        }
        #expect(results.count == 72)
        // This is measurement, not a requirement that a particular model must win.
        for split in ["development", "held_out", "fresh_holdout"] {
            for variant in ["baseline", "standard"] {
                let rows = results.filter { $0.split == split && $0.variant == variant }
                print("[sequence-ab] \(split) \(variant): \(rows.filter(\.passed).count)/\(rows.count)")
            }
        }
    }

    private static func save(_ results: [Result], preparation: String) throws {
        struct Report: Encodable {
            let format = 1
            let model = "installed Qwen3.5-4B 4-bit; native MLXVLM; temperature 0; thinking disabled"
            let scope = "Paired synthetic AX next-decision test. No live desktop actions, microphone, or images. Not end-to-end task accuracy. One sample per case/variant."
            let preparation: String
            let results: [Result]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(preparation: preparation, results: results))
            .write(to: URL(fileURLWithPath: "/private/tmp/hush-sequence-ab-report.json"), options: .atomic)
    }

    static func cases() -> [Case] {
        let now = ISO8601DateFormatter().date(from: "2026-11-01T10:00:00-03:00")!
        let zone = TimeZone(identifier: "America/Asuncion")!
        func observation(_ text: String, elements: [CoworkerObservation.Element] = [], actions: [CoworkerReply.Action], app: String = "Safari") -> CoworkerObservation {
            .init(application: app, window: "Task window", selectedText: "", visibleText: text, elements: elements,
                  editable: actions.contains(.write), limitation: "Synthetic accessibility fixture", availableActions: actions)
        }
        func request(_ goal: String, _ observation: CoworkerObservation, _ steps: [CoworkerProgress.Checkpoint] = []) -> CoworkerRequest {
            .init(text: goal, observation: observation, history: [], now: now, timeZone: zone, checkpoints: steps)
        }
        func field(_ id: Int, _ value: String = "", label: String = "Search") -> CoworkerObservation.Element {
            .init(id: id, role: "AXTextField", label: label, url: nil, value: value)
        }
        func button(_ id: Int, _ label: String) -> CoworkerObservation.Element { .init(id: id, role: "AXButton", label: label, url: nil) }
        func checkpoint(_ action: CoworkerReply.Action, _ result: String) -> CoworkerProgress.Checkpoint { .init(action: action, result: result) }
        let browser: [CoworkerReply.Action] = [.answer, .diagram, .search, .newTab, .navigate]
        var all: [Case] = []
        func browse(_ prefix: String, split: String, site: String, query: String, title: String, id: Int) {
            let goal = "Open a new tab, visit \(site), search for \(query), and open the first matching result."
            let start = observation("An unrelated page is open.", actions: browser)
            let tab = checkpoint(.newTab, "Opened one empty tab.")
            let page = checkpoint(.navigate, "The requested site \(site) is open.")
            let filled = checkpoint(.fill, "Search field now contains \(query).")
            let searched = checkpoint(.submitSearch, "Results for \(query) are visible.")
            all.append(.init(id: prefix + "-tab", split: split, request: request(goal, start), actions: [.newTab], more: true))
            all.append(.init(id: prefix + "-navigate", split: split, request: request(goal, observation("New empty tab. Address bar focused.", actions: browser), [tab]), actions: [.navigate], content: site, more: true))
            all.append(.init(id: prefix + "-fill", split: split, request: request(goal, observation("Requested site is open.", elements: [field(id)], actions: browser + [.fill]), [tab, page]), actions: [.fill], target: id, content: query, more: true))
            all.append(.init(id: prefix + "-submit", split: split, request: request(goal, observation("Search field contains \(query).", elements: [field(id + 1, query)], actions: browser + [.fill, .submitSearch]), [tab, page, filled]), actions: [.submitSearch], target: id + 1, more: true))
            let resultURL = site + "result/1"
            let results = observation("First matching result: \(title)", elements: [.init(id: id + 2, role: "AXLink", label: title, url: resultURL)], actions: browser + [.press])
            all.append(.init(id: prefix + "-result", split: split, request: request(goal, results, [tab, page, filled, searched]), actions: [.press, .navigate], target: id + 2))
        }
        browse("music", split: "development", site: "https://www.youtube.com/", query: "David Guetta", title: "David Guetta - Official Music Video", id: 31)
        all.append(.init(id: "viral", split: "development", request: request("Find David Guetta's most viral video.", observation("Search page without ranking evidence.", actions: browser)), actions: [.answer], question: true))
        // These cases are declared before seeing their outputs and are not prompt examples.
        browse("docs", split: "held_out", site: "https://docs.example.org/", query: "offline maps", title: "Offline maps guide", id: 72)
        all.append(.init(id: "settings-open", split: "held_out", request: request("Open Sound settings.", observation("System Settings", elements: [button(6, "Displays"), button(19, "Sound")], actions: [.answer, .press], app: "System Settings")), actions: [.press], target: 19))
        all.append(.init(id: "settings-sequence", split: "held_out", request: request("Open Sound and choose the Output tab.", observation("System Settings", elements: [button(19, "Sound")], actions: [.answer, .press], app: "System Settings")), actions: [.press], target: 19, more: true))
        all.append(.init(id: "settings-second", split: "held_out", request: request("Open Sound and choose the Output tab.", observation("Sound settings", elements: [button(3, "Input"), button(28, "Output")], actions: [.answer, .press], app: "System Settings"), [checkpoint(.press, "Sound settings is open.")]), actions: [.press], target: 28))
        all.append(.init(id: "stale-target", split: "held_out", request: request("Choose the Output tab.", observation("The settings window closed. No target is exposed.", actions: [.answer], app: "System Settings")), actions: [.answer]))
        all.append(.init(id: "second-result", split: "held_out", request: request("Open the second visible result.", observation("Result order: 1. Parks, 2. Museums", elements: [.init(id: 41, role: "AXLink", label: "Parks", url: "https://example.org/parks"), .init(id: 9, role: "AXLink", label: "Museums", url: "https://example.org/museums")], actions: [.answer, .press, .navigate])), actions: [.press, .navigate], target: 9))
        all.append(.init(id: "field-replace", split: "held_out", request: request("Change the search field to climate policy, but do not submit it.", observation("Search page", elements: [field(62, "old query")], actions: browser + [.fill, .submitSearch])), actions: [.fill], target: 62, content: "climate policy"))
        all.append(.init(id: "german-field", split: "held_out", request: request("Schreibe Berlin in das Suchfeld, ohne die Suche abzusenden.", observation("Suchseite", elements: [field(17, "", label: "Suche")], actions: browser + [.fill])), actions: [.fill], target: 17, content: "Berlin"))
        all.append(.init(id: "document-write", split: "held_out", request: request("Write a brief reminder that the design review starts at 14:00.", observation("Empty note body", actions: [.answer, .write], app: "Notes")), actions: [.write], content: "14:00"))
        let revision = CoworkerRequest(text: "Change the review time to 15:00. Keep the room.",
            observation: observation("Design review at 14:00 in Room B.", actions: [.answer, .write, .revise], app: "TextEdit"),
            history: [.init(request: "Write a review reminder", response: "Ready", artifact: "Design review at 14:00 in Room B.", outcome: "Inserted and verified.")], now: now, timeZone: zone)
        all.append(.init(id: "document-revise", split: "held_out", request: revision, actions: [.revise], content: "15:00"))
        var mail = observation("Blank compose window", actions: [.answer, .write, .revise], app: "Mail")
        mail.mailDraft = .init(subject: "", body: "")
        all.append(.init(id: "mail-fields", split: "held_out", request: request("Draft a brief email to Jo confirming our lunch on Tuesday at noon.", mail), actions: [.write], content: "Jo", subject: true))
        all.append(.init(id: "no-rank-evidence", split: "held_out", request: request("Open the highest-rated restaurant, but only if you can verify its rating here.", observation("Restaurant links without any ratings", elements: [.init(id: 12, role: "AXLink", label: "Cafe One", url: "https://example.org/cafe")], actions: [.answer, .press, .navigate])), actions: [.answer]))
        all.append(.init(id: "uncertain-action", split: "held_out", request: request("Submit this search once and open its first result.", observation("The field still has the query and no results are visible.", elements: [field(21, "city maps")], actions: browser + [.fill, .submitSearch]), [.init(action: .submitSearch, result: "Return was dispatched; its effect could not be verified. Do not repeat it.", verified: false)]), actions: [.answer]))
        all.append(.init(id: "already-complete", split: "held_out", request: request("Open Sound settings.", observation("Sound settings is open.", elements: [button(7, "Sound")], actions: [.answer, .press], app: "System Settings"), [checkpoint(.press, "Verified Sound settings is now open.")]), actions: [.answer]))
        // Fresh holdout declared before running the revised termination rule. Earlier
        // held_out cases now serve as regression evidence, not unseen validation.
        all.append(.init(id: "fresh-toggle", split: "fresh_holdout", request: request("Enable dark appearance.", observation("Light appearance selected", elements: [button(84, "Dark"), button(8, "Auto")], actions: [.answer, .press], app: "Appearance")), actions: [.press], target: 84))
        all.append(.init(id: "fresh-two-controls", split: "fresh_holdout", request: request("Open Keyboard settings, then open Keyboard Shortcuts.", observation("Settings home", elements: [button(13, "Keyboard")], actions: [.answer, .press], app: "System Settings")), actions: [.press], target: 13, more: true))
        all.append(.init(id: "fresh-final-control", split: "fresh_holdout", request: request("Open Keyboard settings, then open Keyboard Shortcuts.", observation("Keyboard settings", elements: [button(57, "Keyboard Shortcuts")], actions: [.answer, .press], app: "System Settings"), [checkpoint(.press, "Keyboard settings is open.")]), actions: [.press], target: 57))
        all.append(.init(id: "fresh-stop-on-unknown", split: "fresh_holdout", request: request("Open Keyboard Shortcuts.", observation("No application window or controls are readable.", actions: [.answer], app: "Your Mac")), actions: [.answer]))
        all.append(.init(id: "fresh-spanish-field", split: "fresh_holdout", request: request("Escribe Lisboa en el campo de búsqueda sin enviar la búsqueda.", observation("Buscar", elements: [field(93, "", label: "Buscar")], actions: browser + [.fill])), actions: [.fill], target: 93, content: "Lisboa"))
        all.append(.init(id: "fresh-ambiguous-field", split: "fresh_holdout", request: request("Put Dublin in the field.", observation("Two empty fields: departure and destination. The user has not specified which.", elements: [field(2, "", label: "Departure"), field(5, "", label: "Destination")], actions: [.answer, .fill])), actions: [.answer], question: true))
        all.append(.init(id: "fresh-third-result", split: "fresh_holdout", request: request("Click the third result.", observation("Results in order: Ocean, Forest, Desert", elements: [button(11, "Ocean"), button(95, "Forest"), button(4, "Desert")], actions: [.answer, .press])), actions: [.press], target: 4))
        all.append(.init(id: "fresh-search-only", split: "fresh_holdout", request: request("Submit the search already entered in the field.", observation("Search field contains train schedules.", elements: [field(38, "train schedules")], actions: browser + [.fill, .submitSearch])), actions: [.submitSearch], target: 38))
        all.append(.init(id: "fresh-unverified", split: "fresh_holdout", request: request("Click the export button once.", observation("Export button still visible. No completion is visible.", elements: [button(68, "Export")], actions: [.answer, .press], app: "Editor"), [.init(action: .press, result: "Export press dispatched, effect not verified. Do not replay.", verified: false)]), actions: [.answer]))
        all.append(.init(id: "fresh-note", split: "fresh_holdout", request: request("Write a note: collect the parcel at 16:30.", observation("Empty note", actions: [.answer, .write], app: "Notes")), actions: [.write], content: "16:30"))
        all.append(.init(id: "fresh-already-filled", split: "fresh_holdout", request: request("Set the city field to Oslo.", observation("City field now reads Oslo.", elements: [field(48, "Oslo", label: "City")], actions: [.answer, .fill]), [checkpoint(.fill, "City value is Oslo and was verified.")]), actions: [.answer]))
        all.append(.init(id: "fresh-choose-sort", split: "fresh_holdout", request: request("Open the sort menu, then choose Date.", observation("Document list", elements: [button(79, "Sort")], actions: [.answer, .press], app: "Documents")), actions: [.press], target: 79, more: true))
        return all
    }
}
#endif

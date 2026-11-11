#if DEBUG
import Foundation
import Testing
@testable import Hush

@Suite("Browser operation A/B", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_OPERATION_AB"] == "1"))
@MainActor
struct CoworkerOperationEvaluation {
    struct Result: Codable {
        let id: String
        let variant: String
        let seconds: Double
        let failures: [String]
        let preferredOperation: Bool
        let rawOutput: String?
        let reply: CoworkerReply?
        let error: String?
    }

    @Test("Paired decisions with native capabilities and a fresh holdout")
    func pairedDecisions() async throws {
        // Predeclared before observing outputs. These are regression states, not
        // a claimed unseen benchmark or a live browser task success rate.
        let ids = ["music-tab", "music-fill", "music-result", "docs-tab", "docs-fill",
                   "second-result", "field-replace", "german-field", "settings-sequence",
                   "stale-target", "no-rank-evidence", "uncertain-action"]
        let regression = CoworkerSequenceEvaluation.cases().filter { ids.contains($0.id) }
        let cases = regression + Self.holdoutCases()
        #expect(cases.count == 28)
        let start = ContinuousClock.now
        _ = try await LLMRuntime.shared.generateCoworkerReply(cases[0].request, provider: .qwen35_4b)
        let warmup = String(describing: start.duration(to: .now))
        var rows: [Result] = []
        var packets: [[String: Any]] = []
        for (index, test) in cases.enumerated() {
            let variants = ProcessInfo.processInfo.environment["HUSH_OPERATION_VARIANTS"]?.components(separatedBy: ",") ?? ["primitive", "bundled"]
            for offset in 0..<variants.count {
                let variant = variants[(index + offset) % variants.count]
                var observation = test.request.observation
                // Match native capability routing, omitted in v1/v2 fixtures.
                if observation.elements.contains(where: { $0.role == "AXTextField" && ["Search", "Suche"].contains($0.label) }) {
                    observation.availableActions?.removeAll { $0 == .search }
                }
                for checkpoint in test.request.checkpoints {
                    if checkpoint.result.hasPrefix("The requested site ") {
                        observation.pageURL = checkpoint.result.components(separatedBy: " ")[3]
                    }
                }
                let actions = observation.availableActions ?? []
                if variant != "primitive" {
                    if actions.contains(.navigate) { observation.availableActions?.append(.openPage) }
                    if actions.contains(.fill), observation.elements.contains(where: { ["Search", "Suche"].contains($0.label) }) {
                        observation.availableActions?.append(.searchPage)
                    }
                }
                var request = CoworkerRequest(text: test.request.text, observation: observation,
                    history: test.request.history, now: test.request.now, timeZone: test.request.timeZone,
                    checkpoints: test.request.checkpoints)
                request.evaluationInstructions = variant == "primitive"
                    ? CoworkerOperationBaseline.instructions
                    : CoworkerReply.operationInstructions(for: observation)
                request.evaluationThinking = variant == "thinking"
                let trace = CoworkerTrace(id: UUID(), root: URL(fileURLWithPath: "/private/tmp/hush-operation-native-traces"))
                request.diagnosticTrace = trace
                var expected = test.actions
                var validActions = test.actions
                if variant != "primitive" {
                    if test.id.hasSuffix("-tab") { expected = [.openPage]; validActions += [.openPage] }
                    if test.id.hasSuffix("-fill") { expected = [.searchPage]; validActions += [.searchPage] }
                }
                let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let supplied = detector.matches(in: request.text, range: NSRange(request.text.startIndex..., in: request.text)).compactMap { $0.url?.absoluteString }
                var packet: [String: Any] = ["id": test.id, "variant": variant,
                    "instructions": request.evaluationInstructions ?? CoworkerReply.instructions(for: observation),
                    "prompt": request.prompt, "schema": CoworkerReply.schema(for: request),
                    "actions": expected.map(\.rawValue), "valid_actions": validActions.map(\.rawValue), "more": test.more,
                    "urls": supplied + observation.elements.compactMap(\.url)]
                packet["target"] = test.target
                packet["content"] = test.content
                packets.append(packet)
                try JSONSerialization.data(withJSONObject: packets, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: "/private/tmp/hush-operation-fixtures.json"), options: .atomic)
                let start = ContinuousClock.now
                var reply: CoworkerReply?
                var error: String?
                do { reply = try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b) }
                catch let failure { error = String(describing: failure) }
                let duration = start.duration(to: .now).components
                trace.finish(error ?? "generated"); await trace.flush()
                let raw = try? String(contentsOf: trace.directory.appendingPathComponent("model-output.txt"), encoding: .utf8)
                var failures: [String] = []
                if let reply {
                    if !validActions.contains(reply.action) { failures.append("action") }
                    if let target = test.target, reply.target != target { failures.append("target") }
                    if let content = test.content, !reply.content.localizedCaseInsensitiveContains(content) { failures.append("arguments") }
                    if reply.more != test.more { failures.append("continuation") }
                    if let allowed = observation.availableActions, !allowed.contains(reply.action) { failures.append("capability") }
                    if [.navigate, .openPage].contains(reply.action),
                       (try? CoworkerLinkPolicy.resolve(reply, request: request.text, observation: observation)) == nil { failures.append("url_grounding") }
                } else { failures.append("generation") }
                rows.append(.init(id: test.id, variant: variant,
                    seconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                    failures: failures, preferredOperation: reply.map { expected.contains($0.action) } ?? false,
                    rawOutput: raw, reply: reply, error: error))
                try save(rows, warmup: warmup)
            }
        }
        #expect(!rows.isEmpty)
        for variant in ["primitive", "bundled", "thinking"] {
            let group = rows.filter { $0.variant == variant }
            print("[operation-ab] \(variant): \(group.filter { $0.failures.isEmpty }.count)/\(group.count)")
        }
    }

    private func save(_ rows: [Result], warmup: String) throws {
        struct Report: Encodable {
            let model = "Installed Qwen3.5-4B Q4, MLX Swift, temperature 0, top_p 1; 1536 direct / 2048 thinking total tokens"
            let scope = "12 corrected regression states plus 16 new holdout states declared before outputs; one sample per variant, rotated order. Valid next action and preferred combined operation are separate. Native capability routing. No desktop actions or screenshots. Not end-to-end accuracy. Thinking disabled by default. Latency includes prefill and grammar preparation; truncation is failure."
            let warmup: String
            let results: [Result]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(warmup: warmup, results: rows)).write(
            to: URL(fileURLWithPath: "/private/tmp/hush-operation-ab.json"), options: .atomic)
    }

    /// Declared before evaluating any model outputs for these cases. They test
    /// generic control semantics, not workflows hard-coded into production.
    static func holdoutCases() -> [CoworkerSequenceEvaluation.Case] {
        typealias Case = CoworkerSequenceEvaluation.Case
        let now = Date(timeIntervalSince1970: 1_793_625_600)
        func make(_ id: String, _ goal: String, _ context: String,
                  _ elements: [CoworkerObservation.Element], _ available: [CoworkerReply.Action],
                  _ expected: [CoworkerReply.Action], target: Int? = nil, content: String? = nil,
                  more: Bool = false, checkpoints: [CoworkerProgress.Checkpoint] = []) -> Case {
            let obs = CoworkerObservation(application: "Test application", window: "Task window", selectedText: "",
                visibleText: context, elements: elements, editable: false, limitation: "Synthetic holdout",
                availableActions: available)
            return .init(id: "holdout-" + id, split: "fresh_holdout",
                request: .init(text: goal, observation: obs, history: [], now: now, timeZone: TimeZone(secondsFromGMT: 0)!, checkpoints: checkpoints),
                actions: expected, target: target, content: content, more: more)
        }
        func button(_ id: Int, _ label: String) -> CoworkerObservation.Element { .init(id: id, role: "AXButton", label: label, url: nil) }
        func field(_ id: Int, _ label: String, _ value: String) -> CoworkerObservation.Element { .init(id: id, role: "AXTextField", label: label, url: nil, value: value) }
        return [
            make("missing-price", "Open the cheapest offer only if its price is visible.", "Two offers with no prices.", [button(31, "Offer A"), button(82, "Offer B")], [.answer, .press], [.answer]),
            make("known-price", "Open the cheaper offer.", "Offer A costs $12. Offer B costs $8.", [button(31, "Offer A"), button(82, "Offer B")], [.answer, .press], [.press], target: 82),
            make("missing-date", "Open the most recently published report only if its publication date is shown.", "Reports have titles but no publication dates.", [button(7, "Report North"), button(53, "Report South")], [.answer, .press], [.answer]),
            make("known-date", "Open the more recent report.", "Report North published 2026-10-01. Report South published 2026-10-20.", [button(7, "Report North"), button(53, "Report South")], [.answer, .press], [.press], target: 53),
            make("ambiguous-label", "Open Details.", "Two panels each have a Details button; neither is selected.", [button(14, "Details"), button(89, "Details")], [.answer, .press], [.answer]),
            make("clear-label", "Open Details.", "One Details button is available.", [button(14, "Details"), button(89, "Help")], [.answer, .press], [.press], target: 14),
            make("uncertain-save", "Save once, then open the details.", "Save and Details remain visible. The previous save effect is unknown.", [button(8, "Save"), button(70, "Details")], [.answer, .press], [.answer], checkpoints: [.init(action: .press, result: "Save dispatched; result unverified. Do not repeat or continue.", verified: false)]),
            make("verified-save", "Save once, then open the details.", "Save completed and Details is available.", [button(8, "Save"), button(70, "Details")], [.answer, .press], [.press], target: 70, checkpoints: [.init(action: .press, result: "Save completed and verified.")]),
            make("uncertain-field", "Set the region field to Lima once.", "The field still exposes an old value; a prior edit has an unknown result.", [field(48, "Region", "Quito")], [.answer, .fill], [.answer], checkpoints: [.init(action: .fill, result: "Field edit dispatched; read-back failed. Do not repeat.", verified: false)]),
            make("fresh-field", "Set the region field to Lima without submitting.", "Region field currently contains Quito. No edit has been attempted.", [field(48, "Region", "Quito")], [.answer, .fill], [.fill], target: 48, content: "Lima"),
            make("spanish-stop", "Abre el primer resultado solo si puedes ver su valoración.", "Primer resultado sin valoración visible.", [button(12, "Resultado uno")], [.answer, .press], [.answer]),
            make("spanish-go", "Abre el primer resultado.", "Primer resultado: Museo local.", [button(12, "Museo local")], [.answer, .press], [.press], target: 12),
            make("german-stop", "Öffne die günstigste Option nur, wenn ihr Preis sichtbar ist.", "Keine Preise sichtbar.", [button(24, "Option Nord")], [.answer, .press], [.answer]),
            make("german-go", "Öffne Option Nord.", "Option Nord ist sichtbar.", [button(24, "Option Nord")], [.answer, .press], [.press], target: 24),
            make("two-steps", "Open Layout, then choose Columns.", "Layout button is visible; Columns belongs to the next panel.", [button(66, "Layout")], [.answer, .press], [.press], target: 66, more: true),
            make("last-step", "Open Layout, then choose Columns.", "Layout panel is open. Columns is visible.", [button(92, "Columns")], [.answer, .press], [.press], target: 92, checkpoints: [.init(action: .press, result: "Layout panel opened and verified.")])
        ]
    }
}
#endif

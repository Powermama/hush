#if DEBUG
import Foundation
import Testing
@testable import Hush

@Suite("Search continuation regression", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_SEARCH_REPLAY"] != nil))
@MainActor
struct CoworkerSearchEvaluation {
    @Test("Recorded search submission and fresh result selection retain the full goal")
    func continuation() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["HUSH_SEARCH_REPLAY"])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CoworkerReplaySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let recorded = try snapshot.input(screenshot: nil)
        let resultURL = "https://www.youtube.com/watch?v=fixture_first"
        let results = CoworkerObservation(application: "Safari", window: "Search results", selectedText: "",
            visibleText: "Search results. First music video: Martin Garrix - Animals (Official Video).", elements: [
                .init(id: 3, role: "AXComboBox", label: "Suchen", url: nil, value: "Martin Garrix", subrole: "AXSearchField"),
                .init(id: 5, role: "AXButton", label: "Search", url: nil),
                .init(id: 19, role: "AXLink", label: "Martin Garrix - Animals (Official Video)", url: resultURL)],
            editable: false, limitation: nil, pageURL: "https://www.youtube.com/results?search_query=Martin+Garrix",
            availableActions: [.answer, .navigate, .press, .fill, .submitSearch])
        var completed = recorded.checkpoints
        completed.append(.init(action: .submitSearch, result: "Search results are open and verified."))
        let fresh = CoworkerRequest(text: recorded.text, observation: results, history: [],
            now: recorded.now, timeZone: recorded.timeZone, checkpoints: completed)
        let searchOnly = CoworkerRequest(text: "Search this website for Martin Garrix.", observation: recorded.observation,
            history: [], now: recorded.now, timeZone: recorded.timeZone,
            checkpoints: [.init(action: .fill, result: "Filled the search field with Martin Garrix and checked its value.")])
        var cases = [("recorded-submit", recorded), ("fresh-result", fresh), ("search-only", searchOnly)]
        if let linkPath = ProcessInfo.processInfo.environment["HUSH_LINK_REPLAY"] {
            let linkSnapshot = try decoder.decode(CoworkerReplaySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: linkPath)))
            cases.append(("recorded-link", try linkSnapshot.input(screenshot: nil)))
        }
        var rows: [[String: Any]] = []
        for (id, input) in cases {
            let start = ContinuousClock.now
            let reply = try await LLMRuntime.shared.generateCoworkerReply(input, provider: .qwen35_4b)
            let passed: Bool
            switch id {
            case "recorded-submit": passed = reply.action == .submitSearch && reply.target == 3 && reply.more
            case "fresh-result":
                // navigate(target:0, exactURL) is a supported direct destination.
                // Judge the actual executor contract, not a redundant copied id.
                let destination = try? CoworkerLinkPolicy.resolve(reply, request: input.text, observation: input.observation)
                passed = !reply.more && ((reply.action == .press && reply.target == 19) ||
                    (reply.action == .navigate && destination?.absoluteString == resultURL))
            case "recorded-link":
                let expected = input.observation.elements.first { $0.id == 26 }?.url
                let destination = try? CoworkerLinkPolicy.resolve(reply, request: input.text, observation: input.observation)
                passed = !reply.more && reply.target == 26 && ((reply.action == .press) ||
                    (reply.action == .navigate && destination?.absoluteString == expected))
            default: passed = reply.action == .submitSearch && reply.target == 3 && !reply.more
            }
            rows.append(["id": id, "passed": passed, "seconds": String(describing: start.duration(to: .now)),
                         "reply": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))])
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/private/tmp/hush-search-evaluation.json"), options: .atomic)
        }
        #expect(rows.allSatisfy { $0["passed"] as? Bool == true })
    }
}
#endif

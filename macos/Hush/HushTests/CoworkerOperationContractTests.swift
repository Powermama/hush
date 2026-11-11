import Foundation
import Testing
@testable import Hush

@Suite("Coworker operation contract", .serialized)
@MainActor
struct CoworkerOperationContractTests {
    @Test("Every adapter is blocked from resuming after an uncertain action")
    func admissionAfterUncertainResult() throws {
        let observation = CoworkerObservation(application: "Test", window: "", selectedText: "", visibleText: "",
            elements: [], editable: false, limitation: nil)
        let reply = CoworkerReply(message: "Next", action: .press, content: "", target: 3, start: "", minutes: 0)
        var stopped = CoworkerProgress(goal: "Save and open Details", conversation: [])
        stopped.record(.press, result: "Save dispatched, effect unknown", verified: false)
        #expect(throws: CoworkerProgressError.self) { try stopped.admit(reply, observation: observation) }
        var ready = CoworkerProgress(goal: "Save and open Details", conversation: [])
        ready.record(.press, result: "Save verified")
        try ready.admit(reply, observation: observation)
    }

    @Test("Model input uses readable URLs while retaining valid JSON")
    func promptURLSerialization() throws {
        let url = "https://example.org/search?q=hello%20world"
        let observation = CoworkerObservation(application: "Browser", window: "", selectedText: "", visibleText: "",
            elements: [.init(id: 7, role: "AXLink", label: "Result", url: url)], editable: false, limitation: nil)
        let request = CoworkerRequest(text: "Open " + url, observation: observation, history: [], now: Date(), timeZone: .current)
        #expect(request.prompt.contains(url))
        #expect(!request.prompt.contains(#"\/"#))
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(request.prompt.utf8)) as? [String: Any])
        #expect(decoded["request"] as? String == request.text)
    }

    @Test("Bundled operations require arguments and accept direct destinations")
    func bundledContracts() throws {
        let observation = CoworkerObservation(application: "Safari", window: "", selectedText: "", visibleText: "",
            elements: [], editable: false, limitation: nil)
        for action in [CoworkerReply.Action.openPage, .searchPage] {
            let empty = CoworkerReply(message: "Next", action: action, content: "", target: 0, start: "", minutes: 0)
            let json = String(decoding: try JSONEncoder().encode(empty), as: UTF8.self)
            #expect(throws: CoworkerError.self) { try CoworkerReply.decode(json) }
        }
        let reply = CoworkerReply(message: "Next", action: .openPage, content: "https://example.org/", target: 0, start: "", minutes: 0)
        #expect(try CoworkerLinkPolicy.resolve(reply, request: "Open Example in a new tab", observation: observation).host == "example.org")
        #expect(try CoworkerLinkPolicy.resolve(reply, request: "Open https://example.org/ in a new tab", observation: observation).host == "example.org")
    }

    #if DEBUG
    @Test("Unqualified operation prompt does not replace the installed default")
    func operationExperimentIsOptIn() {
        guard !CoworkerReply.bundledBrowserOperationsEnabled else { return }
        let observation = CoworkerObservation(application: "Safari", window: "", selectedText: "", visibleText: "",
            elements: [], editable: false, limitation: nil, availableActions: [.answer, .newTab, .navigate])
        #expect(CoworkerReply.instructions(for: observation) == CoworkerReply.instructions)
        let request = CoworkerRequest(text: "Open a new tab", observation: observation, history: [], now: Date(), timeZone: .current)
        #expect(!CoworkerReply.schema(for: request).contains("openPage"))
        #expect(!CoworkerReply.schema(for: request).contains("searchPage"))
    }

    @Test("Thinking output cannot dispatch before a complete validated final object")
    func thinkingBoundary() throws {
        let reply = CoworkerReply(message: "Which result?", action: .answer, content: "", target: 0, start: "", minutes: 0)
        let json = String(decoding: try JSONEncoder().encode(reply), as: UTF8.self)
        #expect(try CoworkerThinkingEvaluation.finalResponse("intermediate content</think>\n" + json) == json)
        #expect(throws: CoworkerError.self) { try CoworkerThinkingEvaluation.finalResponse(json) }
        #expect(throws: CoworkerError.self) { try CoworkerThinkingEvaluation.finalResponse("</think>{\"action\":\"press\"}") }
    }
    #endif

    @Test("Direct destinations do not require observed links; referenced links remain bound")
    func directNavigation() throws {
        let observation = CoworkerObservation(application: "Safari", window: "", selectedText: "", visibleText: "",
            elements: [.init(id: 7, role: "AXLink", label: "Result", url: "https://example.org/item/42")],
            editable: false, limitation: nil)
        func reply(_ url: String, target: Int = 0) -> CoworkerReply {
            .init(message: "Opening", action: .navigate, content: url, target: target, start: "", minutes: 0)
        }
        for url in ["https://www.youtube.com/", "https://en.wikipedia.org/", "https://www.apple.com/mac/"] {
            #expect(try CoworkerLinkPolicy.resolve(reply(url), request: "Open the requested website", observation: observation).absoluteString == url)
        }
        for url in ["javascript:alert(1)", "file:///tmp/example", "data:text/html,hello", "ftp://example.org/", "https://user:pass@example.org/", "/relative"] {
            #expect(throws: CoworkerError.self) { try CoworkerLinkPolicy.resolve(reply(url), request: "Open it", observation: observation) }
        }
        #expect(try CoworkerLinkPolicy.resolve(reply("https://example.org/item/42", target: 7), request: "Open the result", observation: observation).path == "/item/42")
        // The selected native reference owns the destination, not a redundant
        // model-authored URL. A missing reference never falls back to that URL.
        #expect(try CoworkerLinkPolicy.resolve(reply("https://example.org/item/43", target: 7), request: "Open the result", observation: observation).path == "/item/42")
        #expect(throws: CoworkerError.self) { try CoworkerLinkPolicy.resolve(reply("https://example.org/item/43", target: 9), request: "Open the result", observation: observation) }
        let referenced = reply("", target: 7)
        let decoded = try CoworkerReply.decode(String(decoding: JSONEncoder().encode(referenced), as: UTF8.self))
        #expect(try CoworkerLinkPolicy.resolve(decoded, request: "Open the result", observation: observation).path == "/item/42")
    }

    @Test("Observed links preserve every native URL parameter without model copying")
    func referencedLinkResolution() throws {
        let exact = "https://example.org/item?id=42&context=a%2Bb%3D&campaign=test#details"
        let observation = CoworkerObservation(application: "Safari", window: "", selectedText: "", visibleText: "",
            elements: [.init(id: 26, role: "AXLink", label: "First result", url: exact),
                       .init(id: 27, role: "AXLink", label: "Script", url: "javascript:alert(1)"),
                       .init(id: 28, role: "AXButton", label: "Search", url: nil)],
            editable: false, limitation: nil)
        for content in ["", "https://example.org/item?id=42", "https://wrong.example/", "javascript:alert(2)"] {
            let reply = CoworkerReply(message: "Opening", action: .navigate, content: content, target: 26, start: "", minutes: 0)
            #expect(try CoworkerLinkPolicy.resolve(reply, request: "Open the first result", observation: observation).absoluteString == exact)
        }
        for target in [27, 28, 99] {
            let reply = CoworkerReply(message: "Opening", action: .navigate, content: exact, target: target, start: "", minutes: 0)
            #expect(throws: CoworkerError.self) { try CoworkerLinkPolicy.resolve(reply, request: "Open it", observation: observation) }
        }
    }

    @Test("Search verification accepts browser metadata but requires the exact query and endpoint")
    func searchArrival() {
        func arrived(_ url: String, query: String = "David Guetta") -> Bool {
            CoworkerLinkPolicy.arrivedAtWebSearch(query: query, actual: URL(string: url)!)
        }
        #expect(arrived("https://www.google.com/search?client=safari&rls=en&q=David+Guetta&ie=UTF-8&oe=UTF-8"))
        #expect(arrived("https://google.com/search?q=David%20Guetta"))
        #expect(arrived("https://www.google.com/search?q=C%2B%2B+Gr%C3%BC%C3%9Fe", query: "C++ Grüße"))
        for url in ["https://www.google.com/search?q=Wrong", "https://www.google.com/search?q=David+Guetta&q=Wrong",
                    "https://www.google.com/search?client=David+Guetta", "https://www.google.com/?q=David+Guetta",
                    "https://www.google.com.evil.example/search?q=David+Guetta", "http://www.google.com/search?q=David+Guetta",
                    "https://user:pass@www.google.com/search?q=David+Guetta", "https://www.google.com:444/search?q=David+Guetta"] {
            #expect(!arrived(url))
        }
        #expect(!arrived("https://www.google.com/search?q=C+++Gr%C3%BC%C3%9Fe", query: "C++ Grüße"))
        #expect(!CoworkerLinkPolicy.arrived(at: URL(string: "https://example.org/watch?v=1")!,
                                          actual: URL(string: "https://example.org/watch?v=2")!))
    }

    @Test("A new SPA URL with the old content never verifies; fresh content must settle")
    func pageTransition() {
        var gate = CoworkerPageReadiness(previous: ["old result"])
        func observe(_ content: [String], at elapsed: Duration, ready: Bool = true, matches: Bool = true) -> Bool {
            gate.observe(documentReady: ready, urlMatches: matches, content: content, elapsed: elapsed, requiresContentChange: true)
        }
        #expect(!observe(["old result"], at: .seconds(1)))
        #expect(!observe(["old result"], at: .seconds(8)))
        #expect(!observe(["new result"], at: .seconds(9)))
        #expect(observe(["new result"], at: .milliseconds(9400)))
        #expect(!observe([], at: .seconds(10)))
        #expect(!observe(["new result"], at: .seconds(11), ready: false))
        #expect(!observe(["new result"], at: .seconds(12), matches: false))
        // A transient content change cannot certify the page that replaces it.
        #expect(!observe(["transient"], at: .seconds(13)))
        #expect(!observe(["new result"], at: .seconds(14)))
        #expect(observe(["new result"], at: .milliseconds(14400)))
    }

    @Test("Site search verification is shared by Return and search-button activation")
    func siteSearchArrival() {
        let home = URL(string: "https://example.org/")!
        func arrived(_ value: String, query: String = "Martin Garrix") -> Bool {
            CoworkerSiteSearch.arrived(from: home, query: query, at: URL(string: value)!)
        }
        #expect(arrived("https://example.org/results?search_query=Martin+Garrix"))
        #expect(arrived("https://example.org/find?q=C%2B%2B", query: "C++"))
        for value in ["https://other.example/results?q=Martin+Garrix", "https://example.org/results?q=Wrong",
                      "https://example.org/results?q=Martin+Garrix&q=Wrong", "https://example.org/#Martin%20Garrix",
                      "http://example.org/results?q=Martin+Garrix", "https://user:pass@example.org/results?q=Martin+Garrix"] {
            #expect(!arrived(value))
        }
        let same = URL(string: "https://example.org/results?q=Martin+Garrix")!
        #expect(!CoworkerSiteSearch.arrived(from: same, query: "Martin Garrix", at: same))
        #expect(CoworkerSiteSearch.isSubmitButton(role: "AXButton", label: "Search"))
        #expect(CoworkerSiteSearch.isSubmitButton(role: "AXButton", label: "Suchen"))
        #expect(!CoworkerSiteSearch.isSubmitButton(role: "AXButton", label: "Search by voice"))
        #expect(!CoworkerSiteSearch.isSubmitButton(role: "AXTextField", label: "Search"))
    }

}

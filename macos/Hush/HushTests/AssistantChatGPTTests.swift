import Foundation
import Testing
@testable import Hush

/// The Assistant on a ChatGPT plan: its own consent, honest fallbacks and the request it sends.
@Suite("Assistant with a ChatGPT plan", .serialized)
@MainActor
struct AssistantChatGPTTests {
    /// Runs with throwaway defaults and an account that never touches the Keychain or network.
    private func isolated(_ body: (ChatGPTAccount) throws -> Void) rethrows {
        let suite = "hush.tests.assistant.chatgpt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let account = ChatGPTAccount(
            connection: ChatGPTConnection(store: ChatGPTCredentialStore(service: "com.decentralfreedom.hush.tests.\(UUID().uuidString)")),
            defaults: defaults, loads: false)
        let (previousDefaults, previousAccount) = (CoworkerModelSettings.defaults, CoworkerModelSettings.account)
        CoworkerModelSettings.defaults = defaults
        CoworkerModelSettings.account = account
        defer {
            CoworkerModelSettings.defaults = previousDefaults
            CoworkerModelSettings.account = previousAccount
            defaults.removePersistentDomain(forName: suite)
        }
        try body(account)
    }

    @Test("Assistant offers the recommended model first and never Apple Intelligence")
    func choices() {
        #expect(CoworkerModelSettings.choices == [.qwen35_4b, .qwen35_2b, .chatGPT])
    }

    @Test("ChatGPT is used only after the Assistant's own consent")
    func needsAssistantConsent() {
        isolated { account in
            CoworkerModelSettings.select(.chatGPT)
            #expect(CoworkerModelSettings.provider != .chatGPT, "No consent yet: the model on this Mac answers")
            account.grantConsent(.liveWrite)
            #expect(CoworkerModelSettings.provider != .chatGPT, "Live Write's consent does not cover screenshots")
            account.grantConsent(.assistant)
            #expect(CoworkerModelSettings.provider == .chatGPT)
            #expect(CoworkerModelSettings.isCloud)
        }
    }

    @Test("Disconnecting withdraws consent and returns Assistant to this Mac")
    func withdraw() {
        isolated { account in
            account.grantConsent(.assistant)
            CoworkerModelSettings.select(.chatGPT)
            account.withdrawConsent()
            #expect(!account.hasConsent(.assistant))
            #expect(!account.hasConsent(.liveWrite))
            #expect([.qwen35_4b, .qwen35_2b].contains(CoworkerModelSettings.provider))
        }
    }

    @Test("A model on this Mac stays chosen next to the plan")
    func localChoiceKept() {
        isolated { _ in
            CoworkerModelSettings.select(.qwen35_2b)
            #expect(CoworkerModelSettings.provider == .qwen35_2b)
            #expect(CoworkerModelSettings.localProvider == .qwen35_2b)
        }
    }

    @Test("Without a connected plan, ChatGPT is not ready for Assistant setup")
    func readiness() {
        isolated { account in
            account.grantConsent(.assistant)
            CoworkerModelSettings.select(.chatGPT)
            #expect(!CoworkerModelSettings.isReady())
        }
    }

    @Test("A screenshot is sent inline as an image part next to the request")
    func imagePart() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let message = ChatGPTResponses.Message(role: "user", parts: [.text("What is this?"), .image(png)])
        let request = try ChatGPTResponses.request(model: "m", instructions: "i", input: [message], accessToken: "t")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(body["input"] as? [[String: Any]])
        let parts = try #require(input.first?["content"] as? [[String: Any]])
        #expect(parts.first?["type"] as? String == "input_text")
        #expect(parts.first?["text"] as? String == "What is this?")
        #expect(parts.last?["type"] as? String == "input_image")
        #expect(parts.last?["image_url"] as? String == "data:image/png;base64,\(png.base64EncodedString())")
        #expect(ChatGPTResponses.Part.mediaType(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
    }

    @Test("Text-only turns keep the plain string form")
    func textMessage() throws {
        let request = try ChatGPTResponses.request(model: "m", instructions: "i", input: [.init(role: "user", content: "Hi")], accessToken: "t")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.first?["content"] as? String == "Hi")
    }

    @Test("The reply's JSON is found inside a fence or prose")
    func jsonExtraction() {
        #expect(ChatGPTResponses.jsonObject(in: "```json\n{\"action\":\"answer\"}\n```") == "{\"action\":\"answer\"}")
        #expect(ChatGPTResponses.jsonObject(in: "Sure: {\"a\":{\"b\":1}} done") == "{\"a\":{\"b\":1}}")
        #expect(ChatGPTResponses.jsonObject(in: "no json here") == nil)
    }

    @Test("A model that rejects images is remembered, so the next turn sends text only")
    func imageRejection() {
        let account = ChatGPTAccount(connection: ChatGPTConnection(store: ChatGPTCredentialStore(service: "com.decentralfreedom.hush.tests.\(UUID().uuidString)")),
                                     defaults: UserDefaults(suiteName: "hush.tests.\(UUID().uuidString)")!, loads: false)
        #expect(account.acceptsImages("m"))
        account.rejectImages("m")
        #expect(!account.acceptsImages("m"))
        #expect(account.acceptsImages("other"))
        #expect(!account.acceptsImages(nil))
    }

    @Test("Every ChatGPT failure has a sentence the user can read")
    func errorText() {
        let errors: [ChatGPTError] = [.usageLimitReached, .notEligible(nil), .temporarilyUnavailable, .unsupported(nil),
                                      .signInRequired, .planUsageNotGranted, .cancelled, .incomplete(nil), .badResponse("x"),
                                      .keychain(-1), .network("x")]
        for error in errors { #expect(!(error.errorDescription ?? "").isEmpty) }
    }
}

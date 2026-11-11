import Testing
@testable import Hush

@Suite("Verified Message destinations")
struct VerifiedMessageDestinationPolicyTests {
    @Test("Smart mode hides proofs in Terminal without a custom exception")
    func smartModeHidesTerminal() {
        let decision = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [],
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            isSecureField: false
        )

        #expect(decision == .hidden(.terminal(applicationName: "Terminal")))
    }

    @Test("Smart mode keeps normal messaging destinations verified")
    func smartModeAllowsMessaging() {
        let decision = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [],
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            applicationName: "Slack",
            isSecureField: false
        )

        #expect(decision == .allowed)
    }

    @Test("A personal exception prevents proof publication")
    func personalExceptionHidesProof() {
        let exception = VerifiedMessageAppException(
            bundleIdentifier: "com.example.private-notes",
            displayName: "Private Notes"
        )
        let decision = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [exception],
            bundleIdentifier: exception.bundleIdentifier,
            applicationName: exception.displayName,
            isSecureField: false
        )

        #expect(decision == .hidden(.exception(applicationName: "Private Notes")))
    }

    @Test("Everywhere overrides app rules but never secure fields")
    func everywhereStillProtectsSecureFields() {
        let terminal = VerifiedMessageDestinationPolicy.decision(
            mode: .everywhere,
            exceptions: [],
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            isSecureField: false
        )
        let secure = VerifiedMessageDestinationPolicy.decision(
            mode: .everywhere,
            exceptions: [],
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            isSecureField: true
        )

        #expect(terminal == .allowed)
        #expect(secure == .hidden(.secureField))
    }

    @Test("Terminal matching is case insensitive")
    func terminalMatchingIsCaseInsensitive() {
        #expect(VerifiedMessageDestinationPolicy.isKnownTerminal("COM.APPLE.TERMINAL"))
        #expect(VerifiedMessageDestinationPolicy.isKnownTerminal("dev.warp.Warp-Stable"))
        #expect(!VerifiedMessageDestinationPolicy.isKnownTerminal("com.apple.Notes"))
    }

    @Test("A website exception hides that domain and its subdomains only")
    func websiteExceptionMatchesDomainBoundary() throws {
        let exception = try #require(VerifiedMessageWebsiteException(host: "chatgpt.com"))
        let hidden = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [],
            websiteExceptions: [exception],
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            isSecureField: false,
            websiteHost: "chat.openai.chatgpt.com"
        )
        let allowed = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [],
            websiteExceptions: [exception],
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            isSecureField: false,
            websiteHost: "x.com"
        )
        let lookalike = VerifiedMessageDestinationPolicy.decision(
            mode: .smart,
            exceptions: [],
            websiteExceptions: [exception],
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            isSecureField: false,
            websiteHost: "notchatgpt.com"
        )

        #expect(hidden == .hidden(.website(host: "chat.openai.chatgpt.com")))
        #expect(allowed == .allowed)
        #expect(lookalike == .allowed)
    }

    @Test("Browser address and search fields never publish a proof")
    func browserSearchIsAlwaysHidden() {
        let decision = VerifiedMessageDestinationPolicy.decision(
            mode: .everywhere,
            exceptions: [],
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            isSecureField: false,
            websiteHost: "x.com",
            isBrowserAddressOrSearchField: true
        )

        #expect(decision == .hidden(.browserAddressOrSearch))
    }

    @Test("Website input accepts a URL and stores a privacy-minimized host")
    func websiteExceptionNormalizesURL() throws {
        let exception = try #require(
            VerifiedMessageWebsiteException(host: "https://www.ChatGPT.com/c/share?private=1")
        )

        #expect(exception.host == "chatgpt.com")
    }
}

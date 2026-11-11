import Foundation
import Testing
@testable import Hush

@Suite("Contextual persona suggestions")
struct PersonaSuggestionRankerTests {
    @Test("Telegram prefers a casual persona")
    func telegramPrefersCasual() {
        let ranked = PersonaSuggestionRanker.ranked(
            profiles: Profile.seededProfiles,
            activeProfileID: Profile.SeedID.polish,
            applicationName: "Telegram",
            bundleIdentifier: "ru.keepcoder.Telegram",
            websiteHost: nil,
            text: "Hey, thanks for sending this over!"
        )

        #expect(ranked.first?.id == Profile.SeedID.casual)
    }

    @Test("Xcode prefers the code comment persona")
    func xcodePrefersCodeComment() {
        let ranked = PersonaSuggestionRanker.ranked(
            profiles: Profile.seededProfiles,
            activeProfileID: Profile.SeedID.polish,
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            websiteHost: nil,
            text: "func loadModel() async throws { }"
        )

        #expect(ranked.first?.id == Profile.SeedID.codeComment)
    }

    @Test("Mail prefers a business persona")
    func mailPrefersBusiness() {
        let ranked = PersonaSuggestionRanker.ranked(
            profiles: Profile.seededProfiles,
            activeProfileID: Profile.SeedID.casual,
            applicationName: "Mail",
            bundleIdentifier: "com.apple.mail",
            websiteHost: nil,
            text: "Please find the proposal attached for your review."
        )

        #expect(ranked.first?.id == Profile.SeedID.business)
    }

    @Test("Opening gives two short ideas and one contextual persona")
    func contextualOpening() {
        let detail = PersonaSuggestionRanker.openingDetail(
            applicationName: "Telegram",
            bundleIdentifier: "ru.keepcoder.Telegram",
            text: String(repeating: "A useful sentence ", count: 15),
            bestProfileName: "Casual",
            selectedProfileName: nil
        )

        #expect(detail == "I can tighten it or make it more conversational. Casual may fit best.")
    }
}

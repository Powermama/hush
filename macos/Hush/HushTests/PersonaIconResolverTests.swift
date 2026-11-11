import Foundation
import Testing
@testable import Hush

@Suite("Persona icons")
struct PersonaIconResolverTests {
    @Test("Built-in and custom personas receive automatic semantic symbols")
    func automaticSymbols() {
        #expect(PersonaIconResolver.symbol(for: Profile.seededProfiles[0]) == "sparkles")

        let translator = Profile(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            name: "Multilingual",
            systemPrompt: "Translate every message to English."
        )
        #expect(PersonaIconResolver.symbol(for: translator) == "character.book.closed.fill")
    }

    @Test("A manual icon overrides automatic inference")
    func manualOverride() {
        let profile = Profile(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            name: "Legal",
            systemPrompt: "Review contracts.",
            iconName: "paintpalette.fill"
        )
        #expect(PersonaIconResolver.symbol(for: profile) == "paintpalette.fill")
    }

    @Test("Generic custom personas always receive a valid stable fallback")
    func genericFallback() {
        let profile = Profile(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            name: "My mode",
            systemPrompt: "Keep it useful."
        )
        let symbol = PersonaIconResolver.symbol(for: profile)
        #expect(PersonaIconResolver.choices.contains(where: { $0.symbol == symbol }))
        #expect(PersonaIconResolver.symbol(for: profile) == symbol)
    }

    @Test("Profiles saved before icon customization remain in automatic mode")
    func legacyDecode() throws {
        let data = Data(#"{"id":"20000000-0000-0000-0000-000000000003","name":"Legacy","systemPrompt":"Be concise.","creativity":0.3}"#.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        #expect(profile.iconName == nil)
    }
}

import Foundation
import Testing
@testable import Hush

@Suite("Live Write settings")
@MainActor
struct LiveWriteSettingsTests {
    private func settings(_ configure: (UserDefaults) -> Void = { _ in }) -> Settings {
        let suite = "hush.tests.livewrite.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        configure(defaults)
        let settings = Settings(defaults: defaults)
        settings.migrateToLiveWrite()
        return settings
    }

    @Test("A new install starts with Live Write off and no persona")
    func newInstall() {
        let settings = settings()
        #expect(!settings.liveWriteEnabled)
        #expect(!settings.dictationPersonaEnabled)
        #expect(settings.activeDictationProfile == nil)
    }

    @Test("AI on with a persona keeps that persona, now on top of Live Write")
    func personaUserKeepsPersona() {
        let settings = settings { defaults in
            defaults.set(LLMProvider.appleIntelligence.rawValue, forKey: "postprocess.llmProvider")
            defaults.set(Profile.SeedID.business.uuidString, forKey: "postprocess.activeProfileID.v2")
        }
        #expect(settings.liveWriteEnabled)
        #expect(settings.activeDictationProfile?.id == Profile.SeedID.business)
    }

    @Test("AI on with No persona stays plain dictation: Live Write off, engine kept")
    func noPersonaUserStaysPlain() {
        let settings = settings { defaults in
            defaults.set(LLMProvider.appleIntelligence.rawValue, forKey: "postprocess.llmProvider")
            defaults.set(false, forKey: "postprocess.dictationPersona.enabled.v1")
        }
        #expect(!settings.liveWriteEnabled)
        #expect(settings.llmProvider == .appleIntelligence, "The Assistant may share the engine")
        #expect(settings.activeDictationProfile == nil)
    }

    @Test("Live Write without a persona writes with its own behaviour; a chosen persona goes on top")
    func personaIsOptional() {
        let settings = settings { defaults in
            defaults.set(LLMProvider.appleIntelligence.rawValue, forKey: "postprocess.llmProvider")
        }
        settings.liveWriteEnabled = true
        settings.dictationPersonaEnabled = false
        #expect(settings.activeDictationProfile?.id == Profile.liveWrite.id)
        #expect(settings.activeDictationProfile?.mode == .compose)
        settings.activeProfileID = Profile.SeedID.casual
        #expect(settings.activeDictationProfile?.id == Profile.SeedID.casual)
        settings.liveWriteEnabled = false
        #expect(settings.activeDictationProfile == nil)
    }

    @Test("The migration runs once and never overrides a later choice")
    func migratesOnce() {
        let settings = settings { defaults in
            defaults.set(LLMProvider.appleIntelligence.rawValue, forKey: "postprocess.llmProvider")
        }
        #expect(settings.liveWriteEnabled)
        settings.liveWriteEnabled = false
        settings.migrateToLiveWrite()
        #expect(!settings.liveWriteEnabled)
    }

    @Test("The Assistant is on unless the user turns it off")
    func assistantSwitch() {
        let settings = settings()
        #expect(settings.assistantEnabled)
        settings.assistantEnabled = false
        #expect(!settings.assistantEnabled)
    }
}

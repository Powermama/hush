import Foundation
import Testing
@testable import Hush

@Suite("Built-in personas reach existing libraries")
@MainActor
struct BuiltInPersonaMigrationTests {
    private func settings() -> (Settings, UserDefaults) {
        let suite = "hush.tests.personas.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (Settings(defaults: defaults), defaults)
    }

    @Test("A saved library gets Write for me once, and keeps it deleted")
    func addsOnce() {
        let (settings, _) = settings()
        let mine = Profile(id: UUID(), name: "Mine", systemPrompt: "Fix it.")
        settings.profiles = [mine]
        settings.addNewBuiltInPersonas()
        #expect(settings.profiles.map(\.id) == [mine.id, Profile.SeedID.writeForMe])
        #expect(settings.profiles.last?.mode == .compose)

        settings.profiles = [mine]
        settings.addNewBuiltInPersonas()
        #expect(settings.profiles.map(\.id) == [mine.id], "A persona the user deleted stays deleted")
    }

    @Test("A new library already has it from the seeded personas, without duplicates")
    func newLibrary() {
        let (settings, _) = settings()
        settings.addNewBuiltInPersonas()
        #expect(settings.profiles.filter { $0.id == Profile.SeedID.writeForMe }.count == 1)
    }
}

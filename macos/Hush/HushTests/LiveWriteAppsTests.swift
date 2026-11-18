import Foundation
import Testing
@testable import Hush

/// PRD R4: Live Write steps aside where text is a command, code, a prompt or a secret.
@Suite("Live Write apps")
@MainActor
struct LiveWriteAppsTests {
    private func settings() -> Settings {
        let suite = "hush.tests.livewrite.apps.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Settings(defaults: defaults)
    }

    @Test("Terminals, editors, AI chats and password managers are off by default")
    func standardApps() {
        let apps = settings().liveWriteAppExceptions
        for identifier in ["com.apple.Terminal", "com.microsoft.VSCode", "com.openai.chat", "com.1password.1password"] {
            #expect(LiveWriteApps.isExcluded(identifier, apps: apps), "\(identifier)")
        }
        #expect(!LiveWriteApps.isExcluded("com.apple.mail", apps: apps))
        #expect(!LiveWriteApps.isExcluded(nil, apps: apps))
        #expect(LiveWriteApps.isExcluded("COM.APPLE.TERMINAL", apps: apps), "bundle identifiers ignore case")
    }

    @Test("AI chat websites are off by default, subdomains included")
    func standardWebsites() {
        let websites = settings().liveWriteWebsiteExceptions
        #expect(LiveWriteApps.isExcluded("com.apple.Safari", websiteHost: "chatgpt.com", apps: [], websites: websites))
        #expect(LiveWriteApps.isExcluded("com.apple.Safari", websiteHost: "www.claude.ai", apps: [], websites: websites))
        #expect(!LiveWriteApps.isExcluded("com.apple.Safari", websiteHost: "mail.google.com", apps: [], websites: websites))
    }

    @Test("The user changes both lists and can reset them to the standard")
    func editAndReset() {
        let settings = settings()
        settings.liveWriteAppExceptions.removeAll { $0.bundleIdentifier == "com.openai.chat" }
        settings.liveWriteAppExceptions += [LiveWriteAppException(bundleIdentifier: "com.apple.mail", displayName: "Mail")]
        settings.liveWriteWebsiteExceptions = [VerifiedMessageWebsiteException(host: "https://docs.example.com/page")!]
        #expect(!LiveWriteApps.isExcluded("com.openai.chat", apps: settings.liveWriteAppExceptions))
        #expect(LiveWriteApps.isExcluded("com.apple.mail", apps: settings.liveWriteAppExceptions))
        #expect(settings.liveWriteWebsiteExceptions.map(\.host) == ["docs.example.com"])
        settings.resetLiveWriteAppExceptions()
        #expect(LiveWriteApps.isExcluded("com.openai.chat", apps: settings.liveWriteAppExceptions))
        #expect(!LiveWriteApps.isExcluded("com.apple.mail", apps: settings.liveWriteAppExceptions))
        #expect(settings.liveWriteWebsiteExceptions == LiveWriteApps.standardWebsites)
    }

    @Test("Duplicates collapse and the list is sorted by name")
    func normalized() {
        let settings = settings()
        settings.liveWriteAppExceptions = [
            LiveWriteAppException(bundleIdentifier: "b.app", displayName: "Beta"),
            LiveWriteAppException(bundleIdentifier: "A.APP", displayName: "Alpha"),
            LiveWriteAppException(bundleIdentifier: "a.app", displayName: "Alpha again"),
        ]
        #expect(settings.liveWriteAppExceptions.map(\.displayName) == ["Alpha", "Beta"])
    }

    @Test("Only apps on this Mac are listed")
    func installedOnly() {
        let listed = LiveWriteApps.installed(LiveWriteApps.standard) { $0 == "com.apple.Terminal" }
        #expect(listed.map(\.displayName) == ["Terminal"])
    }
}

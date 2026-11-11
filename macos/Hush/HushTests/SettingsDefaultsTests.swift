import Testing
@testable import Hush

@Suite("Settings defaults")
struct SettingsDefaultsTests {
    @Test("Fresh installs auto-detect transcription language")
    func freshLanguageIsAutomatic() {
        #expect(Settings.defaultLanguage == "auto")
        #expect(LanguageOption.popular.first?.code == Settings.defaultLanguage)
    }
}

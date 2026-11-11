import Foundation
import Combine

struct TypingTestResult: Codable, Equatable, Identifiable {
    let id: UUID
    let completedAt: Date
    let wordsPerMinute: Double
    let accuracy: Double

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        wordsPerMinute: Double,
        accuracy: Double
    ) {
        self.id = id
        self.completedAt = completedAt
        self.wordsPerMinute = wordsPerMinute
        self.accuracy = accuracy
    }
}

struct EverydayTypingSample: Codable, Equatable, Identifiable {
    let day: Date
    let characterCount: Int
    let activeDuration: TimeInterval

    var id: Date { day }
    var wordsPerMinute: Double {
        guard activeDuration > 0 else { return 0 }
        return (Double(characterCount) / 5) / (activeDuration / 60)
    }
}

@MainActor
final class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults
    let didChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let hotkeyData = "hotkey.data.v1"
        static let composeHotkeyData = "hotkey.compose.data.v1"
        static let personaHotkeyData = "hotkey.persona.data.v1"
        static let hotkeyMode = "hotkey.mode"
        static let language = "transcription.language"
        static let modelID = "transcription.modelID"
        static let autoInsert = "behavior.autoInsert"
        static let restoreClipboard = "behavior.restoreClipboard"
        static let showHUD = "behavior.showHUD"
        static let hudPosition = "behavior.hudPosition"
        static let llmCleanupEnabled = "postprocess.llm.enabled"
        static let transcriptionQuality = "transcription.quality"
        // v2 schema: profiles no longer carry a `.raw` mode (the off-state
        // lives at `llmProvider == .off` instead). Old v1 keys are ignored
        // and the seeded v2 list is used on first read.
        static let profilesData = "postprocess.profiles.v2"
        static let activeProfileID = "postprocess.activeProfileID.v2"
        static let dictationPersonaEnabled = "postprocess.dictationPersona.enabled.v1"
        static let llmProvider = "postprocess.llmProvider"
        static let historyRetention = "activity.historyRetention"
        static let typingTestResults = "activity.typingTestResults.v1"
        static let everydayTypingMeasurementEnabled = "activity.everydayTyping.enabled.v1"
        static let everydayTypingSamples = "activity.everydayTyping.samples.v1"
        static let verifiedMessagesEnabled = "verifiedMessages.enabled.v1"
        static let verifiedMessagesAuthorName = "verifiedMessages.authorName.v1"
        static let verifiedMessagesLinkPresentation = "verifiedMessages.linkPresentation.v1"
        static let verifiedMessagesDestinationMode = "verifiedMessages.destinationMode.v1"
        static let verifiedMessagesAppExceptions = "verifiedMessages.appExceptions.v1"
        static let verifiedMessagesWebsiteExceptions = "verifiedMessages.websiteExceptions.v1"
        static let verifiedMessagesSuppressionNotices = "verifiedMessages.suppressionNotices.v1"
        static let verifiedMessagesInstallationID = "verifiedMessages.installationID.v1"
        static let verifiedMessagesInstallationFingerprint = "verifiedMessages.installationFingerprint.v1"
        static let verifiedMessagesInstallationServiceURL = "verifiedMessages.installationServiceURL.v1"
    }

    enum HotkeyMode: String {
        case pushToTalk
        case toggle
    }

    /// Where the recording HUD pill appears on screen.
    enum HUDPosition: String, Sendable {
        /// Bottom-centre of the active screen, ~40 pt above the Dock.
        case bottom
        /// Top of the screen, anchored under the Hush menu-bar icon. Useful if the
        /// user dictates into apps that have their own bottom controls (Slack, Notes).
        case top
    }

    /// How aggressively Whisper retries a chunk when its first decoding pass
    /// looks degenerate (high compression ratio, low avg logprob, etc.).
    /// Maps directly to `DecodingOptions.temperatureFallbackCount`.
    enum TranscriptionQuality: String, Sendable, CaseIterable {
        /// One greedy pass at temperature 0. Fastest. No recovery if Whisper
        /// gets stuck in a loop on noisy / Bluetooth-warmup audio.
        case fast
        /// Up to one retry at temperature 0.2 if the first pass looks bad.
        /// Default — costs ~1× extra transcribe time only when the recovery
        /// actually triggers, otherwise free.
        case balanced
        /// Up to three retries at progressively higher temperatures. More
        /// chances to escape a bad pass; pays the price (one extra full
        /// transcribe per retry) only when the audio was already going to
        /// produce garbage.
        case best

        /// Value forwarded to WhisperKit's decoder.
        var fallbackCount: Int {
            switch self {
            case .fast:     return 0
            case .balanced: return 1
            case .best:     return 3
            }
        }

        var displayName: String {
            switch self {
            case .fast:     return "Fast"
            case .balanced: return "Balanced"
            case .best:     return "Best quality"
            }
        }
    }

    enum HistoryRetention: String, Sendable, CaseIterable {
        case off
        case oneDay
        case sevenDays
        case thirtyDays
        case ninetyDays
        case forever

        var displayName: String {
            switch self {
            case .off: return "Off"
            case .oneDay: return "1 day"
            case .sevenDays: return "7 days"
            case .thirtyDays: return "30 days"
            case .ninetyDays: return "90 days"
            case .forever: return "Forever"
            }
        }

        var days: Int? {
            switch self {
            case .off: return 0
            case .oneDay: return 1
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .forever: return nil
            }
        }
    }

    enum VerifiedMessagesLinkPresentation: String, Sendable, CaseIterable {
        case automatic
        case linkedSignature
        case visibleURL

        var displayName: String {
            switch self {
            case .automatic: return "Automatic"
            case .linkedSignature: return "Linked signature"
            case .visibleURL: return "Always show URL"
            }
        }
    }

    var didCompleteOnboarding: Bool {
        get { defaults.bool(forKey: Keys.didCompleteOnboarding) }
        set { defaults.set(newValue, forKey: Keys.didCompleteOnboarding); didChange.send() }
    }

    var hotkey: KeyCombo {
        get {
            if let data = defaults.data(forKey: Keys.hotkeyData),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                return combo
            }
            return .defaultHotkey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotkeyData)
                didChange.send()
            }
        }
    }

    var composeHotkey: KeyCombo {
        get {
            if let data = defaults.data(forKey: Keys.composeHotkeyData),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                return combo
            }
            return .defaultComposeHotkey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.composeHotkeyData)
                didChange.send()
            }
        }
    }

    var personaHotkey: KeyCombo {
        get {
            if let data = defaults.data(forKey: Keys.personaHotkeyData),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                return combo
            }
            return .defaultPersonaHotkey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.personaHotkeyData)
                didChange.send()
            }
        }
    }

    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: defaults.string(forKey: Keys.hotkeyMode) ?? "") ?? .pushToTalk }
        set { defaults.set(newValue.rawValue, forKey: Keys.hotkeyMode); didChange.send() }
    }

    /// ISO 639-1 code, or "auto" for Whisper auto-detection.
    nonisolated static let defaultLanguage = "auto"

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? Self.defaultLanguage }
        set { defaults.set(newValue, forKey: Keys.language); didChange.send() }
    }

    var modelID: String {
        get {
            var raw = defaults.string(forKey: Keys.modelID) ?? ModelInfo.defaultModelID
            // Migration 1: drop legacy `openai_whisper-` prefix WhisperKit prepends itself.
            if raw.hasPrefix("openai_whisper-") {
                raw = String(raw.dropFirst("openai_whisper-".count))
            }
            // Migration 2: turbo variants on HuggingFace use an underscore (not a hyphen)
            // before "turbo" — `openai_whisper-large-v3_turbo`. Older builds stored the
            // hyphen form which the glob never matched.
            raw = raw.replacingOccurrences(of: "-turbo", with: "_turbo")
            return raw
        }
        set { defaults.set(newValue, forKey: Keys.modelID); didChange.send() }
    }

    var autoInsert: Bool {
        get { (defaults.object(forKey: Keys.autoInsert) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.autoInsert); didChange.send() }
    }

    var restoreClipboard: Bool {
        get { (defaults.object(forKey: Keys.restoreClipboard) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.restoreClipboard); didChange.send() }
    }

    var showHUD: Bool {
        get { (defaults.object(forKey: Keys.showHUD) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Keys.showHUD); didChange.send() }
    }

    var verifiedMessagesEnabled: Bool {
        get { defaults.bool(forKey: Keys.verifiedMessagesEnabled) }
        set { defaults.set(newValue, forKey: Keys.verifiedMessagesEnabled); didChange.send() }
    }

    var verifiedMessagesAuthorName: String {
        get { defaults.string(forKey: Keys.verifiedMessagesAuthorName) ?? "" }
        set {
            defaults.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.verifiedMessagesAuthorName
            )
            didChange.send()
        }
    }

    var verifiedMessagesLinkPresentation: VerifiedMessagesLinkPresentation {
        get {
            VerifiedMessagesLinkPresentation(
                rawValue: defaults.string(forKey: Keys.verifiedMessagesLinkPresentation) ?? ""
            ) ?? .automatic
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.verifiedMessagesLinkPresentation)
            didChange.send()
        }
    }

    var verifiedMessagesDestinationMode: VerifiedMessageDestinationMode {
        get {
            VerifiedMessageDestinationMode(
                rawValue: defaults.string(forKey: Keys.verifiedMessagesDestinationMode) ?? ""
            ) ?? .smart
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.verifiedMessagesDestinationMode)
            didChange.send()
        }
    }

    var verifiedMessagesAppExceptions: [VerifiedMessageAppException] {
        get {
            guard let data = defaults.data(forKey: Keys.verifiedMessagesAppExceptions),
                  let exceptions = try? JSONDecoder().decode(
                    [VerifiedMessageAppException].self,
                    from: data
                  ) else { return [] }
            return exceptions
        }
        set {
            var seen = Set<String>()
            let normalized = newValue.filter {
                seen.insert($0.bundleIdentifier.lowercased()).inserted
            }.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            if let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: Keys.verifiedMessagesAppExceptions)
                didChange.send()
            }
        }
    }

    var verifiedMessagesWebsiteExceptions: [VerifiedMessageWebsiteException] {
        get {
            guard let data = defaults.data(forKey: Keys.verifiedMessagesWebsiteExceptions),
                  let exceptions = try? JSONDecoder().decode(
                    [VerifiedMessageWebsiteException].self,
                    from: data
                  ) else { return [] }
            return exceptions
        }
        set {
            let normalized = Array(Set(newValue)).sorted { $0.host < $1.host }
            if let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: Keys.verifiedMessagesWebsiteExceptions)
                didChange.send()
            }
        }
    }

    func shouldShowVerifiedMessageSuppressionNotice(for identifier: String) -> Bool {
        var identifiers = Set(
            defaults.stringArray(forKey: Keys.verifiedMessagesSuppressionNotices) ?? []
        )
        guard identifiers.insert(identifier.lowercased()).inserted else { return false }
        defaults.set(identifiers.sorted(), forKey: Keys.verifiedMessagesSuppressionNotices)
        return true
    }

    var verifiedMessagesInstallationID: String? {
        get { defaults.string(forKey: Keys.verifiedMessagesInstallationID) }
        set { defaults.set(newValue, forKey: Keys.verifiedMessagesInstallationID) }
    }

    var verifiedMessagesInstallationFingerprint: String? {
        get { defaults.string(forKey: Keys.verifiedMessagesInstallationFingerprint) }
        set { defaults.set(newValue, forKey: Keys.verifiedMessagesInstallationFingerprint) }
    }

    var verifiedMessagesInstallationServiceURL: String? {
        get { defaults.string(forKey: Keys.verifiedMessagesInstallationServiceURL) }
        set { defaults.set(newValue, forKey: Keys.verifiedMessagesInstallationServiceURL) }
    }

    var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: defaults.string(forKey: Keys.hudPosition) ?? "") ?? .bottom }
        set { defaults.set(newValue.rawValue, forKey: Keys.hudPosition); didChange.send() }
    }

    /// Reserved for iteration 2 (LLM cleanup).
    var llmCleanupEnabled: Bool {
        get { defaults.bool(forKey: Keys.llmCleanupEnabled) }
        set { defaults.set(newValue, forKey: Keys.llmCleanupEnabled); didChange.send() }
    }

    /// Trade-off between speed and quality of Whisper's decoding. See
    /// `TranscriptionQuality` for the per-preset semantics. Default is
    /// `.balanced` — one retry on degenerate output, otherwise zero cost.
    var transcriptionQuality: TranscriptionQuality {
        get { TranscriptionQuality(rawValue: defaults.string(forKey: Keys.transcriptionQuality) ?? "")
                ?? .balanced }
        set { defaults.set(newValue.rawValue, forKey: Keys.transcriptionQuality); didChange.send() }
    }

    // MARK: - Post-processing profiles
    //
    // Persisted exactly the same way as `hotkey` above: JSON-encode the value
    // into `Data` and stash it on `UserDefaults`. First-launch users get
    // `Profile.seededProfiles`; on every subsequent launch we read whatever
    // they've edited back out. No migration plumbing needed because the
    // version suffix on the key (`postprocess.profiles.v1`) lets us bump if
    // the schema ever changes.

    var profiles: [Profile] {
        get {
            if let data = defaults.data(forKey: Keys.profilesData),
               let arr = try? JSONDecoder().decode([Profile].self, from: data),
               !arr.isEmpty {
                return arr
            }
            return Profile.seededProfiles
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.profilesData)
                didChange.send()
            }
        }
    }

    /// Style profile applied to every dictation **when `llmProvider != .off`**.
    /// Default = Polish (the safest first pick — "fix grammar, keep meaning").
    /// Inert when `llmProvider == .off`; pipeline runs `BasicPostProcessor`
    /// only, exactly as before profiles landed.
    var activeProfileID: UUID {
        get {
            if let s = defaults.string(forKey: Keys.activeProfileID),
               let id = UUID(uuidString: s) {
                return id
            }
            return Profile.defaultProfileID
        }
        set {
            defaults.set(newValue.uuidString, forKey: Keys.activeProfileID)
            defaults.set(true, forKey: Keys.dictationPersonaEnabled)
            didChange.send()
        }
    }

    /// Whether regular dictation uses the selected persona. This is separate
    /// from the provider so `No persona` can stay fast without unloading the
    /// user's on-device AI engine.
    var dictationPersonaEnabled: Bool {
        get {
            if let stored = defaults.object(forKey: Keys.dictationPersonaEnabled) as? Bool {
                return stored
            }
            return llmProvider != .off
        }
        set {
            defaults.set(newValue, forKey: Keys.dictationPersonaEnabled)
            didChange.send()
        }
    }

    var activeDictationProfile: Profile? {
        guard dictationPersonaEnabled, llmProvider != .off else { return nil }
        return activeProfile
    }

    /// Convenience: resolve the active profile against the stored array.
    /// Falls back to the default seeded profile if the `activeProfileID`
    /// references something that's been deleted.
    var activeProfile: Profile {
        let list = profiles
        return list.first(where: { $0.id == activeProfileID })
            ?? list.first(where: { $0.id == Profile.defaultProfileID })
            ?? list.first
            ?? Profile.seededProfiles[0]
    }

    /// AI backend used for post-processing. Default = `.off`: behavior is
    /// identical to the pre-profiles build (Whisper → light cleanup → paste).
    /// Switching to a non-`off` provider is the user's explicit opt-in to AI
    /// rewriting; see PRD §14.3 ("Default = Off, the most important design
    /// decision").
    var llmProvider: LLMProvider {
        get {
            let raw = defaults.string(forKey: Keys.llmProvider) ?? ""
            if raw == "qwen25_1_5b" || raw == "qwen3_1_7b" {
                return .qwen35_2b
            }
            return LLMProvider(rawValue: raw) ?? .off
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.llmProvider); didChange.send() }
    }

    var historyRetention: HistoryRetention {
        get {
            HistoryRetention(rawValue: defaults.string(forKey: Keys.historyRetention) ?? "")
                ?? .thirtyDays
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.historyRetention)
            didChange.send()
        }
    }

    var typingTestResults: [TypingTestResult] {
        guard let data = defaults.data(forKey: Keys.typingTestResults),
              let results = try? JSONDecoder().decode([TypingTestResult].self, from: data) else {
            return []
        }
        return results.sorted { $0.completedAt > $1.completedAt }
    }

    var typingWordsPerMinute: Double {
        if everydayTypingMeasurementEnabled, let everyday = everydayTypingWordsPerMinute {
            return everyday
        }
        let results = typingTestResults
        guard !results.isEmpty else { return 40 }
        return results.map(\.wordsPerMinute).reduce(0, +) / Double(results.count)
    }

    var everydayTypingMeasurementEnabled: Bool {
        get { defaults.bool(forKey: Keys.everydayTypingMeasurementEnabled) }
        set {
            guard newValue != everydayTypingMeasurementEnabled else { return }
            defaults.set(newValue, forKey: Keys.everydayTypingMeasurementEnabled)
            didChange.send()
        }
    }

    var everydayTypingSamples: [EverydayTypingSample] {
        guard let data = defaults.data(forKey: Keys.everydayTypingSamples),
              let samples = try? JSONDecoder().decode([EverydayTypingSample].self, from: data) else {
            return []
        }
        return samples.sorted { $0.day > $1.day }
    }

    var everydayTypingWordsPerMinute: Double? {
        let valid = everydayTypingSamples.filter { $0.characterCount > 0 && $0.activeDuration > 0 }
        let characters = valid.reduce(0) { $0 + $1.characterCount }
        let duration = valid.reduce(0) { $0 + $1.activeDuration }
        guard characters >= 100, duration >= 30 else { return nil }
        return (Double(characters) / 5) / (duration / 60)
    }

    func recordEverydayTyping(day: Date, characterCount: Int, activeDuration: TimeInterval) {
        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: day)
        let previous = everydayTypingSamples
        var samples = previous.filter { !calendar.isDate($0.day, inSameDayAs: normalizedDay) }
        samples.append(EverydayTypingSample(
            day: normalizedDay,
            characterCount: max(0, characterCount),
            activeDuration: max(0, activeDuration)
        ))
        samples.sort { $0.day > $1.day }
        if samples.count > 90 { samples.removeLast(samples.count - 90) }
        guard samples != previous else { return }
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: Keys.everydayTypingSamples)
            didChange.send()
        }
    }

    func recordTypingTest(wordsPerMinute: Double, accuracy: Double) {
        var results = typingTestResults
        results.insert(TypingTestResult(
            wordsPerMinute: max(0, wordsPerMinute),
            accuracy: min(max(accuracy, 0), 1)
        ), at: 0)
        if results.count > 20 {
            results.removeLast(results.count - 20)
        }
        if let data = try? JSONEncoder().encode(results) {
            defaults.set(data, forKey: Keys.typingTestResults)
            didChange.send()
        }
    }
}

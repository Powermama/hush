import Foundation
import Combine

/// Whisper model variant. Most fields are filled in from the live HuggingFace
/// catalog (`ModelCatalogService`); the only hardcoded entry is `bundled`.
///
/// `id` is the WhisperKit variant identifier — the suffix after `openai_whisper-`
/// in the HuggingFace folder name. WhisperKit prepends `openai_*` itself, so we
/// pass only the suffix. (Note: turbo uses an UNDERSCORE before `turbo`,
/// e.g. `large-v3_turbo`.)
struct ModelInfo: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let displayName: String
    /// Approximate compressed download size. `nil` while the size is unknown
    /// (e.g. before the first remote refresh has completed for a new variant).
    let approximateSizeMB: Int?
    let multilingual: Bool
    let tier: Tier
    /// Latest commit date for the model's folder in the HF repo. `nil` for the
    /// bundled model (we use the literal training-date stamp encoded in the id).
    let lastModified: Date?
    /// Hand-curated note (only set for the bundled model). HF-fetched entries
    /// leave this empty.
    let notes: String
    /// Runtime that loads this model.
    let engine: SpeechEngine
    /// ISO 639-1 codes the model can transcribe. `nil` means every Whisper language
    /// (or English only, when `multilingual` is false).
    let supportedLanguages: Set<String>?

    init(
        id: String,
        displayName: String,
        approximateSizeMB: Int?,
        multilingual: Bool,
        tier: Tier,
        lastModified: Date?,
        notes: String,
        engine: SpeechEngine = .whisperKit,
        supportedLanguages: Set<String>? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.approximateSizeMB = approximateSizeMB
        self.multilingual = multilingual
        self.tier = tier
        self.lastModified = lastModified
        self.notes = notes
        self.engine = engine
        self.supportedLanguages = supportedLanguages
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, approximateSizeMB, multilingual, tier, lastModified, notes
        case engine, supportedLanguages
    }

    /// Catalog snapshots cached by earlier builds have no `engine` or
    /// `supportedLanguages`; they are all WhisperKit models.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        approximateSizeMB = try c.decodeIfPresent(Int.self, forKey: .approximateSizeMB)
        multilingual = try c.decode(Bool.self, forKey: .multilingual)
        tier = try c.decode(Tier.self, forKey: .tier)
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified)
        notes = try c.decode(String.self, forKey: .notes)
        engine = try c.decodeIfPresent(SpeechEngine.self, forKey: .engine) ?? .whisperKit
        supportedLanguages = try c.decodeIfPresent(Set<String>.self, forKey: .supportedLanguages)
    }

    /// True when the model can transcribe `language` (ISO 639-1 or "auto").
    func supports(language: String) -> Bool {
        if language == LanguageOption.auto.code { return true }
        if let supportedLanguages { return supportedLanguages.contains(language) }
        return multilingual || language == "en"
    }

    /// Short human description of language coverage, e.g. "99 languages".
    var languageCoverage: String {
        if let supportedLanguages { return "\(supportedLanguages.count) languages" }
        return multilingual ? "99 languages" : "English only"
    }

    /// When the underlying model weights were first published. Falls back to the
    /// catalog's last-modified date for variants we do not recognise.
    var releaseDate: Date? {
        if engine == .whisperKit, let known = Self.whisperReleaseDate(for: id) { return known }
        return lastModified
    }

    enum Tier: String, Sendable, Codable {
        case tiny      // smallest / fastest / lowest accuracy
        case small     // decent balance
        case medium    // high quality, noticeable load
        case large     // max quality, heaviest
    }

    /// True if this model's files are pre-shipped inside the application bundle.
    var isBundled: Bool { Self.bundledIDs.contains(id) }

    /// A remote model is offered only after the catalog has confirmed a non-empty
    /// artifact. This prevents a stale or incomplete catalog row from presenting
    /// an action that cannot succeed.
    var isDownloadAvailable: Bool { isBundled || approximateSizeMB != nil }

    /// Models we ship inside the .app bundle. `WhisperKitTranscriber` points
    /// `modelFolder` directly at the bundle path for these — no download needed.
    ///
    /// Two-tier setup so the same source builds two flavours of the app:
    ///   • **Internal / direct** build ships `large-v3-v20240930_547MB`
    ///     (highest quality, ~547 MB).
    ///   • **Public GitHub** build ships only `base` (~139 MB) — large-v3 has
    ///     one file (TextDecoder weights) right under GitHub's 100 MB per-file
    ///     limit, so the public mirror prunes it via `sync_to_public.sh`.
    /// Both IDs are listed here; `bundledModelFolder()` falls through to nil
    /// when the on-disk folder is missing, so unused entries are harmless.
    nonisolated static let bundledIDs: Set<String> = [
        "large-v3-v20240930_547MB",
        "base"
    ]

    /// First-launch model. Picks the highest-quality variant that's *actually*
    /// present in the .app bundle, falling back through the preferences list.
    /// Lets the public build (only `base` bundled) start offline without ever
    /// touching the network, while the internal build still picks large-v3 by
    /// default — same source, no build-flag plumbing required.
    static var defaultModelID: String {
        let preference = ["large-v3-v20240930_547MB", "base"]
        for id in preference where hasPhysicalBundle(id: id) {
            return id
        }
        return preference.last!
    }

    /// Hardcoded entries for whichever bundled model(s) are *actually present*
    /// in the .app at runtime. Returned in priority order (largest first).
    /// `ModelCatalogService` prepends these to the live HuggingFace catalog so
    /// they always appear even before the first network refresh.
    static var bundledEntries: [ModelInfo] {
        var entries: [ModelInfo] = []
        if hasPhysicalBundle(id: "large-v3-v20240930_547MB") {
            entries.append(ModelInfo(
                id: "large-v3-v20240930_547MB",
                displayName: "Large v3 · compressed",
                approximateSizeMB: 547,
                multilingual: true,
                tier: .large,
                lastModified: ISO8601DateFormatter().date(from: "2024-09-30T00:00:00Z"),
                notes: "Bundled with hush - works offline."
            ))
        }
        if hasPhysicalBundle(id: "base") {
            entries.append(ModelInfo(
                id: "base",
                displayName: "Base",
                approximateSizeMB: 139,
                multilingual: true,
                tier: .small,
                lastModified: nil,
                notes: "Bundled with hush - works offline."
            ))
        }
        return entries
    }

    private static func hasPhysicalBundle(id: String) -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        let folder = resources
            .appendingPathComponent("BundledModels")
            .appendingPathComponent("openai_whisper-\(id)")
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "AudioEncoder.mlmodelc/coremldata.bin",
            "TextDecoder.mlmodelc/coremldata.bin",
            "MelSpectrogram.mlmodelc/coremldata.bin",
        ]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// Lookup helper. Searches the live catalog, which always contains `bundled`.
    @MainActor
    static func info(for id: String) -> ModelInfo? {
        ModelCatalogService.shared.models.value.first { $0.id == id }
    }
}

// MARK: - Display-name & tier inference (used by ModelCatalogService when it
// turns a HuggingFace folder name into a `ModelInfo`).

extension ModelInfo {
    /// Turn a variant id like `large-v3_turbo_954MB` into `Large v3 Turbo (954 MB)`.
    nonisolated static func deriveDisplayName(from id: String) -> String {
        var base = id

        // Pull off a trailing size annotation first ("_547MB", "_954MB", …) so
        // a `.en` token immediately before it is still detectable.
        var sizeSuffix: String?
        if let r = base.range(of: #"_\d+MB$"#, options: .regularExpression) {
            sizeSuffix = String(base[r].dropFirst())   // "547MB"
            base.removeSubrange(r)
        }

        let isEnglish = base.hasSuffix(".en")
        if isEnglish { base.removeLast(".en".count) }

        // Tokenise on '-' / '_' and Title-Case each token.
        var tokens: [String] = []
        var token = ""
        for ch in base {
            if ch == "-" || ch == "_" {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                token.append(ch)
            }
        }
        if !token.isEmpty { tokens.append(token) }

        // Argmax build stamps such as "v20240930" identify an export, not a model the
        // user would recognise; size and release month already tell variants apart.
        tokens.removeAll { $0.range(of: #"^v20\d{6}$"#, options: .regularExpression) != nil }
        let titled = tokens.map(formatToken).joined(separator: " ")
        var result = titled
        if isEnglish { result += " · English" }
        if let sz = sizeSuffix { result += " (\(sz))" }
        return result
    }

    nonisolated private static func formatToken(_ t: String) -> String {
        // "v2", "v3", "v20240930" pass through.
        if t.range(of: #"^v\d"#, options: .regularExpression) != nil { return t }
        if t == "turbo"  { return "Turbo" }
        if t == "distil" { return "Distil" }
        guard let first = t.first else { return t }
        return String(first).uppercased() + t.dropFirst()
    }

    /// A short tag shown next to the model name, when one distinguishes it.
    var tag: String? {
        if isBundled { return "Built in" }
        switch ParakeetModel(rawValue: id) {
        case .ultra?: return "Most accurate"
        case .redux?: return "Smallest"
        case nil: break
        }
        if id.contains("turbo") { return "Fast" }
        if id.hasPrefix("large-v3") { return "Max accuracy" }
        if id.hasPrefix("tiny") { return "Lightweight" }
        return nil
    }

    /// One line on what the model is for, so users choose by purpose, not by name.
    var purpose: String {
        switch ParakeetModel(rawValue: id) {
        case .ultra?: return "Best accuracy across all 25 languages."
        case .redux?: return "A third of the size. Slightly less robust in noise."
        case nil: break
        }
        if id.hasPrefix("distil") { return "Distilled Large v3. Faster, English only." }
        if id.contains("turbo") { return "Close to Large v3 accuracy at a fraction of the decoding time." }
        if id.hasPrefix("large-v3") { return "Highest Whisper accuracy. Handles accents and noise best." }
        if id.hasPrefix("large-v2") { return "Previous large generation." }
        if id.hasPrefix("medium") { return "Higher accuracy, slower to load." }
        if id.hasPrefix("small") { return "Everyday dictation at a modest size." }
        if id.hasPrefix("base") {
            return isBundled ? "Light and quick. Works offline from the first launch." : "Light and quick for short notes."
        }
        if id.hasPrefix("tiny") { return "Smallest footprint. Best for quick drafts." }
        return "Whisper speech model."
    }

    /// Original OpenAI / Hugging Face publication dates of the Whisper families.
    nonisolated static func whisperReleaseDate(for id: String) -> Date? {
        let day: String
        if id.hasPrefix("distil-whisper_distil-large-v3.5") { day = "2025-03-24" }
        else if id.hasPrefix("distil-whisper_distil-large-v3") { day = "2024-03-21" }
        else if id.hasPrefix("distil-whisper") { day = "2023-11-01" }
        else if id.contains("large-v3") && id.contains("turbo") { day = "2024-10-01" }
        else if id.hasPrefix("large-v3") { day = "2023-11-06" }
        else if id.hasPrefix("large-v2") { day = "2022-12-05" }
        else if id.hasPrefix("tiny") || id.hasPrefix("base") || id.hasPrefix("small")
                    || id.hasPrefix("medium") || id.hasPrefix("large") { day = "2022-09-21" }
        else { return nil }
        return ISO8601DateFormatter().date(from: day + "T00:00:00Z")
    }

    /// Crude tier classifier — by id prefix.
    nonisolated static func deriveTier(from id: String) -> Tier {
        if id.hasPrefix("tiny")   { return .tiny }
        if id.hasPrefix("base")   { return .small }
        if id.hasPrefix("small")  { return .small }
        if id.hasPrefix("medium") { return .medium }
        return .large
    }
}

/// Whisper supported languages, popular subset surfaced in UI. Code is ISO 639-1.
struct LanguageOption: Hashable, Sendable {
    let code: String
    let displayName: String

    static let auto = LanguageOption(code: "auto", displayName: "Auto-detect")

    static func displayName(for code: String) -> String {
        popular.first { $0.code == code }?.displayName ?? code
    }

    static let popular: [LanguageOption] = [
        .auto,
        LanguageOption(code: "ru", displayName: "Русский"),
        LanguageOption(code: "en", displayName: "English"),
        LanguageOption(code: "uk", displayName: "Українська"),
        LanguageOption(code: "es", displayName: "Español"),
        LanguageOption(code: "de", displayName: "Deutsch"),
        LanguageOption(code: "fr", displayName: "Français"),
        LanguageOption(code: "it", displayName: "Italiano"),
        LanguageOption(code: "pt", displayName: "Português"),
        LanguageOption(code: "pl", displayName: "Polski"),
        LanguageOption(code: "tr", displayName: "Türkçe"),
        LanguageOption(code: "zh", displayName: "中文"),
        LanguageOption(code: "ja", displayName: "日本語"),
        LanguageOption(code: "ko", displayName: "한국어"),
        LanguageOption(code: "ar", displayName: "العربية"),
        LanguageOption(code: "hi", displayName: "हिन्दी")
    ]
}

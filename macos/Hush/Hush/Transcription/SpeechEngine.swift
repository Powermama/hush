import Foundation

/// The on-device speech recognition runtimes Hush can run.
///
/// Every transcription model belongs to exactly one engine. The engine decides which
/// `Transcriber` implementation loads it and where its files live on disk.
enum SpeechEngine: String, Sendable, Codable, CaseIterable {
    /// OpenAI Whisper through Argmax's WhisperKit (Core ML).
    case whisperKit
    /// NVIDIA Parakeet through FluidInference's FluidAudio (Core ML, Neural Engine).
    case fluidAudio

    /// Derives the engine from a model ID. Parakeet IDs carry a `parakeet-` prefix that
    /// never collides with a WhisperKit variant name, so `Settings.modelID` stays a plain
    /// string and needs no migration.
    nonisolated static func engine(for modelID: String) -> SpeechEngine {
        modelID.hasPrefix(ParakeetModel.idPrefix) ? .fluidAudio : .whisperKit
    }

    var familyName: String {
        switch self {
        case .whisperKit: return "Whisper"
        case .fluidAudio: return "Parakeet"
        }
    }

    var runtimeName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .fluidAudio: return "FluidAudio"
        }
    }

    var tagline: String {
        switch self {
        case .whisperKit: return "Every language. Built in."
        case .fluidAudio: return "Fastest and most accurate. 25 languages."
        }
    }

    var symbolName: String {
        switch self {
        case .whisperKit: return "waveform"
        case .fluidAudio: return "bird.fill"
        }
    }
}

/// The Parakeet models Hush offers through FluidAudio.
///
/// This is a curated list rather than a scraped catalog: FluidAudio's `AsrModelVersion`
/// enum is the source of truth for what the pinned package can load, so the list only
/// changes when the package is bumped. Only the newest generation is offered.
nonisolated enum ParakeetModel: String, CaseIterable, Sendable {
    /// Moondream's post-trained Parakeet TDT v3 (September 2026). Most accurate.
    case ultra = "parakeet-ultra"
    /// Moondream's ternary re-training of v3 (September 2026). Smallest download.
    case redux = "parakeet-redux"

    static let idPrefix = "parakeet-"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultra: return "Parakeet Ultra"
        case .redux: return "Parakeet Redux"
        }
    }

    var summary: String {
        switch self {
        case .ultra: return "Most accurate. Same speed as Parakeet v3."
        case .redux: return "A third of the size, slightly less robust in noise."
        }
    }

    /// Size of the Core ML repository on Hugging Face, measured 2026-10-31.
    var approximateSizeMB: Int {
        switch self {
        case .ultra: return 603
        case .redux: return 210
        }
    }

    /// Release date of the upstream weights (moondream/parakeet-ultra and parakeet-redux).
    var releaseDate: Date {
        ISO8601DateFormatter().date(from: "2026-09-22T00:00:00Z")!
    }

    /// Hugging Face repository folder name used by FluidAudio's cache layout
    /// (`FluidAudio.Repo.folderName`). `AsrModels` resolves `<parent>/<folderName>`.
    var repositoryFolderName: String {
        switch self {
        case .ultra: return "parakeet-ultra"
        case .redux: return "parakeet-redux"
        }
    }

    /// ISO 639-1 codes of the 25 languages covered by the Parakeet TDT v3 family.
    static let supportedLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    @MainActor
    var modelInfo: ModelInfo {
        ModelInfo(
            id: id,
            displayName: displayName,
            approximateSizeMB: approximateSizeMB,
            multilingual: true,
            tier: self == .ultra ? .large : .small,
            lastModified: releaseDate,
            notes: summary,
            engine: .fluidAudio,
            supportedLanguages: Self.supportedLanguages
        )
    }
}

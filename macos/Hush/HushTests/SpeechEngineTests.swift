import Foundation
import Testing
@testable import Hush
#if canImport(FluidAudio)
import FluidAudio
#endif

@MainActor
@Suite("Speech engines and model catalog")
struct SpeechEngineTests {
    @Test("Model IDs map to the right engine")
    func engineMapping() {
        #expect(SpeechEngine.engine(for: "parakeet-ultra") == .fluidAudio)
        #expect(SpeechEngine.engine(for: "parakeet-redux") == .fluidAudio)
        #expect(SpeechEngine.engine(for: "base") == .whisperKit)
        #expect(SpeechEngine.engine(for: "large-v3-v20240930_547MB") == .whisperKit)
        #expect(SpeechEngine.engine(for: "distil-whisper_distil-large-v3") == .whisperKit)
    }

    @Test("Parakeet files live in Hush application data")
    func parakeetStorage() {
        let root = AIModelStorage.root.standardizedFileURL.path
        for model in ParakeetModel.allCases {
            let folder = ModelManager.cacheURL(for: model.id).standardizedFileURL.path
            #expect(folder.hasPrefix(AIModelStorage.fluidAudioRoot.standardizedFileURL.path + "/"))
            #expect(folder.hasPrefix(root + "/"))
            #expect(!folder.contains("/FluidAudio/Models/"))
        }
    }

    @Test("The catalog always lists the curated Parakeet models with sizes")
    func catalogPinsParakeet() {
        let ids = Set(ModelCatalogService.pinnedEntries.map(\.id))
        for model in ParakeetModel.allCases {
            #expect(ids.contains(model.id))
            #expect(model.modelInfo.isDownloadAvailable)
            #expect(model.modelInfo.engine == .fluidAudio)
        }
    }

    @Test("Catalog snapshots from earlier builds still decode as Whisper models")
    func legacyCatalogDecodes() throws {
        let legacy = #"[{"id":"small","displayName":"Small","approximateSizeMB":216,"multilingual":true,"tier":"small","notes":""}]"#
        let decoded = try JSONDecoder().decode([ModelInfo].self, from: Data(legacy.utf8))
        #expect(decoded.first?.engine == .whisperKit)
        #expect(decoded.first?.supportedLanguages == nil)
    }

    @Test("Language support follows each model's coverage")
    func languageSupport() {
        let ultra = ParakeetModel.ultra.modelInfo
        #expect(ultra.supports(language: "auto"))
        #expect(ultra.supports(language: "de"))
        #expect(ultra.supports(language: "uk"))
        #expect(!ultra.supports(language: "ja"))
        #expect(!ultra.supports(language: "zh"))
        #expect(ultra.languageCoverage == "25 languages")

        let englishOnly = ModelInfo(id: "small.en", displayName: "Small", approximateSizeMB: 216,
                                    multilingual: false, tier: .small, lastModified: nil, notes: "")
        #expect(englishOnly.supports(language: "en"))
        #expect(!englishOnly.supports(language: "de"))
        #expect(englishOnly.languageCoverage == "English only")
    }

    @Test("Whisper rows show the original release date, not the catalog upload date")
    func whisperReleaseDates() {
        let formatter = ISO8601DateFormatter()
        #expect(ModelInfo.whisperReleaseDate(for: "base") == formatter.date(from: "2022-09-21T00:00:00Z"))
        #expect(ModelInfo.whisperReleaseDate(for: "large-v3_turbo") == formatter.date(from: "2024-10-01T00:00:00Z"))
        #expect(ModelInfo.whisperReleaseDate(for: "large-v3-v20240930_547MB") == formatter.date(from: "2023-11-06T00:00:00Z"))
        #expect(ModelInfo.whisperReleaseDate(for: "unknown-model") == nil)
    }

    @Test("Whisper models are grouped by size, newest first, and filtered by language")
    func whisperGrouping() {
        func model(_ id: String, _ mb: Int, multilingual: Bool = true) -> ModelInfo {
            ModelInfo(id: id, displayName: id, approximateSizeMB: mb, multilingual: multilingual,
                      tier: .small, lastModified: nil, notes: "")
        }
        let catalog = [
            model("tiny", 75), model("base.en", 140, multilingual: false),
            model("large-v2", 2900), model("large-v3_turbo", 1600),
            model("small", 480), ParakeetModel.ultra.modelInfo,
        ]
        let sections = TranscriptionModelGrouping.sections(for: .whisperKit, in: catalog)
        #expect(sections.map(\.title) == ["Fast", "Balanced", "Most accurate"])
        #expect(sections.last?.models.map(\.id) == ["large-v3_turbo", "large-v2"])
        #expect(!sections.flatMap(\.models).contains { $0.engine == .fluidAudio })

        let english = TranscriptionModelGrouping.sections(for: .whisperKit, in: catalog, filter: .englishOnly)
        #expect(english.flatMap(\.models).map(\.id) == ["base.en"])

        let parakeet = TranscriptionModelGrouping.sections(for: .fluidAudio, in: catalog)
        #expect(parakeet.flatMap(\.models).map(\.id) == ["parakeet-ultra"])
    }

    @Test("Parakeet unsupported languages offer a switch to Whisper")
    func generalPageLanguageMessage() {
        let unsupported = GeneralSettingsPageViewController.languageSubtitle(language: "ja", modelID: "parakeet-ultra")
        #expect(unsupported.isUnsupported)
        let auto = GeneralSettingsPageViewController.languageSubtitle(language: "auto", modelID: "parakeet-ultra")
        #expect(!auto.isUnsupported)
        let whisper = GeneralSettingsPageViewController.languageSubtitle(language: "ja", modelID: "base")
        #expect(!whisper.isUnsupported)
        #expect(GeneralSettingsPageViewController.qualitySubtitle(for: .fluidAudio).contains("Parakeet"))
    }

    @Test("Models explain their purpose and what sets them apart")
    func purposeAndTags() {
        #expect(ParakeetModel.ultra.modelInfo.tag == "Most accurate")
        #expect(ParakeetModel.redux.modelInfo.tag == "Smallest")
        func whisper(_ id: String) -> ModelInfo {
            ModelInfo(id: id, displayName: id, approximateSizeMB: 600, multilingual: true,
                      tier: .large, lastModified: nil, notes: "")
        }
        #expect(whisper("large-v3-v20240930_turbo").tag == "Fast")
        #expect(whisper("large-v3").tag == "Max accuracy")
        #expect(whisper("small").tag == nil)
        #expect(whisper("distil-whisper_distil-large-v3").purpose.contains("English only"))
        #expect(!whisper("medium").purpose.isEmpty)
    }

    @Test("Whisper names hide Argmax build stamps")
    func whisperNames() {
        #expect(ModelInfo.deriveDisplayName(from: "large-v3-v20240930_626MB") == "Large v3 (626MB)")
        #expect(ModelInfo.deriveDisplayName(from: "large-v3-v20240930_turbo") == "Large v3 Turbo")
        #expect(ModelInfo.deriveDisplayName(from: "small.en") == "Small · English")
    }

    @Test("Model metadata reads as size, languages and release month")
    func metadataLine() {
        #expect(ModelPresentation.metadata(for: ParakeetModel.ultra.modelInfo) == "603 MB · 25 languages · Sep 2026")
        #expect(ModelPresentation.size(1600) == "1.6 GB")
        #expect(ModelPresentation.title("Large v3 · compressed (547 MB)") == "Large v3 · compressed")
    }

    #if canImport(FluidAudio)
    @Test("Hush's Parakeet layout matches FluidAudio's own cache contract")
    func matchesFluidAudioContract() {
        for model in ParakeetModel.allCases {
            #expect(model.repositoryFolderName == model.repository.folderName)
        }
        let required = Set(ModelManager.parakeetRequiredFiles.map { $0.components(separatedBy: "/")[0] })
        let fluidRequired = ModelNames.ASR.requiredModelsV3().union([ModelNames.ASR.vocabularyFile])
        #expect(required == fluidRequired)
    }

    @Test("Language hints use FluidAudio's script filter only for supported languages")
    func languageHints() {
        #expect(FluidAudioTranscriber.languageHint(for: "de") == .german)
        #expect(FluidAudioTranscriber.languageHint(for: "uk") == .ukrainian)
        #expect(FluidAudioTranscriber.languageHint(for: "auto") == nil)
        #expect(FluidAudioTranscriber.languageHint(for: "ja") == nil)
    }

    @Test("Each engine gets its own transcriber")
    func factoryRoutesByEngine() {
        #expect(TranscriberFactory.make(for: "parakeet-ultra") is FluidAudioTranscriber)
        #if canImport(WhisperKit)
        #expect(TranscriberFactory.make(for: "base") is WhisperKitTranscriber)
        #endif
    }
    #endif
}

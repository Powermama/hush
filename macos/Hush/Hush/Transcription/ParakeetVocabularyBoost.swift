import Foundation
import OSLog

#if canImport(FluidAudio)
import FluidAudio

/// Helps Parakeet hear the user's words (PRD R13): FluidAudio's CTC keyword spotter listens
/// for each word in the audio and corrects the transcript where it finds acoustic evidence
/// (arXiv 2406.07096). It needs a separate 97.5 MB CTC model, which the user downloads on
/// purpose and can remove; without it the learned spellings still apply.
///
/// This is `VocabularyBoostingSession`'s pipeline built from FluidAudio's public parts,
/// because the session reads its tokenizer from FluidAudio's default cache and hush keeps
/// every model in `AIModelStorage`. The parameters follow the session exactly.
actor ParakeetVocabularyBoost {
    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "VocabularyBoost")
    static let variant = CtcModelVariant.ctc110m
    /// The download, as FluidAudio documents it, for the consent dialog.
    static let downloadSize = Measurement(value: 97.5, unit: UnitInformationStorage.megabytes)

    nonisolated static var defaultDirectory: URL {
        AIModelStorage.fluidAudioRoot.appendingPathComponent(variant.repo.folderName, isDirectory: true)
    }

    nonisolated static func isInstalled(at directory: URL = defaultDirectory) -> Bool {
        CtcModels.modelsExist(at: directory)
    }

    /// FluidAudio downloads into `<parent>/<repository folder>`, so `directory` must end in
    /// the repository's folder name, as `defaultDirectory` does.
    nonisolated static func install(at directory: URL = defaultDirectory) async throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await CtcModels.download(to: directory, variant: variant)
        guard isInstalled(at: directory) else { throw TranscriberError.backendUnavailable }
    }

    nonisolated static func remove(at directory: URL = defaultDirectory) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// A personal vocabulary is small and often short ("Qwen", "hush"), the case where the
    /// default rescorer replaces ordinary words that were never said. In dictation a wrong
    /// replacement is worse than a missed one, so hush takes FluidAudio's documented
    /// short-vocabulary settings (#702, #724): no acoustic-only rescue (false positives
    /// 94 to 19 and recall 0.92 to 0.97 in its measurement), a smaller boost for short
    /// words, and similarity floors.
    static let rescorerConfig = VocabularyRescorer.Config(
        shortTermCbwTaperPivot: 5,
        spotterRescueMinSimilarity: 0.30,
        spotterRescueMultiWordMinSimilarity: 0.50,
        spotterRescueEnabled: false
    )

    private struct Session {
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer
        let vocabulary: CustomVocabularyContext
        let sizeConfig: ContextBiasingConstants.VocabSizeConfig
    }

    let directory: URL
    private var models: CtcModels?
    private var tokenizer: CtcTokenizer?
    private var session: Session?

    init(directory: URL = ParakeetVocabularyBoost.defaultDirectory) {
        self.directory = directory
    }

    var isActive: Bool { session != nil }

    /// Loads the model once and prepares the user's words; an empty list switches it off.
    func configure(_ terms: [VocabularyTerm]) async throws {
        guard !terms.isEmpty else {
            session = nil
            return
        }
        if models == nil { models = try await CtcModels.load(from: directory, variant: Self.variant) }
        if tokenizer == nil { tokenizer = try await CtcTokenizer.load(from: directory) }
        guard let models, let tokenizer else { return }
        // Terms without CTC token IDs are skipped silently by the spotter and the rescorer
        // (FluidAudio #851), so every word is tokenized here.
        let vocabularyTerms = terms.compactMap { term -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(term.term)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: term.term, aliases: term.soundsLike.isEmpty ? nil : term.soundsLike, ctcTokenIds: ids)
        }
        guard !vocabularyTerms.isEmpty else {
            session = nil
            return
        }
        let vocabulary = CustomVocabularyContext(terms: vocabularyTerms)
        let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter, vocabulary: vocabulary, config: Self.rescorerConfig, ctcModelDirectory: directory)
        session = Session(spotter: spotter, rescorer: rescorer, vocabulary: vocabulary,
                          sizeConfig: ContextBiasingConstants.rescorerConfig(forVocabSize: vocabularyTerms.count))
        Self.log.info("Vocabulary boost ready for \(vocabularyTerms.count) word(s)")
    }

    func unload() {
        session = nil
        models = nil
        tokenizer = nil
    }

    /// The transcript corrected where the audio shows one of the user's words, or nil when
    /// nothing changed. Timings and audio share one clock: zero is the first sample.
    func rescore(text: String, timings: [TokenTiming], samples: [Float]) async -> String? {
        guard let session, !timings.isEmpty, !samples.isEmpty else { return nil }
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let spot = try await session.spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: session.vocabulary, minScore: nil)
            guard !spot.logProbs.isEmpty else { return nil }
            let output = session.rescorer.ctcTokenRescore(
                transcript: text,
                tokenTimings: timings,
                logProbs: spot.logProbs,
                frameDuration: spot.frameDuration,
                cbw: session.sizeConfig.cbw,
                marginSeconds: 0.5,
                minSimilarity: max(session.sizeConfig.minSimilarity, session.vocabulary.minSimilarity)
            )
            let seconds = CFAbsoluteTimeGetCurrent() - start
            Self.log.info("Vocabulary boost: \(seconds, format: .fixed(precision: 3))s for \(Double(samples.count) / 16_000, format: .fixed(precision: 1))s audio, \(output.wasModified ? "changed" : "unchanged", privacy: .public)")
            return output.wasModified ? output.text : nil
        } catch {
            // Boosting must never break a dictation.
            Self.log.notice("Vocabulary boost skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Token timings from the timed words speech rounds keep: one "▁word" token per word,
    /// ending where the next word starts.
    nonisolated static func timings(for words: [TimedWord], end: TimeInterval) -> [TokenTiming] {
        words.enumerated().map { index, word in
            let next = index + 1 < words.count ? words[index + 1].start : end
            return TokenTiming(token: "\u{2581}" + word.text, tokenId: 0, startTime: word.start,
                               endTime: max(word.start, min(next, word.start + 1.5)), confidence: 1)
        }
    }
}
#endif

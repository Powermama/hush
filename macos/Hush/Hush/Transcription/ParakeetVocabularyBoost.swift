import Foundation
import NaturalLanguage
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
    /// Downloads through `ModelHub`, which reports progress per file; `CtcModels.download`
    /// does the same download without a progress callback.
    nonisolated static func install(
        at directory: URL = defaultDirectory,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try await ModelHub.download(variant.repo, to: parent, progressHandler: { update in
            progress(min(max(update.fractionCompleted, 0), 1))
        })
        guard isInstalled(at: directory) else { throw TranscriberError.backendUnavailable }
        progress(1)
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
    /// The languages whose ordinary words the boost never replaces.
    private var languages: [NLLanguage] = [.english]

    init(directory: URL = ParakeetVocabularyBoost.defaultDirectory) {
        self.directory = directory
    }

    var isActive: Bool { session != nil }

    /// Loads the model once and prepares the user's words; an empty list switches it off.
    func configure(_ terms: [VocabularyTerm], dictationLanguage: String = "auto") async throws {
        languages = EverydayWords.languages(dictationLanguage: dictationLanguage)
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
        let minimumSimilarity = max(session.sizeConfig.minSimilarity, session.vocabulary.minSimilarity)
        // With the acoustic-only rescue off, a dictation can only change where a written
        // word resembles one of the user's words. A text check finds that without the CTC
        // pass, so dictations that mention none of them pay nothing.
        guard session.rescorer.hasCTCRescoringCandidates(
            transcript: text, tokenTimings: timings, minSimilarity: minimumSimilarity) else { return nil }
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
                minSimilarity: minimumSimilarity
            )
            let corrected = output.wasModified ? Self.apply(output.replacements, to: text, languages: languages) : nil
            let seconds = CFAbsoluteTimeGetCurrent() - start
            Self.log.info("Vocabulary boost: \(seconds, format: .fixed(precision: 3))s for \(Double(samples.count) / 16_000, format: .fixed(precision: 1))s audio, \(corrected == nil ? "unchanged" : "changed", privacy: .public)")
            return corrected
        } catch {
            // Boosting must never break a dictation.
            Self.log.notice("Vocabulary boost skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The rescorer's replacements applied to the original text, word for word, so nothing
    /// else in the sentence moves. A replacement whose original is a real word is skipped:
    /// on real speech (earnings22) the spotter turned "going" into "Hong" and "April" into
    /// "Gabriel", while every right fix replaced a misheard non-word such as "Quen" or
    /// "Cressman". phonon's correction follows the same rule with a word list.
    static func apply(_ replacements: [VocabularyRescorer.RescoringResult], to text: String, languages: [NLLanguage]) -> String? {
        var result = text
        var searchFrom = result.startIndex
        var changed = false
        for replacement in replacements where replacement.shouldReplace {
            guard let word = replacement.replacementWord, !word.isEmpty, word != replacement.originalWord,
                  !Self.isPart(word, of: replacement.originalWord),
                  !EverydayWords.containsAny(of: replacement.originalWord, languages: languages) else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: replacement.originalWord)
                .replacingOccurrences(of: " ", with: "\\s+") + "(?![\\p{L}\\p{N}])"
            guard let found = result.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: searchFrom..<result.endIndex)
                    ?? result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            result.replaceSubrange(found, with: word)
            searchFrom = result.index(found.lowerBound, offsetBy: word.count, limitedBy: result.endIndex) ?? result.endIndex
            changed = true
        }
        return changed ? result : nil
    }

    /// Whether `word` is a shorter piece of `original`, as "Java" is of "XJava": replacing
    /// it would only drop letters the speaker said.
    static func isPart(_ word: String, of original: String) -> Bool {
        func letters(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let piece = letters(word), whole = letters(original)
        return piece.count < whole.count && whole.contains(piece)
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

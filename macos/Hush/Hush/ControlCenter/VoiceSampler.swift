import Combine
import Foundation

/// Listens for one spoken sample through dictation's own recorder and speech model, and
/// stops by itself when the user pauses (`SpeechEndpoint`). Used to teach hush a word.
@MainActor
final class VoiceSampler: ObservableObject {
    enum Phase: Equatable { case idle, getReady, listening, checking }
    enum Outcome: Equatable {
        case heard(String, modelID: String?)
        case nothingHeard
        case unavailable(String)
    }

    static let levelCount = 32

    @Published var phase: Phase = .idle
    @Published private(set) var levels = [Float](repeating: 0, count: VoiceSampler.levelCount)

    private weak var coordinator: DictationCoordinator?
    private var endpoint = SpeechEndpoint.word
    private var decision: CheckedContinuation<SpeechEndpoint.Decision, Never>?

    init(coordinator: DictationCoordinator?) {
        self.coordinator = coordinator
    }

    var isAvailable: Bool { coordinator?.vocabularySampleModelID != nil }

    func listen(_ endpoint: SpeechEndpoint) async -> Outcome {
        guard let coordinator else { return .unavailable("Open hush from the menu bar to teach it words.") }
        let modelID = coordinator.vocabularySampleModelID
        self.endpoint = endpoint
        levels = [Float](repeating: 0, count: Self.levelCount)
        do {
            try coordinator.beginVocabularySample { [weak self] level in self?.receive(level) }
        } catch {
            phase = .idle
            return .unavailable(error.localizedDescription)
        }
        phase = .listening
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { self.decision = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.settle(.noSpeech) }
        }
        guard result == .finished, !Task.isCancelled else {
            coordinator.cancelVocabularySample()
            phase = .idle
            return .nothingHeard
        }
        phase = .checking
        defer { phase = .idle }
        do {
            guard let text = try await coordinator.finishVocabularySample(),
                  !Vocabulary.cleanHeard(text).isEmpty else { return .nothingHeard }
            return .heard(text, modelID: modelID)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func cancel() {
        settle(.noSpeech)
        coordinator?.cancelVocabularySample()
        phase = .idle
    }

    private func receive(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
        let next = endpoint.feed(level: level, at: Date())
        if next != .listening { settle(next) }
    }

    private func settle(_ value: SpeechEndpoint.Decision) {
        decision?.resume(returning: value)
        decision = nil
    }
}

/// The steps of teaching hush a word, after FluidVoice's flow: type the word, say it a
/// few times while hush shows what it hears, keep those spellings, then try it out.
@MainActor
final class WordTeacher: ObservableObject {
    enum Step: Equatable { case word, listen, review, saved, manual }
    struct Attempt: Identifiable, Equatable {
        let id = UUID()
        let heard: String
        let matches: Bool
    }
    enum Trial: Equatable {
        case idle, listening, checking
        case recognized(String), missed(String), nothingHeard
        case unavailable(String)
    }

    static let attemptsPerRound = 3

    @Published var step: Step
    @Published var word: String
    @Published private(set) var attempts: [Attempt] = []
    @Published private(set) var target = WordTeacher.attemptsPerRound
    @Published var spellings: [VocabularyTerm.Spelling]
    @Published var problem: String?
    @Published private(set) var trial: Trial = .idle
    let sampler: VoiceSampler
    /// The word as saved before this session, when the user is teaching it again.
    let original: String?

    private var task: Task<Void, Never>?

    init(coordinator: DictationCoordinator?, term: VocabularyTerm? = nil, step: Step = .word) {
        sampler = VoiceSampler(coordinator: coordinator)
        word = term?.term ?? ""
        spellings = term?.spellings ?? []
        original = term?.term
        self.step = step
    }

    var trimmedWord: String { word.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Another saved word with the same name, which this one would replace.
    var isDuplicate: Bool {
        Settings.shared.vocabulary.contains {
            $0.term.caseInsensitiveCompare(trimmedWord) == .orderedSame
                && $0.term.caseInsensitiveCompare(original ?? "") != .orderedSame
        }
    }

    var recognizedEveryTime: Bool { !attempts.isEmpty && attempts.allSatisfy(\.matches) }

    func listen() {
        problem = nil
        step = .listen
        startRound()
    }

    /// One more round on top of what was heard so far.
    func listenMore() {
        target = attempts.count + Self.attemptsPerRound
        listen()
    }

    func startOver() {
        stop()
        attempts = []
        spellings.removeAll { $0.modelID != nil }
        target = Self.attemptsPerRound
        listen()
    }

    func stop() {
        task?.cancel()
        task = nil
        sampler.cancel()
    }

    func addSpelling(_ text: String) {
        let spelling = VocabularyTerm.Spelling(text: Vocabulary.cleanHeard(text), modelID: nil)
        guard !spelling.text.isEmpty, !Vocabulary.matches(spelling.text, trimmedWord),
              !spellings.contains(where: { $0.text.caseInsensitiveCompare(spelling.text) == .orderedSame }) else { return }
        spellings.append(spelling)
    }

    func removeSpelling(_ spelling: VocabularyTerm.Spelling) {
        spellings.removeAll { $0 == spelling }
    }

    /// Saves the word, replacing the version it was opened from.
    func save() {
        stop()
        let term = VocabularyTerm(term: trimmedWord, spellings: spellings)
        var terms = Settings.shared.vocabulary
        terms.removeAll {
            $0.term.caseInsensitiveCompare(term.term) == .orderedSame
                || $0.term.caseInsensitiveCompare(original ?? "") == .orderedSame
        }
        terms.append(term)
        Settings.shared.vocabulary = terms
        trial = .idle
        step = .saved
    }

    /// The user says a sentence with the word; hush shows what it would write.
    func tryIt() {
        stop()
        trial = .listening
        task = Task { [weak self] in
            guard let self else { return }
            let observer = Task { @MainActor [weak self] in
                guard let self else { return }
                for await phase in self.sampler.$phase.values {
                    if phase == .checking { self.trial = .checking }
                }
            }
            defer { observer.cancel() }
            switch await sampler.listen(.sentence) {
            case .heard(let text, _):
                let written = Vocabulary.apply(Settings.shared.vocabulary, to: text.trimmingCharacters(in: .whitespacesAndNewlines))
                trial = Vocabulary.contains(written, term: trimmedWord) ? .recognized(written) : .missed(written)
            case .nothingHeard:
                trial = Task.isCancelled ? .idle : .nothingHeard
            case .unavailable(let message):
                trial = .unavailable(message)
            }
        }
    }

    private func startRound() {
        task?.cancel()
        task = Task { [weak self] in await self?.runRound() }
    }

    private func runRound() async {
        var misses = 0
        while attempts.count < target, !Task.isCancelled {
            sampler.phase = .getReady
            try? await Task.sleep(for: .milliseconds(attempts.isEmpty && misses == 0 ? 350 : 900))
            guard !Task.isCancelled else { return }
            switch await sampler.listen(.word) {
            case .heard(let text, let modelID):
                misses = 0
                problem = nil
                let matches = Vocabulary.matches(text, trimmedWord)
                attempts.append(Attempt(heard: Vocabulary.cleanHeard(text), matches: matches))
                if !matches,
                   !spellings.contains(where: { Vocabulary.matches($0.text, text) }) {
                    spellings.append(.init(text: Vocabulary.cleanHeard(text), modelID: modelID))
                }
            case .nothingHeard:
                guard !Task.isCancelled else { return }
                misses += 1
                problem = "hush didn\u{2019}t hear anything. Say \u{201C}\(trimmedWord)\u{201D} a little closer to the microphone."
                if misses >= 3 {
                    sampler.phase = .idle
                    return
                }
            case .unavailable(let message):
                problem = message
                sampler.phase = .idle
                return
            }
        }
        guard !Task.isCancelled else { return }
        sampler.phase = .idle
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        step = .review
    }
}

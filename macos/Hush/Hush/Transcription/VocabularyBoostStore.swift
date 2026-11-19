import Combine
import Foundation

/// The Parakeet vocabulary boost as the user sees it (PRD R13): a 97.5 MB model that is
/// downloaded only after the user accepts, can be removed, and is only offered while
/// Parakeet is the speech engine. Without it the words the user taught still apply.
@MainActor
final class VocabularyBoostStore: ObservableObject {
    enum State: Equatable {
        case notInstalled
        /// Fraction downloaded, 0 to 1.
        case downloading(Double)
        case installed
        case failed(String)
    }

    static let shared = VocabularyBoostStore()

    @Published private(set) var state: State
    private var download: Task<Void, Never>?

    private init() {
        #if canImport(FluidAudio)
        state = ParakeetVocabularyBoost.isInstalled() ? .installed : .notInstalled
        #else
        state = .notInstalled
        #endif
    }

    var isInstalled: Bool { state == .installed }

    /// The download in words, such as "97.5 MB".
    var sizeDescription: String {
        #if canImport(FluidAudio)
        ParakeetVocabularyBoost.downloadSize.formatted(.measurement(width: .abbreviated, usage: .asProvided))
        #else
        ""
        #endif
    }

    /// Whether the boost applies: Parakeet is the speech engine.
    static func appliesToActiveEngine() -> Bool {
        SpeechEngine.engine(for: Settings.shared.modelID) == .fluidAudio
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    func install() {
        guard !isDownloading, state != .installed else { return }
        state = .downloading(0)
        download = Task {
            do {
                #if canImport(FluidAudio)
                try await ParakeetVocabularyBoost.install { fraction in
                    Task { @MainActor [weak self] in
                        // FluidAudio reports thousands of updates; the card shows whole percents.
                        guard let self, case .downloading(let shown) = self.state,
                              Int(fraction * 100) > Int(shown * 100) else { return }
                        self.state = .downloading(fraction)
                    }
                }
                #endif
                try Task.checkCancellation()
                state = .installed
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("The download did not finish. Check your connection and try again.")
            }
        }
    }

    #if DEBUG
    /// Shows a state without downloading, for previews and visual checks only.
    func showForPreview(_ state: State) { self.state = state }
    #endif

    /// Stops the download and removes what arrived, like a speech model's download.
    func cancelDownload() {
        guard isDownloading else { return }
        download?.cancel()
        download = nil
        #if canImport(FluidAudio)
        try? ParakeetVocabularyBoost.remove()
        #endif
        state = .notInstalled
    }

    func remove() {
        #if canImport(FluidAudio)
        do {
            try ParakeetVocabularyBoost.remove()
            state = .notInstalled
        } catch {
            state = .failed("hush could not remove the boost: \(error.localizedDescription)")
        }
        #endif
    }
}

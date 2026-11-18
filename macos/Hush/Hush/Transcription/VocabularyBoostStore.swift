import Combine
import Foundation

/// The Parakeet vocabulary boost as the user sees it (PRD R13): a 97.5 MB model that is
/// downloaded only after the user accepts, can be removed, and is only offered while
/// Parakeet is the speech engine. Without it the words the user taught still apply.
@MainActor
final class VocabularyBoostStore: ObservableObject {
    enum State: Equatable {
        case notInstalled
        case downloading
        case installed
        case failed(String)
    }

    static let shared = VocabularyBoostStore()

    @Published private(set) var state: State

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

    func install() {
        guard state != .downloading, state != .installed else { return }
        state = .downloading
        Task {
            do {
                #if canImport(FluidAudio)
                try await ParakeetVocabularyBoost.install()
                #endif
                state = .installed
            } catch {
                state = .failed("The download did not finish. Check your connection and try again.")
            }
        }
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

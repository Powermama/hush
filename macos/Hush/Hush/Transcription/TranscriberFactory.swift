import Foundation

/// Single seam between the rest of the app and the speech engines.
/// The engine is derived from the model ID; each real implementation is selected
/// via `#if canImport(...)` so the project still builds without either package.
enum TranscriberFactory {
    static func make(for modelID: String) -> Transcriber {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--use-mock-transcriber") {
            return MockTranscriber()
        }
        #endif
        switch SpeechEngine.engine(for: modelID) {
        case .whisperKit:
            #if canImport(WhisperKit)
            return WhisperKitTranscriber()
            #else
            return MockTranscriber()
            #endif
        case .fluidAudio:
            #if canImport(FluidAudio)
            return FluidAudioTranscriber()
            #else
            return MockTranscriber()
            #endif
        }
    }

    static var isUsingMock: Bool {
        #if canImport(WhisperKit)
        return false
        #else
        return true
        #endif
    }
}

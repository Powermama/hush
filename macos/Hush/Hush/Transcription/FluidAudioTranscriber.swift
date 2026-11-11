import Foundation
import OSLog

#if canImport(FluidAudio)
import FluidAudio

/// FluidAudio-backed implementation of `Transcriber` for the Parakeet models.
///
/// Follows FluidAudio's documented batch path: `AsrModels.downloadAndLoad` (Core ML,
/// encoder on the Neural Engine by default) → `AsrManager.loadModels` → `transcribe`.
/// Model files live under `AIModelStorage.fluidAudioRoot`, never in FluidAudio's
/// default `Application Support/FluidAudio` cache.
///
/// Like `WhisperKitTranscriber`, the class opts out of the project's MainActor default
/// isolation. `AsrManager` is itself an actor; the reference to it is guarded by a
/// private serial queue.
nonisolated
final class FluidAudioTranscriber: Transcriber, @unchecked Sendable {

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "FluidAudio")

    /// 16 kHz mono, as required by the `Transcriber` protocol and Parakeet.
    static let sampleRate = 16_000

    private var manager: AsrManager?
    private var loadedID: String?
    private let queue = DispatchQueue(label: "com.decentralfreedom.hush.fluidaudio.state")

    func prepare(modelID: String, progress: @Sendable @MainActor @escaping (Double) -> Void) async throws {
        let preparationStart = CFAbsoluteTimeGetCurrent()
        let alreadyLoaded = queue.sync { loadedID == modelID && manager != nil }
        if alreadyLoaded {
            await MainActor.run { progress(1.0) }
            return
        }
        guard let model = ParakeetModel(rawValue: modelID) else {
            throw TranscriberError.backendUnavailable
        }

        let directory = ModelManager.fluidAudioCacheURL(for: model)
        let wasCached = ModelManager.isParakeetComplete(at: directory)
        Self.log.info("Loading \(wasCached ? "cached" : "remote", privacy: .public) model \(modelID, privacy: .public)")
        await MainActor.run { progress(wasCached ? 0.95 : 0.0) }

        try FileManager.default.createDirectory(
            at: AIModelStorage.fluidAudioRoot,
            withIntermediateDirectories: true
        )
        try Task.checkCancellation()

        // Download (when needed), compile and load in one documented call. The top 5%
        // of the progress bar is reserved for the warm-up below.
        let loadStart = CFAbsoluteTimeGetCurrent()
        let models = try await AsrModels.downloadAndLoad(
            to: directory,
            version: model.asrModelVersion,
            progressHandler: { update in
                guard !wasCached else { return }
                let fraction = max(0, min(1, update.fractionCompleted))
                Task { @MainActor in progress(fraction * 0.95) }
            }
        )
        try Task.checkCancellation()

        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        try Task.checkCancellation()
        Self.log.info(
            "FluidAudio model load: \(CFAbsoluteTimeGetCurrent() - loadStart, format: .fixed(precision: 2))s for \(modelID, privacy: .public)"
        )

        // Core ML specialises parts of the graph on the first prediction. Run one second
        // of silence now, behind the progress UI, so the first hotkey press does not pay it.
        let warmStart = CFAbsoluteTimeGetCurrent()
        var warmState = TdtDecoderState.make()
        _ = try? await asr.transcribe(
            [Float](repeating: 0, count: Self.sampleRate),
            decoderState: &warmState
        )
        Self.log.info("FluidAudio warmup: \(CFAbsoluteTimeGetCurrent() - warmStart, format: .fixed(precision: 2))s")
        try Task.checkCancellation()

        queue.sync {
            self.manager = asr
            self.loadedID = modelID
        }
        Self.log.info(
            "FluidAudio ready: \(CFAbsoluteTimeGetCurrent() - preparationStart, format: .fixed(precision: 2))s total for \(modelID, privacy: .public)"
        )
        await MainActor.run { progress(1.0) }
    }

    /// `fallbackCount` is Whisper's temperature-fallback budget; Parakeet's TDT decoder
    /// has no equivalent, so it is ignored.
    func transcribe(samples: [Float], language: String, fallbackCount: Int) async throws -> String? {
        let asr = queue.sync { manager }
        guard let asr else { throw TranscriberError.modelNotLoaded }
        if samples.isEmpty { throw TranscriberError.empty }

        // Below FluidAudio's minimum there is nothing a speech model can recognise.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate)
        guard samples.count >= minimum else { return nil }

        // Clips are decoded as recorded: padding 0.5-0.9 s clips with silence was
        // measured during integration and changed no transcript.
        // A fresh decoder state per dictation: nothing from the previous clip carries over.
        var state = TdtDecoderState.make()
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = try await asr.transcribe(
            samples,
            decoderState: &state,
            language: Self.languageHint(for: language)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        let audioSec = Double(samples.count) / Double(Self.sampleRate)
        let rtf = audioSec > 0 ? elapsed / audioSec : 0
        Self.log.info("asr.transcribe: \(elapsed, format: .fixed(precision: 2))s for \(audioSec, format: .fixed(precision: 2))s audio (RTF=\(rtf, format: .fixed(precision: 3)))")

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func unload() async {
        let asr = queue.sync { () -> AsrManager? in
            defer {
                manager = nil
                loadedID = nil
            }
            return manager
        }
        await asr?.cleanup()
    }

    /// Script-aware token filtering hint. `nil` for "auto" and for languages outside
    /// Parakeet's 25, which lets the model detect the language itself.
    static func languageHint(for code: String) -> Language? {
        guard ParakeetModel.supportedLanguages.contains(code) else { return nil }
        return Language(rawValue: code)
    }
}

nonisolated extension ParakeetModel {
    var asrModelVersion: AsrModelVersion {
        switch self {
        case .ultra: return .ultra
        case .redux: return .redux
        }
    }

    /// FluidAudio's own repository descriptor for this model.
    var repository: Repo {
        switch self {
        case .ultra: return .parakeetUltra
        case .redux: return .parakeetRedux
        }
    }
}
#endif

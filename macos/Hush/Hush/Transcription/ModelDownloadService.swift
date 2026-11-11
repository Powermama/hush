import Combine
import Foundation
import OSLog

#if canImport(WhisperKit)
import WhisperKit
#endif
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Downloads transcription models without activating them.
///
/// Downloading is deliberately separate from activation (`DictationCoordinator`
/// `prepareModelInBackground`): the active model keeps working while a new one
/// downloads, and a finished download only becomes active when the user chooses Use.
/// One download runs at a time, because WhisperKit's Hub downloader is not safe for
/// overlapping writes.
@MainActor
final class ModelDownloadService {
    static let shared = ModelDownloadService()

    enum State: Equatable {
        case downloading(progress: Double)
        case failed(message: String)
    }

    enum DownloadError: LocalizedError {
        case insufficientSpace(neededMB: Int, availableMB: Int)
        case engineUnavailable

        var errorDescription: String? {
            switch self {
            case .insufficientSpace(let needed, let available):
                return "Needs \(ModelPresentation.size(needed)), \(ModelPresentation.size(available)) available"
            case .engineUnavailable:
                return "This engine is not available in this build"
            }
        }
    }

    /// Per-model download state. Models absent from the dictionary are idle.
    let states = CurrentValueSubject<[String: State], Never>([:])

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "ModelDownload")
    private var task: Task<Void, Never>?
    private var activeID: String?

    var isBusy: Bool { activeID != nil }

    func state(for id: String) -> State? { states.value[id] }

    /// Free space for user-initiated downloads, as the system reports it for
    /// "important" usage (it may purge caches to make room).
    static func availableCapacityMB() -> Int? {
        let values = try? AIModelStorage.root.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Int($0 / 1_048_576) }
    }

    /// Required space: the download plus ~15% for the compiled Core ML cache.
    static func requiredCapacityMB(for model: ModelInfo) -> Int? {
        model.approximateSizeMB.map { Int((Double($0) * 1.15).rounded(.up)) }
    }

    /// Nil when there is enough space or the size is unknown.
    static func spaceShortfall(for model: ModelInfo) -> DownloadError? {
        guard let needed = requiredCapacityMB(for: model),
              let available = availableCapacityMB(),
              available < needed else { return nil }
        return .insufficientSpace(neededMB: needed, availableMB: available)
    }

    func download(_ model: ModelInfo) {
        guard activeID == nil, !ModelManager.isAvailable(model.id) else { return }
        if let shortfall = Self.spaceShortfall(for: model) {
            set(model.id, .failed(message: shortfall.localizedDescription))
            return
        }
        activeID = model.id
        set(model.id, .downloading(progress: 0))
        Self.log.info("Downloading \(model.id, privacy: .public)")

        task = Task { [weak self] in
            guard let service = self else { return }
            do {
                try await Self.fetch(model) { fraction in
                    Task { @MainActor [weak service] in
                        guard let service, service.activeID == model.id,
                              case .downloading = service.states.value[model.id] else { return }
                        service.set(model.id, .downloading(progress: fraction))
                    }
                }
                try Task.checkCancellation()
                self?.finish(model.id, state: nil)
                Self.log.info("Downloaded \(model.id, privacy: .public)")
            } catch is CancellationError {
                Self.discardPartialFiles(for: model.id)
                self?.finish(model.id, state: nil)
            } catch {
                guard let self else { return }
                if Task.isCancelled {
                    Self.discardPartialFiles(for: model.id)
                    self.finish(model.id, state: nil)
                } else {
                    Self.log.error("Download failed for \(model.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.finish(model.id, state: .failed(message: Self.describe(error)))
                }
            }
        }
    }

    /// Stops the running download and removes its partial files.
    func cancel(_ id: String) {
        guard activeID == id else {
            set(id, nil)
            return
        }
        task?.cancel()
    }

    func clearFailure(_ id: String) {
        if case .failed = states.value[id] { set(id, nil) }
    }

    func cancelAndWait(_ id: String) async {
        guard activeID == id, let pending = task else { return }
        pending.cancel()
        await pending.value
    }

    private func finish(_ id: String, state: State?) {
        if activeID == id {
            activeID = nil
            task = nil
        }
        set(id, state)
    }

    private func set(_ id: String, _ state: State?) {
        var all = states.value
        all[id] = state
        states.send(all)
    }

    private static func discardPartialFiles(for id: String) {
        guard !ModelManager.isInCache(id) else { return }
        try? FileManager.default.removeItem(at: ModelManager.cacheURL(for: id))
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Download failed: connection lost"
            case .timedOut:
                return "Download failed: the server did not respond"
            default:
                break
            }
        }
        if (error as NSError).code == NSFileWriteOutOfSpaceError {
            return "Not enough disk space"
        }
        return "Download failed"
    }

    /// Downloads (and, for FluidAudio, compiles) the model files into Hush's private
    /// model storage, using each engine's own documented download API.
    private static func fetch(
        _ model: ModelInfo,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch model.engine {
        case .whisperKit:
            #if canImport(WhisperKit)
            _ = try await WhisperKit.download(
                variant: model.id,
                downloadBase: AIModelStorage.whisperHuggingFaceRoot,
                progressCallback: { progress(max(0, min(1, $0.fractionCompleted))) }
            )
            #else
            throw DownloadError.engineUnavailable
            #endif
        case .fluidAudio:
            #if canImport(FluidAudio)
            guard let parakeet = ParakeetModel(rawValue: model.id) else {
                throw DownloadError.engineUnavailable
            }
            try FileManager.default.createDirectory(
                at: AIModelStorage.fluidAudioRoot,
                withIntermediateDirectories: true
            )
            _ = try await AsrModels.download(
                to: ModelManager.fluidAudioCacheURL(for: parakeet),
                version: parakeet.asrModelVersion,
                progressHandler: { progress(max(0, min(1, $0.fractionCompleted))) }
            )
            #else
            throw DownloadError.engineUnavailable
            #endif
        }
    }
}

/// Shared formatting for model metadata, so every surface shows the same values.
enum ModelPresentation {
    nonisolated static func size(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        // Release dates are calendar days stored at UTC midnight.
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// "603 MB · 25 languages · Sep 2026"
    @MainActor
    static func metadata(for model: ModelInfo) -> String {
        var parts: [String] = []
        if let mb = model.approximateSizeMB { parts.append(size(mb)) }
        parts.append(model.languageCoverage)
        if let date = model.releaseDate { parts.append(month(date)) }
        return parts.joined(separator: " · ")
    }

    /// "25 languages · Sep 2026", for rows that show the size in its own column.
    @MainActor
    static func coverageAndDate(for model: ModelInfo) -> String {
        var parts = [model.languageCoverage]
        if let date = model.releaseDate { parts.append(month(date)) }
        return parts.joined(separator: " · ")
    }

    /// Strips the trailing "(547 MB)" WhisperKit adds to compressed variant names.
    static func title(_ displayName: String) -> String {
        displayName.replacingOccurrences(
            of: #"\s*\(\d+\s*MB\)$"#,
            with: "",
            options: .regularExpression
        )
    }
}

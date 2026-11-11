import AppKit
import Foundation
import OSLog

/// Side-channel knowledge of each speech engine's on-disk model layout.
///
/// Hush downloads models into its Application Support directory:
///   WhisperKit: `~/Library/Application Support/Hush/Models/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-<id>/`
///   FluidAudio: `~/Library/Application Support/Hush/Models/fluidaudio/<repository folder>/`
/// WhisperKit has no public API to query "is X downloaded" or to delete it, so we
/// touch the filesystem directly.
@MainActor
enum ModelManager {

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "ModelManager")

    /// Hub root passed to WhisperKit. Models are application data, not user documents.
    /// Keeping them in Application Support avoids an unrelated Documents-folder privacy
    /// prompt on first launch.
    static var huggingFaceRoot: URL {
        AIModelStorage.whisperHuggingFaceRoot
    }

    /// Root directory under which all WhisperKit model variants live for this app.
    static var cacheRoot: URL {
        huggingFaceRoot
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
    }

    /// Folder name on HuggingFace for a given model variant id.
    static func folderName(for modelID: String) -> String {
        if modelID.hasPrefix("distil-whisper_") {
            return modelID
        }
        return "openai_whisper-\(modelID)"
    }

    static func cacheURL(for modelID: String) -> URL {
        if let parakeet = ParakeetModel(rawValue: modelID) {
            return fluidAudioCacheURL(for: parakeet)
        }
        return cacheRoot.appendingPathComponent(folderName(for: modelID))
    }

    nonisolated static func fluidAudioCacheURL(for model: ParakeetModel) -> URL {
        AIModelStorage.fluidAudioRoot
            .appendingPathComponent(model.repositoryFolderName, isDirectory: true)
    }

    /// The four Core ML bundles and the vocabulary every Parakeet v3-family model needs.
    /// Matches FluidAudio's `AsrModels.modelsExist(at:version:)`; the `coremldata.bin`
    /// inside each bundle is written last, so its presence means the bundle finished.
    nonisolated static let parakeetRequiredFiles = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Encoder.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecisionv3.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]

    nonisolated static func isParakeetComplete(at folder: URL) -> Bool {
        parakeetRequiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// True if the model is shipped with the app or has been downloaded into the cache.
    static func isAvailable(_ modelID: String) -> Bool {
        if ModelInfo.bundledEntries.contains(where: { $0.id == modelID }) { return true }
        return isInCache(modelID)
    }

    /// Backwards-compat alias used by older call sites.
    static func isDownloaded(_ modelID: String) -> Bool { isAvailable(modelID) }

    /// True specifically if the user has a complete copy in Hush's Application Support
    /// cache. We check for the small `coremldata.bin` metadata file in all three of
    /// WhisperKit's CoreML containers — they're the last things written when an
    /// `.mlmodelc` is finalised, so seeing all three means the download finished and the
    /// model is loadable. The previous "directory not empty" fallback was returning
    /// true mid-download (HuggingFace's HubApi creates the folder and starts streaming
    /// blobs into it) which made the UI flip from "Downloading" to "Loading from cache"
    /// half-way through.
    static func isInCache(_ modelID: String) -> Bool {
        if let parakeet = ParakeetModel(rawValue: modelID) {
            return isParakeetComplete(at: fluidAudioCacheURL(for: parakeet))
        }
        let folder = cacheURL(for: modelID)
        let fm = FileManager.default
        let required = ["AudioEncoder", "TextDecoder", "MelSpectrogram"]
        return required.allSatisfy { sub in
            let path = folder
                .appendingPathComponent("\(sub).mlmodelc")
                .appendingPathComponent("coremldata.bin").path
            return fm.fileExists(atPath: path)
        }
    }

    /// IDs that are *available right now* — bundled with the app or already in cache.
    /// Walks the on-disk cache directly so it picks up anything the user has, even
    /// variants that aren't (yet) in the live HuggingFace catalog snapshot.
    static func availableIDs() -> Set<String> {
        var ids = Set(ModelInfo.bundledEntries.map(\.id))
        for parakeet in ParakeetModel.allCases where isInCache(parakeet.id) {
            ids.insert(parakeet.id)
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: cacheRoot,
                                                          includingPropertiesForKeys: nil)
        else { return ids }
        for url in contents {
            let name = url.lastPathComponent
            // WhisperKit puts every variant inside `openai_whisper-<id>`.
            guard name.hasPrefix("openai_whisper-") else { continue }
            let id = String(name.dropFirst("openai_whisper-".count))
            if isInCache(id) { ids.insert(id) }
        }
        return ids
    }

    /// Backwards-compat alias.
    static func downloadedIDs() -> Set<String> { availableIDs() }

    /// Disk usage for a given model (sum of all files in the folder), nil if not present.
    static func diskUsageBytes(for modelID: String) -> Int64? {
        let url = cacheURL(for: modelID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var total: Int64 = 0
        if let it = FileManager.default.enumerator(at: url,
                                                    includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in it {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    /// Deletes the model from disk so the user can free space.
    /// Bundled models can't be deleted — they live read-only inside the .app.
    static func delete(_ modelID: String) throws {
        if ModelInfo.bundledEntries.contains(where: { $0.id == modelID }) { return }
        let url = cacheURL(for: modelID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        log.info("Deleted model \(modelID, privacy: .public)")
    }

    static func reveal(_ modelID: String) {
        let url = cacheURL(for: modelID)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if SpeechEngine.engine(for: modelID) == .fluidAudio {
            NSWorkspace.shared.open(AIModelStorage.fluidAudioRoot)
        } else {
            NSWorkspace.shared.open(cacheRoot)
        }
    }
}

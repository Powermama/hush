import Foundation

/// One private home for every downloadable AI model owned by Hush.
///
/// Keeping this policy separate from the model runtimes prevents third-party SDK
/// defaults from scattering large model files across Documents or the shared
/// `~/.cache/huggingface` directory.
nonisolated enum AIModelStorage {
    static var root: URL {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("Hush", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// WhisperKit's `downloadBase`. It appends its own `models/...` hierarchy.
    static var whisperHuggingFaceRoot: URL {
        root.appendingPathComponent("huggingface", isDirectory: true)
    }

    /// FluidAudio's model root. Each Parakeet repository lives in its own
    /// `<root>/fluidaudio/<repository folder>/` directory, matching FluidAudio's cache
    /// layout, instead of FluidAudio's default `Application Support/FluidAudio`.
    static var fluidAudioRoot: URL {
        root.appendingPathComponent("fluidaudio", isDirectory: true)
    }

    /// Swift Hugging Face Hub cache used by the Qwen refinement models.
    static var qwenHuggingFaceHubRoot: URL {
        whisperHuggingFaceRoot.appendingPathComponent("hub", isDirectory: true)
    }

    /// Location used by earlier Hush builds through Hugging Face's default client.
    static var legacySharedHuggingFaceHubRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    static let qwenRepositoryFolders = [
        "models--mlx-community--Qwen2.5-1.5B-Instruct-4bit",
        "models--mlx-community--Qwen3-1.7B-4bit",
        "models--mlx-community--Qwen3.5-2B-4bit",
        "models--mlx-community--Qwen3.5-4B-4bit",
    ]

    /// Moves only repositories supported by Hush from the old shared cache into
    /// Hush's private application-data directory. Unrelated Hugging Face models
    /// are deliberately left untouched.
    @discardableResult
    static func migrateLegacyQwenRepositories(
        fileManager: FileManager = .default,
        from legacyHubRoot: URL = legacySharedHuggingFaceHubRoot,
        to destinationHubRoot: URL = qwenHuggingFaceHubRoot
    ) throws -> [String] {
        try fileManager.createDirectory(
            at: destinationHubRoot,
            withIntermediateDirectories: true
        )
        let destinationLocks = destinationHubRoot.appendingPathComponent(".locks", isDirectory: true)
        try fileManager.createDirectory(at: destinationLocks, withIntermediateDirectories: true)

        var migrated: [String] = []
        for folder in qwenRepositoryFolders {
            let source = legacyHubRoot.appendingPathComponent(folder, isDirectory: true)
            let destination = destinationHubRoot.appendingPathComponent(folder, isDirectory: true)
            if fileManager.fileExists(atPath: source.path),
               !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: source, to: destination)
                migrated.append(folder)
            }

            // Preserve Hugging Face's per-blob lock hierarchy too. Lock files are
            // advisory coordination records, not model content, but keeping them
            // beside the relocated cache retains the SDK's expected layout.
            let sourceLock = legacyHubRoot
                .appendingPathComponent(".locks", isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
            let destinationLock = destinationLocks
                .appendingPathComponent(folder, isDirectory: true)
            if fileManager.fileExists(atPath: sourceLock.path),
               !fileManager.fileExists(atPath: destinationLock.path) {
                try fileManager.moveItem(at: sourceLock, to: destinationLock)
            }
        }
        return migrated
    }
}

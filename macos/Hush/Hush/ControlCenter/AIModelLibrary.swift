import AppKit
import Combine

nonisolated enum LocalAIModel: Hashable, Sendable {
    case intelligence(LLMProvider)
    case speech(String)
    case voice

    var id: String {
        switch self {
        case .intelligence(let provider): provider.rawValue
        case .speech(let id): id
        case .voice: "kokoro"
        }
    }
}

/// Only Hush-owned voice assets. Parakeet and other engines share the parent
/// directory, so deleting that parent would destroy unrelated downloads.
nonisolated enum VoiceModelFiles {
    static let folders = ["kokoro-82m-coreml", "kokoro"]
    static func urls(in root: URL) -> [URL] { folders.map { root.appendingPathComponent($0, isDirectory: true) } }
    static func remove(in root: URL) throws {
        for url in urls(in: root) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    static func bytes(in root: URL) -> Int64 { urls(in: root).reduce(0) { $0 + bytes(at: $1) } }
    static func bytes(at url: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var size: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }
}

@MainActor
final class AIModelLibrary {
    static let shared = AIModelLibrary()
    let changes = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    private var operations: [LocalAIModel: Task<Void, Never>] = [:]
    private(set) var failures: [LocalAIModel: String] = [:]
    private(set) var sizes: [LocalAIModel: Int64] = [:]
    private(set) var isRemoving = false
    private var knownSpeechIDs = Set(UserDefaults.standard.stringArray(forKey: "aiLibrary.knownSpeechIDs") ?? [])
    weak var coordinator: DictationCoordinator?
    var assistantIsWorking: () -> Bool = { false }

    init() {
        LLMRuntime.shared.stateChange.sink { [weak self] in self?.changes.send() }.store(in: &subscriptions)
        ModelDownloadService.shared.states.sink { [weak self] _ in self?.changes.send() }.store(in: &subscriptions)
        CoworkerVoice.shared.setupProgress.removeDuplicates().sink { [weak self] _ in self?.changes.send() }.store(in: &subscriptions)
        CoworkerVoice.shared.setupState.sink { [weak self] _ in self?.changes.send() }.store(in: &subscriptions)
        Settings.shared.didChange.sink { [weak self] in self?.changes.send() }.store(in: &subscriptions)
    }

    var catalog: [LocalAIModel] {
        let speech = ModelCatalogService.shared.models.value
        var ids = Set(speech.filter { $0.engine == .fluidAudio || ModelManager.isAvailable($0.id) }.map(\.id))
        ids.formUnion(ModelManager.availableIDs())
        let previous = knownSpeechIDs
        knownSpeechIDs.formUnion(ids)
        if knownSpeechIDs != previous { UserDefaults.standard.set(knownSpeechIDs.sorted(), forKey: "aiLibrary.knownSpeechIDs") }
        ids.formUnion(knownSpeechIDs)
        return [.intelligence(.qwen35_4b), .intelligence(.qwen35_2b), .voice]
            + ids.sorted().map(LocalAIModel.speech)
    }
    func name(_ item: LocalAIModel) -> String {
        switch item {
        case .intelligence(let provider): return provider.displayName
        case .speech(let id):
            let name = ModelCatalogService.shared.models.value.first { $0.id == id }?.displayName
                ?? ModelInfo.deriveDisplayName(from: id)
            return SpeechEngine.engine(for: id) == .whisperKit ? "Whisper " + name : name
        case .voice: return "Kokoro"
        }
    }
    func installed(_ item: LocalAIModel) -> Bool {
        switch item {
        case .intelligence(let provider):
            guard let model = LLMRuntime.QwenModel(provider: provider) else { return false }
            return LLMRuntime.cachedQwenSnapshotURL(for: model) != nil
        case .speech(let id): return ModelManager.isAvailable(id)
        case .voice: return CoworkerVoice.hasCachedAssets
        }
    }
    func bundled(_ item: LocalAIModel) -> Bool {
        if case .speech(let id) = item { return ModelInfo.bundledEntries.contains { $0.id == id } }
        return false
    }
    func busy(_ item: LocalAIModel) -> Bool {
        if operations[item] != nil { return true }
        switch item {
        case .intelligence(let provider):
            if let model = LLMRuntime.QwenModel(provider: provider), case .downloading = LLMRuntime.shared.qwenState(for: model) { return true }
        case .speech(let id):
            if case .downloading = ModelDownloadService.shared.state(for: id) { return true }
            if coordinator?.loadedModelID == nil, Settings.shared.modelID == id,
               case .modelLoading = coordinator?.phase.value { return true }
        case .voice: return CoworkerVoice.shared.setupState.value == .preparing
        }
        return false
    }
    func detail(_ item: LocalAIModel) -> String {
        if let failure = failures[item] { return failure }
        switch item {
        case .intelligence(let provider):
            if let model = LLMRuntime.QwenModel(provider: provider), case .downloading(let progress) = LLMRuntime.shared.qwenState(for: model) { return progress.statusText }
            var uses: [String] = []
            if provider == Settings.shared.llmProvider { uses.append("Personas") }
            if provider == CoworkerModelSettings.provider { uses.append("Assistant") }
            return installed(item) ? "Intelligence & vision" + (uses.isEmpty ? "" : " · " + uses.joined(separator: ", ")) : "Intelligence & vision · \(provider.approxDownloadSize ?? "") download"
        case .speech(let id):
            if case .downloading(let progress) = ModelDownloadService.shared.state(for: id) { return "Downloading \(Int(progress * 100))%" }
            return "Transcription" + (id == Settings.shared.modelID ? " · In use" : "")
        case .voice:
            if CoworkerVoice.shared.setupState.value == .preparing { return CoworkerVoice.shared.setupProgress.value.label }
            return "Spoken replies · English"
        }
    }

    func refreshSizes() async {
        let items = catalog.filter { installed($0) && !bundled($0) }
        let paths: [(LocalAIModel, [URL])] = items.map { item in
            switch item {
            case .intelligence(let provider):
                return (item, LLMRuntime.QwenModel(provider: provider).map { [LLMRuntime.qwenCacheURL(for: $0)] } ?? [])
            case .speech(let id): return (item, [ModelManager.cacheURL(for: id)])
            case .voice: return (item, VoiceModelFiles.urls(in: AIModelStorage.fluidAudioRoot))
            }
        }
        sizes = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: paths.map { item, urls in
                (item, urls.reduce(Int64(0)) { $0 + VoiceModelFiles.bytes(at: $1) })
            })
        }.value
        changes.send()
    }

    func download(_ item: LocalAIModel) {
        guard operations[item] == nil, !isRemoving else { return }
        failures[item] = nil
        operations[item] = Task { [weak self] in
            guard let self else { return }
            do { try await install(item) }
            catch is CancellationError { }
            catch { failures[item] = error.localizedDescription }
            operations[item] = nil
            await refreshSizes()
        }
        changes.send()
    }

    /// Setup and individual downloads share the same native runtimes and caches.
    func install(_ item: LocalAIModel) async throws {
        try Task.checkCancellation()
        switch item {
        case .intelligence(let provider):
            guard let model = LLMRuntime.QwenModel(provider: provider) else { throw LibraryError.unavailable }
            let runtime = LLMRuntime.shared
            if installed(item), case .warm = runtime.qwenState(for: model) { return }
            try await runtime.downloadQwenAndWait(model)
        case .speech(let id):
            if installed(item) { return }
            guard let model = ModelCatalogService.shared.models.value.first(where: { $0.id == id }) else { throw LibraryError.unavailable }
            let service = ModelDownloadService.shared
            let owned = !service.isBusy
            if service.isBusy {
                guard case .downloading = service.state(for: id) else { throw LibraryError.busy }
            }
            service.clearFailure(id)
            service.download(model)
            do {
                while true {
                    try Task.checkCancellation()
                    if case .failed(let message) = service.state(for: id) { throw LibraryError.failed(message) }
                    if service.state(for: id) == nil {
                        guard installed(item) else { throw CancellationError() }
                        return
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
            } catch {
                if owned { await service.cancelAndWait(id) }
                throw error
            }
        case .voice:
            try await withTaskCancellationHandler {
                try await CoworkerVoice.shared.prepare()
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor in CoworkerVoice.shared.cancelPreparation() }
            }
        }
    }

    func cancel(_ item: LocalAIModel) {
        operations[item]?.cancel()
        if operations[item] == nil {
            switch item {
            case .intelligence(let provider):
                if let model = LLMRuntime.QwenModel(provider: provider) { Task { await LLMRuntime.shared.cancelQwenDownloadAndWait(model) } }
            case .speech(let id): ModelDownloadService.shared.cancel(id)
            case .voice: CoworkerVoice.shared.cancelPreparation()
            }
        }
    }

    var canRemove: Bool {
        !isRemoving && !assistantIsWorking() && coordinator?.canManageModels != false && !AssistantSetupFlow.shared.isRunning
    }
    func remove(_ item: LocalAIModel) async throws {
        guard canRemove, !busy(item), !bundled(item) else { throw LibraryError.busy }
        isRemoving = true; changes.send()
        defer { isRemoving = false; changes.send() }
        switch item {
        case .intelligence(let provider):
            guard let model = LLMRuntime.QwenModel(provider: provider) else { throw LibraryError.unavailable }
            try LLMRuntime.shared.deleteQwen(model)
            if Settings.shared.llmProvider == provider { Settings.shared.llmProvider = .off }
        case .speech(let id):
            guard !id.contains("/"), !id.contains("..") else { throw LibraryError.unavailable }
            if Settings.shared.modelID == id {
                if let coordinator { try await coordinator.releaseModelForRemoval(id) }
                Settings.shared.modelID = ModelInfo.defaultModelID
            }
            try ModelManager.delete(id)
            if let coordinator { Task { await coordinator.prepareModelInBackground() } }
        case .voice:
            try await CoworkerVoice.shared.removeModel()
        }
        failures[item] = nil
        await refreshSizes()
    }

    enum LibraryError: LocalizedError {
        case unavailable, busy, failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "This model is unavailable."
            case .busy: "Finish the current recording, response or model setup, then try again."
            case .failed(let message): message
            }
        }
    }
}

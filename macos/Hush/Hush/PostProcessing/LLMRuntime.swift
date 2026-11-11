import Foundation
import Combine
import OSLog

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
import MLX
import MLXLLM
import MLXVLM
import CoreImage
import MLXLMCommon
import MLXStructured
import MLXHuggingFace
import HuggingFace
#if canImport(Tokenizers)
import Tokenizers
#endif
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct HushEditStreamResult: Sendable, Equatable {
    let assistantMessage: String
    let text: String
    let outputTokenCount: Int?
}

@MainActor
protocol HushConversationalEditingSession: AnyObject {
    func prewarm()
    func edit(
        text: String,
        instruction: String,
        persona: Profile?,
        onPartialResult: @escaping @MainActor (HushEditStreamResult) -> Void
    ) async throws -> HushEditStreamResult
}

/// Lifecycle for the on-device LLM(s) used to post-process Whisper transcripts.
///
/// Providers are picked by `Settings.llmProvider`:
/// - **Apple Intelligence** - `import FoundationModels`, macOS 26+.
/// - **Qwen 3.5 2B** - fast 4-bit MLX build, ~1.6 GB.
/// - **Qwen 3.5 4B** - higher-quality 4-bit MLX build, ~3.1 GB.
///
/// Every Qwen model has an independent disk cache and download state. Users
/// can keep any combination on disk. Only one is held in RAM at a
/// time (the active provider). When the user switches active providers,
/// the previously-warm container is released.
///
/// Prompt assembly is centralized in `Profile.buildSystemPrompt(...)` so
/// all backends see the same template (XML-tagged style + creativity
/// + `<output>` envelope). Unsupported legacy thinking-mode switches are
/// never injected into Qwen 3.5 prompts.
@MainActor
final class LLMRuntime {

    static let shared = LLMRuntime()
    private init() {
        do {
            let migrated = try AIModelStorage.migrateLegacyQwenRepositories()
            if !migrated.isEmpty {
                Self.log.notice("Moved \(migrated.count) legacy Qwen model cache(s) into Hush application data")
            }
        } catch {
            Self.log.error("Could not migrate legacy Qwen model cache: \(error.localizedDescription, privacy: .public)")
        }
        refreshAppleAvailability()
        for model in QwenModel.allCases { refreshQwenDiskState(for: model) }
    }

    fileprivate static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "LLMRuntime")

    /// One Combine ping for the Settings UI / menu bar to re-render on any
    /// state change (Apple availability flipped, Qwen download progressed
    /// or finished, etc.).
    let stateChange = PassthroughSubject<Void, Never>()

    /// State can change while a SwiftUI settings row is evaluating the
    /// runtime. Publish on the next main-loop turn so observers never mutate
    /// view state from inside that update transaction.
    private func notifyStateChange() {
        DispatchQueue.main.async { [weak self] in
            self?.stateChange.send()
        }
    }

    // MARK: - Apple Intelligence

    enum AppleAvailability: Equatable, Sendable {
        case unsupportedOS
        case unavailable(reason: String)
        case available
    }

    private(set) var appleAvailability: AppleAvailability = .unsupportedOS

    func refreshAppleAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            appleAvailability = SystemLanguageModel.default.isAvailable
                ? .available
                : .unavailable(reason: "Apple Intelligence isn't enabled - turn it on in System Settings.")
        } else {
            appleAvailability = .unsupportedOS
        }
        #else
        appleAvailability = .unsupportedOS
        #endif
        notifyStateChange()
    }

    // MARK: - Qwen models (independent state)

    /// Internal handle for the Qwen variant. It centralizes each model's
    /// cache directory, expected size, and registry configuration.
    enum QwenModel: String, CaseIterable, Sendable {
        case qwen35_2b
        case qwen35_4b

        /// Maps the public `LLMProvider` enum into the internal model
        /// handle. Returns nil for non-Qwen providers.
        init?(provider: LLMProvider) {
            switch provider {
            case .qwen35_2b: self = .qwen35_2b
            case .qwen35_4b: self = .qwen35_4b
            default:         return nil
            }
        }

        // These are pure value-derived helpers with no shared
        // state, no main-actor dependency. Marked `nonisolated` so the
        // static `qwenCacheURL(for:)` and `qwenDiskSizeMB(for:)` can
        // call them under Swift 6 strict concurrency without needing a
        // main-actor hop.
        nonisolated var hfRepoFolder: String {
            switch self {
            case .qwen35_2b: return "models--mlx-community--Qwen3.5-2B-4bit"
            case .qwen35_4b: return "models--mlx-community--Qwen3.5-4B-4bit"
            }
        }

        /// Sanity threshold for "we have enough bytes on disk to consider
        /// this downloaded." Lower than the real size to allow for HF's
        /// staged-file layout. Catches partial downloads.
        nonisolated var diskCompleteThresholdMB: Int {
            switch self {
            case .qwen35_2b: return 1_100 // ~1.6 GB full
            case .qwen35_4b: return 2_200 // ~3.1 GB full
            }
        }
    }

    /// State for one Qwen variant. Per-model so the UI can show both
    /// providers' download status side by side.
    enum QwenState: Equatable, Sendable {
        case notDownloaded
        case downloading(QwenDownloadProgress)
        case downloaded
        case warm
        case failed(String)
    }

    struct QwenDownloadProgress: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case downloading
            case preparing
        }

        let phase: Phase
        let fraction: Double?
        let estimatedSecondsRemaining: TimeInterval?

        static let waiting = QwenDownloadProgress(
            phase: .downloading,
            fraction: nil,
            estimatedSecondsRemaining: nil
        )

        var statusText: String {
            if phase == .preparing {
                return "Preparing on this Mac…"
            }
            guard let fraction else {
                return "Starting download…"
            }
            let percent = min(99, max(0, Int((fraction * 100).rounded(.down))))
            guard let seconds = estimatedSecondsRemaining else {
                return "Downloading \(percent)%"
            }
            let minutes = max(1, Int(ceil(seconds / 60)))
            if minutes == 1 {
                return "Downloading \(percent)% · About 1 min left"
            }
            return "Downloading \(percent)% · About \(minutes) min left"
        }
    }

    private struct QwenDownloadSample {
        var completedBytes: Int64
        var timestamp: TimeInterval
        var smoothedBytesPerSecond: Double?
    }

    /// Per-model state. Every catalog entry exists from init so callers can
    /// read state without nil-checking.
    private var qwenStates = Dictionary(
        uniqueKeysWithValues: QwenModel.allCases.map { ($0, QwenState.notDownloaded) }
    )

    /// One container at a time - the currently-loaded model. When the
    /// user switches active Qwen variants, this is dropped so the
    /// previous variant's RAM is released.
    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    private var qwenContainer: ModelContainer?
    private var qwenContainerModel: QwenModel?
    #endif
    private var qwenDownloadTasks: [QwenModel: Task<Void, any Swift.Error>] = [:]
    private var qwenDownloadTaskIDs: [QwenModel: UUID] = [:]
    private var qwenWarmTasks: [QwenModel: Task<Void, any Swift.Error>] = [:]
    private var qwenWarmTaskIDs: [QwenModel: UUID] = [:]
    private var qwenDownloadSamples: [QwenModel: QwenDownloadSample] = [:]
    private var qwenExpectedBytes: [QwenModel: Int64] = [:]
    private var qwenUpstreamCompletedBytes: [QwenModel: Int64] = [:]
    private var qwenObservedTaskBytes: [QwenModel: Int64] = [:]

    func qwenState(for model: QwenModel) -> QwenState {
        qwenStates[model] ?? .notDownloaded
    }

    nonisolated static func qwenCacheURL(for model: QwenModel) -> URL {
        AIModelStorage.qwenHuggingFaceHubRoot
            .appendingPathComponent(model.hfRepoFolder)
    }

    #if canImport(HuggingFace)
    nonisolated static func makeQwenHubClient(session: URLSession) -> HubClient {
        HubClient(
            session: session,
            userAgent: "Hush/0.1 model-download",
            cache: HubCache(cacheDirectory: AIModelStorage.qwenHuggingFaceHubRoot)
        )
    }
    #endif

    nonisolated static func qwenDiskSizeMB(for model: QwenModel) -> Int? {
        let url = qwenCacheURL(for: model)
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                total += Int64(size)
            }
        }
        return total > 0 ? Int(total / (1024 * 1024)) : nil
    }

    /// Resolves a complete Hugging Face snapshot without contacting the Hub.
    /// The canonical `refs/main` target wins. A validated snapshot directory
    /// is used as a fallback for caches created without a ref file.
    nonisolated static func cachedQwenSnapshotURL(in repositoryRoot: URL) -> URL? {
        let fileManager = FileManager.default

        func isValidSnapshot(_ url: URL) -> Bool {
            guard fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path),
                  fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer_config.json").path),
                  let files = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) else { return false }
            return files.contains { $0.pathExtension == "safetensors" }
        }

        let refsMain = repositoryRoot.appendingPathComponent("refs/main")
        if let revision = try? String(contentsOf: refsMain, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !revision.isEmpty,
           revision.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil {
            let referenced = repositoryRoot
                .appendingPathComponent("snapshots", isDirectory: true)
                .appendingPathComponent(revision, isDirectory: true)
            if isValidSnapshot(referenced) {
                return referenced
            }
        }

        let snapshotsRoot = repositoryRoot.appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return snapshots
            .filter(isValidSnapshot)
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return left > right
            }
            .first
    }

    nonisolated static func cachedQwenSnapshotURL(for model: QwenModel) -> URL? {
        cachedQwenSnapshotURL(in: qwenCacheURL(for: model))
    }

    func refreshQwenDiskState(for model: QwenModel) {
        switch qwenStates[model] ?? .notDownloaded {
        case .downloading, .warm: return
        default: break
        }
        let mb = Self.qwenDiskSizeMB(for: model) ?? 0
        qwenStates[model] = mb > model.diskCompleteThresholdMB ? .downloaded : .notDownloaded
        notifyStateChange()
    }

    // MARK: - Combined readiness

    var isActiveProviderReady: Bool {
        isReady(provider: Settings.shared.llmProvider)
    }

    func isReady(provider: LLMProvider) -> Bool {
        switch provider {
        case .off: return true
        case .appleIntelligence: return appleAvailability == .available
        case .qwen35_2b, .qwen35_4b:
            guard let model = QwenModel(provider: provider) else { return false }
            switch qwenStates[model] ?? .notDownloaded {
            case .warm, .downloaded: return true
            default: return false
            }
        }
    }

    var isPackageInstalled: Bool {
        #if canImport(MLXLLM)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Public actions (per-model)

    func startDownloadQwen(_ model: QwenModel) {
        guard qwenDownloadTasks[model] == nil else { return }
        let taskID = UUID()
        qwenDownloadTaskIDs[model] = taskID
        qwenDownloadTasks[model] = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    guard self?.qwenDownloadTaskIDs[model] == taskID else { return }
                    self?.qwenDownloadTasks[model] = nil
                    self?.qwenDownloadTaskIDs[model] = nil
                }
            }
            try await self?.runQwenLoad(model)
        }
    }

    func cancelQwenDownload(_ model: QwenModel) {
        qwenDownloadTasks[model]?.cancel()
        qwenDownloadTasks[model] = nil
        qwenDownloadTaskIDs[model] = nil
        resetQwenDownloadTracking(for: model)
        if case .downloading = qwenStates[model] ?? .notDownloaded {
            let mb = Self.qwenDiskSizeMB(for: model) ?? 0
            qwenStates[model] = mb > model.diskCompleteThresholdMB ? .downloaded : .notDownloaded
            notifyStateChange()
        }
    }

    func deleteQwen(_ model: QwenModel) throws {
        guard qwenDownloadTasks[model] == nil, qwenWarmTasks[model] == nil else { throw Error.qwenBusy }
        let url = Self.qwenCacheURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        #if canImport(MLXLLM)
        if qwenContainerModel == model {
            qwenContainer = nil
            qwenContainerModel = nil
            Memory.clearCache()
        }
        #endif
        qwenStates[model] = .notDownloaded
        notifyStateChange()
    }

    func cancelQwenDownloadAndWait(_ model: QwenModel) async {
        guard let task = qwenDownloadTasks[model] else { return }
        task.cancel()
        _ = try? await task.value
    }

    /// Await the actual download/load task instead of polling published UI state.
    /// A cancelled setup only cancels work it started, not another caller's load.
    func downloadQwenAndWait(_ model: QwenModel) async throws {
        let owned = qwenDownloadTasks[model] == nil && qwenWarmTasks[model] == nil
        if let warm = qwenWarmTasks[model] {
            try await warm.value
        } else {
            startDownloadQwen(model)
            guard let task = qwenDownloadTasks[model] else { throw Error.qwenBusy }
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                if owned { task.cancel() }
            }
        }
        try Task.checkCancellation()
    }

    /// Hotkey-press pre-warm: kick off a load for the active Qwen variant
    /// if it's on disk but not yet in RAM. No-op for Apple Intelligence /
    /// Off / a Qwen variant that's still downloading.
    func preload() {
        preload(provider: Settings.shared.llmProvider)
    }

    func preload(provider: LLMProvider) {
        guard let model = QwenModel(provider: provider) else { return }
        guard case .downloaded = qwenStates[model] ?? .notDownloaded else { return }
        Task { try? await self.ensureQwenWarm(model) }
    }

    func makeConversationalEditingSession(provider: LLMProvider) -> any HushConversationalEditingSession {
        switch provider {
        case .off:
            return UnavailableConversationalEditingSession(error: .providerOff)
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                refreshAppleAvailability()
                switch appleAvailability {
                case .available:
                    return AppleConversationalEditingSession()
                case .unavailable(let reason):
                    return UnavailableConversationalEditingSession(error: .appleUnavailable(reason))
                case .unsupportedOS:
                    return UnavailableConversationalEditingSession(error: .appleUnsupportedOS)
                }
            }
            #endif
            return UnavailableConversationalEditingSession(error: .appleUnsupportedOS)
        case .qwen35_2b, .qwen35_4b:
            return QwenConversationalEditingSession(runtime: self, provider: provider)
        }
    }

    /// Run the active profile's prompt through the active provider.
    func generate(transcript: String, profile: Profile) async throws -> String {
        try await generate(
            transcript: transcript,
            profile: profile,
            provider: Settings.shared.llmProvider
        )
    }

    func generate(
        transcript: String,
        profile: Profile,
        provider: LLMProvider
    ) async throws -> String {
        let systemPrompt = Profile.buildSystemPrompt(for: profile)
        let userPrompt = Profile.buildUserPrompt(transcript: transcript)
        return try await generate(
            userPrompt: userPrompt,
            systemPrompt: systemPrompt,
            profile: profile,
            provider: provider
        )
    }

    /// Applies one explicit conversational edit to the complete current text.
    /// Every turn is stateless at the model layer: the editor passes the chosen
    /// version in full, which keeps results deterministic and prevents an old
    /// chat turn from silently changing a later accepted artifact.
    func generateEdit(
        text: String,
        instruction: String,
        persona: Profile?,
        provider: LLMProvider
    ) async throws -> String {
        let samplingProfile = persona ?? Profile(
            id: UUID(),
            name: "Direct edit",
            systemPrompt: "",
            creativity: 0.3
        )
        return try await generate(
            userPrompt: Profile.buildEditingUserPrompt(text: text, instruction: instruction),
            systemPrompt: Profile.buildEditingSystemPrompt(persona: persona),
            profile: samplingProfile,
            provider: provider
        )
    }

    private func generate(
        userPrompt: String,
        systemPrompt: String,
        profile: Profile,
        provider: LLMProvider
    ) async throws -> String {
        switch provider {
        case .off:
            throw Error.providerOff
        case .appleIntelligence:
            return try await generateApple(userPrompt: userPrompt, systemPrompt: systemPrompt, profile: profile)
        case .qwen35_2b, .qwen35_4b:
            guard let model = QwenModel(provider: provider) else { throw Error.providerOff }
            return try await generateQwen(model: model, userPrompt: userPrompt, systemPrompt: systemPrompt, profile: profile)
        }
    }

    // MARK: - Apple call

    private func generateApple(userPrompt: String, systemPrompt: String, profile: Profile) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            refreshAppleAvailability()
            switch appleAvailability {
            case .available:
                // Pin this provider to Apple's on-device system model. Private
                // Cloud Compute is a separate API and is never selected here.
                let session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: systemPrompt
                )
                let options = GenerationOptions(temperature: profile.creativity)
                let t0 = CFAbsoluteTimeGetCurrent()
                let response = try await session.respond(to: userPrompt, options: options)
                Self.log.info("Apple LLM \(CFAbsoluteTimeGetCurrent() - t0, format: .fixed(precision: 2))s · creativity=\(profile.creativity, format: .fixed(precision: 2))")
                return Self.extractOutput(response.content)
            case .unavailable(let reason): throw Error.appleUnavailable(reason)
            case .unsupportedOS:           throw Error.appleUnsupportedOS
            }
        } else {
            throw Error.appleUnsupportedOS
        }
        #else
        throw Error.appleUnsupportedOS
        #endif
    }

    // MARK: - Qwen call

    private func generateQwen(model: QwenModel,
                               userPrompt: String,
                               systemPrompt: String,
                               profile: Profile) async throws -> String {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
        let container = try await requireQwenContainer(model)

        let parameters = GenerateParameters(
            maxTokens: Self.editingOutputTokenBudget(for: userPrompt),
            temperature: Float(profile.creativity),
            topP: 0.95,
            topK: 20,
            minP: 0,
            repetitionPenalty: 1.0,
            presencePenalty: 1.5,
            presenceContextSize: 128
        )
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": false]
        )
        let t0 = CFAbsoluteTimeGetCurrent()
        let raw = try await session.respond(to: userPrompt)
        Self.log.info("Qwen[\(model.rawValue, privacy: .public)] \(CFAbsoluteTimeGetCurrent() - t0, format: .fixed(precision: 2))s · creativity=\(profile.creativity, format: .fixed(precision: 2))")
        return Self.extractOutput(raw)
        #else
        throw Error.notCompiled
        #endif
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    fileprivate func makeQwenConversation(
        provider: LLMProvider,
        instructions: String,
        history: [Chat.Message] = [],
        tools: [ToolSpec] = [],
        enableThinking: Bool = true
    ) async throws -> ChatSession {
        guard let model = QwenModel(provider: provider) else { throw Error.providerOff }
        let container = try await requireQwenContainer(model)
        let parameters = GenerateParameters(
            maxTokens: 1_024,
            temperature: 1.0,
            topP: 1.0,
            topK: 20,
            minP: 0,
            repetitionPenalty: 1.0,
            presencePenalty: 2.0,
            presenceContextSize: 128
        )
        if !history.isEmpty {
            return ChatSession(
                container,
                instructions: instructions,
                history: history,
                generateParameters: parameters,
                additionalContext: ["enable_thinking": enableThinking],
                tools: tools.isEmpty ? nil : tools
            )
        }
        return ChatSession(
            container,
            instructions: instructions,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": enableThinking],
            tools: tools.isEmpty ? nil : tools
        )
    }

    /// A bounded, direct JSON turn. Grammar masking applies to every generated
    /// token; the model never emits an executable tool call in this workflow.
    func generateAssistantDraft(_ brief: AssistantBrief, provider: LLMProvider) async throws -> AssistantProposal {
        guard let model = QwenModel(provider: provider) else { throw AssistantFailure.modelSetup }
        try brief.validate()
        let container = try await requireQwenContainer(model)
        return try await Self.generateAssistantDraft(brief, container: container)
    }

    func generateCoworkerReply(_ request: CoworkerRequest, provider: LLMProvider) async throws -> CoworkerReply {
        try Task.checkCancellation()
        guard let model = QwenModel(provider: provider), request.text.utf8.count <= 4_000 else {
            throw AssistantFailure.modelSetup
        }
        request.onStage?(.preparingModel)
        let container = try await requireQwenContainer(model)
        try Task.checkCancellation()
        request.onStage?(.readingContext)
        let prompt = request.prompt
        #if DEBUG
        let schema = request.evaluationSchema ?? CoworkerReply.schema(for: request)
        let instructions = request.evaluationInstructions ?? CoworkerReply.instructions(for: request.observation)
        let thinking = request.evaluationThinking
        #else
        let schema = CoworkerReply.schema(for: request)
        let instructions = CoworkerReply.instructions(for: request.observation)
        let thinking = false
        #endif
        let screenshot = request.screenshot
        #if DEBUG
        let trace = request.diagnosticTrace
        trace?.artifact(.system, text: instructions + "\nOutput schema:\n" + schema)
        trace?.artifact(.prompt, text: prompt)
        trace?.event("model.started", ["provider": provider.rawValue, "max_tokens": thinking ? "2048" : "1536", "temperature": "0", "thinking": String(thinking),
            "snapshot": Self.cachedQwenSnapshotURL(for: model)?.lastPathComponent ?? "unknown"])
        #endif
        let raw: String = try await container.perform { context in
            // A stopped turn can have waited behind another container operation.
            // Do not prepare its prompt or grammar after it acquires the container.
            try Task.checkCancellation()
            guard case .directory = context.configuration.id else { throw AssistantFailure.modelSetup }
            #if DEBUG
            let grammar: Grammar = try thinking ? CoworkerThinkingEvaluation.grammar(schema: schema) : .schema(schema, format: .init(whitespace: .none))
            #else
            // The default permits unbounded inter-field whitespace. Greedy
            // generation can spend its entire token budget producing spaces.
            // Compact JSON changes formatting only, never whitespace in strings.
            let grammar: Grammar = .schema(schema, format: .init(whitespace: .none))
            #endif
            let input = try await context.processor.prepare(input: UserInput(
                chat: [.system(instructions + "\nOutput schema:\n" + schema),
                       .user(prompt, images: screenshot.flatMap { CIImage(data: $0) }.map { [.ciImage($0)] } ?? [])],
                additionalContext: ["enable_thinking": thinking]
            ))
            try Task.checkCancellation()
            guard input.text.tokens.size <= 8_192 else { throw AssistantFailure.contextTooLarge }
            await request.onStage?(.preparingActions)
            #if DEBUG
            trace?.event("model.input_prepared", ["input_tokens": String(input.text.tokens.size)])
            #endif
            // Prepare the cached grammar explicitly so cold setup is distinguishable
            // from image/prompt prefill. generate() reuses the library's compiler cache.
            let actionPreparation = ContinuousClock.now
            _ = try await GrammarMaskedLogitProcessor.from(configuration: context.configuration, grammar: grammar)
            try Task.checkCancellation()
            #if DEBUG
            trace?.event("model.actions_prepared", ["duration": String(describing: actionPreparation.duration(to: .now))])
            #endif
            await request.onStage?(.readingContext)
            let stream = try await MLXStructured.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: thinking ? 2_048 : 1_536, temperature: 0, topP: 1,
                                               repetitionPenalty: 1, presencePenalty: 0),
                context: context, grammar: grammar
            )
            await request.onStage?(.choosingAction)
            var output = ""
            var completed = false
            #if DEBUG
            defer { if !thinking { trace?.artifact(.rawReply, text: output) } }
            #endif
            for await update in stream {
                try Task.checkCancellation()
                switch update {
                case .chunk(let chunk): output += chunk
                case .info(let info):
                    completed = info.stopReason == .stop
                    #if DEBUG
                    trace?.event("model.completed", ["stop_reason": String(describing: info.stopReason),
                        "output_tokens": String(info.generationTokenCount), "prompt_seconds": String(info.promptTime),
                        "generation_seconds": String(info.generateTime)])
                    #endif
                case .toolCall: throw CoworkerError.invalidResponse
                }
                guard output.utf8.count < 20_000 else { throw CoworkerError.invalidResponse }
            }
            guard completed else { throw CoworkerError.invalidResponse }
            #if DEBUG
            if thinking { return try await CoworkerThinkingEvaluation.finalResponse(output) }
            #endif
            return output
        }
        try Task.checkCancellation()
        #if DEBUG
        if ProcessInfo.processInfo.environment["HUSH_COWORKER_LIVE"] == "1" {
            print("[coworker-live] synthetic fixture raw reply: \(raw)")
        }
        #endif
        let decoded = try CoworkerReply.decode(raw)
        let reply = request.observation.mailDraft == nil ? decoded : CoworkerMailDraftPolicy.normalize(decoded)
        #if DEBUG
        trace?.event("model.decoded", ["action": reply.action.rawValue])
        #endif
        if let feedback = CoworkerMailDraftPolicy.feedback(for: reply, observation: request.observation) {
            guard request.validationFeedback == nil else { throw CoworkerError.invalidResponse }
            var repair = request
            repair.validationFeedback = feedback
            return try await generateCoworkerReply(repair, provider: provider)
        }
        if [.write, .revise].contains(reply.action), let maximum = request.maximumDraftCharacters, reply.content.count > maximum {
            guard request.validationFeedback == nil else { throw CoworkerError.invalidResponse }
            var repair = request
            repair.validationFeedback = "The previous attempt was too long. Write a revised draft of at most \(maximum) characters, preserving the supplied names and meeting details. Return the full response schema."
            return try await generateCoworkerReply(repair, provider: provider)
        }
        return reply
    }

    /// Shared with the opt-in native model conformance test. Callers supply a
    /// local container; this method has no download or provider fallback path.
    static func generateAssistantDraft(_ brief: AssistantBrief, container: ModelContainer) async throws -> AssistantProposal {
        try brief.validate()
        let prompt = brief.prompt
        let raw: String = try await container.perform { context in
            // Require the already resolved local snapshot. The grammar compiler's
            // tokenizer loader must not make a Hub request during a local turn.
            guard case .directory = context.configuration.id else { throw AssistantFailure.modelSetup }
            let input = try await context.processor.prepare(input: UserInput(
                chat: [.system(AssistantProposal.instructions + "\nOutput schema:\n" + AssistantProposal.schema), .user(prompt)],
                additionalContext: ["enable_thinking": false]
            ))
            guard input.text.tokens.size <= 4_096 else { throw AssistantFailure.contextTooLarge }
            let stream = try await MLXStructured.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 1_024, temperature: 0, topP: 1,
                                               repetitionPenalty: 1, presencePenalty: 0),
                context: context,
                grammar: .schema(AssistantProposal.schema)
            )
            var output = ""
            var completed = false
            for await update in stream {
                try Task.checkCancellation()
                switch update {
                case .chunk(let chunk): output += chunk
                case .info(let info): completed = info.stopReason == .stop
                case .toolCall: throw AssistantFailure.invalidProposal
                }
                guard output.utf8.count <= 24_000 else { throw AssistantFailure.invalidProposal }
            }
            guard completed else { throw AssistantFailure.invalidProposal }
            return output
        }
        try Task.checkCancellation()
        return try AssistantProposal.decode(raw, completed: true)
    }

    private func requireQwenContainer(_ model: QwenModel) async throws -> ModelContainer {
        switch qwenStates[model] ?? .notDownloaded {
        case .warm where qwenContainerModel == model:
            break
        case .warm:
            qwenContainer = nil
            qwenContainerModel = nil
            Memory.clearCache()
            try await ensureQwenWarm(model)
        case .downloaded:
            try await ensureQwenWarm(model)
        case .notDownloaded:
            throw Error.qwenNotDownloaded
        case .downloading:
            if let warmTask = qwenWarmTasks[model] {
                try await warmTask.value
            } else if let downloadTask = qwenDownloadTasks[model] {
                try await downloadTask.value
            } else {
                throw Error.qwenBusy
            }
        case .failed(let message):
            throw Error.qwenLoadFailed(message)
        }
        guard let container = qwenContainer, qwenContainerModel == model else {
            throw Error.qwenBusy
        }
        return container
    }
    #endif

    // MARK: - Qwen load (shared download + warm path, per model)

    private func ensureQwenWarm(_ model: QwenModel) async throws {
        if case .warm = qwenStates[model] ?? .notDownloaded,
           qwenContainerModel == model,
           qwenContainer != nil {
            return
        }
        if let existing = qwenWarmTasks[model] {
            try await existing.value
            return
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.runQwenLoad(model)
        }
        qwenWarmTaskIDs[model] = taskID
        qwenWarmTasks[model] = task
        defer {
            if qwenWarmTaskIDs[model] == taskID {
                qwenWarmTasks[model] = nil
                qwenWarmTaskIDs[model] = nil
            }
        }
        try await task.value
    }

    private func runQwenLoad(_ model: QwenModel) async throws {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
        Memory.cacheLimit = 256 * 1024 * 1024

        // If a DIFFERENT Qwen is warm, release it first so the new one can
        // claim the GPU buffer cache. macOS handles paging normally for
        // the on-disk files of the deactivated variant.
        if qwenContainerModel != nil, qwenContainerModel != model {
            qwenContainer = nil
            qwenContainerModel = nil
            Memory.clearCache()
        }

        if case .warm = qwenStates[model] ?? .notDownloaded, qwenContainerModel == model { return }

        resetQwenDownloadTracking(for: model)
        let cachedSnapshot = Self.cachedQwenSnapshotURL(for: model)
        qwenStates[model] = .downloading(
            cachedSnapshot == nil
                ? .waiting
                : QwenDownloadProgress(
                    phase: .preparing,
                    fraction: nil,
                    estimatedSecondsRemaining: nil
                )
        )
        notifyStateChange()

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let container: ModelContainer
            let source: String
            if let cachedSnapshot {
                source = "cached-snapshot"
                Self.log.notice("Qwen[\(model.rawValue, privacy: .public)] loading directly from cached snapshot")
                container = try await VLMModelFactory.shared.loadContainer(
                    from: cachedSnapshot,
                    using: #huggingFaceTokenizerLoader()
                )
            } else {
                source = "hugging-face-hub"
                let downloadSession = URLSession(configuration: .default)
                let hubClient = Self.makeQwenHubClient(session: downloadSession)
                let taskMonitor = Task { [weak self] in
                    while !Task.isCancelled {
                        let tasks = await downloadSession.allTasks
                        let receivedBytes = tasks.reduce(Int64(0)) { total, task in
                            total + max(0, task.countOfBytesReceived)
                        }
                        self?.updateObservedTaskBytes(receivedBytes, for: model)
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer {
                    taskMonitor.cancel()
                    downloadSession.invalidateAndCancel()
                }
                container = try await VLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(hubClient),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: registryConfiguration(for: model),
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.updateDownloadProgress(progress, for: model)
                        }
                    }
                )
            }
            qwenContainer = container
            qwenContainerModel = model
            await primeQwenContainer(container, model: model)
            Self.log.notice("Qwen[\(model.rawValue, privacy: .public)] ready in \(CFAbsoluteTimeGetCurrent() - t0, format: .fixed(precision: 2))s · source=\(source, privacy: .public) · \(Self.qwenDiskSizeMB(for: model) ?? 0) MB on disk")
            resetQwenDownloadTracking(for: model)
            qwenStates[model] = .warm
            notifyStateChange()
        } catch is CancellationError {
            resetQwenDownloadTracking(for: model)
            let mb = Self.qwenDiskSizeMB(for: model) ?? 0
            qwenStates[model] = mb > model.diskCompleteThresholdMB ? .downloaded : .notDownloaded
            notifyStateChange()
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                resetQwenDownloadTracking(for: model)
                let mb = Self.qwenDiskSizeMB(for: model) ?? 0
                qwenStates[model] = mb > model.diskCompleteThresholdMB ? .downloaded : .notDownloaded
                notifyStateChange()
                throw CancellationError()
            }
            let msg = error.localizedDescription
            Self.log.error("Qwen[\(model.rawValue, privacy: .public)] load failed: \(msg, privacy: .public)")
            resetQwenDownloadTracking(for: model)
            qwenStates[model] = .failed(msg)
            notifyStateChange()
            throw Error.qwenLoadFailed(msg)
        }
        #else
        throw Error.notCompiled
        #endif
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    private func primeQwenContainer(_ container: ModelContainer, model: QwenModel) async {
        let parameters = GenerateParameters(maxTokens: 1, temperature: 0)
        let session = ChatSession(container, generateParameters: parameters)
        let startedAt = CFAbsoluteTimeGetCurrent()
        do {
            for try await _ in session.streamDetails(to: "Reply with OK.") {}
            Self.log.info("Qwen[\(model.rawValue, privacy: .public)] first-generation warm-up \(CFAbsoluteTimeGetCurrent() - startedAt, format: .fixed(precision: 2))s")
        } catch {
            Self.log.warning("Qwen[\(model.rawValue, privacy: .public)] warm-up skipped after error: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    private func updateDownloadProgress(_ progress: Progress, for model: QwenModel) {
        guard case .downloading = qwenStates[model] ?? .notDownloaded else { return }

        let total = progress.totalUnitCount
        guard total > 0 else { return }
        qwenExpectedBytes[model] = max(qwenExpectedBytes[model] ?? 0, total)
        qwenUpstreamCompletedBytes[model] = max(
            qwenUpstreamCompletedBytes[model] ?? 0,
            progress.completedUnitCount
        )
        publishDownloadProgress(for: model)
    }

    private func updateObservedTaskBytes(_ receivedBytes: Int64, for model: QwenModel) {
        guard case .downloading = qwenStates[model] ?? .notDownloaded else { return }
        qwenObservedTaskBytes[model] = max(qwenObservedTaskBytes[model] ?? 0, receivedBytes)
        publishDownloadProgress(for: model)
    }

    private func publishDownloadProgress(for model: QwenModel) {
        guard case .downloading = qwenStates[model] ?? .notDownloaded,
              let total = qwenExpectedBytes[model], total > 0 else { return }

        let completed = min(
            total,
            max(
                qwenUpstreamCompletedBytes[model] ?? 0,
                qwenObservedTaskBytes[model] ?? 0
            )
        )

        let measuredFraction = min(1, max(0, Double(completed) / Double(total)))
        let fraction = floor(measuredFraction * 1_000) / 1_000
        let now = ProcessInfo.processInfo.systemUptime
        var sample = qwenDownloadSamples[model] ?? QwenDownloadSample(
            completedBytes: completed,
            timestamp: now,
            smoothedBytesPerSecond: nil
        )

        if completed < sample.completedBytes {
            sample = QwenDownloadSample(
                completedBytes: completed,
                timestamp: now,
                smoothedBytesPerSecond: nil
            )
        } else {
            let elapsed = now - sample.timestamp
            let transferred = completed - sample.completedBytes
            if elapsed >= 0.4, transferred > 0 {
                let currentSpeed = Double(transferred) / elapsed
                sample.smoothedBytesPerSecond = sample.smoothedBytesPerSecond.map {
                    ($0 * 0.72) + (currentSpeed * 0.28)
                } ?? currentSpeed
                sample.completedBytes = completed
                sample.timestamp = now
            }
        }
        qwenDownloadSamples[model] = sample

        let phase: QwenDownloadProgress.Phase = measuredFraction >= 0.999 ? .preparing : .downloading
        let remainingSeconds: TimeInterval? = {
            guard phase == .downloading,
                  let speed = sample.smoothedBytesPerSecond,
                  speed > 1_024 else { return nil }
            let estimate = Double(max(0, total - completed)) / speed
            return ceil(estimate / 5) * 5
        }()
        let next = QwenDownloadProgress(
            phase: phase,
            fraction: phase == .downloading ? fraction : nil,
            estimatedSecondsRemaining: remainingSeconds
        )
        guard qwenStates[model] != .downloading(next) else { return }
        qwenStates[model] = .downloading(next)
        notifyStateChange()
    }

    private func resetQwenDownloadTracking(for model: QwenModel) {
        qwenDownloadSamples[model] = nil
        qwenExpectedBytes[model] = nil
        qwenUpstreamCompletedBytes[model] = nil
        qwenObservedTaskBytes[model] = nil
    }

    private func registryConfiguration(for model: QwenModel) -> ModelConfiguration {
        switch model {
        case .qwen35_2b:
            return LLMRegistry.qwen3_5_2b_4bit
        case .qwen35_4b:
            return ModelConfiguration(
                id: "mlx-community/Qwen3.5-4B-4bit",
                defaultPrompt: "Why is the sky blue?",
                extraEOSTokens: ["<|im_end|>"]
            )
        }
    }
    #endif

    // MARK: - Output extraction

    /// Strip the `<output>...</output>` envelope our system prompt asks
    /// the model to wrap its answer in. Falls back to the raw (trimmed)
    /// response when the tags are missing. Also strips any leftover
    /// `<think>...</think>` block defensively.
    nonisolated static func extractOutput(_ raw: String) -> String {
        var s = raw

        // Remove a leading <think>...</think> if a provider emits one.
        if let range = s.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            s.removeSubrange(range)
        }

        // Pull out <output>…</output> if present.
        if let openRange = s.range(of: "<output>", options: .caseInsensitive) {
            if let closeRange = s.range(of: "</output>", options: [.backwards, .caseInsensitive]),
               openRange.upperBound <= closeRange.lowerBound {
                s = String(s[openRange.upperBound..<closeRange.lowerBound])
            } else {
                // Plain post-processing should never expose protocol markup,
                // even when a provider stops before emitting the closing tag.
                s = String(s[openRange.upperBound...])
            }
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts a partial provider response into only the editable artifact.
    /// The opening XML envelope is withheld instead of flashing into the UI.
    nonisolated static func extractStreamingOutput(_ raw: String) -> String {
        var value = raw
        if let thinkRange = value.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            value.removeSubrange(thinkRange)
        }
        if let open = value.range(of: "<output>") {
            value = String(value[open.upperBound...])
        } else if value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            return ""
        }
        if let close = value.range(of: "</output>") {
            value = String(value[..<close.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func extractStreamingEdit(_ raw: String) -> HushEditStreamResult {
        HushEditStreamResult(
            assistantMessage: partialTaggedContent(in: raw, tag: "message"),
            text: streamingArtifactContent(in: raw),
            outputTokenCount: nil
        )
    }

    nonisolated static func extractCompletedEdit(
        _ raw: String,
        outputTokenCount: Int?,
        instruction: String? = nil
    ) -> HushEditStreamResult {
        let message = partialTaggedContent(in: raw, tag: "message")
        let text = completedArtifactContent(in: raw)
        return HushEditStreamResult(
            assistantMessage: message.isEmpty
                ? fallbackAssistantMessage(for: instruction, createdArtifact: !text.isEmpty)
                : message,
            text: text,
            outputTokenCount: outputTokenCount
        )
    }

    /// A conversational response is complete only when every protocol tag the
    /// provider started was also closed. This prevents token-limit truncation
    /// from becoming an editable artifact or poisoning the next chat turn.
    nonisolated static func completedEditResponseIsWellFormed(_ raw: String) -> Bool {
        ["message", "output"].allSatisfy { tag in
            let opening = raw.range(of: "<\(tag)>", options: .caseInsensitive)
            let closing = raw.range(of: "</\(tag)>", options: [.backwards, .caseInsensitive])
            switch (opening, closing) {
            case (nil, nil):
                return true
            case (.some(let open), .some(let close)):
                return open.upperBound <= close.lowerBound
            default:
                return false
            }
        }
    }

    /// Translation and full-document rewriting need room proportional to the
    /// source. A fixed 512-token ceiling truncated ordinary multi-paragraph
    /// messages, so the budget scales up without changing short-edit latency.
    nonisolated static func editingOutputTokenBudget(for text: String) -> Int {
        let estimatedInputTokens = max(
            text.utf8.count / 3,
            text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count * 2
        )
        return min(4_096, max(1_024, estimatedInputTokens + 512))
    }

    private nonisolated static func streamingArtifactContent(in raw: String) -> String {
        if raw.range(of: "<output>") != nil {
            return partialTaggedContent(in: raw, tag: "output")
        }
        if let messageEnd = raw.range(of: "</message>") {
            return stripProtocolTags(String(raw[messageEnd.upperBound...]))
        }
        if raw.range(of: "<message>") != nil {
            return ""
        }
        return extractStreamingOutput(raw)
    }

    private nonisolated static func completedArtifactContent(in raw: String) -> String {
        if raw.range(of: "<output>", options: .caseInsensitive) != nil {
            guard completedEditResponseIsWellFormed(raw) else { return "" }
            return extractOutput(raw)
        }
        if let messageEnd = raw.range(of: "</message>") {
            return stripProtocolTags(String(raw[messageEnd.upperBound...]))
        }
        return stripProtocolTags(extractOutput(raw))
    }

    private nonisolated static func stripProtocolTags(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: "</?(?:message|output|think)>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func fallbackAssistantMessage(
        for instruction: String?,
        createdArtifact: Bool
    ) -> String {
        guard createdArtifact else {
            return "I could not finish that response. Please try again."
        }
        let request = instruction?.lowercased() ?? ""
        if request.contains("translat") || request.contains("übersetz") {
            return "I translated the text into the requested language."
        }
        if request.contains("short") || request.contains("kürz") {
            return "I shortened the text while preserving its meaning."
        }
        if request.contains("tone") || request.contains("friendly") || request.contains("formal") {
            return "I adjusted the tone and created a new version."
        }
        return "I created a new version based on your request."
    }

    private nonisolated static func partialTaggedContent(in raw: String, tag: String) -> String {
        let opening = "<\(tag)>"
        let closing = "</\(tag)>"
        guard let openRange = raw.range(of: opening) else { return "" }
        var content = String(raw[openRange.upperBound...])
        if let closeRange = content.range(of: closing) {
            content = String(content[..<closeRange.lowerBound])
        } else if let nextTag = content.range(of: "<", options: .backwards),
                  content[nextTag.lowerBound...].contains(">") == false {
            content = String(content[..<nextTag.lowerBound])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case providerOff
        case notCompiled
        case appleUnsupportedOS
        case appleUnavailable(String)
        case qwenNotDownloaded
        case qwenBusy
        case qwenLoadFailed(String)
        case incompleteResponse

        var errorDescription: String? {
            switch self {
            case .providerOff:              return "AI post-processing is off."
            case .notCompiled:              return "MLX-Swift isn't installed."
            case .appleUnsupportedOS:       return "Apple Intelligence needs macOS 26 or later."
            case .appleUnavailable(let r):  return r
            case .qwenNotDownloaded:        return "Download the Qwen model in Settings."
            case .qwenBusy:                 return "AI model is loading - try again in a moment."
            case .qwenLoadFailed(let m):    return "AI model failed to load: \(m)"
            case .incompleteResponse:       return "The local AI stopped before finishing this version. Your current text has not changed. Please try again."
            }
        }
    }
}

@MainActor
private final class UnavailableConversationalEditingSession: HushConversationalEditingSession {
    private let error: LLMRuntime.Error

    init(error: LLMRuntime.Error) {
        self.error = error
    }

    func prewarm() {}

    func edit(
        text: String,
        instruction: String,
        persona: Profile?,
        onPartialResult: @escaping @MainActor (HushEditStreamResult) -> Void
    ) async throws -> HushEditStreamResult {
        throw error
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@MainActor
private final class AppleConversationalEditingSession: HushConversationalEditingSession {
    private let session = LanguageModelSession(
        model: SystemLanguageModel.default,
        instructions: Profile.buildEditingConversationSystemPrompt()
    )

    func prewarm() {
        session.prewarm()
    }

    func edit(
        text: String,
        instruction: String,
        persona: Profile?,
        onPartialResult: @escaping @MainActor (HushEditStreamResult) -> Void
    ) async throws -> HushEditStreamResult {
        let prompt = Profile.buildEditingConversationTurnPrompt(
            text: text,
            instruction: instruction,
            persona: persona
        )
        let requiresArtifact = Profile.editingRequestRequiresArtifact(instruction)
        let options = GenerationOptions(temperature: persona?.creativity ?? 0.3)
        var raw = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            try Task.checkCancellation()
            raw = snapshot.content
            let partial = LLMRuntime.extractStreamingEdit(raw)
            if !partial.assistantMessage.isEmpty || !partial.text.isEmpty {
                onPartialResult(partial)
            }
        }
        let parsed = LLMRuntime.extractCompletedEdit(
            raw,
            outputTokenCount: nil,
            instruction: instruction
        )
        guard LLMRuntime.completedEditResponseIsWellFormed(raw),
              !requiresArtifact || !parsed.text.isEmpty else {
            throw LLMRuntime.Error.incompleteResponse
        }
        return parsed
    }
}
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
private struct QwenCreatedArtifact: Sendable {
    let summary: String
    let text: String
}

private enum QwenTurnIntent: String, Sendable {
    case conversation
    case artifact
}

private enum QwenArtifactToolError: LocalizedError {
    case wrongTool(String)
    case duplicateCall
    case missingArgument(String)
    case protocolMarkup

    var errorDescription: String? {
        switch self {
        case .wrongTool(let name): return "Unexpected tool call: \(name)"
        case .duplicateCall: return "create_artifact may only be called once per turn"
        case .missingArgument(let name): return "Missing create_artifact argument: \(name)"
        case .protocolMarkup: return "Artifact arguments must not contain protocol or reasoning tags"
        }
    }
}

private actor QwenArtifactCapture {
    private var artifact: QwenCreatedArtifact?

    func dispatch(_ call: ToolCall) throws -> String {
        guard call.function.name == "create_artifact" else {
            throw QwenArtifactToolError.wrongTool(call.function.name)
        }
        guard case nil = artifact else { throw QwenArtifactToolError.duplicateCall }
        guard case .string(let summary)? = call.function.arguments["summary"],
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwenArtifactToolError.missingArgument("summary")
        }
        guard case .string(let text)? = call.function.arguments["text"],
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwenArtifactToolError.missingArgument("text")
        }
        let blockedTags = ["<think", "</think", "<output", "</output", "<message", "</message", "<tool_call"]
        guard !blockedTags.contains(where: { summary.localizedCaseInsensitiveContains($0) }),
              !blockedTags.contains(where: { text.localizedCaseInsensitiveContains($0) }) else {
            throw QwenArtifactToolError.protocolMarkup
        }
        artifact = QwenCreatedArtifact(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return "The artifact is now visible to the user. Reply with one concise sentence describing the completed change. Do not repeat the artifact."
    }

    func value() -> QwenCreatedArtifact? { artifact }
}

private let qwenCreateArtifactTool: ToolSpec = [
    "type": "function",
    "function": [
        "name": "create_artifact",
        "description": "Create a complete revised version of the current text. Use when the user requests a concrete text change, including a politely phrased question such as 'Could you rewrite this?'. Do not use for advice or discussion.",
        "parameters": [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "One brief past-tense sentence describing the completed change."
                ] as [String: any Sendable],
                "text": [
                    "type": "string",
                    "description": "The complete finished revision only, with no commentary, reasoning, or protocol tags."
                ] as [String: any Sendable]
            ] as [String: any Sendable],
            "required": ["summary", "text"],
            "additionalProperties": false
        ] as [String: any Sendable]
    ] as [String: any Sendable]
]

private let qwenRouteTurnTool: ToolSpec = [
    "type": "function",
    "function": [
        "name": "route_turn",
        "description": "Choose whether this turn is conversation or requires a complete revised artifact.",
        "parameters": [
            "type": "object",
            "properties": [
                "mode": [
                    "type": "string",
                    "enum": ["conversation", "artifact"],
                    "description": "artifact only for an explicit request to create or change usable text; otherwise conversation."
                ] as [String: any Sendable]
            ] as [String: any Sendable],
            "required": ["mode"],
            "additionalProperties": false
        ] as [String: any Sendable]
    ] as [String: any Sendable]
]
#endif

@MainActor
private final class QwenConversationalEditingSession: HushConversationalEditingSession {
    private unowned let runtime: LLMRuntime
    private let provider: LLMProvider
    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    private var session: ChatSession?
    private var successfulHistory: [Chat.Message] = []
    private var conversationPersona: Profile?
    private var hasResolvedConversationPersona = false
    #endif

    init(runtime: LLMRuntime, provider: LLMProvider) {
        self.runtime = runtime
        self.provider = provider
    }

    func prewarm() {
        runtime.preload(provider: provider)
    }

    func edit(
        text: String,
        instruction: String,
        persona: Profile?,
        onPartialResult: @escaping @MainActor (HushEditStreamResult) -> Void
    ) async throws -> HushEditStreamResult {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
        let prompt = Profile.buildEditingAgentTurnPrompt(text: text, instruction: instruction)
        let baseBudget = LLMRuntime.editingOutputTokenBudget(for: text)

        if !hasResolvedConversationPersona {
            conversationPersona = persona
            hasResolvedConversationPersona = true
        }

        let intent = try await classifyTurn(prompt)
        let routedPrompt = "<hush_response_mode>\(intent.rawValue)</hush_response_mode>\n" + prompt

        func makeSession(enableThinking: Bool) async throws -> ChatSession {
            if let session { return session }
            let created = try await runtime.makeQwenConversation(
                provider: provider,
                instructions: Profile.buildEditingAgentSystemPrompt(persona: conversationPersona),
                history: successfulHistory,
                tools: [qwenCreateArtifactTool],
                enableThinking: enableThinking
            )
            session = created
            return created
        }

        func generate(
            using conversation: ChatSession,
            maxTokens: Int,
            enableThinking: Bool,
            intent: QwenTurnIntent
        ) async throws -> HushEditStreamResult {
            let capture = QwenArtifactCapture()
            conversation.toolDispatch = nil
            conversation.tools = intent == .artifact ? [qwenCreateArtifactTool] : nil
            conversation.generateParameters = GenerateParameters(
                maxTokens: maxTokens,
                temperature: enableThinking ? 1.0 : 0.7,
                topP: enableThinking ? 0.95 : 0.8,
                topK: 20,
                minP: 0,
                repetitionPenalty: 1.0,
                presencePenalty: 1.5,
                presenceContextSize: 128
            )
            conversation.additionalContext = ["enable_thinking": enableThinking]
            var passRaw = ""
            var visibleReply = ""
            var outputTokens = 0
            var completionInfo: GenerateCompletionInfo?
            var toolCalls: [ToolCall] = []
            let startedAt = CFAbsoluteTimeGetCurrent()
            var firstChunkAt: CFAbsoluteTime?
            var waitingForReasoningClose = enableThinking
            for try await update in conversation.streamDetails(to: routedPrompt) {
                try Task.checkCancellation()
                switch update {
                case .chunk(let chunk):
                    if firstChunkAt == nil, !chunk.isEmpty {
                        firstChunkAt = CFAbsoluteTimeGetCurrent()
                    }
                    passRaw += chunk
                    if waitingForReasoningClose {
                        if let close = passRaw.range(of: "</think>", options: .caseInsensitive) {
                            waitingForReasoningClose = false
                            visibleReply = String(passRaw[close.upperBound...])
                        }
                    } else {
                        visibleReply = passRaw
                    }
                    let partial = HushEditStreamResult(
                        assistantMessage: visibleReply.trimmingCharacters(in: .whitespacesAndNewlines),
                        text: "",
                        outputTokenCount: outputTokens == 0 ? nil : outputTokens
                    )
                    if !partial.assistantMessage.isEmpty || !partial.text.isEmpty {
                        onPartialResult(partial)
                    }
                case .info(let info):
                    outputTokens += info.generationTokenCount
                    completionInfo = info
                    passRaw = ""
                    waitingForReasoningClose = enableThinking
                case .toolCall(let call):
                    toolCalls.append(call)
                }
            }
            if let info = completionInfo {
                let firstTokenSeconds = firstChunkAt.map { $0 - startedAt } ?? 0
                let model = LLMRuntime.QwenModel(provider: provider)?.rawValue ?? "unknown"
                LLMRuntime.log.info("Qwen[\(model, privacy: .public)] conversation · first chunk \(firstTokenSeconds, format: .fixed(precision: 2))s · prefill \(info.promptTokenCount) tok / \(info.promptTime, format: .fixed(precision: 2))s / \(info.promptTokensPerSecond, format: .fixed(precision: 1)) tok/s · decode \(info.generationTokenCount) tok / \(info.generateTime, format: .fixed(precision: 2))s / \(info.tokensPerSecond, format: .fixed(precision: 1)) tok/s · limit=\(maxTokens)")
            }
            for call in toolCalls {
                _ = try await capture.dispatch(call)
            }
            let artifact = await capture.value()
            if intent == .artifact, artifact == nil {
                throw LLMRuntime.Error.incompleteResponse
            }

            // MLX Swift LM's automatic dispatcher currently restarts Qwen 3.5
            // with only the tool result, which its template rejects because the
            // original user query is absent. Rehydrate one structured follow-up
            // containing the complete user, tool-call, and tool-result history.
            // This also ensures the user always receives a natural assistant
            // message after the artifact is created.
            if let artifact, let call = toolCalls.first {
                onPartialResult(HushEditStreamResult(
                    assistantMessage: artifact.summary,
                    text: artifact.text,
                    outputTokenCount: outputTokens == 0 ? nil : outputTokens
                ))
                await conversation.clear()
                let followUpHistory = successfulHistory + [
                    .user(routedPrompt),
                    .assistant("", toolCalls: [call]),
                    .tool(
                        "The artifact is visible to the user. Reply with one concise sentence describing the completed change. Do not repeat the artifact.",
                        id: call.id
                    )
                ]
                let followUp = try await runtime.makeQwenConversation(
                    provider: provider,
                    instructions: Profile.buildEditingAgentSystemPrompt(persona: conversationPersona),
                    history: followUpHistory,
                    enableThinking: enableThinking
                )
                followUp.generateParameters = conversation.generateParameters
                passRaw = ""
                visibleReply = ""
                waitingForReasoningClose = enableThinking
                for try await update in followUp.streamDetails(to: []) {
                    try Task.checkCancellation()
                    switch update {
                    case .chunk(let chunk):
                        passRaw += chunk
                        if waitingForReasoningClose {
                            if let close = passRaw.range(of: "</think>", options: .caseInsensitive) {
                                waitingForReasoningClose = false
                                visibleReply = String(passRaw[close.upperBound...])
                            }
                        } else {
                            visibleReply = passRaw
                        }
                        let partialReply = visibleReply.trimmingCharacters(in: .whitespacesAndNewlines)
                        onPartialResult(HushEditStreamResult(
                            assistantMessage: partialReply.isEmpty ? artifact.summary : partialReply,
                            text: artifact.text,
                            outputTokenCount: outputTokens == 0 ? nil : outputTokens
                        ))
                    case .info(let info):
                        outputTokens += info.generationTokenCount
                    case .toolCall:
                        throw LLMRuntime.Error.incompleteResponse
                    }
                }
                followUp.tools = [qwenCreateArtifactTool]
                session = followUp
            }

            let cleanReply = visibleReply.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistantMessage = cleanReply.isEmpty ? (artifact?.summary ?? "") : cleanReply
            let blockedTags = ["<think", "</think", "<tool_call", "<output", "<message"]
            guard !assistantMessage.isEmpty,
                  !blockedTags.contains(where: { assistantMessage.localizedCaseInsensitiveContains($0) }) else {
                throw LLMRuntime.Error.incompleteResponse
            }
            let result = HushEditStreamResult(
                assistantMessage: assistantMessage,
                text: artifact?.text ?? "",
                outputTokenCount: outputTokens == 0 ? nil : outputTokens
            )
            onPartialResult(result)
            return result
        }

        let usesBoundedThinking = intent == .conversation
        var conversation = try await makeSession(enableThinking: usesBoundedThinking)
        let result: HushEditStreamResult
        do {
            result = try await generate(
                using: conversation,
                maxTokens: usesBoundedThinking ? min(baseBudget, 256) : baseBudget,
                enableThinking: usesBoundedThinking,
                intent: intent
            )
        } catch {
            // Qwen 3.5 can spend an entire small-model budget in a thinking
            // loop. Rebuild from clean, visible history and retry once without
            // private reasoning. The broken turn never enters the next KV cache.
            await conversation.clear()
            session = nil
            conversation = try await makeSession(enableThinking: false)
            result = try await generate(
                using: conversation,
                maxTokens: min(4_096, max(baseBudget + 512, baseBudget * 2)),
                enableThinking: false,
                intent: intent
            )
        }
        successfulHistory.append(.user(routedPrompt))
        successfulHistory.append(.assistant(result.assistantMessage))
        return result
        #else
        throw LLMRuntime.Error.notCompiled
        #endif
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
    private func classifyTurn(_ prompt: String) async throws -> QwenTurnIntent {
        let router = try await runtime.makeQwenConversation(
            provider: provider,
            instructions: """
            Route this writing-assistant turn. You must call route_turn exactly once and output nothing else.
            Choose artifact when the user explicitly asks for a complete usable creation or a direct change such as rewriting, translating, shortening, adding, removing, or correcting text. A polite question that requests the action is still artifact.
            Choose conversation for advice, questions about the text, critique, brainstorming, explanations, acknowledgements, thanks, or ordinary discussion.
            Decide from meaning in any language, not punctuation or a keyword list.
            """,
            tools: [qwenRouteTurnTool],
            enableThinking: false
        )
        router.generateParameters = GenerateParameters(
            maxTokens: 48,
            temperature: 0.1,
            topP: 0.9,
            topK: 20,
            minP: 0,
            repetitionPenalty: 1.0,
            presencePenalty: 0,
            presenceContextSize: 64
        )
        var routedIntent: QwenTurnIntent?
        for try await update in router.streamDetails(to: prompt) {
            try Task.checkCancellation()
            guard case .toolCall(let call) = update else { continue }
            guard call.function.name == "route_turn",
                  case .string(let mode)? = call.function.arguments["mode"],
                  let intent = QwenTurnIntent(rawValue: mode) else {
                throw LLMRuntime.Error.incompleteResponse
            }
            guard routedIntent == nil else { throw LLMRuntime.Error.incompleteResponse }
            routedIntent = intent
        }
        await router.clear()
        guard let routedIntent else { throw LLMRuntime.Error.incompleteResponse }
        return routedIntent
    }
    #endif
}

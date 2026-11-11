import AppKit
import Combine
import SwiftUI

struct TranscriptionModelLoadingPresentation: Equatable {
    let label: String
    let toolTip: String

    static func make(modelName: String, progress: Double, isLocal: Bool) -> Self {
        let percent = min(100, max(0, Int((progress * 100).rounded())))
        let verb = isLocal ? "Preparing" : "Downloading"
        return Self(
            label: "\(verb) \(percent)%",
            toolTip: isLocal
                ? "Loading \(modelName) from this Mac"
                : "Downloading \(modelName) to this Mac"
        )
    }
}

/// Groups an engine's models into the sections shown on its page.
///
/// Whisper has dozens of variants, so it is grouped by size into Fast, Balanced and
/// Most accurate, newest release first. Parakeet is a short curated list.
enum TranscriptionModelGrouping {
    enum LanguageFilter: Int, CaseIterable, Identifiable {
        case all, multilingual, englishOnly

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .multilingual: return "Multilingual"
            case .englishOnly: return "English Only"
            }
        }

        func includes(_ model: ModelInfo) -> Bool {
            switch self {
            case .all: return true
            case .multilingual: return model.multilingual
            case .englishOnly: return !model.multilingual
            }
        }
    }

    struct Section: Equatable, Identifiable {
        let title: String
        let detail: String
        let models: [ModelInfo]
        var id: String { title }
    }

    @MainActor
    static func sections(
        for engine: SpeechEngine,
        in catalog: [ModelInfo],
        filter: LanguageFilter = .all
    ) -> [Section] {
        let models = catalog.filter { $0.engine == engine && filter.includes($0) }
        guard engine == .whisperKit else {
            return models.isEmpty ? [] : [Section(title: "Models", detail: "", models: models)]
        }
        let ordered = models.sorted { lhs, rhs in
            let l = lhs.releaseDate ?? .distantPast
            let r = rhs.releaseDate ?? .distantPast
            if l != r { return l > r }
            return (lhs.approximateSizeMB ?? .max) < (rhs.approximateSizeMB ?? .max)
        }
        let groups: [(String, String, (Int) -> Bool)] = [
            ("Fast", "Under 300 MB. Quick to download, lower accuracy.", { $0 < 300 }),
            ("Balanced", "300 MB to 1 GB.", { $0 >= 300 && $0 < 1024 }),
            ("Most accurate", "Over 1 GB. Slower to load.", { $0 >= 1024 }),
        ]
        var sections = groups.compactMap { title, detail, matches -> Section? in
            let members = ordered.filter { $0.approximateSizeMB.map(matches) ?? false }
            return members.isEmpty ? nil : Section(title: title, detail: detail, models: members)
        }
        let unsized = ordered.filter { $0.approximateSizeMB == nil }
        if !unsized.isEmpty {
            sections.append(Section(title: "Size unknown", detail: "Waiting for the catalog.", models: unsized))
        }
        return sections
    }
}

enum ActiveModelStatus: Equatable {
    case ready
    case preparing(progress: Double, isDownloading: Bool)
    case failed(message: String)
    case idle

    @MainActor
    static func current(coordinator: DictationCoordinator?, modelID: String) -> Self {
        if coordinator?.isModelReady == true, coordinator?.loadedModelID == modelID { return .ready }
        switch coordinator?.phase.value {
        case .modelLoading(let progress)?:
            return .preparing(progress: progress, isDownloading: !ModelManager.isAvailable(modelID))
        case .error(let message)?:
            return .failed(message: message)
        default:
            return coordinator?.isModelReady == true ? .ready : .idle
        }
    }
}

/// What a model row shows, derived from the catalog, downloads and the coordinator.
enum ModelRowState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case preparing(progress: Double, isDownloading: Bool)
    case active
    case failed(message: String)

    static func make(
        modelID: String,
        activeID: String,
        activeStatus: ActiveModelStatus,
        download: ModelDownloadService.State?,
        isAvailable: Bool
    ) -> Self {
        if modelID == activeID {
            switch activeStatus {
            case .preparing(let progress, let isDownloading):
                return .preparing(progress: progress, isDownloading: isDownloading)
            case .failed(let message): return .failed(message: message)
            case .ready, .idle: return .active
            }
        }
        switch download {
        case .downloading(let progress)?: return .downloading(progress: progress)
        case .failed(let message)?: return .failed(message: message)
        case nil: return isAvailable ? .downloaded : .notDownloaded
        }
    }
}

// MARK: - Store

/// Bridges the catalog, downloads, settings and the dictation coordinator into one
/// observable snapshot for the Transcription pages.
@MainActor
final class TranscriptionModelsStore: ObservableObject {
    @Published private(set) var catalog: [ModelInfo] = []
    @Published private(set) var activeID = Settings.shared.modelID
    @Published private(set) var activeStatus = ActiveModelStatus.idle
    @Published private(set) var downloads: [String: ModelDownloadService.State] = [:]
    @Published private(set) var language = Settings.shared.language
    /// Bumped after disk changes (delete) that no publisher reports.
    @Published private(set) var diskRevision = 0

    private weak var coordinator: DictationCoordinator?
    private var subscriptions = Set<AnyCancellable>()

    init(coordinator: DictationCoordinator?) {
        self.coordinator = coordinator
        ModelCatalogService.shared.models
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.catalog = $0 }
            .store(in: &subscriptions)
        ModelDownloadService.shared.states
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.downloads = $0 }
            .store(in: &subscriptions)
        coordinator?.phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatus() }
            .store(in: &subscriptions)
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshStatus() }
            .store(in: &subscriptions)
        refreshStatus()
    }

    private func refreshStatus() {
        activeID = Settings.shared.modelID
        language = Settings.shared.language
        activeStatus = ActiveModelStatus.current(coordinator: coordinator, modelID: activeID)
    }

    var activeModel: ModelInfo? { catalog.first { $0.id == activeID } }
    var activeEngine: SpeechEngine { activeModel?.engine ?? SpeechEngine.engine(for: activeID) }
    var isDownloadBusy: Bool { downloads.values.contains { if case .downloading = $0 { return true }; return false } }

    func models(for engine: SpeechEngine) -> [ModelInfo] { catalog.filter { $0.engine == engine } }

    func rowState(for model: ModelInfo) -> ModelRowState {
        _ = diskRevision
        return ModelRowState.make(
            modelID: model.id,
            activeID: activeID,
            activeStatus: activeStatus,
            download: downloads[model.id],
            isAvailable: ModelManager.isAvailable(model.id)
        )
    }

    func downloadedCount(for engine: SpeechEngine) -> Int {
        _ = diskRevision
        return models(for: engine).filter { ModelManager.isAvailable($0.id) }.count
    }

    func storageSummary(for engine: SpeechEngine) -> String {
        _ = diskRevision
        let onDisk = models(for: engine).filter { ModelManager.isInCache($0.id) }
        guard !onDisk.isEmpty else { return "None" }
        let bytes = onDisk.compactMap { ModelManager.diskUsageBytes(for: $0.id) }.reduce(0, +)
        let count = onDisk.count == 1 ? "1 model" : "\(onDisk.count) models"
        return "\(count) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    func freedSpace(for model: ModelInfo) -> String? {
        ModelManager.diskUsageBytes(for: model.id)
            .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    func languageNote(for model: ModelInfo) -> String? {
        model.supports(language: language) ? nil : "Doesn’t support \(LanguageOption.displayName(for: language))"
    }

    func canDelete(_ model: ModelInfo) -> Bool {
        !model.isBundled && model.id != activeID && ModelManager.isInCache(model.id)
    }

    // MARK: Actions

    func download(_ model: ModelInfo) {
        ModelDownloadService.shared.clearFailure(model.id)
        ModelDownloadService.shared.download(model)
    }

    func cancelDownload(_ model: ModelInfo) {
        ModelDownloadService.shared.cancel(model.id)
    }

    func use(_ model: ModelInfo) {
        Settings.shared.modelID = model.id
        Task { await coordinator?.prepareModelInBackground() }
    }

    func retry(_ model: ModelInfo) {
        if model.id == activeID {
            Task { await coordinator?.prepareModelInBackground() }
        } else {
            download(model)
        }
    }

    func delete(_ model: ModelInfo) {
        try? ModelManager.delete(model.id)
        diskRevision += 1
    }

    func reveal(_ model: ModelInfo) {
        ModelManager.reveal(model.id)
    }

    func revealStorage(for engine: SpeechEngine) {
        let root = engine == .fluidAudio ? AIModelStorage.fluidAudioRoot : ModelManager.cacheRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    func refreshCatalog() {
        ModelCatalogService.shared.refresh()
    }
}

// MARK: - Page controllers

/// Settings > Transcription: the active model, then the engines.
@MainActor
final class TranscriptionSettingsPageViewController: NSViewController {
    private let store: TranscriptionModelsStore
    private let onOpenEngine: (SpeechEngine) -> Void

    init(coordinator: DictationCoordinator?, onOpenEngine: @escaping (SpeechEngine) -> Void) {
        store = TranscriptionModelsStore(coordinator: coordinator)
        self.onOpenEngine = onOpenEngine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSHostingView(rootView: TranscriptionOverviewView(store: store, openEngine: onOpenEngine))
        host.sizingOptions = []
        view = host
    }
}

/// Settings > Transcription > Parakeet / Whisper: the engine's models.
@MainActor
final class TranscriptionEngineModelsViewController: NSViewController {
    private let store: TranscriptionModelsStore
    private let engine: SpeechEngine

    init(engine: SpeechEngine, coordinator: DictationCoordinator?) {
        store = TranscriptionModelsStore(coordinator: coordinator)
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSHostingView(rootView: TranscriptionEngineView(store: store, engine: engine))
        host.sizingOptions = []
        view = host
    }
}

// MARK: - Overview

private struct TranscriptionOverviewView: View {
    @ObservedObject var store: TranscriptionModelsStore
    let openEngine: (SpeechEngine) -> Void

    var body: some View {
        Form {
            Section {
                ActiveModelHeader(store: store)
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Section("Speech Engine") {
                ForEach([SpeechEngine.fluidAudio, .whisperKit], id: \.self) { engine in
                    EngineRow(
                        engine: engine,
                        modelCount: store.models(for: engine).count,
                        downloadedCount: store.downloadedCount(for: engine),
                        isActive: store.activeEngine == engine,
                        open: { openEngine(engine) }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: ControlCenterStyle.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var footer: String {
        switch store.activeStatus {
        case .preparing(_, true): return "Downloading the model to this Mac. Dictation is available when it’s ready."
        case .preparing(_, false): return "Optimizing the model for this Mac. The first time can take a minute."
        case .failed(let message): return message
        case .ready, .idle: return "Your voice never leaves this Mac."
        }
    }
}

private struct ActiveModelHeader: View {
    @ObservedObject var store: TranscriptionModelsStore

    var body: some View {
        let engine = store.activeEngine
        let name = ModelPresentation.title(
            store.activeModel?.displayName ?? ModelInfo.deriveDisplayName(from: store.activeID)
        )
        let metadata = store.activeModel.map(ModelPresentation.metadata(for:)) ?? "On this Mac"
        VStack(spacing: 10) {
            EngineIcon(engine: engine, size: 76)
                .padding(.bottom, 4)
            Text(name)
                .font(.system(size: 26, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(metadata)
                .font(.callout)
                .foregroundStyle(.secondary)
            ModelStatusView(status: store.activeStatus)
                .font(.callout)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Active model, \(name), \(metadata), \(statusText)")
    }

    private var statusText: String {
        switch store.activeStatus {
        case .ready: return "Ready"
        case .idle: return "On this Mac"
        case .failed: return "Needs attention"
        case .preparing(let progress, let downloading):
            return "\(downloading ? "Downloading" : "Preparing") \(Int((progress * 100).rounded()))%"
        }
    }
}

private struct ModelStatusView: View {
    let status: ActiveModelStatus

    var body: some View {
        switch status {
        case .ready:
            Label {
                Text("Ready")
            } icon: {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
        case .idle:
            Text("On this Mac").foregroundStyle(.secondary)
        case .preparing(let progress, let downloading):
            HStack(spacing: 8) {
                Text("\(downloading ? "Downloading" : "Preparing") \(Int((progress * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressRing(progress: progress)
            }
        case .failed:
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct EngineRow: View {
    let engine: SpeechEngine
    let modelCount: Int
    let downloadedCount: Int
    let isActive: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                EngineIcon(engine: engine, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.familyName)
                    Text(engine.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(isActive ? "In Use" : downloadedCount == 0 ? "\(modelCount) available" : "\(downloadedCount) downloaded")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(engine.familyName) models")
        .accessibilityValue(isActive ? "In use" : "\(downloadedCount) of \(modelCount) downloaded")
        .accessibilityHint(engine.tagline)
    }
}

/// System Settings style icon: a white symbol on a tinted rounded square.
private struct EngineIcon: View {
    let engine: SpeechEngine
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: engine.symbolName)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch engine {
        case .fluidAudio: return .green
        case .whisperKit: return .indigo
        }
    }
}

// MARK: - Engine page

private struct TranscriptionEngineView: View {
    @ObservedObject var store: TranscriptionModelsStore
    let engine: SpeechEngine
    @State private var filter = TranscriptionModelGrouping.LanguageFilter.all
    @State private var pendingDelete: ModelInfo?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    EngineIcon(engine: engine, size: 60)
                        .padding(.bottom, 2)
                    Text(engine.familyName)
                        .font(.system(size: 22, weight: .semibold))
                    Text(engine.tagline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                if engine == .whisperKit {
                    Picker("Languages", selection: $filter) {
                        ForEach(TranscriptionModelGrouping.LanguageFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            let sections = TranscriptionModelGrouping.sections(for: engine, in: store.catalog, filter: filter)
            if sections.isEmpty {
                Section { Text("No models match this filter.").foregroundStyle(.secondary) }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.models) { model in
                        ModelRow(
                            model: model,
                            state: store.rowState(for: model),
                            languageNote: store.languageNote(for: model),
                            downloadBlocked: store.isDownloadBusy,
                            canDelete: store.canDelete(model),
                            onDownload: { store.download(model) },
                            onCancel: { store.cancelDownload(model) },
                            onUse: { store.use(model) },
                            onRetry: { store.retry(model) },
                            onReveal: { store.reveal(model) },
                            onDelete: { pendingDelete = model }
                        )
                    }
                } header: {
                    if engine == .whisperKit { Text(section.title) }
                } footer: {
                    if !section.detail.isEmpty {
                        Text(section.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Downloaded", value: store.storageSummary(for: engine))
                HStack {
                    Button("Show in Finder") { store.revealStorage(for: engine) }
                        .hushGlassButton()
                    if engine == .whisperKit {
                        Button("Refresh Catalog") { store.refreshCatalog() }
                            .hushGlassButton()
                    }
                }
            } footer: {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: ControlCenterStyle.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .alert(
            pendingDelete.map { "Delete “\(ModelPresentation.title($0.displayName))”?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { model in
            Button("Delete", role: .destructive) { store.delete(model) }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text(store.freedSpace(for: model).map { "This frees \($0). You can download it again anytime." }
                 ?? "You can download it again anytime.")
        }
    }

    private var footnote: String {
        switch engine {
        case .fluidAudio:
            return "Detects 25 European languages automatically, including English, German, French, Spanish, Russian and Ukrainian. Built by Moondream on NVIDIA Parakeet (CC-BY-4.0), running with FluidAudio."
        case .whisperKit:
            return "From Argmax’s WhisperKit catalog. Dates show when OpenAI first released each model."
        }
    }
}

private struct ModelRow: View {
    let model: ModelInfo
    let state: ModelRowState
    let languageNote: String?
    let downloadBlocked: Bool
    let canDelete: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onUse: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private var name: String { ModelPresentation.title(model.displayName) }

    private var isInUse: Bool {
        switch state {
        case .active, .preparing: return true
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                    ModelInfoButton(model: model)
                }
                Text(model.purpose)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ModelPresentation.coverageAndDate(for: model))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let note {
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(note.color)
                }
            }
            Spacer(minLength: 12)
            if let size = model.approximateSizeMB {
                Text(ModelPresentation.size(size))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            trailing
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .listRowBackground(isInUse ? Color.accentColor.opacity(0.08) : nil)
        .contextMenu {
            if case .downloaded = state, languageNote == nil { Button("Use", action: onUse) }
            if ModelManager.isAvailable(model.id) { Button("Show in Finder", action: onReveal) }
            if canDelete {
                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            }
        }
    }

    private var note: (text: String, color: Color)? {
        switch state {
        case .failed(let message): return (message, .red)
        case .downloading(let progress):
            return ("Downloading · \(Int((progress * 100).rounded()))%", .secondary)
        case .preparing(let progress, let downloading):
            return ("\(downloading ? "Downloading" : "Optimizing for this Mac") · \(Int((progress * 100).rounded()))%", .secondary)
        case .active:
            return languageNote.map { ($0, .orange) }
        case .downloaded:
            return languageNote.map { ($0, .secondary) }
        case .notDownloaded:
            return nil
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(downloadBlocked || !model.isDownloadAvailable)
            .help(downloadBlocked ? "Another model is downloading" : "Download \(name)")
            .accessibilityLabel("Download \(name)")
        case .downloading(let progress):
            Button(action: onCancel) {
                ProgressRing(progress: progress, showsStop: true)
            }
            .buttonStyle(.borderless)
            .help("Stop downloading and remove the partial file")
            .accessibilityLabel("Cancel downloading \(name)")
        case .downloaded:
            HStack(spacing: 6) {
                Button("Use", action: onUse)
                    .hushGlassButton()
                    .disabled(languageNote != nil)
                    .accessibilityLabel("Use \(name)")
                if canDelete {
                    Menu {
                        Button("Show in Finder", action: onReveal)
                        Button("Delete…", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More for \(name)")
                }
            }
        case .preparing(let progress, _):
            ProgressRing(progress: progress)
                .accessibilityLabel("Preparing \(name)")
        case .active:
            Label("In Use", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
        case .failed:
            Button("Retry", action: onRetry)
                .hushGlassButton()
        }
    }
}

/// A small info button next to a model's name. The popover holds the details that
/// would otherwise crowd the row.
private struct ModelInfoButton: View {
    let model: ModelInfo
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("About \(ModelPresentation.title(model.displayName))")
        .accessibilityLabel("About \(ModelPresentation.title(model.displayName))")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelDetailsPopover(model: model)
        }
    }
}

private struct ModelDetailsPopover: View {
    let model: ModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelPresentation.title(model.displayName))
                    .font(.headline)
                if let tag = model.tag {
                    Text(tag)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(model.purpose)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                if let size = model.approximateSizeMB {
                    row("Size", ModelPresentation.size(size))
                }
                if let date = model.releaseDate {
                    row("Released", ModelPresentation.month(date))
                }
                row("Engine", "\(model.engine.familyName) via \(model.engine.runtimeName)")
                row("License", model.engine == .fluidAudio ? "CC-BY-4.0" : "MIT")
                row("Languages", model.languageCoverage)
            }
            .font(.callout)
            if let names = languageNames {
                Text(names)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var languageNames: String? {
        guard let codes = model.supportedLanguages else { return nil }
        return codes
            .compactMap { Locale.current.localizedString(forLanguageCode: $0) }
            .sorted()
            .joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// App Store style determinate ring, optionally with a stop glyph to cancel.
private struct ProgressRing: View {
    let progress: Double
    var showsStop = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            if showsStop {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(Circle())
    }
}

private extension View {
    /// Liquid Glass buttons on macOS 26, the standard bordered style before it.
    @ViewBuilder
    func hushGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

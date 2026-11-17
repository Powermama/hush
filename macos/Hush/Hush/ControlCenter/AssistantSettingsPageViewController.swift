import AppKit
import Combine

/// Setup reflects independent components. Missing screen access never blocks
/// dictation, and changing the assistant model never changes the persona engine.
struct AssistantSetupSnapshot: Equatable {
    let intelligence: Bool
    let transcription: Bool
    let voice: Bool
    let microphone: Bool
    let accessibility: Bool
    let screen: Bool

    var ready: Bool { remaining == 0 }
    var remaining: Int { [intelligence, transcription, voice, microphone, accessibility, screen].filter { !$0 }.count }
    var title: String { ready ? "Ready when you are" : "Set up your assistant" }

    @MainActor static var modelsInstalled: Bool {
        guard let model = LLMRuntime.QwenModel(provider: CoworkerModelSettings.provider) else { return false }
        let voiceEnabled = UserDefaults.standard.object(forKey: "assistant.voiceEnabled") as? Bool ?? true
        return LLMRuntime.cachedQwenSnapshotURL(for: model) != nil && ModelManager.isAvailable(Settings.shared.modelID)
            && (!voiceEnabled || CoworkerVoice.hasCachedAssets)
    }
}

/// Where the Assistant stands, in one line, for its page and the hush AI page.
@MainActor
struct AssistantStatus {
    let isOn: Bool
    let text: String
    let tone: AIFeatureSwitchCard.Tone
    let action: String?
    var secondary: String? = nil
    let progress: Double?

    /// On starts setup when something is missing; off keeps models and permissions.
    static func setEnabled(_ on: Bool, flow: AssistantSetupFlow = .shared) {
        Settings.shared.assistantEnabled = on
        if on, !flow.isReady, !flow.isRunning, !AIModelLibrary.shared.isRemoving { flow.start() }
    }

    /// The card's button: continue a setup that needs the user, or start one.
    static func performNextStep(flow: AssistantSetupFlow = .shared) {
        if case .working(let step) = flow.state, [.microphone, .accessibility, .screen].contains(step) {
            flow.openPermissionSettings()
        } else if flow.isRunning {
            flow.cancel()
        } else {
            Settings.shared.assistantEnabled = true
            if !AIModelLibrary.shared.isRemoving { flow.start() }
        }
    }

    static func current(flow: AssistantSetupFlow = .shared) -> AssistantStatus {
        let on = Settings.shared.assistantEnabled
        if case .working(let step) = flow.state {
            let needsUser = [.microphone, .accessibility, .screen].contains(step)
            var fraction: Double?
            if step == .voice { fraction = CoworkerVoice.shared.setupProgress.value.fraction }
            return AssistantStatus(isOn: on, text: "Setting up: \(step.title)", tone: needsUser ? .attention : .neutral,
                                   action: needsUser ? "Open System Settings" : "Cancel",
                                   secondary: needsUser ? "Cancel" : nil, progress: fraction)
        }
        if flow.state == .cancelling {
            return AssistantStatus(isOn: on, text: "Stopping setup\u{2026}", tone: .neutral, action: nil, progress: nil)
        }
        guard on else {
            return AssistantStatus(isOn: false, text: "Off. Its shortcut does nothing until you turn it on.", tone: .neutral, action: nil, progress: nil)
        }
        if flow.isReady {
            return AssistantStatus(isOn: true, text: "Ready. Hold Control + Fn in any app to talk.", tone: .ready, action: nil, progress: nil)
        }
        switch flow.state {
        case .failed(let message):
            return AssistantStatus(isOn: true, text: message, tone: .attention, action: "Retry setup", progress: nil)
        case .cancelled:
            return AssistantStatus(isOn: true, text: "Setup paused. Finished downloads and permissions are kept.", tone: .attention, action: "Resume setup", progress: nil)
        default:
            return AssistantStatus(isOn: true, text: "Needs a one-time setup: models and permissions, guided.", tone: .attention, action: "Set up Assistant", progress: nil)
        }
    }
}

@MainActor
final class AssistantSettingsPageViewController: ControlCenterPageViewController {
    private let onNavigate: (HushDestination) -> Void
    private let flow: AssistantSetupFlow
    private let library = AIModelLibrary.shared
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private let feature = AIFeatureSwitchCard(
        title: "Assistant",
        description: "A voice coworker that sees the window you\u{2019}re in and makes changes with you.",
        symbol: "cursorarrow.rays",
        colors: AIFeatureIcon.assistant,
        badge: "BETA",
        identifier: "hush.assistant"
    )
    private let models = AIModelControlsView(scope: .assistant)
    private var statuses: [AssistantSetupFlow.Step: NSTextField] = [:]
    private let modelPicker = NSPopUpButton()

    init(coordinator: DictationCoordinator?, onNavigate: @escaping (HushDestination) -> Void) {
        self.onNavigate = onNavigate
        #if DEBUG
        flow = ProcessInfo.processInfo.arguments.contains("--preview-assistant-setup-flow")
            ? AssistantSetupFlow.settingsJourneyFixture() : .shared
        #else
        flow = .shared
        #endif
        super.init(nibName: nil, bundle: nil)
        if let coordinator { library.coordinator = coordinator }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        stack.spacing = 14
        addFullWidth(aiPageHeader(title: "Assistant", detail: "Talk to hush about what\u{2019}s on your screen, entirely on this Mac."))
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        feature.onToggle = { [weak self] on in
            guard let self else { return }
            AssistantStatus.setEnabled(on, flow: self.flow)
            self.refresh()
        }
        feature.onAction = { [weak self] in
            guard let self else { return }
            AssistantStatus.performNextStep(flow: self.flow)
            self.refresh()
        }
        feature.onSecondaryAction = { [weak self] in self?.flow.cancel(); self?.refresh() }
        addFullWidth(feature)
        let usage = subtitle("Hold Control + Fn in the app you want help with and release to send. Press Escape to stop and start a fresh conversation.")
        usage.setAccessibilityIdentifier("hush.assistant.local-processing")
        addFullWidth(usage)

        stack.setCustomSpacing(22, after: usage)
        let modelHeading = NSStackView(views: [sectionHeading("Models"), NSView(), modelPicker]); modelHeading.spacing = 12
        modelHeading.alignment = .centerY
        modelPicker.addItems(withTitles: ["Qwen 3.5 4B", "Qwen 3.5 2B"])
        modelPicker.controlSize = .small
        modelPicker.setAccessibilityLabel("Assistant intelligence model")
        modelPicker.target = self; modelPicker.action = #selector(changeModel)
        addFullWidth(modelHeading)
        addFullWidth(makeCard(content: models))

        let permissionsHeading = sectionHeading("Permissions")
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        addFullWidth(permissionsHeading)
        let rows = NSStackView()
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 0
        let entries: [(AssistantSetupFlow.Step, String, String)] = [
            (.microphone, "Microphone", "Hear you while you hold Control + Fn."),
            (.accessibility, "Accessibility", "Read controls and make the edits you ask for."),
            (.screen, "Screen Recording", "Understand the window you\u{2019}re working in.")
        ]
        for (index, entry) in entries.enumerated() {
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12, weight: .medium); statuses[entry.0] = status
            status.setAccessibilityIdentifier("hush.assistant.\(entry.0.rawValue).status")
            let row = ControlCenterKeyValueRow(title: entry.1, subtitle: entry.2, trailing: status, showsSeparator: index < entries.count - 1)
            rows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        addFullWidth(makeCard(content: rows))
        addFullWidth(subtitle("Setup downloads what is missing and walks you through each macOS permission. What you say and show hush stays on this Mac; downloads and websites you open use the internet."))
        library.changes.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        flow.changes.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        Settings.shared.didChange.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }
    override func viewWillAppear() {
        super.viewWillAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    override func viewWillDisappear() { super.viewWillDisappear(); timer?.invalidate(); timer = nil }

    private func sectionHeading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func refresh() {
        guard isViewLoaded else { return }
        let status = AssistantStatus.current(flow: flow)
        feature.update(isOn: status.isOn, status: status.text, tone: status.tone, action: status.action, secondary: status.secondary,
                       progress: status.progress, toggleEnabled: flow.state != .cancelling && !library.isRemoving)
        for (step, label) in statuses {
            let available = flow.ready(step)
            label.stringValue = available ? "Allowed" : "Not allowed yet"
            label.textColor = available ? DesignTokens.goodInk : .secondaryLabelColor
            if case .working(let current) = flow.state, current == step, flow.isRunning { label.stringValue = "Waiting for you\u{2026}" }
        }
        modelPicker.selectItem(at: CoworkerModelSettings.provider == .qwen35_4b ? 0 : 1)
        modelPicker.isEnabled = !flow.isRunning
    }
    @objc private func changeModel() {
        CoworkerModelSettings.provider = modelPicker.indexOfSelectedItem == 0 ? .qwen35_4b : .qwen35_2b
        // Recreate static labels for the chosen configuration through navigation.
        onNavigate(.assistant)
    }
}

/// A native symbol and spacious typography carry the Hush identity without
/// continuous animation or a web-style settings banner.
@MainActor
final class AISettingsHeader: NSView {
    init(title: String, detail: String, symbol: String, badge: String? = nil) {
        super.init(frame: .zero)
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: 34, weight: .regular)
        image.contentTintColor = DesignTokens.brand500
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 26, weight: .semibold)
        let tag = NSTextField(labelWithString: badge ?? "")
        tag.font = .systemFont(ofSize: 11, weight: .medium)
        tag.textColor = .secondaryLabelColor
        let titleRow = NSStackView(views: [heading, tag]); titleRow.spacing = 10
        let description = NSTextField(wrappingLabelWithString: detail)
        description.font = .systemFont(ofSize: 13); description.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [titleRow, description])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 6
        let row = NSStackView(views: [image, labels, NSView()]); row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 48), image.heightAnchor.constraint(equalToConstant: 56),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

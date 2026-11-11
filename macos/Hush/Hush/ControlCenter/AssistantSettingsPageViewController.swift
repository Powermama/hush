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

@MainActor
final class AssistantSettingsPageViewController: ControlCenterPageViewController {
    private let onNavigate: (HushDestination) -> Void
    private let flow: AssistantSetupFlow
    private let library = AIModelLibrary.shared
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private let setupTitle = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let setup = NSButton(title: "Set up Assistant", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let permission = NSButton(title: "Open Settings", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let downloadBar = NSProgressIndicator()
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
        addFullWidth(AISettingsHeader(title: "Hush Assistant", detail: "Your voice coworker, powered by this Mac.", symbol: "cursorarrow.rays", badge: "Beta"))
        setupTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        setupTitle.setAccessibilityIdentifier("hush.assistant.setup.status")
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 0
        setup.bezelStyle = .rounded; setup.target = self; setup.action = #selector(startSetup)
        setup.setAccessibilityIdentifier("hush.assistant.setup.start")
        cancel.bezelStyle = .rounded; cancel.target = self; cancel.action = #selector(cancelSetup)
        permission.bezelStyle = .rounded; permission.target = self; permission.action = #selector(openPermission)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let buttons = NSStackView(views: [setup, permission, cancel, spinner]); buttons.spacing = 10
        downloadBar.style = .bar; downloadBar.isIndeterminate = false; downloadBar.minValue = 0; downloadBar.maxValue = 1
        downloadBar.widthAnchor.constraint(equalToConstant: 240).isActive = true
        downloadBar.setAccessibilityIdentifier("hush.assistant.download-progress")
        let content = NSStackView(views: [setupTitle, detail, downloadBar, buttons])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 10
        addFullWidth(makeCard(content: content, insets: .init(top: 20, left: 20, bottom: 20, right: 20)))
        addFullWidth(subtitle("Setup downloads missing models and guides you through macOS permissions. Everything you say and show Hush is processed on this Mac. Downloads and websites you open use the internet."))
        let modelHeading = NSStackView(views: [sectionTitle("On this Mac"), NSView(), modelPicker]); modelHeading.spacing = 12
        modelPicker.addItems(withTitles: ["Qwen 3.5 4B", "Qwen 3.5 2B"])
        modelPicker.setAccessibilityLabel("Assistant intelligence model")
        modelPicker.target = self; modelPicker.action = #selector(changeModel)
        addFullWidth(modelHeading)
        addFullWidth(makeCard(content: models))
        addFullWidth(sectionTitle("Permissions"))
        let rows = NSStackView()
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 0
        let entries: [(AssistantSetupFlow.Step, String, String)] = [
            (.microphone, "Microphone", "Hear you while you hold Control + Fn."),
            (.accessibility, "Accessibility", "Read controls and make the edits you ask for."),
            (.screen, "Screen Recording", "Understand the window you’re working in.")
        ]
        for (index, entry) in entries.enumerated() {
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12); statuses[entry.0] = status
            status.setAccessibilityIdentifier("hush.assistant.\(entry.0.rawValue).status")
            let row = ControlCenterKeyValueRow(title: entry.1, subtitle: entry.2, trailing: status, showsSeparator: index < entries.count - 1)
            rows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        addFullWidth(makeCard(content: rows))
        let privacy = subtitle("Hold Control + Fn to talk in any app. Release to submit. Press Escape to stop and start a fresh conversation.")
        privacy.setAccessibilityIdentifier("hush.assistant.local-processing")
        addFullWidth(privacy)
        library.changes.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        flow.changes.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }
    override func viewWillAppear() {
        super.viewWillAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    override func viewWillDisappear() { super.viewWillDisappear(); timer?.invalidate(); timer = nil }

    private func refresh() {
        guard isViewLoaded else { return }
        let ready = flow.isReady
        setupTitle.stringValue = ready ? "Ready when you are" : "Meet your new coworker"
        detail.stringValue = ready ? "Hold Control + Fn in the app you want help with.\nPress Escape whenever you want to stop." : "One setup, then you’re ready to talk. Existing downloads are reused."
        setup.title = "Set up Assistant"
        permission.isHidden = true
        if case .failed(let message) = flow.state, !ready { detail.stringValue = message; setup.title = "Retry setup" }
        if case .cancelled = flow.state, !ready { detail.stringValue = "Setup paused. Completed downloads and permissions are kept."; setup.title = "Resume setup" }
        downloadBar.isHidden = true
        if case .working(let step) = flow.state {
            setupTitle.stringValue = "Setting up Assistant"
            detail.stringValue = step.title
            if step == .intelligence { detail.stringValue += "\n" + library.detail(.intelligence(CoworkerModelSettings.provider)) }
            if step == .voice {
                detail.stringValue = CoworkerVoice.shared.setupProgress.value.label
                if let fraction = CoworkerVoice.shared.setupProgress.value.fraction {
                    downloadBar.isHidden = false; downloadBar.doubleValue = fraction
                }
            }
            permission.isHidden = ![.microphone, .accessibility, .screen].contains(step)
        }
        setup.isHidden = ready || flow.isRunning
        setup.isEnabled = !library.isRemoving
        cancel.isHidden = !flow.isRunning
        cancel.isEnabled = flow.state != .cancelling
        if flow.state == .cancelling { detail.stringValue = "Stopping setup…" }
        if flow.isRunning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        for (step, status) in statuses {
            let available = flow.ready(step)
            status.stringValue = available ? "Ready" : "Needs setup"
            status.textColor = available ? DesignTokens.goodInk : .secondaryLabelColor
            if case .working(let current) = flow.state, current == step, flow.isRunning { status.stringValue = "Waiting for access…" }
        }
        modelPicker.selectItem(at: CoworkerModelSettings.provider == .qwen35_4b ? 0 : 1)
        modelPicker.isEnabled = !flow.isRunning
    }
    @objc private func startSetup() { flow.start() }
    @objc private func cancelSetup() { flow.cancel() }
    @objc private func openPermission() { flow.openPermissionSettings() }
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

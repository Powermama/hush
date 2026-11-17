import AppKit
import Combine

/// hush AI: the two AI features side by side as rows you can switch on right here, with
/// where each stands and the one next step, the way System Settings lists features.
@MainActor
final class HushAIPageViewController: ControlCenterPageViewController {
    private let onNavigate: (HushDestination) -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private let liveWrite = AIFeatureSwitchCard(
        title: "Live Write",
        description: "Talk naturally. Ask for a text and hush writes it; anything else is cleaned up in your words.",
        symbol: "text.bubble.fill",
        colors: AIFeatureIcon.liveWrite,
        identifier: "hush.ai.livewrite"
    )
    private let assistant = AIFeatureSwitchCard(
        title: "Assistant",
        description: "A voice coworker that sees the window you\u{2019}re in and makes changes with you.",
        symbol: "cursorarrow.rays",
        colors: AIFeatureIcon.assistant,
        badge: "BETA",
        identifier: "hush.ai.assistant"
    )

    init(coordinator: DictationCoordinator?, onNavigate: @escaping (HushDestination) -> Void) {
        self.onNavigate = onNavigate
        super.init(nibName: nil, bundle: nil)
        if let coordinator { AIModelLibrary.shared.coordinator = coordinator }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        stack.spacing = 12
        addFullWidth(aiPageHeader(title: "hush AI", detail: "Private AI that runs on this Mac. Turn on what you need."))
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        for card in [liveWrite, assistant] {
            card.toggle.controlSize = .small
            addFullWidth(card)
        }
        liveWrite.onOpen = { [weak self] in self?.onNavigate(.liveWrite()) }
        liveWrite.onToggle = { [weak self] on in
            if !LiveWriteStatus.setEnabled(on) { self?.onNavigate(.liveWrite(focusEnableAI: true)) }
            self?.refresh()
        }
        liveWrite.onAction = { [weak self] in
            if !LiveWriteStatus.downloadRecommendedEngine() { self?.onNavigate(.liveWrite(focusEnableAI: true)) }
            self?.refresh()
        }
        assistant.onOpen = { [weak self] in self?.onNavigate(.assistant) }
        assistant.onToggle = { [weak self] on in AssistantStatus.setEnabled(on); self?.refresh() }
        assistant.onSecondaryAction = { [weak self] in AssistantSetupFlow.shared.cancel(); self?.refresh() }
        assistant.onAction = { [weak self] in
            AssistantStatus.performNextStep()
            self?.onNavigate(.assistant)
        }

        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let privacy = NSTextField(wrappingLabelWithString: "Personal by design. Your voice, writing and screen are processed on this Mac. Model downloads are the only thing that uses the internet.")
        privacy.font = .systemFont(ofSize: 12); privacy.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [icon, privacy]); footer.spacing = 9; footer.alignment = .top
        stack.setCustomSpacing(18, after: assistant)
        addFullWidth(footer)
        AIModelLibrary.shared.changes.merge(with: AssistantSetupFlow.shared.changes)
            .merge(with: Settings.shared.didChange)
            .merge(with: LLMRuntime.shared.stateChange)
            .receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
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
        let writing = LiveWriteStatus.current()
        liveWrite.update(isOn: writing.isOn, status: writing.text, tone: writing.tone, action: writing.action, progress: writing.progress)
        let coworker = AssistantStatus.current()
        assistant.update(isOn: coworker.isOn, status: coworker.text, tone: coworker.tone, action: coworker.action, secondary: coworker.secondary, progress: coworker.progress)
    }
}

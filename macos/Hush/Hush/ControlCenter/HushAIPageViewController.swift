import AppKit
import Combine

@MainActor
final class HushAIPageViewController: ControlCenterPageViewController {
    private let onNavigate: (HushDestination) -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private let personas = AIFeatureCard(title: "Personas", description: "Your words, in your style. Refine what you dictate without losing your voice.", symbol: "text.badge.star")
    private let assistant = AIFeatureCard(title: "Assistant", description: "A coworker you can talk to. Understand what’s on screen and make changes together.", symbol: "cursorarrow.rays", beta: true)

    init(coordinator: DictationCoordinator?, onNavigate: @escaping (HushDestination) -> Void) {
        self.onNavigate = onNavigate
        super.init(nibName: nil, bundle: nil)
        if let coordinator { AIModelLibrary.shared.coordinator = coordinator }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        stack.spacing = 24
        addFullWidth(AISettingsHeader(title: "Hush AI", detail: "Write in your style. Work with your voice.", symbol: "sparkles"))
        let cards = NSStackView(views: [personas, assistant])
        cards.orientation = .horizontal; cards.distribution = .fillEqually; cards.spacing = 16
        addFullWidth(cards)
        personas.onOpen = { [weak self] in self?.onNavigate(.personas()) }
        personas.onAction = personas.onOpen
        assistant.onOpen = { [weak self] in self?.onNavigate(.assistant) }
        assistant.onAction = { [weak self] in
            self?.onNavigate(.assistant)
            if !AssistantSetupFlow.shared.isReady, !AIModelLibrary.shared.isRemoving { AssistantSetupFlow.shared.start() }
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let privacy = NSTextField(wrappingLabelWithString: "Personal by design. Your voice, writing and screen are processed on this Mac.")
        privacy.font = .systemFont(ofSize: 12); privacy.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [icon, privacy]); footer.spacing = 9
        addFullWidth(footer)
        AIModelLibrary.shared.changes.merge(with: AssistantSetupFlow.shared.changes)
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
        let provider = Settings.shared.llmProvider
        let enabled = provider != .off && LLMRuntime.shared.isReady(provider: provider)
        personas.update(status: enabled ? "\(Settings.shared.activeProfile.name) · Active" : "Choose your writing style", ready: enabled, action: "Personalize", detail: enabled ? provider.displayName : "Optional, entirely local")
        let flow = AssistantSetupFlow.shared
        let ready = flow.isReady
        var status = ready ? "Ready on this Mac" : "Setup needed"
        if flow.isRunning { status = "Setting up…" }
        assistant.update(status: status, ready: ready && !flow.isRunning, action: ready ? "Open Assistant" : flow.isRunning ? "Continue setup" : "Set up Assistant", detail: ready ? "Hold Control + Fn to talk" : "Models and permissions, guided")
    }
}

@MainActor
private final class AIFeatureCard: ControlCenterCardView {
    var onOpen: (() -> Void)?
    var onAction: (() -> Void)?
    private let status = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let detail = NSTextField(labelWithString: "")
    private let action = AIModelActionButton(title: "")

    init(title: String, description: String, symbol: String, beta: Bool = false) {
        super.init(frame: .zero)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 46, weight: .light)
        icon.contentTintColor = DesignTokens.brand500
        let tag = NSTextField(labelWithString: beta ? "Beta" : "")
        tag.font = .systemFont(ofSize: 11, weight: .medium); tag.textColor = .secondaryLabelColor
        let illustration = NSStackView(views: [icon, NSView(), tag]); illustration.alignment = .top
        let open = AIModelActionButton(title: title)
        open.isBordered = false; open.font = .systemFont(ofSize: 23, weight: .semibold)
        open.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: NSColor.labelColor])
        open.alignment = .left
        open.setAccessibilityLabel("Open \(title)")
        open.onPress = { [weak self] in self?.onOpen?() }
        let copy = NSTextField(wrappingLabelWithString: description)
        copy.font = .systemFont(ofSize: 13); copy.textColor = .secondaryLabelColor
        copy.maximumNumberOfLines = 3
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityIdentifier("hush.ai.\(title.lowercased()).status")
        statusIcon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        let state = NSStackView(views: [statusIcon, status]); state.spacing = 6
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
        action.controlSize = .large
        action.setAccessibilityIdentifier("hush.ai.\(title.lowercased()).action")
        action.onPress = { [weak self] in self?.onAction?() }
        let stack = NSStackView(views: [illustration, open, copy, NSView(), state, detail, action])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.setCustomSpacing(20, after: illustration)
        stack.setCustomSpacing(4, after: state)
        stack.setCustomSpacing(18, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 348),
            icon.widthAnchor.constraint(equalToConstant: 58), icon.heightAnchor.constraint(equalToConstant: 58),
            illustration.widthAnchor.constraint(equalTo: stack.widthAnchor),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            copy.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(status value: String, ready: Bool, action title: String, detail subtitle: String) {
        status.stringValue = value
        status.textColor = ready ? DesignTokens.goodInk : .secondaryLabelColor
        statusIcon.image = NSImage(systemSymbolName: ready ? "checkmark.circle.fill" : "circle.dashed", accessibilityDescription: nil)
        statusIcon.contentTintColor = status.textColor
        action.title = title; detail.stringValue = subtitle
    }
}

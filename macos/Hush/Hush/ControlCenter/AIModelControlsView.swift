import AppKit
import Combine

/// The same file lifecycle, presented in the workflow that uses each model. Engine lists
/// (Live Write, Assistant's AI model) put the recommended engine first and the user's
/// ChatGPT plan last; each feature keeps its own choice and its own ChatGPT consent.
@MainActor
final class AIModelControlsView: NSStackView {
    enum Scope {
        /// Live Write's writing engine.
        case liveWrite
        /// The model Assistant thinks with.
        case assistantIntelligence
        /// What Assistant needs besides its AI model: listening and spoken replies.
        case assistantSupport
    }
    private let scope: Scope
    private let library = AIModelLibrary.shared
    private var subscriptions = Set<AnyCancellable>()

    init(scope: Scope) {
        self.scope = scope
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 0
        library.changes.merge(with: AssistantSetupFlow.shared.changes, ChatGPTAccount.shared.changes,
                              Settings.shared.didChange, LLMRuntime.shared.stateChange, CoworkerModelSettings.changes)
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
        Task { await library.refreshSizes() }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Which feature's choice this list shows

    private var purpose: ChatGPTAccount.Purpose { scope == .liveWrite ? .liveWrite : .assistant }
    private var selected: LLMProvider { scope == .liveWrite ? Settings.shared.llmProvider : CoworkerModelSettings.provider }

    private func isReady(_ provider: LLMProvider) -> Bool {
        scope == .liveWrite ? LLMRuntime.shared.isReady(provider: provider) : CoworkerModelSettings.isReady(provider)
    }

    private func select(_ provider: LLMProvider) {
        switch scope {
        case .liveWrite:
            Settings.shared.llmProvider = provider
            if provider == .chatGPT { Settings.shared.liveWriteEnabled = true }
        case .assistantIntelligence, .assistantSupport:
            CoworkerModelSettings.select(provider)
        }
    }

    // MARK: Rows

    func refresh() {
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        switch scope {
        case .liveWrite:
            addEngine(.qwen35_4b, purpose: "Recommended")
            addSystemEngine()
            addEngine(.qwen35_2b, purpose: "Faster")
            addChatGPTRow()
        case .assistantIntelligence:
            addEngine(.qwen35_4b, purpose: "Recommended")
            addEngine(.qwen35_2b, purpose: "Faster")
            addChatGPTRow()
        case .assistantSupport:
            let items: [LocalAIModel] = [.speech(Settings.shared.modelID), .voice]
            for (index, item) in items.enumerated() {
                let controls = controlStack()
                let step: AssistantSetupFlow.Step = item == .voice ? .voice : .transcription
                if library.installed(item), !library.busy(item) {
                    let active = AssistantSetupFlow.shared.ready(step) && library.failures[item] == nil
                    controls.addArrangedSubview(modelStatus(active ? "Active" : "Downloaded", name: library.name(item), active: active))
                }
                addFileControl(item, to: controls)
                addRow(title: library.name(item), detail: detail(for: item, purpose: item == .voice ? "Spoken replies · English" : "Listening"),
                       controls: controls, separator: index < items.count - 1)
            }
        }
    }

    /// A model on this Mac: Download until it is here, then Use or Active, and its More menu.
    private func addEngine(_ provider: LLMProvider, purpose: String) {
        let item = LocalAIModel.intelligence(provider)
        let controls = controlStack()
        if library.installed(item), !library.busy(item) { controls.addArrangedSubview(selectionControl(for: provider)) }
        addFileControl(item, to: controls)
        addRow(title: library.name(item), detail: detail(for: item, purpose: purpose + " · On this Mac"), controls: controls, separator: true)
    }

    /// Apple Intelligence is managed by macOS: nothing to download or remove.
    private func addSystemEngine() {
        // A menu-width spacer keeps Use in the same column as the rows with a More menu.
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let controls = controlStack()
        controls.addArrangedSubview(selectionControl(for: .appleIntelligence))
        controls.addArrangedSubview(spacer)
        addRow(title: "Apple Intelligence", detail: "On this Mac · Managed by macOS", controls: controls, separator: true)
    }

    private func detail(for item: LocalAIModel, purpose: String) -> String {
        let installed = library.installed(item)
        if let failure = library.failures[item] { return failure }
        if library.busy(item) { return library.detail(item) }
        if library.bundled(item) { return purpose + " · Included with hush" }
        if let size = library.sizes[item], installed { return purpose + " · " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
        return purpose + (installed ? "" : " · Not installed")
    }

    /// Download or Cancel while missing, a More menu with Remove once installed.
    private func addFileControl(_ item: LocalAIModel, to controls: NSStackView) {
        guard !library.bundled(item) else { return }
        let control: NSControl
        if library.installed(item) && !library.busy(item) {
            let menu = AIModelMenuButton(modelName: library.name(item))
            menu.onRemove = { [weak self] in self?.confirmRemoval(item) }
            control = menu
        } else {
            let busy = library.busy(item)
            let button = AIModelActionButton(title: busy ? "Cancel" : "Download", inline: true,
                                             symbol: busy ? "xmark.circle" : "arrow.down.circle")
            button.setAccessibilityLabel("\(busy ? "Cancel" : "Download") \(library.name(item))")
            button.onPress = { [weak self] in
                guard let self else { return }
                if library.busy(item) { library.cancel(item) } else { library.download(item) }
            }
            control = button
        }
        control.setAccessibilityIdentifier("hush.ai.model.\(item.id)")
        control.isEnabled = !library.isRemoving && !AssistantSetupFlow.shared.isRunning
        controls.addArrangedSubview(control)
    }

    /// The user's ChatGPT plan as the last engine. Choosing it asks for this feature's consent
    /// first (Assistant shares more than Live Write), then signs in when needed. Connected, its
    /// More menu holds the model, Manage Usage and Disconnect.
    private func addChatGPTRow() {
        let account = ChatGPTAccount.shared
        let controls = controlStack()
        let choose = { [weak self] in
            guard let self else { return }
            account.withConsent(for: self.purpose, in: self.window) { [weak self] in self?.select(.chatGPT) }
        }
        var detail = "Your ChatGPT plan · Sent to OpenAI"
        switch account.state {
        case .disconnected, .failed:
            if case .failed(let message) = account.state { detail = message }
            let connect = AIModelActionButton(title: "Continue with ChatGPT", inline: true, symbol: "cloud")
            connect.setAccessibilityIdentifier("hush.ai.model.chatgpt")
            connect.onPress = choose
            controls.addArrangedSubview(connect)
        case .connecting:
            detail = "Finish signing in in your browser"
            let cancel = AIModelActionButton(title: "Cancel", inline: true, symbol: "xmark.circle")
            cancel.onPress = { account.cancelConnect() }
            controls.addArrangedSubview(cancel)
        case .connected(let email, let planUsage):
            if planUsage {
                let model = account.modelName(Settings.shared.chatGPTModel)
                let fallback = scope == .liveWrite ? "Writing" : "Answering"
                detail = account.isLimitPaused ? "Plan limit reached · \(fallback) on this Mac for now" : "\(model) · Your ChatGPT plan"
                if selected == .chatGPT && account.hasConsent(purpose) {
                    controls.addArrangedSubview(modelStatus("Active", name: "ChatGPT", active: true))
                } else {
                    let use = AIModelActionButton(title: "Use", inline: true)
                    use.setAccessibilityLabel("Use ChatGPT")
                    use.setAccessibilityIdentifier("hush.ai.model.chatgpt")
                    use.isEnabled = !AssistantSetupFlow.shared.isRunning
                    use.onPress = choose
                    controls.addArrangedSubview(use)
                }
            } else {
                detail = "\(email ?? "Signed in") · Plan use not allowed yet"
                let allow = AIModelActionButton(title: "Continue with ChatGPT", inline: true, symbol: "cloud")
                allow.setAccessibilityIdentifier("hush.ai.model.chatgpt")
                allow.onPress = { [weak self] in
                    guard let self else { return }
                    account.requestConsent(for: self.purpose, in: self.window) { [weak self] in self?.select(.chatGPT) }
                }
                controls.addArrangedSubview(allow)
            }
            let menu = ChatGPTMenuButton(account: account)
            menu.onDisconnect = { [weak self] in account.disconnectReporting(in: self?.window) }
            controls.addArrangedSubview(menu)
        }
        addRow(title: "ChatGPT", detail: detail, controls: controls, separator: false)
    }

    private func selectionControl(for provider: LLMProvider) -> NSView {
        let ready = isReady(provider)
        if selected == provider && ready {
            return modelStatus("Active", name: provider.displayName, active: true)
        }
        let use = AIModelActionButton(title: "Use", inline: true)
        use.setAccessibilityLabel("Use \(provider.displayName)")
        use.isEnabled = ready && !library.isRemoving && !AssistantSetupFlow.shared.isRunning
        use.onPress = { [weak self] in self?.select(provider) }
        return use
    }

    private func controlStack() -> NSStackView {
        let controls = NSStackView(); controls.spacing = 14; controls.alignment = .centerY
        return controls
    }

    private func modelStatus(_ title: String, name: String, active: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = active ? NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.48, green: 0.85, blue: 0.64, alpha: 1)
                : NSColor(srgbRed: 0.12, green: 0.40, blue: 0.25, alpha: 1)
        } : .secondaryLabelColor
        label.setAccessibilityIdentifier("hush.ai.model.status.\(name)")
        label.setAccessibilityLabel("\(name), \(title.lowercased())")
        return label
    }

    private func addRow(title: String, detail: String, controls: NSView, separator: Bool) {
        let row = ControlCenterKeyValueRow(title: title, subtitle: detail, trailing: controls, showsSeparator: separator)
        addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    private func confirmRemoval(_ item: LocalAIModel) {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(library.name(item))?"
        let effect: String
        switch item {
        case .voice: effect = "Assistant will need voice setup again."
        case .intelligence: effect = "Any personas using this model will be turned off. Assistant will ask for setup if it needs this model."
        case .speech: effect = "If this is your active transcription model, Hush will switch to the model included with the app."
        }
        alert.informativeText = "\(effect) Your styles and settings are kept. You can download the model again from this page."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { @MainActor in
                do { try await self.library.remove(item) }
                catch {
                    let errorAlert = NSAlert(error: error)
                    await errorAlert.beginSheetModal(for: window)
                }
            }
        }
    }
}

@MainActor
final class AIModelActionButton: NSButton {
    var onPress: (() -> Void)?
    private let inline: Bool
    init(title: String, inline: Bool = false, symbol: String? = nil) {
        self.inline = inline
        super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; controlSize = .small
        if inline {
            isBordered = false
            font = .systemFont(ofSize: 12)
            if let symbol {
                image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                imagePosition = .imageLeading
                symbolConfiguration = .init(pointSize: 14, weight: .regular)
            }
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        }
        target = self; action = #selector(pressed)
        updateInk()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isEnabled: Bool { didSet { updateInk() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateInk() }
    private func updateInk() {
        guard inline else { return }
        let color: NSColor = isEnabled ? .controlAccentColor : .disabledControlTextColor
        contentTintColor = color
        attributedTitle = NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: color])
    }
    @objc private func pressed() { onPress?() }
}

/// Removal is a secondary action in a standard macOS pull-down menu.
@MainActor
private final class AIModelMenuButton: NSPopUpButton {
    var onRemove: (() -> Void)?
    init(modelName: String) {
        super.init(frame: .zero, pullsDown: true)
        isBordered = false; controlSize = .small
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        addItem(withTitle: "")
        item(at: 0)?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        let remove = NSMenuItem(title: "Remove \(modelName)…", action: #selector(removeModel), keyEquivalent: "")
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        remove.target = self
        menu?.addItem(remove)
        setAccessibilityLabel("More options for \(modelName)")
        toolTip = "Manage \(modelName)"
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 28), heightAnchor.constraint(equalToConstant: 26)])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func removeModel() { onRemove?() }
}

/// ChatGPT's secondary actions in a standard pull-down: the model, Manage usage, Disconnect.
@MainActor
private final class ChatGPTMenuButton: NSPopUpButton {
    var onDisconnect: (() -> Void)?
    private let account: ChatGPTAccount

    init(account: ChatGPTAccount) {
        self.account = account
        super.init(frame: .zero, pullsDown: true)
        isBordered = false; controlSize = .small
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        addItem(withTitle: "")
        item(at: 0)?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        if !account.models.isEmpty {
            let models = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for model in account.models {
                let item = NSMenuItem(title: model.displayName, action: #selector(chooseModel(_:)), keyEquivalent: "")
                item.representedObject = model.slug
                item.state = model.slug == Settings.shared.chatGPTModel ? .on : .off
                item.target = self
                submenu.addItem(item)
            }
            models.submenu = submenu
            menu?.addItem(models)
            menu?.addItem(.separator())
        }
        let manage = NSMenuItem(title: "Manage Usage\u{2026}", action: #selector(manageUsage), keyEquivalent: "")
        manage.target = self
        menu?.addItem(manage)
        let disconnect = NSMenuItem(title: "Disconnect ChatGPT\u{2026}", action: #selector(disconnect), keyEquivalent: "")
        disconnect.target = self
        menu?.addItem(disconnect)
        setAccessibilityLabel("More options for ChatGPT")
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 28), heightAnchor.constraint(equalToConstant: 26)])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func chooseModel(_ sender: NSMenuItem) { Settings.shared.chatGPTModel = sender.representedObject as? String }
    @objc private func manageUsage() { NSWorkspace.shared.open(ChatGPTAccount.manageUsageURL) }
    @objc private func disconnect() { onDisconnect?() }
}

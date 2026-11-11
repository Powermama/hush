import AppKit
import Combine

/// The same file lifecycle, presented in the workflow that uses each model.
@MainActor
final class AIModelControlsView: NSStackView {
    enum Scope { case personas, assistant }
    private let scope: Scope
    private let library = AIModelLibrary.shared
    private var subscriptions = Set<AnyCancellable>()

    init(scope: Scope) {
        self.scope = scope
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 0
        library.changes.merge(with: AssistantSetupFlow.shared.changes)
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        refresh()
        Task { await library.refreshSizes() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        let items: [LocalAIModel] = scope == .personas
            ? [.intelligence(.qwen35_4b), .intelligence(.qwen35_2b)]
            : [.intelligence(CoworkerModelSettings.provider), .speech(Settings.shared.modelID), .voice]
        if scope == .personas {
            addRow(title: "Apple Intelligence", detail: "On this Mac · Managed by macOS",
                   controls: selectionControl(for: .appleIntelligence), separator: true)
        }
        for (index, item) in items.enumerated() {
            let installed = library.installed(item)
            let busy = library.busy(item)
            let controls = NSStackView(); controls.spacing = 14; controls.alignment = .centerY
            if scope == .personas, case .intelligence(let provider) = item, installed, !busy {
                controls.addArrangedSubview(selectionControl(for: provider))
            } else if scope == .assistant, installed, !busy {
                let step: AssistantSetupFlow.Step
                switch item {
                case .intelligence: step = .intelligence
                case .speech: step = .transcription
                case .voice: step = .voice
                }
                let active = AssistantSetupFlow.shared.ready(step) && library.failures[item] == nil
                controls.addArrangedSubview(modelStatus(active ? "Active" : "Downloaded", name: library.name(item), active: active))
            }
            if !library.bundled(item) {
                let control: NSControl
                if installed && !busy {
                    let menu = AIModelMenuButton(modelName: library.name(item))
                    menu.onRemove = { [weak self] in self?.confirmRemoval(item) }
                    control = menu
                } else {
                    let button = AIModelActionButton(title: busy ? "Cancel" : "Download", inline: true,
                                                     symbol: busy ? "xmark.circle" : "arrow.down.circle")
                    button.setAccessibilityLabel("\(busy ? "Cancel" : "Download") \(library.name(item))")
                    button.onPress = { [weak self] in
                        guard let self else { return }
                        if library.busy(item) { library.cancel(item) }
                        else { library.download(item) }
                    }
                    control = button
                }
                control.setAccessibilityIdentifier("hush.ai.model.\(item.id)")
                control.isEnabled = !library.isRemoving && !AssistantSetupFlow.shared.isRunning
                controls.addArrangedSubview(control)
            }
            let purpose: String
            switch item {
            case .intelligence: purpose = scope == .personas ? "Writing engine" : "Intelligence & vision"
            case .speech: purpose = "Listening"
            case .voice: purpose = "Spoken replies · English"
            }
            var detail = purpose
            if let failure = library.failures[item] { detail = failure }
            else if busy { detail = library.detail(item) }
            else if library.bundled(item) { detail += " · Included with Hush" }
            else if let size = library.sizes[item], installed { detail += " · " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
            else { detail += installed ? " · On this Mac" : " · Not installed" }
            addRow(title: library.name(item), detail: detail, controls: controls, separator: index < items.count - 1)
        }
    }

    private func selectionControl(for provider: LLMProvider) -> NSView {
        let ready = LLMRuntime.shared.isReady(provider: provider)
        if Settings.shared.llmProvider == provider && ready {
            return modelStatus("Active", name: provider.displayName, active: true)
        }
        let use = AIModelActionButton(title: "Use", inline: true)
        use.setAccessibilityLabel("Use \(provider.displayName)")
        use.isEnabled = ready && !library.isRemoving
        use.onPress = { Settings.shared.llmProvider = provider }
        return use
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

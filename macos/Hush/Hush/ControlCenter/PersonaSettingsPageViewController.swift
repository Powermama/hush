import AppKit
import Combine

@MainActor
final class PersonaSettingsPageViewController: ControlCenterPageViewController {
    private let focusEnableAI: Bool
    private let engineDisclosure = NSButton()
    private let engineSummary = NSTextField(labelWithString: "")
    private let engineModels = AIModelControlsView(scope: .personas)
    private var enginesExpanded = false
    private var subscriptions = Set<AnyCancellable>()
    private var isRefreshing = false

    private let enableSwitch = NSSwitch()
    private let personaListStack = NSStackView()
    private var editorController: PersonaEditorSheetController?

    init(focusEnableAI: Bool) {
        self.focusEnableAI = focusEnableAI
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        stack.spacing = 18
        addFullWidth(AISettingsHeader(title: "Personas", detail: "Your words, with your own finishing touch.", symbol: "sparkles"))
        buildMasterCard()
        buildPersonaWorkspace()
        buildProviders()
        bind()
        refresh()
        if focusEnableAI {
            DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(self?.enableSwitch) }
        }
    }

    private func buildMasterCard() {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Style your dictation")
        icon.symbolConfiguration = .init(pointSize: 23, weight: .medium)
        icon.contentTintColor = DesignTokens.brand500
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let title = NSTextField(labelWithString: "Style your dictation")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        let detail = NSTextField(wrappingLabelWithString: "Apply your chosen writing style after you speak.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        enableSwitch.setAccessibilityLabel("Style your dictation")
        enableSwitch.setAccessibilityIdentifier("hush.personas.enabled")
        enableSwitch.target = self
        enableSwitch.action = #selector(enableChanged(_:))

        let row = NSStackView(views: [icon, labels, NSView(), enableSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 13
        addFullWidth(makeCard(content: row, insets: .init(top: 14, left: 16, bottom: 14, right: 16)))
    }

    private func buildProviders() {
        engineDisclosure.setButtonType(.onOff)
        engineDisclosure.isBordered = false
        engineDisclosure.font = .systemFont(ofSize: 14, weight: .semibold)
        engineDisclosure.imagePosition = .imageLeading
        engineDisclosure.title = "Writing engine"
        engineDisclosure.setAccessibilityLabel("Writing engine")
        engineDisclosure.setAccessibilityIdentifier("hush.personas.engines")
        engineDisclosure.target = self; engineDisclosure.action = #selector(toggleEngines)
        engineSummary.font = .systemFont(ofSize: 12); engineSummary.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [engineDisclosure, NSView(), engineSummary])
        heading.spacing = 12
        let content = NSStackView(views: [heading, engineModels])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 10
        heading.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        engineModels.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        addFullWidth(makeCard(content: content, insets: .init(top: 14, left: 16, bottom: 14, right: 16)))
        addFullWidth(subtitle("Choose an engine for your writing. Downloads stay on this Mac and can also be used by Assistant."))
        enginesExpanded = focusEnableAI
        refreshProviders()
    }
    @objc private func toggleEngines() { enginesExpanded.toggle(); refreshProviders() }

    private func buildPersonaWorkspace() {
        let addButton = NSButton(title: "Add Persona", target: self, action: #selector(addPersona(_:)))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.bezelStyle = .rounded
        let header = NSStackView(views: [sectionTitle("Choose your style"), NSView(), addButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        addFullWidth(header)
        personaListStack.orientation = .vertical
        personaListStack.alignment = .leading
        personaListStack.spacing = 10
        addFullWidth(personaListStack)
    }

    private func bind() {
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        LLMRuntime.shared.stateChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshProviders() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let enabled = Settings.shared.llmProvider != .off
        enableSwitch.state = enabled ? .on : .off
        refreshProviders()
        refreshPersonaList()
    }

    private func refreshProviders() {
        engineDisclosure.state = enginesExpanded ? .on : .off
        engineDisclosure.image = NSImage(systemSymbolName: enginesExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        engineModels.isHidden = !enginesExpanded
        engineSummary.stringValue = Settings.shared.llmProvider == .off ? "Choose an engine" : Settings.shared.llmProvider.displayName
    }

    private func refreshPersonaList() {
        personaListStack.arrangedSubviews.forEach {
            personaListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let activeID = Settings.shared.activeProfileID
        let profiles = Settings.shared.profiles
        for offset in stride(from: 0, to: profiles.count, by: 2) {
            let pair = NSStackView()
            pair.orientation = .horizontal
            pair.distribution = .fillEqually
            pair.spacing = 10
            for profile in profiles[offset..<min(offset + 2, profiles.count)] {
                let row = PersonaLibraryRow(profile: profile, isSelected: profile.id == activeID)
                row.onSelect = { Settings.shared.activeProfileID = profile.id }
                row.onEdit = { [weak self] in self?.presentEditor(for: profile, isNew: false) }
                pair.addArrangedSubview(row)
            }
            if pair.arrangedSubviews.count == 1 { pair.addArrangedSubview(NSView()) }
            personaListStack.addArrangedSubview(pair)
            pair.widthAnchor.constraint(equalTo: personaListStack.widthAnchor).isActive = true
        }
    }

    @objc private func enableChanged(_ sender: NSSwitch) {
        if sender.state == .off {
            Settings.shared.llmProvider = .off
            return
        }
        LLMRuntime.shared.refreshAppleAvailability()
        if LLMRuntime.shared.appleAvailability == .available {
            Settings.shared.llmProvider = .appleIntelligence
            return
        }
        for provider in LLMProvider.localFallbackOrder {
            guard let model = LLMRuntime.QwenModel(provider: provider) else { continue }
            switch LLMRuntime.shared.qwenState(for: model) {
            case .downloaded, .warm:
                Settings.shared.llmProvider = provider
                return
            default:
                continue
            }
        }
        sender.state = .off
        enginesExpanded = true
        refreshProviders()
    }

    @objc private func addPersona(_ sender: Any?) {
        let profile = Profile(
            id: UUID(),
            name: uniqueName("New persona", profiles: Settings.shared.profiles),
            systemPrompt: "",
            creativity: 0.3
        )
        presentEditor(for: profile, isNew: true)
    }

    private func presentEditor(for profile: Profile, isNew: Bool) {
        guard editorController == nil, let parentWindow = view.window else { return }
        let editor = PersonaEditorSheetController(
            profile: profile,
            isNew: isNew,
            aiReady: Settings.shared.llmProvider != .off && LLMRuntime.shared.isActiveProviderReady,
            canDelete: !isNew && Settings.shared.profiles.count > 1
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = isNew ? "New Persona" : "Edit Persona"
        panel.contentViewController = editor
        editorController = editor

        let dismiss = { [weak self, weak parentWindow, weak panel] in
            guard let panel else { return }
            parentWindow?.endSheet(panel)
            self?.editorController = nil
        }
        editor.onCancel = dismiss
        editor.onSave = { [weak self] draft in
            var profiles = Settings.shared.profiles
            if let index = profiles.firstIndex(where: { $0.id == draft.id }) {
                profiles[index] = draft
            } else {
                profiles.append(draft)
                Settings.shared.activeProfileID = draft.id
            }
            Settings.shared.profiles = profiles
            dismiss()
            self?.refreshPersonaList()
        }
        editor.onDuplicate = { [weak self] draft in
            guard let self else { return }
            var profiles = Settings.shared.profiles
            let copy = Profile(
                id: UUID(),
                name: self.uniqueName("\(draft.name) copy", profiles: profiles),
                systemPrompt: draft.systemPrompt,
                creativity: draft.creativity,
                iconName: draft.iconName
            )
            profiles.append(copy)
            Settings.shared.profiles = profiles
            Settings.shared.activeProfileID = copy.id
            dismiss()
        }
        editor.onDelete = { [weak self] profileID in
            var profiles = Settings.shared.profiles
            guard profiles.count > 1 else { return }
            profiles.removeAll { $0.id == profileID }
            Settings.shared.profiles = profiles
            if Settings.shared.activeProfileID == profileID {
                Settings.shared.activeProfileID = profiles[0].id
            }
            dismiss()
            self?.refreshPersonaList()
        }
        parentWindow.beginSheet(panel)
    }

    private func uniqueName(_ base: String, profiles: [Profile]) -> String {
        let names = Set(profiles.map(\.name))
        if !names.contains(base) { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

}

@MainActor
private final class PersonaLibraryRow: NSView {
    var onSelect: (() -> Void)?
    var onEdit: (() -> Void)?
    private let selected: Bool
    private let selectionButton = NSButton()

    init(profile: Profile, isSelected: Bool) {
        selected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        updateColors()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: PersonaIconResolver.symbol(for: profile), accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 19, weight: .medium)
        icon.contentTintColor = isSelected ? DesignTokens.brand500 : .secondaryLabelColor
        let name = NSTextField(labelWithString: profile.name)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        let summary = NSTextField(wrappingLabelWithString: Self.summary(profile))
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = .secondaryLabelColor
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byTruncatingTail
        summary.toolTip = profile.systemPrompt
        let edit = NSButton(title: "Edit", target: self, action: #selector(editTapped))
        edit.bezelStyle = .rounded; edit.controlSize = .small
        edit.setAccessibilityLabel("Edit \(profile.name)")
        selectionButton.title = ""
        selectionButton.isBordered = false
        selectionButton.target = self; selectionButton.action = #selector(selectTapped)
        selectionButton.setAccessibilityLabel("Use \(profile.name)")
        selectionButton.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        selectionButton.toolTip = "Use \(profile.name) for dictation"
        for child in [icon, name, summary, selectionButton, edit] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 108),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: edit.leadingAnchor, constant: -8),
            edit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            edit.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            summary.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            summary.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 11),
            selectionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionButton.topAnchor.constraint(equalTo: topAnchor),
            selectionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    @objc private func selectTapped() { onSelect?() }
    @objc private func editTapped() { onEdit?() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = selected ? DesignTokens.brand500.withAlphaComponent(0.10).cgColor : ControlCenterStyle.cardBackground.cgColor
            layer?.borderWidth = selected ? 1.5 : 0
            layer?.borderColor = DesignTokens.brand500.withAlphaComponent(0.55).cgColor
        }
    }
    private static func summary(_ profile: Profile) -> String {
        // Only describe an unmodified built-in. Custom instructions remain the
        // source of truth, even if someone keeps a built-in's name or ID.
        if let original = Profile.seededProfiles.first(where: { $0.id == profile.id }), original.systemPrompt == profile.systemPrompt {
            switch profile.id {
            case Profile.SeedID.polish: return "A lighter touch. Fix grammar and keep your voice."
            case Profile.SeedID.business: return "Clear, confident and ready for work."
            case Profile.SeedID.casual: return "Easygoing words that sound like you."
            case Profile.SeedID.slack: return "Short, direct and ready for the team."
            case Profile.SeedID.codeComment: return "Concise comments that get to the point."
            default: break
            }
        }
        let text = profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Add your own writing instructions." : text
    }
}

@MainActor
private final class PersonaEditorSheetController: NSViewController, NSTextViewDelegate {
    var onSave: ((Profile) -> Void)?
    var onCancel: (() -> Void)?
    var onDuplicate: ((Profile) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private let original: Profile
    private let isNew: Bool
    private let aiReady: Bool
    private let canDelete: Bool
    private var selectedIconName: String?

    private let iconButton = NSButton()
    private let nameField = NSTextField()
    private let promptTextView = NSTextView()
    private let creativitySlider = NSSlider(value: 0.3, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let creativityValue = NSTextField(labelWithString: "Balanced")
    private let tryInput = NSTextField(string: "so um the meeting is at three i think")
    private let tryButton = NSButton(title: "Try Persona", target: nil, action: nil)
    private let tryOutput = NSTextField(wrappingLabelWithString: "")

    init(profile: Profile, isNew: Bool, aiReady: Bool, canDelete: Bool) {
        original = profile
        self.isNew = isNew
        self.aiReady = aiReady
        self.canDelete = canDelete
        selectedIconName = profile.iconName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = ControlCenterStyle.contentBackground.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let title = NSTextField(labelWithString: isNew ? "Create a persona" : "Make this persona yours")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor
        let detail = NSTextField(labelWithString: "Describe the voice once, then test it before saving.")
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, detail])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4

        let actions = NSButton()
        actions.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Persona actions")
        actions.bezelStyle = .inline
        actions.isBordered = false
        actions.target = self
        actions.action = #selector(showActions(_:))
        actions.isHidden = isNew
        let headingRow = NSStackView(views: [heading, NSView(), actions])
        headingRow.orientation = .horizontal
        headingRow.alignment = .top

        iconButton.bezelStyle = .texturedRounded
        iconButton.imagePosition = .imageOnly
        iconButton.target = self
        iconButton.action = #selector(showIconMenu(_:))
        iconButton.setAccessibilityLabel("Persona icon")
        iconButton.translatesAutoresizingMaskIntoConstraints = false
        iconButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
        iconButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        nameField.stringValue = original.name
        nameField.placeholderString = "Persona name"
        nameField.font = .systemFont(ofSize: 14, weight: .semibold)
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setAccessibilityIdentifier("hush.personaEditor.name")
        let identity = NSStackView(views: [iconButton, nameField])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 9

        let instructionsLabel = fieldLabel("Instructions")
        let instructionsHint = NSTextField(labelWithString: "What should the final message sound like?")
        instructionsHint.font = .systemFont(ofSize: 10.5)
        instructionsHint.textColor = .tertiaryLabelColor
        let instructionsHeader = NSStackView(views: [instructionsLabel, NSView(), instructionsHint])
        instructionsHeader.orientation = .horizontal
        instructionsHeader.alignment = .firstBaseline

        promptTextView.string = original.systemPrompt
        promptTextView.font = .systemFont(ofSize: 12.5)
        promptTextView.textColor = .labelColor
        promptTextView.backgroundColor = .clear
        promptTextView.isRichText = false
        promptTextView.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView.isAutomaticDashSubstitutionEnabled = false
        promptTextView.textContainerInset = .init(width: 9, height: 9)
        promptTextView.delegate = self
        promptTextView.setAccessibilityIdentifier("hush.personaEditor.instructions")
        let promptScroll = NSScrollView()
        promptScroll.documentView = promptTextView
        promptScroll.hasVerticalScroller = true
        promptScroll.drawsBackground = false
        promptScroll.borderType = .noBorder
        promptScroll.wantsLayer = true
        promptScroll.layer?.cornerRadius = 10
        promptScroll.layer?.cornerCurve = .continuous
        promptScroll.layer?.backgroundColor = ControlCenterStyle.softFill.cgColor
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true

        creativitySlider.doubleValue = original.creativity
        creativitySlider.numberOfTickMarks = 3
        creativitySlider.isContinuous = true
        creativitySlider.target = self
        creativitySlider.action = #selector(creativityChanged(_:))
        creativitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        creativityValue.font = .systemFont(ofSize: 11, weight: .semibold)
        creativityValue.textColor = .secondaryLabelColor
        creativityValue.translatesAutoresizingMaskIntoConstraints = false
        creativityValue.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let creativity = NSStackView(views: [fieldLabel("Creativity"), creativitySlider, creativityValue])
        creativity.orientation = .horizontal
        creativity.alignment = .centerY
        creativity.spacing = 10

        let tryTitle = NSTextField(labelWithString: "Try it")
        tryTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let tryDetail = NSTextField(labelWithString: "Preview the current draft without saving it.")
        tryDetail.font = .systemFont(ofSize: 10.5)
        tryDetail.textColor = .secondaryLabelColor
        let tryLabels = NSStackView(views: [tryTitle, tryDetail])
        tryLabels.orientation = .vertical
        tryLabels.alignment = .leading
        tryLabels.spacing = 2

        tryInput.placeholderString = "Type a sample sentence"
        tryInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tryButton.bezelStyle = .rounded
        tryButton.target = self
        tryButton.action = #selector(tryPersona(_:))
        tryButton.isEnabled = aiReady
        let tryRow = NSStackView(views: [tryInput, tryButton])
        tryRow.orientation = .horizontal
        tryRow.spacing = 8
        tryOutput.font = .systemFont(ofSize: 11.5)
        tryOutput.textColor = .secondaryLabelColor
        tryOutput.maximumNumberOfLines = 3
        tryOutput.stringValue = aiReady ? "" : "Choose a ready AI engine to test this persona."

        let tryStack = NSStackView(views: [tryLabels, tryRow, tryOutput])
        tryStack.orientation = .vertical
        tryStack.alignment = .leading
        tryStack.spacing = 9
        tryStack.edgeInsets = .init(top: 14, left: 14, bottom: 14, right: 14)
        let tryCard = ControlCenterCardView()
        tryCard.translatesAutoresizingMaskIntoConstraints = false
        tryStack.translatesAutoresizingMaskIntoConstraints = false
        tryCard.addSubview(tryStack)
        NSLayoutConstraint.activate([
            tryStack.topAnchor.constraint(equalTo: tryCard.topAnchor),
            tryStack.bottomAnchor.constraint(equalTo: tryCard.bottomAnchor),
            tryStack.leadingAnchor.constraint(equalTo: tryCard.leadingAnchor),
            tryStack.trailingAnchor.constraint(equalTo: tryCard.trailingAnchor),
        ])

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: isNew ? "Create Persona" : "Save Changes", target: self, action: #selector(saveTapped(_:)))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), cancel, save])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let stack = NSStackView(views: [headingRow, identity, instructionsHeader, promptScroll, creativity, tryCard, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        for child in [headingRow, identity, instructionsHeader, promptScroll, creativity, tryCard, footer] {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 540),
            root.heightAnchor.constraint(equalToConstant: 480),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
        ])
        updateCreativityLabel()
        updateIcon()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nameField.window?.makeFirstResponder(self.nameField)
            if self.isNew { self.nameField.selectText(nil) }
        }
    }

    private func fieldLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private var draft: Profile {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return Profile(
            id: original.id,
            name: name.isEmpty ? original.name : name,
            systemPrompt: promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines),
            creativity: creativitySlider.doubleValue,
            iconName: selectedIconName
        )
    }

    @objc private func creativityChanged(_ sender: NSSlider) { updateCreativityLabel() }

    private func updateCreativityLabel() {
        creativityValue.stringValue = switch creativitySlider.doubleValue {
        case ..<0.15: "Faithful"
        case ..<0.55: "Balanced"
        default: "Creative"
        }
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === promptTextView,
              selectedIconName == nil else { return }
        updateIcon()
    }

    @objc private func showIconMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let automatic = NSMenuItem(title: "Auto", action: #selector(changeIcon(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.representedObject = ""
        automatic.state = selectedIconName == nil ? .on : .off
        automatic.image = NSImage(systemSymbolName: PersonaIconResolver.symbol(for: draft), accessibilityDescription: nil)
        menu.addItem(automatic)
        menu.addItem(.separator())
        for choice in PersonaIconResolver.choices {
            let item = NSMenuItem(title: choice.title, action: #selector(changeIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.symbol
            item.state = selectedIconName == choice.symbol ? .on : .off
            item.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func changeIcon(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        selectedIconName = value.isEmpty ? nil : value
        updateIcon()
    }

    private func updateIcon() {
        iconButton.image = NSImage(
            systemSymbolName: PersonaIconResolver.symbol(for: draft),
            accessibilityDescription: "Persona icon"
        )
        iconButton.toolTip = selectedIconName == nil ? "Icon: Auto" : "Change persona icon"
    }

    @objc private func tryPersona(_ sender: Any?) {
        let input = tryInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        tryButton.isEnabled = false
        tryOutput.stringValue = "Generating preview..."
        Task { @MainActor in
            defer { tryButton.isEnabled = aiReady }
            do {
                tryOutput.stringValue = try await LLMRuntime.shared.generate(transcript: input, profile: draft)
                tryOutput.textColor = .labelColor
            } catch {
                tryOutput.stringValue = error.localizedDescription
                tryOutput.textColor = DesignTokens.danger
            }
        }
    }

    @objc private func showActions(_ sender: NSButton) {
        let menu = NSMenu()
        let duplicate = NSMenuItem(title: "Duplicate Persona", action: #selector(duplicateTapped(_:)), keyEquivalent: "")
        duplicate.target = self
        menu.addItem(duplicate)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Persona...", action: #selector(deleteTapped(_:)), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = canDelete
        menu.addItem(delete)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func duplicateTapped(_ sender: Any?) { onDuplicate?(draft) }

    @objc private func deleteTapped(_ sender: Any?) {
        guard canDelete, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(original.name)?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onDelete?(self?.original.id ?? UUID())
        }
    }

    @objc private func cancelTapped(_ sender: Any?) { onCancel?() }

    @objc private func saveTapped(_ sender: Any?) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            nameField.window?.makeFirstResponder(nameField)
            return
        }
        onSave?(draft)
    }
}

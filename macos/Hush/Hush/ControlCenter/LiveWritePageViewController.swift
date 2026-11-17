import AppKit
import Combine

@MainActor
final class LiveWritePageViewController: ControlCenterPageViewController {
    private let focusEnableAI: Bool
    private let feature = AIFeatureSwitchCard(
        title: "Live Write",
        description: "Talk naturally. Ask for a text and hush writes it; anything else is cleaned up in your words.",
        symbol: "text.bubble.fill",
        colors: AIFeatureIcon.liveWrite,
        identifier: "hush.livewrite"
    )
    private let engineModels = AIModelControlsView(scope: .liveWrite)
    private var subscriptions = Set<AnyCancellable>()
    private var isRefreshing = false
    private let personaListStack = NSStackView()
    private var editorController: PersonaEditorSheetController?

    init(focusEnableAI: Bool) {
        self.focusEnableAI = focusEnableAI
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        stack.spacing = 14
        addFullWidth(aiPageHeader(title: "Live Write", detail: "Say what you want. Get finished text."))
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        feature.onToggle = { [weak self] on in self?.setLiveWrite(on) }
        feature.onAction = { [weak self] in self?.performNextStep() }
        addFullWidth(feature)
        buildExamples()
        buildEngines()
        buildPersonas()
        bind()
        refresh()
        if focusEnableAI {
            DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(self?.feature.toggle) }
        }
    }

    // MARK: Sections

    private func buildExamples() {
        addFullWidth(sectionHeading("What it does"))
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        let examples: [(String, String, String)] = [
            ("envelope", "\u{201C}Write Tom that I\u{2019}m running ten minutes late\u{201D}", "The finished message, greeting and sign-off included"),
            ("checklist", "\u{201C}To-do: call the bank, finish the slides, book the train\u{201D}", "A clean list, one item per line"),
            ("waveform", "\u{201C}Um, so I think we should, uh, move it to Monday\u{201D}", "\u{201C}I think we should move it to Monday.\u{201D}"),
        ]
        for (index, example) in examples.enumerated() {
            let icon = NSImageView(image: NSImage(systemSymbolName: example.0, accessibilityDescription: nil)!)
            icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
            icon.contentTintColor = DesignTokens.brand500
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let said = NSTextField(labelWithString: example.1)
            said.font = .systemFont(ofSize: 13)
            let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "becomes")!)
            arrow.contentTintColor = .tertiaryLabelColor
            arrow.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
            let result = NSTextField(labelWithString: example.2)
            result.font = .systemFont(ofSize: 12)
            result.textColor = .secondaryLabelColor
            let resultRow = NSStackView(views: [arrow, result]); resultRow.spacing = 6
            let texts = NSStackView(views: [said, resultRow])
            texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 3
            let line = NSStackView(views: [icon, texts])
            line.alignment = .top; line.spacing = 10
            line.translatesAutoresizingMaskIntoConstraints = false
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                line.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -16),
                line.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
                line.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -13),
            ])
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            if index < examples.count - 1 {
                let separator = ControlCenterSeparatorView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                rows.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -32).isActive = true
            }
        }
        rows.alignment = .centerX
        addFullWidth(makeCard(content: rows))
    }

    private func buildEngines() {
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        addFullWidth(sectionHeading("Writing engine"))
        engineModels.setAccessibilityIdentifier("hush.livewrite.engines")
        addFullWidth(makeCard(content: engineModels))
        addFullWidth(subtitle("Qwen 3.5 4B wrote best in hush\u{2019}s tests. Engines on this Mac keep your words here and are shared with Assistant; with ChatGPT, what you dictate is sent to OpenAI."))
    }

    private func buildPersonas() {
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        let addButton = NSButton(title: "Add Persona", target: self, action: #selector(addPersona(_:)))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        let optional = NSTextField(labelWithString: "Optional")
        optional.font = .systemFont(ofSize: 11, weight: .medium)
        optional.textColor = .tertiaryLabelColor
        let title = NSStackView(views: [sectionHeading("Personas"), optional]); title.spacing = 8; title.alignment = .firstBaseline
        let header = NSStackView(views: [title, NSView(), addButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        addFullWidth(header)
        personaListStack.orientation = .vertical
        personaListStack.alignment = .leading
        personaListStack.spacing = 0
        addFullWidth(makeCard(content: personaListStack))
        addFullWidth(subtitle("Live Write needs no persona. Add one when you want a set tone or vocabulary on top, such as formal for clients."))
    }

    private func sectionHeading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func bind() {
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        LLMRuntime.shared.stateChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let status = LiveWriteStatus.current()
        feature.update(isOn: status.isOn, status: status.text, tone: status.tone, action: status.action, progress: status.progress)
        refreshPersonaList()
    }

    private func refreshPersonaList() {
        personaListStack.arrangedSubviews.forEach {
            personaListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let personaOn = Settings.shared.dictationPersonaEnabled
        let activeID = Settings.shared.activeProfileID
        let profiles = Settings.shared.profiles
        var rows: [PersonaListRow] = [
            PersonaListRow(
                name: "None",
                summary: "Live Write decides on its own. Recommended.",
                symbol: "sparkles",
                isSelected: !personaOn,
                editable: false
            )
        ]
        rows[0].onSelect = { Settings.shared.dictationPersonaEnabled = false }
        for profile in profiles {
            let row = PersonaListRow(
                name: profile.name,
                summary: PersonaListRow.summary(profile),
                symbol: PersonaIconResolver.symbol(for: profile),
                isSelected: personaOn && profile.id == activeID,
                editable: true
            )
            row.onSelect = { Settings.shared.activeProfileID = profile.id }
            row.onEdit = { [weak self] in self?.presentEditor(for: profile, isNew: false) }
            rows.append(row)
        }
        for (index, row) in rows.enumerated() {
            row.showsSeparator = index < rows.count - 1
            personaListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: personaListStack.widthAnchor).isActive = true
        }
    }

    // MARK: Actions

    private func setLiveWrite(_ on: Bool) {
        LiveWriteStatus.setEnabled(on)
        refresh()
    }

    /// The card's button: download the recommended engine, or open the engine list.
    private func performNextStep() {
        LiveWriteStatus.downloadRecommendedEngine()
    }

    /// A new persona starts from what it should do: write what you describe, or clean up your words.
    @objc private func addPersona(_ sender: Any?) {
        let menu = NSMenu()
        for (title, mode) in [("Write for Me", Profile.Mode.compose), ("Clean Up My Words", .correct)] {
            let item = NSMenuItem(title: title, action: #selector(createPersona(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.toolTip = mode == .compose
                ? "Turns \"an email to Tom that I'm running late\" into the finished email."
                : "Fixes grammar and filler words and keeps your own words."
            menu.addItem(item)
        }
        if let button = sender as? NSButton {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func createPersona(_ sender: NSMenuItem) {
        let mode = (sender.representedObject as? String).flatMap(Profile.Mode.init(rawValue:)) ?? .correct
        let profile = Profile(
            id: UUID(),
            name: uniqueName("New persona", profiles: Settings.shared.profiles),
            systemPrompt: "",
            creativity: 0.3,
            mode: mode
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
                iconName: draft.iconName,
                mode: draft.mode
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
final class PersonaEditorSheetController: NSViewController, NSTextViewDelegate {
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
    /// What the persona does, chosen when it was created and changeable from the
    /// actions menu, so the model never has to guess it from the instructions.
    private var mode: Profile.Mode
    private let detail = NSTextField(labelWithString: "")
    // AppKit's own scrolling text view: the text view tracks the scroll view's width and
    // grows with its text. A bare NSTextView() as a document view keeps a zero-width text
    // container, so its instructions were invisible and could not be clicked into.
    private let promptScroll = NSTextView.scrollableTextView()
    private var promptTextView: NSTextView { promptScroll.documentView as! NSTextView }
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
        mode = profile.mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = ControlCenterBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let title = NSTextField(labelWithString: isNew ? "Create a persona" : "Make this persona yours")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor
        detail.font = .systemFont(ofSize: 11.5)
        detail.setAccessibilityIdentifier("hush.personaEditor.purpose")
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
        promptTextView.drawsBackground = false
        promptScroll.hasVerticalScroller = true
        promptScroll.autohidesScrollers = true
        promptScroll.drawsBackground = false
        promptScroll.borderType = .noBorder
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        let promptBox = ControlCenterFieldBackgroundView()
        promptBox.translatesAutoresizingMaskIntoConstraints = false
        promptBox.addSubview(promptScroll)
        NSLayoutConstraint.activate([
            promptScroll.topAnchor.constraint(equalTo: promptBox.topAnchor),
            promptScroll.bottomAnchor.constraint(equalTo: promptBox.bottomAnchor),
            promptScroll.leadingAnchor.constraint(equalTo: promptBox.leadingAnchor),
            promptScroll.trailingAnchor.constraint(equalTo: promptBox.trailingAnchor),
            promptBox.heightAnchor.constraint(equalToConstant: 112),
        ])

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

        let stack = NSStackView(views: [headingRow, identity, instructionsHeader, promptBox, creativity, tryCard, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        for child in [headingRow, identity, instructionsHeader, promptBox, creativity, tryCard, footer] {
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
        updatePurpose()
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
            iconName: selectedIconName,
            mode: mode
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

    /// The subtitle says what this persona does with a dictation.
    private func updatePurpose() {
        detail.stringValue = switch mode {
        case .compose: "Writes the email, message, list or steps you describe."
        case .correct: "Cleans up what you say and keeps it in your words."
        }
    }

    @objc private func showActions(_ sender: NSButton) {
        let menu = NSMenu()
        let duplicate = NSMenuItem(title: "Duplicate Persona", action: #selector(duplicateTapped(_:)), keyEquivalent: "")
        duplicate.target = self
        menu.addItem(duplicate)
        let purpose = NSMenuItem(
            title: mode == .compose ? "Clean Up My Words Instead" : "Write What I Describe Instead",
            action: #selector(switchPurpose(_:)), keyEquivalent: ""
        )
        purpose.target = self
        menu.addItem(purpose)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Persona...", action: #selector(deleteTapped(_:)), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = canDelete
        menu.addItem(delete)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func duplicateTapped(_ sender: Any?) { onDuplicate?(draft) }

    @objc private func switchPurpose(_ sender: Any?) {
        mode = mode == .compose ? .correct : .compose
        updatePurpose()
    }

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

/// Where Live Write stands, in one line, for the Live Write page and the hush AI page.
@MainActor
struct LiveWriteStatus {
    let isOn: Bool
    let text: String
    let tone: AIFeatureSwitchCard.Tone
    let action: String?
    let progress: Double?

    /// The best engine that can write right now. Qwen 3.5 4B first: it wrote best in
    /// hush's live persona benchmark (33/36 against Apple Intelligence's 28/36).
    static func bestReadyEngine() -> LLMProvider? {
        LLMRuntime.shared.refreshAppleAvailability()
        return [LLMProvider.qwen35_4b, .appleIntelligence, .qwen35_2b].first { LLMRuntime.shared.isReady(provider: $0) }
    }

    /// Turns Live Write on or off from any page. On picks the best engine that is ready;
    /// returns false when there is none yet, so the caller can show the engines.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        let settings = Settings.shared
        settings.liveWriteEnabled = on
        guard on else { return true }
        if settings.llmProvider != .off, LLMRuntime.shared.isReady(provider: settings.llmProvider) { return true }
        guard let provider = bestReadyEngine() else { return false }
        settings.llmProvider = provider
        return true
    }

    /// Starts downloading Qwen 3.5 4B and selects it, or, at a ChatGPT plan limit, opens
    /// Manage usage. False when there is nothing to do here.
    @discardableResult
    static func downloadRecommendedEngine() -> Bool {
        if Settings.shared.llmProvider == .chatGPT, ChatGPTAccount.shared.isLimitPaused {
            NSWorkspace.shared.open(ChatGPTAccount.manageUsageURL)
            return true
        }
        guard let model = LLMRuntime.QwenModel(provider: .qwen35_4b),
              case .notDownloaded = LLMRuntime.shared.qwenState(for: model) else { return false }
        Settings.shared.llmProvider = .qwen35_4b
        LLMRuntime.shared.startDownloadQwen(model)
        return true
    }

    static func current() -> LiveWriteStatus {
        let settings = Settings.shared
        let runtime = LLMRuntime.shared
        let on = settings.liveWriteEnabled
        for provider in [LLMProvider.qwen35_4b, .qwen35_2b] {
            guard let model = LLMRuntime.QwenModel(provider: provider),
                  case .downloading(let download) = runtime.qwenState(for: model) else { continue }
            let text = download.phase == .preparing
                ? "Preparing \(provider.displayName) for this Mac"
                : "Downloading \(provider.displayName)"
            return LiveWriteStatus(isOn: on, text: text, tone: .neutral, action: nil, progress: download.fraction ?? 0)
        }
        guard on else {
            return LiveWriteStatus(isOn: false, text: "Off. Your words go in as you say them.", tone: .neutral, action: nil, progress: nil)
        }
        let provider = settings.llmProvider
        if provider == .chatGPT {
            let account = ChatGPTAccount.shared
            if account.isLimitPaused {
                let fallback = bestReadyEngine().map { "Writing on \($0.displayName) for now." } ?? "Your words go in as you say them for now."
                return LiveWriteStatus(isOn: true, text: "ChatGPT plan limit reached. \(fallback)", tone: .attention, action: "Manage usage", progress: nil)
            }
            if account.isUsable {
                let persona = settings.dictationPersonaEnabled ? " with \(settings.activeProfile.name)" : ""
                return LiveWriteStatus(isOn: true, text: "Ready on \(account.modelName(settings.chatGPTModel))\(persona). Using ChatGPT plan.", tone: .ready, action: nil, progress: nil)
            }
            return LiveWriteStatus(isOn: true, text: "ChatGPT is not connected. Connect it below or choose an engine on this Mac.", tone: .attention, action: nil, progress: nil)
        }
        if provider != .off, runtime.isReady(provider: provider) {
            let persona = settings.dictationPersonaEnabled ? " with \(settings.activeProfile.name)" : ""
            return LiveWriteStatus(isOn: true, text: "Ready on \(provider.displayName)\(persona)", tone: .ready, action: nil, progress: nil)
        }
        let size = LLMProvider.qwen35_4b.approxDownloadSize.map { " (\($0))" } ?? ""
        return LiveWriteStatus(
            isOn: true,
            text: "Needs a writing engine. Dictation works as usual until then.",
            tone: .attention,
            action: "Download Qwen 3.5 4B\(size)",
            progress: nil
        )
    }
}

/// One persona in the optional list: a native, selectable row with a checkmark, its icon,
/// one line of what it does, and Edit.
@MainActor
private final class PersonaListRow: NSView {
    var onSelect: (() -> Void)?
    var onEdit: (() -> Void)?
    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }
    private let separator = ControlCenterSeparatorView()

    init(name: String, summary: String, symbol: String, isSelected: Bool, editable: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let check = NSImageView(image: NSImage(systemSymbolName: isSelected ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)!)
        check.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        check.contentTintColor = isSelected ? DesignTokens.brand500 : .tertiaryLabelColor
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = NSTextField(labelWithString: summary)
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.toolTip = summary
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 1
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [check, icon, labels, NSView()])
        row.spacing = 10
        row.alignment = .centerY
        if editable {
            let edit = NSButton(title: "Edit", target: self, action: #selector(editTapped))
            edit.bezelStyle = .rounded; edit.controlSize = .small
            edit.setAccessibilityLabel("Edit \(name)")
            row.addArrangedSubview(edit)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        addSubview(separator)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 18),
            icon.widthAnchor.constraint(equalToConstant: 20),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 72),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(name)
        setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        setAccessibilityHelp("Use \(name) for dictation")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 1 else { return super.mouseUp(with: event) }
        onSelect?()
    }
    override func accessibilityPerformPress() -> Bool { onSelect?(); return true }
    @objc private func editTapped() { onEdit?() }

    static func summary(_ profile: Profile) -> String {
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
            .replacingOccurrences(of: "\n", with: " ")
        return text.isEmpty ? "Add your own writing instructions." : text
    }
}

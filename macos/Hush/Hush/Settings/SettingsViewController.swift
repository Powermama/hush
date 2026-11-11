import AppKit
import Combine

/// All app settings on one window. Sections:
///   - Hotkey
///   - Language
///   - Transcription models  ← scrollable list, per-row download/delete/use
///   - Behaviour
///   - Permissions
@MainActor
final class SettingsViewController: NSViewController {

    private weak var coordinator: DictationCoordinator?
    private var subs = Set<AnyCancellable>()
    private var statusPollTimer: Timer?

    // Width applied to all "form" controls in the right column of each row, so
    // every row is the same width regardless of whether the control inside is a
    // popup, a hotkey recorder, or anything else.
    private static let formControlWidth: CGFloat = 260

    // Hotkey / language / behaviour controls
    private let hotkeyControl: HotkeyRecorderControl
    private let modeButton = NSPopUpButton()
    private let languageButton = NSPopUpButton()
    private let qualityButton = NSPopUpButton()
    private let autoInsertCheck = NSButton(checkboxWithTitle: "Auto-paste into the focused app",
                                            target: nil, action: nil)
    private let restoreClipboardCheck = NSButton(checkboxWithTitle: "Restore clipboard after paste",
                                                  target: nil, action: nil)
    private let showHUDCheck = NSButton(checkboxWithTitle: "Show floating HUD while dictating",
                                         target: nil, action: nil)
    private let hudPositionButton = NSPopUpButton()

    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let accessibilityButton = BrandButton(title: "Open Universal Access",
                                                   variant: .secondary, size: .sm)
    private let storeNoticeLabel = NSTextField(wrappingLabelWithString: "")

    // Post-processing section
    /// Master enable switch — the binary "is AI post-processing on at all?"
    /// control. When off, every other control in this section is hidden;
    /// when on, the provider cards appear and the user picks a backend.
    /// Brand-tinted switch (not NSSwitch — see `BrandSwitch.swift` for
    /// why). Uses `DesignTokens.brand500` for the "on" track so the
    /// control matches the rest of Hush's chrome instead of the
    /// system-wide accent colour.
    private let enableSwitch = BrandSwitch()
    private let enableTitle = NSTextField(labelWithString: "Enable AI post-processing")
    private let enableSubtitle = NSTextField(wrappingLabelWithString:
        "Rewrites your dictation with on-device AI before paste. Audio and text never leave your Mac.")

    /// Card-style rows for the on-device backends. Visual recipe
    /// matches the existing Transcription models list so Post-processing
    /// feels like part of the same product. `.off` isn't a card — that's
    /// what the master switch above represents.
    private let providerRows = Dictionary(
        uniqueKeysWithValues: LLMProvider.engineCatalog.map {
            ($0, ProviderRowView(provider: $0))
        }
    )

    /// Wraps the cards + profile + prompt + try-it section. Hidden in one
    /// call when `enableSwitch` is off.
    private let postProcessingBody = NSStackView()

    // "Try it" sandbox — lets users see what the active profile produces
    // without doing a real dictation.
    private let tryInputField = NSTextField(string: "so um the meeting is at three i think")
    private let tryButton = BrandButton(title: "Try it",
                                         variant: .secondary, size: .sm)
    private let tryOutputLabel = NSTextField(wrappingLabelWithString: "")

    /// Profile picker — a popup gives a smooth, dense way to switch among
    /// any number of profiles without each one stealing a whole card row.
    /// Cards are reserved for backends (Apple Intelligence / Qwen) and
    /// transcription models, where the visual weight earns its keep.
    private let profilePopup = NSPopUpButton()
    /// Single ⋯ menu that holds every profile-management action (Edit,
    /// New, Duplicate, Delete). Replaces the four-button cluster that
    /// was overwhelming the row — same macOS pattern Finder / Notes /
    /// Reminders use for "actions on the selected item."
    private let manageMenuButton = NSButton()

    /// Editor controls — hosted inside `profileEditorPopover` rather than
    /// inline, so the main Post-processing section stays focused on
    /// "what's enabled / which profile is active" without competing with
    /// the (much taller) edit surface.
    private let profileNameField = NSTextField()
    private let creativitySlider = NSSlider(value: 0.3, minValue: 0, maxValue: 1,
                                             target: nil, action: nil)
    private let creativityValueLabel = NSTextField(labelWithString: "Balanced")
    private var profileEditorPopover: NSPopover?
    private let promptTextView = NSTextView()
    private let promptScrollView = NSScrollView()
    private let postProcessHelp = NSTextField(wrappingLabelWithString: "")

    // Models list
    private var modelRows: [String: ModelRowView] = [:]
    // Model picker — collapses the full model list into one row that opens a popover.
    private let modelPopover = NSPopover()
    private let modelPickerCard = NSView()
    private let modelPickerDot = CALayer()
    private let modelPickerTitle = NSTextField(labelWithString: "")
    private let modelPickerSub = NSTextField(labelWithString: "")
    private let modelsScrollView = NSScrollView()
    private let modelsStack = NSStackView()
    private let modelsHelp = NSTextField(wrappingLabelWithString:
        "Tap Use to switch the active model. New models download automatically on first use.")
    private let reloadCatalogButton = NSButton()
    private let reloadSpinner = NSProgressIndicator()

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        self.hotkeyControl = HotkeyRecorderControl(combo: Settings.shared.hotkey)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 790))
        root.wantsLayer = true
        root.layer?.backgroundColor = DesignTokens.paper.cgColor
        view = root

        // Wrap the settings stack in a vertical NSScrollView so that the
        // window fits on small laptop displays. App Review flagged truncated
        // content on a 1280×800 reviewer screen — without this scroll the
        // bottom of the panel (Permissions, App Store notice) was unreachable.
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        root.addSubview(scrollView)

        // `documentView` is the container the scroll view scrolls *over*.
        // Its width is locked to the visible content area so we never get
        // horizontal scrolling; height grows with the stack content.
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        documentView.addSubview(outer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            // Match document width to the scroll view's visible content width
            // (NSClipView). Outer stack then pins to documentView, so all
            // existing `widthAnchor.constraint(equalTo: outer.widthAnchor, …)`
            // constraints inside the body keep working without changes.
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            outer.topAnchor.constraint(equalTo: documentView.topAnchor),
            outer.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: documentView.trailingAnchor)
        ])

        // Hotkey section
        outer.addArrangedSubview(sectionTitle("Hotkey"))
        outer.addArrangedSubview(makeRow(title: "Push-to-talk hotkey", control: hotkeyControl))
        outer.addArrangedSubview(makeRow(title: "Mode", control: modeButton))
        let modeHelp = NSTextField(wrappingLabelWithString:
            "Hold — record while the hotkey is pressed, release to transcribe. " +
            "Toggle — press once to start, again to stop.")
        modeHelp.font = NSFont.systemFont(ofSize: 11)
        modeHelp.textColor = DesignTokens.inkMute
        modeHelp.preferredMaxLayoutWidth = 540
        outer.addArrangedSubview(modeHelp)
        outer.addArrangedSubview(makeRow(title: "Spoken language", control: languageButton))
        outer.addArrangedSubview(makeRow(title: "Quality", control: qualityButton))
        let qualityHelp = NSTextField(wrappingLabelWithString:
            "Whisper occasionally derails on noisy or Bluetooth audio and " +
            "produces gibberish (the classic “1, 2, 3, 1, 2, 3…” loop). When " +
            "that happens, it can re-run the failed chunk with a touch of " +
            "randomness to recover.\n\n" +
            "• Fast — one greedy pass, no recovery. Quickest, but a bad " +
            "capture stays bad.\n" +
            "• Balanced — one safety-net retry. Costs nothing on clean audio.\n" +
            "• Best quality — up to three retries with progressively more " +
            "randomness. Best chance to escape a degenerate decode; you only " +
            "pay extra time when the first pass was already going to fail.")
        qualityHelp.font = NSFont.systemFont(ofSize: 11)
        qualityHelp.textColor = DesignTokens.inkMute
        qualityHelp.preferredMaxLayoutWidth = 540
        outer.addArrangedSubview(qualityHelp)
        outer.addArrangedSubview(divider())

        // Transcription model — one summary row that opens a popover with the
        // full list (each model shows size, description, and install state).
        // Keeps advanced choice a click away without crowding the panel.
        outer.addArrangedSubview(sectionTitle("Transcription model"))
        modelsHelp.font = .systemFont(ofSize: 11)
        modelsHelp.textColor = DesignTokens.inkMute
        modelsHelp.preferredMaxLayoutWidth = 540
        outer.addArrangedSubview(modelsHelp)

        configureModelsList()
        setupModelPopover()

        let picker = makeModelPicker()
        outer.addArrangedSubview(picker)
        picker.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -56).isActive = true
        // Lock the inner stack to the scroll view's content width so each row stretches to the
        // visible scroll area instead of fading into empty space at the right edge.
        modelsStack.widthAnchor.constraint(equalTo: modelsScrollView.contentView.widthAnchor).isActive = true
        updateModelSummary()

        outer.addArrangedSubview(divider())

        // Behaviour section
        outer.addArrangedSubview(sectionTitle("Behaviour"))
        outer.addArrangedSubview(autoInsertCheck)
        outer.addArrangedSubview(restoreClipboardCheck)
        outer.addArrangedSubview(showHUDCheck)
        outer.addArrangedSubview(makeRow(title: "HUD position", control: hudPositionButton))

        outer.addArrangedSubview(divider())

        // Post-processing section — see PRD §14.8 + v3 rework. Flow:
        //   1. User picks an AI provider by tapping a card (Off / Apple /
        //      Qwen). Each card shows its status inline (Ready / Needs
        //      Download / Downloading… / Unavailable) so users see at a
        //      glance what every provider's state is.
        //   2. If Qwen and not downloaded: tap "Download" on the Qwen card.
        //      Progress + Cancel live inside the card itself.
        //   3. Profile picker + prompt editor: enabled only once the chosen
        //      provider is actually ready to run.
        //
        // The card-row layout mirrors `ModelRowView` from the Transcription
        // models section so the two sections share visual DNA — same
        // status dot + title + subtitle + action button pattern.
        outer.addArrangedSubview(sectionTitle("Post-processing"))

        // Master enable switch row. Title + switch on top, descriptive
        // subtitle below. When off, the rest of the section is hidden.
        enableTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        enableTitle.textColor = DesignTokens.ink
        enableSubtitle.font = NSFont.systemFont(ofSize: 11)
        enableSubtitle.textColor = DesignTokens.inkMute
        enableSubtitle.preferredMaxLayoutWidth = 540
        let enableRow = NSStackView(views: [enableTitle, NSView(), enableSwitch])
        enableRow.orientation = .horizontal
        enableRow.alignment = .centerY
        enableRow.distribution = .fill
        outer.addArrangedSubview(enableRow)
        outer.addArrangedSubview(enableSubtitle)
        enableRow.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -56).isActive = true

        // Everything below the switch lives in `postProcessingBody`. Hidden
        // in one assignment when the switch is off.
        postProcessingBody.orientation = .vertical
        postProcessingBody.alignment = .leading
        postProcessingBody.spacing = 14
        postProcessingBody.translatesAutoresizingMaskIntoConstraints = false
        outer.addArrangedSubview(postProcessingBody)
        postProcessingBody.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -56).isActive = true

        // Provider cards come from the shared engine catalog. `.off` isn't
        // a card - that's the master switch state above. Each Qwen card
        // carries its own download/cancel/delete
        // actions, scoped to that variant only.
        //
        // Order: smaller/faster Qwen 2.5 first, then larger/better Qwen
        // 3 — matches the "smaller → larger" pattern users expect when
        // scanning trade-offs top-to-bottom.
        for provider in LLMProvider.engineCatalog {
            guard let row = providerRows[provider] else { continue }
            row.onUse = { [weak self] p in self?.useProvider(p) }
            row.onCancel = { [weak self] p in self?.cancelDownload(for: p) }
            row.onDelete = { [weak self] p in self?.deleteModel(for: p) }
            postProcessingBody.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: postProcessingBody.widthAnchor).isActive = true
        }

        // Profile picker — dense dropdown + management buttons in one
        // row. Cards would over-weight what's essentially a select.
        // Editing (name, creativity, prompt, try-it) opens in a
        // dedicated popover anchored to the Edit button, so the main
        // section stays focused on "what's enabled, what's active."
        postProcessingBody.addArrangedSubview(sectionTitle("Profiles"))

        profilePopup.translatesAutoresizingMaskIntoConstraints = false
        profilePopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Tight, content-sized label so the popup sits right next to
        // "Active" with the stack view's standard 8pt spacing — instead
        // of the 180pt dead zone the form's `makeRow` baseline imposes.
        // No other controls in this section are column-aligned, so
        // breaking the form's label grid here is harmless and reads as
        // a deliberate hierarchy difference (this row is its own
        // self-contained selector).
        let profileLabel = NSTextField(labelWithString: "Active")
        profileLabel.font = NSFont.systemFont(ofSize: 12)
        profileLabel.textColor = DesignTokens.ink
        profileLabel.translatesAutoresizingMaskIntoConstraints = false
        profileLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Single ⋯ icon button next to the dropdown. Click → NSMenu with
        // Edit / New / Duplicate / Delete. Lets the row breathe.
        manageMenuButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                          accessibilityDescription: "Manage profile")
        manageMenuButton.bezelStyle = .regularSquare
        manageMenuButton.isBordered = false
        manageMenuButton.contentTintColor = DesignTokens.ink
        manageMenuButton.translatesAutoresizingMaskIntoConstraints = false
        manageMenuButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        manageMenuButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        manageMenuButton.toolTip = "Manage profile — edit, new, duplicate, delete."

        let profileRow = NSStackView(views: [profileLabel, profilePopup, manageMenuButton])
        profileRow.orientation = .horizontal
        profileRow.spacing = 8
        profileRow.alignment = .centerY
        postProcessingBody.addArrangedSubview(profileRow)

        // Editor controls are configured here so their constraints exist
        // before the popover hosts them, but they're added to the
        // popover's content view (not `postProcessingBody`).
        configureEditorControls()

        // Help text — single line under the profile row. The big editor
        // (prompt, creativity, try-it) lives in `profileEditorPopover`.
        postProcessHelp.font = NSFont.systemFont(ofSize: 11)
        postProcessHelp.textColor = DesignTokens.inkMute
        postProcessHelp.preferredMaxLayoutWidth = 540
        postProcessHelp.stringValue =
            "Apple Intelligence and Qwen run entirely on this Mac. Qwen needs a one-time download."
        postProcessingBody.addArrangedSubview(postProcessHelp)

        outer.addArrangedSubview(divider())
        outer.addArrangedSubview(sectionTitle("Permissions"))

        let permRow = NSStackView(views: [accessibilityStatus, accessibilityButton])
        permRow.orientation = .horizontal
        permRow.spacing = 12
        permRow.alignment = .centerY
        outer.addArrangedSubview(permRow)

        storeNoticeLabel.font = NSFont.systemFont(ofSize: 11)
        storeNoticeLabel.textColor = DesignTokens.inkMute
        storeNoticeLabel.preferredMaxLayoutWidth = 540
        outer.addArrangedSubview(storeNoticeLabel)

        configureControls()
        styleCheckboxes()
        refreshFromSettings()
        refreshProviderControls()
        refreshAccessibilityStatus()
        bindCoordinator()
        bindCatalogService()
        bindSettingsChanges()
        refreshModelStates()
    }

    /// Watch the two signals that affect the post-processing section:
    ///   1. `Settings.didChange` — user picked a different provider, profile,
    ///      or edited a prompt elsewhere (menu-bar submenu, etc.).
    ///   2. `LLMRuntime.stateChange` — model download progress, Apple
    ///      Intelligence availability flip, load completion.
    /// Both route into the single `refreshProviderControls()` rebuild.
    private func bindSettingsChanges() {
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshProviderControls() }
            .store(in: &subs)
        LLMRuntime.shared.stateChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshProviderControls() }
            .store(in: &subs)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Poll permission state (and the global-event counter) every second so the user
        // sees the indicator turn green as soon as they grant Input Monitoring.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAccessibilityStatus() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusPollTimer = timer
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    private func sectionTitle(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        l.textColor = DesignTokens.inkMute
        return l
    }

    /// "TRANSCRIPTION MODELS" with a small reload button on the right edge that
    /// re-fetches the live catalog from HuggingFace. The caller is expected to
    /// install the row's width constraint *after* adding it to the outer
    /// stack — the row has no superview at construction time.
    private func makeModelsHeaderRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(sectionTitle("Transcription models"))

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        reloadSpinner.style = .spinning
        reloadSpinner.controlSize = .small
        reloadSpinner.isDisplayedWhenStopped = false
        reloadSpinner.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(reloadSpinner)

        reloadCatalogButton.image = NSImage(systemSymbolName: "arrow.clockwise",
                                             accessibilityDescription: "Reload model catalog")
        reloadCatalogButton.bezelStyle = .regularSquare
        reloadCatalogButton.isBordered = false
        reloadCatalogButton.contentTintColor = DesignTokens.inkMute
        reloadCatalogButton.toolTip = "Refresh model list from HuggingFace"
        reloadCatalogButton.target = self
        reloadCatalogButton.action = #selector(refreshCatalogTapped(_:))
        reloadCatalogButton.translatesAutoresizingMaskIntoConstraints = false
        reloadCatalogButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        reloadCatalogButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(reloadCatalogButton)

        return row
    }

    private func makeRow(title: String, control: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: title)
        l.font = NSFont.systemFont(ofSize: 12)
        l.textColor = DesignTokens.ink
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 180).isActive = true
        // Pin every form control to the same width so each row aligns visually.
        // Without this, an `NSPopUpButton` only takes its intrinsic title width,
        // so the Mode/Language/HUD-position rows render narrower than the
        // composite Hotkey row.
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Self.formControlWidth).isActive = true
        let row = NSStackView(views: [l, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func divider() -> NSBox {
        let b = NSBox()
        b.boxType = .custom
        b.fillColor = DesignTokens.paperBorder
        b.borderColor = .clear
        b.borderWidth = 0
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return b
    }

    private func styleCheckboxes() {
        for cb in [autoInsertCheck, restoreClipboardCheck, showHUDCheck] {
            cb.contentTintColor = DesignTokens.ink
        }
    }

    // MARK: - Models list

    private func configureModelsList() {
        modelsStack.orientation = .vertical
        modelsStack.alignment = .leading
        modelsStack.spacing = 10
        modelsStack.translatesAutoresizingMaskIntoConstraints = false
        // Horizontal insets match the inter-row spacing so the gutter on the
        // sides of each cell visually equals the gap between rows.
        modelsStack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // Rows are populated by `bindCatalogService()` once the live catalog
        // emits — see `rebuildModelRows(_:)`. Until then the bundled model is
        // the only entry (the service publishes it synchronously on init).
        rebuildModelRows(ModelCatalogService.shared.models.value)

        // Background, border and rounded corners live on a wrapper container
        // (see `loadView`). The scroll view itself is fully transparent.
        modelsScrollView.drawsBackground = false
        modelsScrollView.borderType = .noBorder
        modelsScrollView.hasVerticalScroller = true
        modelsScrollView.scrollerStyle = .overlay
        modelsScrollView.documentView = modelsStack
        modelsScrollView.contentView.postsBoundsChangedNotifications = false
        modelsScrollView.contentView.drawsBackground = false
    }

    /// Reconcile the visible row list with whatever the catalog service is
    /// currently publishing. Removes rows for IDs that disappeared, creates
    /// rows for new IDs, and re-orders the stack so the bundled row is first.
    private func rebuildModelRows(_ models: [ModelInfo]) {
        let newIDs = Set(models.map(\.id))

        // Remove any row whose model is no longer in the live catalog.
        for (id, row) in modelRows where !newIDs.contains(id) {
            modelsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            modelRows.removeValue(forKey: id)
        }

        // Strip arrangement so we can re-add in the new order.
        for view in modelsStack.arrangedSubviews {
            modelsStack.removeArrangedSubview(view)
        }

        let stackInsets = modelsStack.edgeInsets.left + modelsStack.edgeInsets.right
        for model in models {
            let row: ModelRowView
            let isNew: Bool
            if let existing = modelRows[model.id] {
                row = existing
                isNew = false
            } else {
                row = ModelRowView(model: model)
                row.onUse = { [weak self] in self?.useModel($0) }
                row.onDelete = { [weak self] in self?.deleteModel($0) }
                row.translatesAutoresizingMaskIntoConstraints = false
                modelRows[model.id] = row
                isNew = true
            }
            // Add to the stack first so the row and the stack share an ancestor;
            // only THEN install the width constraint that ties them together.
            // Activating it before `addArrangedSubview` raises
            // "no common ancestor" / NSGenericException.
            modelsStack.addArrangedSubview(row)
            if isNew {
                row.widthAnchor.constraint(equalTo: modelsStack.widthAnchor,
                                           constant: -stackInsets).isActive = true
            }
        }

        refreshModelStates()
    }

    private func refreshModelStates() {
        let active = Settings.shared.modelID
        for (id, row) in modelRows {
            let isBundled = ModelInfo.bundledIDs.contains(id)
            let isCached = ModelManager.isInCache(id)
            switch (id == active, isBundled, isCached) {
            case (true, true, _):       row.apply(.bundledActive)
            case (true, false, _):      row.apply(.active)
            case (false, true, _):      row.apply(.bundled)
            case (false, false, true):  row.apply(.downloaded)
            case (false, false, false): row.apply(.notDownloaded)
            }
        }
        updateModelSummary()
    }

    // MARK: - Model picker (popover)

    /// The single always-visible row: status dot + current model name + a
    /// friendly one-liner + a chevron. Clicking it opens the model popover.
    private func makeModelPicker() -> NSView {
        modelPickerCard.wantsLayer = true
        modelPickerCard.translatesAutoresizingMaskIntoConstraints = false
        modelPickerCard.layer?.backgroundColor = DesignTokens.card.cgColor
        modelPickerCard.layer?.cornerRadius = DesignTokens.radius
        modelPickerCard.layer?.cornerCurve = .continuous
        modelPickerCard.layer?.borderWidth = 1
        modelPickerCard.layer?.borderColor = DesignTokens.paperBorder.cgColor
        modelPickerCard.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let dotHost = NSView()
        dotHost.wantsLayer = true
        dotHost.translatesAutoresizingMaskIntoConstraints = false
        dotHost.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dotHost.heightAnchor.constraint(equalToConstant: 10).isActive = true
        modelPickerDot.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        modelPickerDot.cornerRadius = 5
        modelPickerDot.backgroundColor = DesignTokens.good.cgColor
        dotHost.layer?.addSublayer(modelPickerDot)

        modelPickerTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        modelPickerTitle.textColor = DesignTokens.ink
        modelPickerSub.font = .systemFont(ofSize: 11)
        modelPickerSub.textColor = DesignTokens.inkDim
        let textCol = NSStackView(views: [modelPickerTitle, modelPickerSub])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down",
                                accessibilityDescription: "Choose model")
        chevron.contentTintColor = DesignTokens.inkMute
        chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [dotHost, textCol, NSView(), chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        modelPickerCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: modelPickerCard.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: modelPickerCard.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: modelPickerCard.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleModelPopover(_:)))
        modelPickerCard.addGestureRecognizer(click)
        return modelPickerCard
    }

    /// Popover body: the "Transcription models" header (with catalog refresh)
    /// over the scrollable list of `ModelRowView`s.
    private func setupModelPopover() {
        let header = makeModelsHeaderRow()
        header.translatesAutoresizingMaskIntoConstraints = false

        let scrollWrap = NSView()
        scrollWrap.wantsLayer = true
        scrollWrap.translatesAutoresizingMaskIntoConstraints = false
        scrollWrap.layer?.backgroundColor = DesignTokens.paperDeep.cgColor
        scrollWrap.layer?.cornerRadius = DesignTokens.radius
        scrollWrap.layer?.cornerCurve = .continuous
        scrollWrap.layer?.borderWidth = 1
        scrollWrap.layer?.borderColor = DesignTokens.paperBorder.cgColor
        scrollWrap.layer?.masksToBounds = true
        scrollWrap.addSubview(modelsScrollView)
        modelsScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modelsScrollView.topAnchor.constraint(equalTo: scrollWrap.topAnchor, constant: 1),
            modelsScrollView.bottomAnchor.constraint(equalTo: scrollWrap.bottomAnchor, constant: -1),
            modelsScrollView.leadingAnchor.constraint(equalTo: scrollWrap.leadingAnchor, constant: 1),
            modelsScrollView.trailingAnchor.constraint(equalTo: scrollWrap.trailingAnchor, constant: -1),
        ])

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 424))
        content.wantsLayer = true
        content.layer?.backgroundColor = DesignTokens.paper.cgColor
        let stack = NSStackView(views: [header, scrollWrap])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scrollWrap.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scrollWrap.heightAnchor.constraint(equalToConstant: 330),
        ])

        let vc = NSViewController()
        vc.view = content
        modelPopover.contentViewController = vc
        modelPopover.behavior = .transient
        modelPopover.contentSize = NSSize(width: 470, height: 424)
    }

    @objc private func toggleModelPopover(_ sender: Any?) {
        if modelPopover.isShown {
            modelPopover.performClose(sender)
        } else {
            modelPopover.show(relativeTo: modelPickerCard.bounds,
                              of: modelPickerCard, preferredEdge: .maxY)
        }
    }

    /// Refresh the summary row from the active model + its install state.
    private func updateModelSummary() {
        let id = Settings.shared.modelID
        let info = ModelInfo.info(for: id)
        modelPickerTitle.stringValue = info?.displayName ?? id
        let installed = ModelInfo.bundledIDs.contains(id) || ModelManager.isInCache(id)
        var parts: [String] = []
        if let mb = info?.approximateSizeMB { parts.append(ModelRowView.formattedSize(mb)) }
        parts.append(installed ? "Installed · on device" : "Not installed")
        modelPickerSub.stringValue = parts.joined(separator: " · ")
        modelPickerDot.backgroundColor = (installed ? DesignTokens.good : DesignTokens.inkMute).cgColor
    }

    private func useModel(_ model: ModelInfo) {
        guard model.id != Settings.shared.modelID else { return }
        Settings.shared.modelID = model.id
        // If the model is already on disk we're not downloading anything — just loading
        // it into memory. Show a quieter "Loading…" state so the UI doesn't lie about
        // bytes being transferred.
        let alreadyLocal = ModelInfo.bundledIDs.contains(model.id) || ModelManager.isInCache(model.id)
        modelRows[model.id]?.apply(alreadyLocal
                                   ? .preparing(progress: 0)
                                   : .downloading(progress: 0))
        Task { await coordinator?.prepareModelInBackground() }
    }

    private func deleteModel(_ model: ModelInfo) {
        let alert = NSAlert()
        alert.messageText = "Delete \(model.displayName)?"
        if let mb = model.approximateSizeMB {
            alert.informativeText = "This frees ~\(mb) MB. The model can be re-downloaded later."
        } else {
            alert.informativeText = "The model can be re-downloaded later."
        }
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            try? ModelManager.delete(model.id)
            refreshModelStates()
        }
    }

    @objc private func refreshCatalogTapped(_ sender: Any?) {
        ModelCatalogService.shared.refresh()
    }

    // MARK: - Other controls

    private func configureControls() {
        modeButton.removeAllItems()
        modeButton.addItems(withTitles: ["Hold (push-to-talk)", "Toggle"])
        modeButton.target = self
        modeButton.action = #selector(modeChanged(_:))
        modeButton.toolTip =
            "Hold — press and hold the hotkey to record, release to stop and transcribe.\n" +
            "Toggle — press once to start recording, press again to stop and transcribe."

        languageButton.removeAllItems()
        for opt in LanguageOption.popular {
            languageButton.addItem(withTitle: opt.displayName)
            languageButton.lastItem?.representedObject = opt.code
        }
        languageButton.target = self
        languageButton.action = #selector(languageChanged(_:))

        autoInsertCheck.target = self
        autoInsertCheck.action = #selector(autoInsertChanged(_:))
        restoreClipboardCheck.target = self
        restoreClipboardCheck.action = #selector(restoreClipboardChanged(_:))
        showHUDCheck.target = self
        showHUDCheck.action = #selector(showHUDChanged(_:))

        hudPositionButton.removeAllItems()
        hudPositionButton.addItem(withTitle: "Bottom of screen")
        hudPositionButton.lastItem?.representedObject = Settings.HUDPosition.bottom.rawValue
        hudPositionButton.addItem(withTitle: "Top - under hush icon")
        hudPositionButton.lastItem?.representedObject = Settings.HUDPosition.top.rawValue
        hudPositionButton.target = self
        hudPositionButton.action = #selector(hudPositionChanged(_:))

        qualityButton.removeAllItems()
        for q in Settings.TranscriptionQuality.allCases {
            qualityButton.addItem(withTitle: q.displayName)
            qualityButton.lastItem?.representedObject = q.rawValue
        }
        qualityButton.target = self
        qualityButton.action = #selector(qualityChanged(_:))

        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibility(_:))

        hotkeyControl.onChange = { [weak self] combo in
            Settings.shared.hotkey = combo
            self?.coordinator?.hotkey.update(combo: combo)
        }

        // Post-processing controls
        enableSwitch.target = self
        enableSwitch.action = #selector(enableSwitchChanged(_:))

        tryButton.target = self
        tryButton.action = #selector(tryItTapped(_:))

        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))
        manageMenuButton.target = self
        manageMenuButton.action = #selector(showManageMenu(_:))
        profileNameField.target = self
        profileNameField.action = #selector(profileNameChanged(_:))
        creativitySlider.target = self
        creativitySlider.action = #selector(creativityChanged(_:))
    }

    /// One-time configuration of the editor controls (name field, prompt
    /// textarea, creativity slider, try-it widgets). They're built here so
    /// constraints + delegate are set up exactly once; the popover
    /// content view picks them up by adding them as subviews.
    private func configureEditorControls() {
        configurePromptTextView()
        promptScrollView.translatesAutoresizingMaskIntoConstraints = false
        promptScrollView.hasVerticalScroller = true
        promptScrollView.hasHorizontalScroller = false
        promptScrollView.autohidesScrollers = true
        promptScrollView.borderType = .lineBorder
        promptScrollView.drawsBackground = true
        promptScrollView.backgroundColor = DesignTokens.card
        promptScrollView.documentView = promptTextView
        promptScrollView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        promptScrollView.widthAnchor.constraint(equalToConstant: 360).isActive = true

        profileNameField.translatesAutoresizingMaskIntoConstraints = false
        profileNameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        profileNameField.font = NSFont.systemFont(ofSize: 12)
        profileNameField.placeholderString = "Profile name"
        profileNameField.bezelStyle = .roundedBezel
        profileNameField.usesSingleLineMode = true
        profileNameField.lineBreakMode = .byTruncatingTail

        creativitySlider.translatesAutoresizingMaskIntoConstraints = false
        creativitySlider.widthAnchor.constraint(equalToConstant: 280).isActive = true
        creativitySlider.numberOfTickMarks = 3
        creativitySlider.allowsTickMarkValuesOnly = false

        creativityValueLabel.font = NSFont.systemFont(ofSize: 11)
        creativityValueLabel.textColor = DesignTokens.inkDim
        creativityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        // Wider so "Balanced · 100 %" fits without truncation.
        creativityValueLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true

        tryInputField.translatesAutoresizingMaskIntoConstraints = false
        tryInputField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        tryInputField.font = NSFont.systemFont(ofSize: 12)
        tryInputField.usesSingleLineMode = true
        tryInputField.bezelStyle = .roundedBezel
        tryInputField.placeholderString = "Sample input"

        tryOutputLabel.font = NSFont.systemFont(ofSize: 12)
        tryOutputLabel.textColor = DesignTokens.inkDim
        tryOutputLabel.preferredMaxLayoutWidth = 380
        tryOutputLabel.maximumNumberOfLines = 4
        tryOutputLabel.lineBreakMode = .byWordWrapping
    }

    /// Lazy popover constructor. Built once, reused on subsequent Edit
    /// clicks. `.transient` so it dismisses on outside click — matches the
    /// macOS convention for contextual editors (think Finder Get Info,
    /// menu-bar app popovers, etc.).
    private func makeProfileEditorPopover() -> NSPopover {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = makeProfileEditorViewController()
        return pop
    }

    private func makeProfileEditorViewController() -> NSViewController {
        let vc = NSViewController()
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = DesignTokens.paper.cgColor

        // Local row helper — does NOT pin a width on the control, so the
        // explicit widths set in `configureEditorControls()` (360 for the
        // name/prompt/try fields, 280 for the slider) don't conflict
        // with the 260pt the main-form `makeRow()` enforces.
        func editorRow(title: String, control: NSView, top: Bool = false) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = DesignTokens.ink
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 100).isActive = true
            let row = NSStackView(views: [label, control])
            row.orientation = .horizontal
            row.spacing = 12
            row.alignment = top ? .top : .centerY
            return row
        }

        let nameRow = editorRow(title: "Name", control: profileNameField)

        let creativityRow = NSStackView(views: [creativitySlider, creativityValueLabel])
        creativityRow.orientation = .horizontal
        creativityRow.spacing = 10
        creativityRow.alignment = .centerY
        let creativityFormRow = editorRow(title: "Creativity", control: creativityRow)

        let creativityHelp = NSTextField(wrappingLabelWithString:
            "Faithful: corrects but barely changes wording. Creative: rephrases freely. Stored per profile and sent to the AI both as temperature and as plain-language guidance for more predictable results.")
        creativityHelp.font = NSFont.systemFont(ofSize: 11)
        creativityHelp.textColor = DesignTokens.inkMute
        creativityHelp.preferredMaxLayoutWidth = 480

        let promptRow = editorRow(title: "Prompt", control: promptScrollView, top: true)

        let trySampleRow = NSStackView(views: [tryInputField, tryButton])
        trySampleRow.orientation = .horizontal
        trySampleRow.spacing = 8
        trySampleRow.alignment = .centerY
        let tryFormRow = editorRow(title: "Try it", control: trySampleRow)

        let stack = NSStackView(views: [
            nameRow, creativityFormRow, creativityHelp, promptRow, tryFormRow, tryOutputLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        vc.view = root
        vc.preferredContentSize = NSSize(width: 580, height: 420)
        return vc
    }

    /// Side-label for the prompt textview, sized to match the form's left column.
    private func makePromptLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "Prompt")
        l.font = NSFont.systemFont(ofSize: 12)
        l.textColor = DesignTokens.ink
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return l
    }

    /// Configures the prompt `NSTextView` for embedding inside `promptScrollView`.
    /// Following Apple's canonical pattern: text view uses autoresizing (not
    /// AutoLayout) inside the scroll view; the text container width tracks the
    /// scroll view so wrapping behaves naturally as the window resizes.
    private func configurePromptTextView() {
        promptTextView.isEditable = true
        promptTextView.isRichText = false
        promptTextView.font = NSFont.systemFont(ofSize: 12)
        promptTextView.textColor = DesignTokens.ink
        promptTextView.drawsBackground = false
        promptTextView.allowsUndo = true
        promptTextView.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView.isAutomaticDashSubstitutionEnabled = false
        promptTextView.isAutomaticTextReplacementEnabled = false

        // Resize/container config — must match the scroll view's behavior or
        // text either clips horizontally or refuses to scroll vertically.
        promptTextView.minSize = NSSize(width: 0, height: 0)
        promptTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                         height: CGFloat.greatestFiniteMagnitude)
        promptTextView.isVerticallyResizable = true
        promptTextView.isHorizontallyResizable = false
        promptTextView.autoresizingMask = [.width]
        promptTextView.textContainer?.widthTracksTextView = true
        promptTextView.textContainer?.containerSize = NSSize(
            width: 1_000_000,
            height: CGFloat.greatestFiniteMagnitude
        )

        promptTextView.delegate = self
    }

    private func bindCoordinator() {
        coordinator?.phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                let activeID = Settings.shared.modelID
                switch phase {
                case .modelLoading(let p):
                    if let row = self.modelRows[activeID] {
                        let isLocal = ModelInfo.bundledIDs.contains(activeID)
                            || ModelManager.isInCache(activeID)
                        row.apply(isLocal ? .preparing(progress: p) : .downloading(progress: p))
                    }
                case .idle:
                    if self.coordinator?.isModelReady == true {
                        self.refreshModelStates()
                    }
                case .error:
                    self.refreshModelStates()
                default: break
                }
            }
            .store(in: &subs)
    }

    /// Subscribe to the live HuggingFace-backed model catalog. We rebuild the
    /// row list every time the catalog publishes a new snapshot, and reflect
    /// loading / error state on the section header.
    private func bindCatalogService() {
        let svc = ModelCatalogService.shared
        svc.models
            .receive(on: RunLoop.main)
            .sink { [weak self] models in
                self?.rebuildModelRows(models)
            }
            .store(in: &subs)
        svc.isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] loading in
                guard let self else { return }
                if loading {
                    self.reloadCatalogButton.isHidden = true
                    self.reloadSpinner.startAnimation(nil)
                } else {
                    self.reloadSpinner.stopAnimation(nil)
                    self.reloadCatalogButton.isHidden = false
                }
            }
            .store(in: &subs)
        svc.lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                guard let self else { return }
                if let err {
                    self.modelsHelp.stringValue =
                        "Couldn't refresh model list: \(err). Tap ⟳ to retry."
                } else {
                    self.modelsHelp.stringValue =
                        "Tap Use to switch the active model. New models download automatically on first use."
                }
            }
            .store(in: &subs)
    }

    /// Source of truth for the entire post-processing UI. Reads from
    /// `Settings.shared.llmProvider` + `LLMRuntime.shared` and rebuilds
    /// every visible string. Called on first load and whenever
    /// `Settings.didChange` or `LLMRuntime.stateChange` fires.
    private func refreshProviderControls() {
        let provider = Settings.shared.llmProvider
        let runtime = LLMRuntime.shared
        let isEnabled = provider != .off

        // Master switch + body visibility.
        enableSwitch.isOn = isEnabled
        postProcessingBody.isHidden = !isEnabled

        // Provider cards are rendered and refreshed from the same catalog,
        // preventing a model from appearing in one settings surface only.
        for candidate in LLMProvider.engineCatalog {
            refreshProviderCard(candidate, isActive: provider == candidate, runtime: runtime)
        }

        // Profile + prompt — enabled only when provider is ready.
        let profiles = Settings.shared.profiles
        let active = Settings.shared.activeProfile
        let providerReady = runtime.isActiveProviderReady && isEnabled

        profilePopup.removeAllItems()
        for p in profiles {
            profilePopup.addItem(withTitle: p.name)
            profilePopup.lastItem?.representedObject = p.id.uuidString
        }
        // Separator + "+ New profile" at the bottom of the dropdown for
        // direct creation without going through the ⋯ menu. Discoverable
        // via the same picker the user already opened to look at
        // profiles — matches macOS conventions (Spaces switcher, Tags
        // dropdown, etc. all use this "list + separator + add" shape).
        profilePopup.menu?.addItem(.separator())
        let newItem = NSMenuItem(title: "+ New profile…", action: nil, keyEquivalent: "")
        newItem.representedObject = Self.newProfileSentinel
        profilePopup.menu?.addItem(newItem)

        if let idx = profiles.firstIndex(where: { $0.id == active.id }) {
            profilePopup.selectItem(at: idx)
        }
        profilePopup.isEnabled = providerReady
        manageMenuButton.isEnabled = providerReady

        if promptTextView.string != active.systemPrompt {
            promptTextView.string = active.systemPrompt
        }
        promptTextView.isEditable = providerReady
        promptTextView.textColor = providerReady ? DesignTokens.ink : DesignTokens.inkMute

        let isEditingName = view.window?.firstResponder === profileNameField.currentEditor()
        if !isEditingName && profileNameField.stringValue != active.name {
            profileNameField.stringValue = active.name
        }
        profileNameField.isEnabled = providerReady

        if creativitySlider.doubleValue != active.creativity {
            creativitySlider.doubleValue = active.creativity
        }
        creativitySlider.isEnabled = providerReady
        creativityValueLabel.stringValue = Self.creativityLabel(active.creativity)

        tryButton.isEnabled = providerReady
        tryInputField.isEnabled = providerReady
    }

    /// Map a 0…1 creativity value to a label combining a semantic bucket
    /// and the exact percentage — gives the user the named feeling
    /// ("Balanced") AND an accurate readout ("30 %") in one line.
    private static func creativityLabel(_ value: Double) -> String {
        let pct = Int((value * 100).rounded())
        let bucket: String
        switch value {
        case ..<0.15:  bucket = "Faithful"
        case ..<0.55:  bucket = "Balanced"
        default:       bucket = "Creative"
        }
        return "\(bucket) · \(pct)%"
    }

    /// Per-card state mapping. Tells each `ProviderRowView` how to render
    /// itself based on `(isActive, runtime state)`.
    private func refreshProviderCard(_ provider: LLMProvider, isActive: Bool, runtime: LLMRuntime) {
        guard let row = providerRows[provider] else { return }
        switch provider {
        case .off:
            return
        case .appleIntelligence:
            switch runtime.appleAvailability {
            case .available:
                // Same `provider.blurb` source of truth as the Qwen
                // cards: the LLMProvider enum owns each backend's user-
                // facing description. Active state still gets a "Ready"
                // prefix so users see at a glance which card is on.
                row.apply(isActive ? .active(subtitle: "Ready · \(provider.blurb)")
                                    : .inactive(subtitle: provider.blurb))
            case .unavailable(let reason):
                row.apply(.unavailable(reason: reason))
            case .unsupportedOS:
                row.apply(.unavailable(reason: "Requires macOS 26 or later."))
            }
        case .qwen35_2b, .qwen35_4b:
            // Every Qwen model shares the same card-rendering machinery. Copy
            // is composed from two `LLMProvider` sources of truth:
            //   - `provider.blurb`              — pure descriptive
            //                                     ("Smaller and faster…")
            //   - `provider.approxDownloadSize` — surfaced ONLY when the
            //                                     model isn't on disk yet
            // Once the model is downloaded, we report the real on-disk
            // size and suppress the approximate one (otherwise the row
            // reads "Downloaded · 936 MB. … (~1.1 GB). …" — same info
            // twice).
            guard let model = LLMRuntime.QwenModel(provider: provider) else { return }
            let approxSize = provider.approxDownloadSize ?? "?"
            let runtimeDetail = provider.runtimeDetail ?? "On this Mac"
            switch runtime.qwenState(for: model) {
            case .notDownloaded:
                row.apply(.needsDownload(
                    subtitle: "\(provider.blurb) \(runtimeDetail) · ~\(approxSize) one-time download.",
                    isActive: isActive
                ))
            case .downloading(let progress):
                row.apply(.downloading(
                    subtitle: progress.statusText,
                    progress: progress.fraction
                ))
            case .downloaded, .warm:
                let mb = LLMRuntime.qwenDiskSizeMB(for: model) ?? 1024
                let size = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
                if isActive {
                    row.apply(.readyWithDelete(subtitle: "Ready · \(size) · \(runtimeDetail)"))
                } else {
                    row.apply(.inactive(subtitle: "Downloaded · \(size) · \(runtimeDetail)"))
                }
            case .failed(let msg):
                row.apply(.unavailable(reason: msg))
            }
        }
    }

    private func refreshFromSettings() {
        modeButton.selectItem(at: Settings.shared.hotkeyMode == .pushToTalk ? 0 : 1)

        let lang = Settings.shared.language
        if let idx = LanguageOption.popular.firstIndex(where: { $0.code == lang }) {
            languageButton.selectItem(at: idx)
        }

        autoInsertCheck.state = Settings.shared.autoInsert ? .on : .off
        restoreClipboardCheck.state = Settings.shared.restoreClipboard ? .on : .off
        showHUDCheck.state = Settings.shared.showHUD ? .on : .off

        let pos = Settings.shared.hudPosition
        hudPositionButton.selectItem(at: pos == .bottom ? 0 : 1)

        let quality = Settings.shared.transcriptionQuality
        if let idx = Settings.TranscriptionQuality.allCases.firstIndex(of: quality) {
            qualityButton.selectItem(at: idx)
        }

        #if APP_STORE
        autoInsertCheck.isEnabled = false
        autoInsertCheck.state = .off
        storeNoticeLabel.stringValue = "The Mac App Store version doesn't auto-paste — text goes to the clipboard, press ⌘V to paste. The full version with auto-paste is available from the website."
        #else
        storeNoticeLabel.stringValue = "Auto-paste needs Universal Access. Grant hush access in System Settings → Privacy & Security → Accessibility."
        #endif
    }

    private func refreshAccessibilityStatus() {
        let granted = PermissionsChecker.isAccessibilityGranted
        accessibilityStatus.stringValue = granted
            ? "✓ Universal Access granted"
            : "⚠ Universal Access not granted"
        accessibilityStatus.textColor = granted ? DesignTokens.goodInk : DesignTokens.danger
        accessibilityStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        Settings.shared.hotkeyMode = sender.indexOfSelectedItem == 0 ? .pushToTalk : .toggle
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        if let code = sender.selectedItem?.representedObject as? String {
            Settings.shared.language = code
        }
    }

    @objc private func autoInsertChanged(_ sender: NSButton) {
        Settings.shared.autoInsert = sender.state == .on
    }

    @objc private func restoreClipboardChanged(_ sender: NSButton) {
        Settings.shared.restoreClipboard = sender.state == .on
    }

    @objc private func showHUDChanged(_ sender: NSButton) {
        Settings.shared.showHUD = sender.state == .on
    }

    @objc private func hudPositionChanged(_ sender: NSPopUpButton) {
        if let raw = sender.selectedItem?.representedObject as? String,
           let pos = Settings.HUDPosition(rawValue: raw) {
            Settings.shared.hudPosition = pos
        }
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        if let raw = sender.selectedItem?.representedObject as? String,
           let q = Settings.TranscriptionQuality(rawValue: raw) {
            Settings.shared.transcriptionQuality = q
        }
    }

    @objc private func openAccessibility(_ sender: Any?) {
        PermissionsChecker.promptAccessibilityIfNeeded()
        PermissionsChecker.openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshAccessibilityStatus()
        }
    }

    // MARK: - Post-processing profile actions

    /// Toggle the master enable switch. Off → llmProvider = .off and the
    /// body section collapses. On → pick a sensible default backend in
    /// preference order: Apple Intelligence (free, no download), then
    /// whichever Qwen is already downloaded, else Qwen 3.5 2B (the
    /// quality-focused default).
    @objc private func enableSwitchChanged(_ sender: BrandSwitch) {
        if !sender.isOn {
            Settings.shared.llmProvider = .off
            return
        }
        let runtime = LLMRuntime.shared
        runtime.refreshAppleAvailability()
        if runtime.appleAvailability == .available {
            Settings.shared.llmProvider = .appleIntelligence
            return
        }
        // Prefer whatever the user has already downloaded; otherwise
        // default to the newer model.
        for candidate in LLMProvider.localFallbackOrder {
            if let model = LLMRuntime.QwenModel(provider: candidate),
               case .downloaded = runtime.qwenState(for: model) {
                Settings.shared.llmProvider = candidate
                return
            }
        }
        Settings.shared.llmProvider = .qwen35_2b
    }

    /// Activate this provider (called when the user taps "Use" on a card).
    /// For a Qwen variant that's not yet downloaded, "Use" auto-starts
    /// the download — the card's primary button says "Download" in that
    /// state and routes back here.
    private func useProvider(_ provider: LLMProvider) {
        Settings.shared.llmProvider = provider
        if provider == .appleIntelligence {
            LLMRuntime.shared.refreshAppleAvailability()
            return
        }
        if let model = LLMRuntime.QwenModel(provider: provider) {
            switch LLMRuntime.shared.qwenState(for: model) {
            case .notDownloaded, .failed:
                LLMRuntime.shared.startDownloadQwen(model)
            default:
                break
            }
        }
    }

    /// Per-card Cancel handler. Routes the cancel to the specific Qwen
    /// variant the user clicked on (not the active provider — those can
    /// be different cards).
    private func cancelDownload(for provider: LLMProvider) {
        guard let model = LLMRuntime.QwenModel(provider: provider) else { return }
        LLMRuntime.shared.cancelQwenDownload(model)
    }

    /// Run the active profile's prompt over the sandbox input field's
    /// text. Surfaces the LLM's response below the field. Errors land in
    /// the same label so users see what went wrong (Apple Intelligence
    /// unavailable, model still loading, etc.).
    @objc private func tryItTapped(_ sender: Any?) {
        let active = Settings.shared.activeProfile
        let input = tryInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            tryOutputLabel.stringValue = "Type a sample sentence above first."
            tryOutputLabel.textColor = DesignTokens.inkMute
            return
        }
        tryOutputLabel.stringValue = "Running…"
        tryOutputLabel.textColor = DesignTokens.inkDim
        tryButton.isEnabled = false
        Task { @MainActor in
            defer { tryButton.isEnabled = true }
            do {
                let result = try await LLMRuntime.shared.generate(transcript: input, profile: active)
                tryOutputLabel.stringValue = result
                tryOutputLabel.textColor = DesignTokens.ink
            } catch {
                tryOutputLabel.stringValue = "⚠ \(error.localizedDescription)"
                tryOutputLabel.textColor = DesignTokens.danger
            }
        }
    }

    /// Per-card Delete handler. Routes the delete to the specific Qwen
    /// variant the user clicked on, names it in the confirmation dialog,
    /// and reports the actual on-disk size for that variant.
    private func deleteModel(for provider: LLMProvider) {
        guard let model = LLMRuntime.QwenModel(provider: provider) else { return }
        let mb = LLMRuntime.qwenDiskSizeMB(for: model) ?? 1024
        let sizeLabel = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
        let alert = NSAlert()
        alert.messageText = "Delete \(provider.displayName)?"
        alert.informativeText =
            "Frees ~\(sizeLabel). You can re-download it any time. " +
            "If this is the active provider, AI post-processing will be disabled until you download again or switch to a different backend."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try LLMRuntime.shared.deleteQwen(model)
        } catch {
            let err = NSAlert()
            err.messageText = "Couldn't delete the model"
            err.informativeText = error.localizedDescription
            err.runModal()
        }
    }

    /// Sentinel used by the "+ New profile…" item at the bottom of the
    /// dropdown. Lets `profileChanged(_:)` distinguish that pick from a
    /// real profile UUID without inventing a new selection-type field.
    private static let newProfileSentinel = "__new__"

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        if raw == Self.newProfileSentinel {
            // Route through the same handler as the ⋯ menu's New so a
            // fresh profile is created + the editor pops up to name it.
            addProfileTapped(sender)
            return
        }
        guard let id = UUID(uuidString: raw) else { return }
        Settings.shared.activeProfileID = id
    }

    /// Build + present the ⋯ overflow menu next to the profile dropdown.
    /// Lives here rather than as a `NSPopUpButton` so the items can be
    /// enabled / disabled / labelled with the active profile name on
    /// every open.
    @objc private func showManageMenu(_ sender: NSButton) {
        let active = Settings.shared.activeProfile
        let menu = NSMenu()

        let editItem = NSMenuItem(
            title: "Edit “\(active.name)”…",
            action: #selector(editProfileTapped(_:)),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let newItem = NSMenuItem(
            title: "New profile",
            action: #selector(addProfileTapped(_:)),
            keyEquivalent: "n"
        )
        newItem.target = self
        menu.addItem(newItem)

        let dupItem = NSMenuItem(
            title: "Duplicate “\(active.name)”",
            action: #selector(duplicateProfileTapped(_:)),
            keyEquivalent: "d"
        )
        dupItem.target = self
        menu.addItem(dupItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "Delete “\(active.name)”…",
            action: #selector(deleteProfileTapped(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = active.isDeletable
        menu.addItem(deleteItem)

        // Drop the menu below the button so it doesn't overlap.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.height + 4),
            in: sender
        )
    }

    /// Open the editor popover. Anchors to the ⋯ button so it lands in
    /// the same visual neighborhood the user just clicked from.
    @objc private func editProfileTapped(_ sender: Any?) {
        let pop = profileEditorPopover ?? makeProfileEditorPopover()
        profileEditorPopover = pop
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(
                relativeTo: manageMenuButton.bounds,
                of: manageMenuButton,
                preferredEdge: .maxY
            )
        }
    }

    @objc private func duplicateProfileTapped(_ sender: Any?) {
        let active = Settings.shared.activeProfile
        var profiles = Settings.shared.profiles
        let copy = Profile(
            id: UUID(),
            name: Self.uniqueName(base: "\(active.name) copy", in: profiles),
            systemPrompt: active.systemPrompt,
            creativity: active.creativity,
            iconName: active.iconName
        )
        profiles.append(copy)
        Settings.shared.profiles = profiles
        Settings.shared.activeProfileID = copy.id
        refreshProviderControls()
        presentEditorAndFocusName()
    }

    /// Opens the profile editor popover anchored to the ⋯ button and
    /// drops the keyboard focus into the name field with the placeholder
    /// pre-selected. Used by both "+ New profile" and "Duplicate" so a
    /// freshly-created profile lands the user in rename mode immediately.
    private func presentEditorAndFocusName() {
        let pop = profileEditorPopover ?? makeProfileEditorPopover()
        profileEditorPopover = pop
        if !pop.isShown {
            pop.show(
                relativeTo: manageMenuButton.bounds,
                of: manageMenuButton,
                preferredEdge: .maxY
            )
        }
        // The popover content view isn't in the window hierarchy until
        // `show(relativeTo:...)` returns; defer focus + selectText to the
        // next runloop tick so first-responder routing actually sticks.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.profileNameField.window?.makeFirstResponder(self.profileNameField)
            self.profileNameField.selectText(nil)
        }
    }

    /// Live-update the active profile's creativity as the slider moves.
    /// `NSSlider.isContinuous` defaults to true, so this fires while the
    /// user is dragging — gives instant feedback in the trailing
    /// "Faithful / Balanced / Creative" label.
    @objc private func creativityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        creativityValueLabel.stringValue = Self.creativityLabel(value)
        let activeID = Settings.shared.activeProfileID
        var profiles = Settings.shared.profiles
        guard let idx = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        guard abs(profiles[idx].creativity - value) > 0.001 else { return }
        profiles[idx].creativity = value
        Settings.shared.profiles = profiles
    }

    private static func uniqueName(base: String, in profiles: [Profile]) -> String {
        let existing = Set(profiles.map(\.name))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Rename the active profile. Fires on Enter / Tab / focus-loss
    /// (default NSTextField action behavior). Empty input is rejected;
    /// the field is restored to the current name so the user sees that
    /// their edit didn't take effect.
    @objc private func profileNameChanged(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeID = Settings.shared.activeProfileID
        var profiles = Settings.shared.profiles
        guard let idx = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        guard !trimmed.isEmpty else {
            sender.stringValue = profiles[idx].name
            return
        }
        guard profiles[idx].name != trimmed else { return }
        profiles[idx].name = trimmed
        Settings.shared.profiles = profiles
    }

    @objc private func addProfileTapped(_ sender: Any?) {
        var profiles = Settings.shared.profiles
        let newProfile = Profile(
            id: UUID(),
            name: Self.uniqueName(base: "New profile", in: profiles),
            systemPrompt: "",
            creativity: 0.3
        )
        profiles.append(newProfile)
        Settings.shared.profiles = profiles
        Settings.shared.activeProfileID = newProfile.id
        // Sync the editor controls to the new profile NOW, before the
        // popover opens — Settings.didChange runs through a RunLoop.main
        // hop, so without the explicit refresh the popover would briefly
        // display the previous active profile's name/prompt.
        refreshProviderControls()
        presentEditorAndFocusName()
    }

    @objc private func deleteProfileTapped(_ sender: Any?) {
        let active = Settings.shared.activeProfile
        guard active.isDeletable else { return }

        let alert = NSAlert()
        alert.messageText = "Delete profile “\(active.name)”?"
        alert.informativeText = "This can't be undone. The active profile will switch to the default."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var profiles = Settings.shared.profiles
        profiles.removeAll { $0.id == active.id }
        Settings.shared.profiles = profiles
        Settings.shared.activeProfileID = Profile.defaultProfileID
    }
}

// MARK: - NSTextViewDelegate (prompt autosave)

extension SettingsViewController: NSTextViewDelegate {

    /// Live: every keystroke writes through to the active profile. Cheap (it's
    /// just a UserDefaults set + Combine signal) and matches Cooper's
    /// "save automatically" rule — no "Save" button needed.
    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === promptTextView else { return }
        let activeID = Settings.shared.activeProfileID
        var profiles = Settings.shared.profiles
        guard let idx = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        guard profiles[idx].systemPrompt != promptTextView.string else { return }
        profiles[idx].systemPrompt = promptTextView.string
        Settings.shared.profiles = profiles
    }
}

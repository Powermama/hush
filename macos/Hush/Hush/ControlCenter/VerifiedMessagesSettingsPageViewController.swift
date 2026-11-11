import AppKit
import HushProvenance
import UniformTypeIdentifiers

@MainActor
final class VerifiedMessagesSettingsPageViewController: ControlCenterPageViewController {
    private weak var coordinator: DictationCoordinator?
    private let enabledSwitch = NSSwitch()
    private let authorNameField = NSTextField()
    private let linkPresentationPopUp = NSPopUpButton()
    private let destinationModePopUp = NSPopUpButton()
    private let destinationExceptionsButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let signaturePreview = NSTextField(labelWithString: "")
    private var exceptionsWindowController: NSWindowController?

    init(coordinator: DictationCoordinator?) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "Typed with hush",
            detail: "Add a private proof link that shows how a message was captured and refined."
        ))
        buildEnableCard()
        buildDestinationCard()
        buildDisclosureCard()
        buildPreview()
        configureControls()
        refresh()
    }

    private func buildDestinationCard() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        destinationModePopUp.controlSize = .small
        destinationModePopUp.widthAnchor.constraint(equalToConstant: 118).isActive = true
        destinationModePopUp.addItems(
            withTitles: VerifiedMessageDestinationMode.allCases.map(\.displayName)
        )
        destinationModePopUp.setAccessibilityIdentifier("hush.verified.destinationMode")
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Signature destinations",
            subtitle: "Smart hides signatures in terminal apps and your personal exceptions.",
            trailing: destinationModePopUp
        ))

        destinationExceptionsButton.title = "Manage\u{2026}"
        destinationExceptionsButton.bezelStyle = .rounded
        destinationExceptionsButton.controlSize = .small
        destinationExceptionsButton.setAccessibilityIdentifier("hush.verified.destinationExceptions")
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "App & website exceptions",
            subtitle: "Never publish or append a proof in selected apps or on selected websites.",
            trailing: destinationExceptionsButton,
            showsSeparator: false
        ))

        for row in rows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        addFullWidth(sectionTitle("Where signatures appear"))
        addFullWidth(makeCard(content: rows))
    }

    private func buildEnableCard() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Verified Messages",
            subtitle: "Append a link only after hush receives a matching cryptographic receipt.",
            trailing: enabledSwitch
        ))

        authorNameField.placeholderString = "Anonymous"
        authorNameField.controlSize = .small
        authorNameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Display name",
            subtitle: "Optional and always labeled self-declared.",
            trailing: authorNameField
        ))

        linkPresentationPopUp.controlSize = .small
        linkPresentationPopUp.widthAnchor.constraint(equalToConstant: 150).isActive = true
        linkPresentationPopUp.addItems(
            withTitles: Settings.VerifiedMessagesLinkPresentation.allCases.map(\.displayName)
        )
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Link appearance",
            subtitle: "Automatic uses links only in verified rich-text apps and shows the URL elsewhere.",
            trailing: linkPresentationPopUp,
            showsSeparator: false
        ))

        for row in rows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        addFullWidth(makeCard(content: rows))
    }

    private func buildDisclosureCard() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        rows.addArrangedSubview(valueRow(
            title: "Signed message record",
            subtitle: "Raw transcript, final wording, local AI details, and audio hash.",
            value: "Included"
        ))
        rows.addArrangedSubview(valueRow(
            title: "Original audio",
            subtitle: "Audio stays on this Mac and is never uploaded.",
            value: "Off"
        ))
        rows.addArrangedSubview(valueRow(
            title: "Proof lifetime",
            subtitle: "The encrypted proof expires automatically.",
            value: "30 days",
            showsSeparator: false
        ))
        for row in rows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        addFullWidth(sectionTitle("What recipients can see"))
        addFullWidth(makeCard(content: rows))
    }

    private func buildPreview() {
        let message = NSTextField(wrappingLabelWithString: "Perfect, let's lock in Thursday at 10.")
        message.font = .systemFont(ofSize: 15, weight: .medium)

        signaturePreview.font = .systemFont(ofSize: 11.5, weight: .medium)
        signaturePreview.textColor = .linkColor

        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        let content = NSStackView(views: [message, signaturePreview, statusLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        addFullWidth(sectionTitle("Signature preview"))
        addFullWidth(makeCard(
            content: content,
            insets: .init(top: 18, left: 20, bottom: 18, right: 20)
        ))
    }

    private func valueRow(
        title: String,
        subtitle: String,
        value: String,
        showsSeparator: Bool = true
    ) -> ControlCenterKeyValueRow {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        return ControlCenterKeyValueRow(
            title: title,
            subtitle: subtitle,
            trailing: label,
            showsSeparator: showsSeparator
        )
    }

    private func configureControls() {
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged(_:))
        authorNameField.target = self
        authorNameField.action = #selector(authorNameChanged(_:))
        linkPresentationPopUp.target = self
        linkPresentationPopUp.action = #selector(linkPresentationChanged(_:))
        destinationModePopUp.target = self
        destinationModePopUp.action = #selector(destinationModeChanged(_:))
        destinationExceptionsButton.target = self
        destinationExceptionsButton.action = #selector(showDestinationExceptions(_:))
    }

    private func refresh() {
        let enabled = Settings.shared.verifiedMessagesEnabled
        enabledSwitch.state = enabled ? .on : .off
        authorNameField.stringValue = Settings.shared.verifiedMessagesAuthorName
        authorNameField.isEnabled = enabled
        let presentation = Settings.shared.verifiedMessagesLinkPresentation
        linkPresentationPopUp.selectItem(
            at: Settings.VerifiedMessagesLinkPresentation.allCases.firstIndex(of: presentation) ?? 0
        )
        linkPresentationPopUp.isEnabled = enabled
        let destinationMode = Settings.shared.verifiedMessagesDestinationMode
        destinationModePopUp.selectItem(
            at: VerifiedMessageDestinationMode.allCases.firstIndex(of: destinationMode) ?? 0
        )
        destinationModePopUp.isEnabled = enabled
        let exceptionCount = Settings.shared.verifiedMessagesAppExceptions.count
            + Settings.shared.verifiedMessagesWebsiteExceptions.count
        destinationExceptionsButton.title = exceptionCount == 0
            ? "Manage\u{2026}"
            : "\(exceptionCount) rules"
        destinationExceptionsButton.isEnabled = enabled && destinationMode == .smart
        signaturePreview.stringValue = presentation == .visibleURL
            ? "-typed with hush: behu.sh/A7k2Qx#k=private-key"
            : "-typed with hush"
        statusLabel.stringValue = enabled
            ? "Message contents are encrypted on this Mac. The private key exists only in the link."
            : "Off by default. Normal hush messages never contain a signature or upload a proof."
    }

    @objc private func enabledChanged(_ sender: NSSwitch) {
        guard sender.state == .on else {
            Settings.shared.verifiedMessagesEnabled = false
            refresh()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Enable Typed with hush links?"
        alert.informativeText = "hush will upload an end-to-end encrypted message proof after dictation. The decryption key stays in the link, and original audio is not shared."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            refresh()
            return
        }
        guard let coordinator else {
            refresh()
            return
        }

        enabledSwitch.isEnabled = false
        authorNameField.isEnabled = false
        statusLabel.stringValue = "Creating this Mac's private signing identity..."
        Task { [weak self] in
            guard let self else { return }
            do {
                try await coordinator.prepareVerifiedMessages()
                Settings.shared.verifiedMessagesEnabled = true
            } catch {
                Settings.shared.verifiedMessagesEnabled = false
                let errorAlert = NSAlert()
                errorAlert.alertStyle = .warning
                errorAlert.messageText = "Typed with hush could not be enabled"
                errorAlert.informativeText = if let publisherError = error as? ProofPublisherError {
                    publisherError.localizedDescription
                } else {
                    "hush could not create a private signing identity on this Mac. Try again."
                }
                errorAlert.addButton(withTitle: "OK")
                errorAlert.runModal()
            }
            enabledSwitch.isEnabled = true
            refresh()
        }
    }

    @objc private func authorNameChanged(_ sender: NSTextField) {
        Settings.shared.verifiedMessagesAuthorName = sender.stringValue
        refresh()
    }

    @objc private func linkPresentationChanged(_ sender: NSPopUpButton) {
        let presentations = Settings.VerifiedMessagesLinkPresentation.allCases
        guard presentations.indices.contains(sender.indexOfSelectedItem) else { return }
        Settings.shared.verifiedMessagesLinkPresentation = presentations[sender.indexOfSelectedItem]
        refresh()
    }

    @objc private func destinationModeChanged(_ sender: NSPopUpButton) {
        let modes = VerifiedMessageDestinationMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        Settings.shared.verifiedMessagesDestinationMode = modes[sender.indexOfSelectedItem]
        refresh()
    }

    @objc private func showDestinationExceptions(_ sender: NSButton) {
        guard exceptionsWindowController == nil, let parentWindow = view.window else { return }

        let content = VerifiedMessageDestinationExceptionsViewController()
        let panel = NSPanel(contentViewController: content)
        panel.title = "Destination Exceptions"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 480, height: 546))
        let controller = NSWindowController(window: panel)
        exceptionsWindowController = controller

        content.onChange = { [weak self] in self?.refresh() }
        content.onDone = { [weak self, weak parentWindow, weak panel] in
            guard let panel else { return }
            parentWindow?.endSheet(panel)
            self?.exceptionsWindowController = nil
            self?.refresh()
        }
        parentWindow.beginSheet(panel)
    }
}

@MainActor
private final class VerifiedMessageDestinationExceptionsViewController: NSViewController {
    var onChange: (() -> Void)?
    var onDone: (() -> Void)?

    private let listStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No personal exceptions")
    private let websiteListStack = NSStackView()
    private let websiteField = NSTextField()

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let title = NSTextField(labelWithString: "Destination Exceptions")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString:
            "hush never publishes or appends a proof in these apps or websites. Your message still inserts normally."
        )
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let automaticLabel = NSTextField(labelWithString: "Sensitive destinations")
        automaticLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let automaticDetail = NSTextField(
            labelWithString: "Terminal apps and browser address or search fields"
        )
        automaticDetail.font = .systemFont(ofSize: 11)
        automaticDetail.textColor = .secondaryLabelColor
        let automaticLabels = NSStackView(views: [automaticLabel, automaticDetail])
        automaticLabels.orientation = .vertical
        automaticLabels.alignment = .leading
        automaticLabels.spacing = 2
        let automaticStatus = NSTextField(labelWithString: "Automatic")
        automaticStatus.font = .systemFont(ofSize: 11.5, weight: .medium)
        automaticStatus.textColor = .secondaryLabelColor
        let automaticRow = NSStackView(views: [automaticLabels, NSView(), automaticStatus])
        automaticRow.orientation = .horizontal
        automaticRow.alignment = .centerY
        automaticRow.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let automaticCard = ControlCenterCardView()
        automaticCard.addSubview(automaticRow)
        automaticRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            automaticRow.topAnchor.constraint(equalTo: automaticCard.topAnchor),
            automaticRow.bottomAnchor.constraint(equalTo: automaticCard.bottomAnchor),
            automaticRow.leadingAnchor.constraint(equalTo: automaticCard.leadingAnchor),
            automaticRow.trailingAnchor.constraint(equalTo: automaticCard.trailingAnchor),
        ])

        let personalTitle = NSTextField(labelWithString: "Apps")
        personalTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let listDocument = ControlCenterFlippedDocumentView()
        listDocument.translatesAutoresizingMaskIntoConstraints = false
        listDocument.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: listDocument.topAnchor),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: listDocument.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: listDocument.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listDocument.trailingAnchor),
            listStack.widthAnchor.constraint(equalTo: listDocument.widthAnchor),
        ])

        let scroll = NSScrollView()
        scroll.documentView = listDocument
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listDocument.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        listDocument.heightAnchor.constraint(
            greaterThanOrEqualTo: scroll.contentView.heightAnchor
        ).isActive = true
        let listCard = ControlCenterCardView()
        listCard.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: listCard.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listCard.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: listCard.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listCard.trailingAnchor),
            listCard.heightAnchor.constraint(equalToConstant: 112),
        ])

        let websitesTitle = NSTextField(labelWithString: "Websites")
        websitesTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        websiteField.placeholderString = "example.com"
        websiteField.controlSize = .regular
        websiteField.setAccessibilityIdentifier("hush.verified.websiteField")
        websiteField.target = self
        websiteField.action = #selector(addWebsite(_:))
        let addWebsiteButton = NSButton(
            title: "Add",
            target: self,
            action: #selector(addWebsite(_:))
        )
        addWebsiteButton.bezelStyle = .rounded
        addWebsiteButton.controlSize = .regular
        addWebsiteButton.setAccessibilityIdentifier("hush.verified.addWebsite")
        let websiteEntry = NSStackView(views: [websiteField, addWebsiteButton])
        websiteEntry.orientation = .horizontal
        websiteEntry.alignment = .centerY
        websiteEntry.spacing = 8
        websiteField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        websiteListStack.orientation = .vertical
        websiteListStack.alignment = .leading
        websiteListStack.spacing = 0
        websiteListStack.translatesAutoresizingMaskIntoConstraints = false
        let websiteDocument = ControlCenterFlippedDocumentView()
        websiteDocument.translatesAutoresizingMaskIntoConstraints = false
        websiteDocument.addSubview(websiteListStack)
        NSLayoutConstraint.activate([
            websiteListStack.topAnchor.constraint(equalTo: websiteDocument.topAnchor),
            websiteListStack.bottomAnchor.constraint(lessThanOrEqualTo: websiteDocument.bottomAnchor),
            websiteListStack.leadingAnchor.constraint(equalTo: websiteDocument.leadingAnchor),
            websiteListStack.trailingAnchor.constraint(equalTo: websiteDocument.trailingAnchor),
            websiteListStack.widthAnchor.constraint(equalTo: websiteDocument.widthAnchor),
        ])
        let websiteScroll = NSScrollView()
        websiteScroll.documentView = websiteDocument
        websiteScroll.hasVerticalScroller = true
        websiteScroll.autohidesScrollers = true
        websiteScroll.drawsBackground = false
        websiteScroll.borderType = .noBorder
        websiteScroll.translatesAutoresizingMaskIntoConstraints = false
        websiteDocument.widthAnchor.constraint(
            equalTo: websiteScroll.contentView.widthAnchor
        ).isActive = true
        websiteDocument.heightAnchor.constraint(
            greaterThanOrEqualTo: websiteScroll.contentView.heightAnchor
        ).isActive = true
        let websiteCard = ControlCenterCardView()
        websiteCard.addSubview(websiteScroll)
        NSLayoutConstraint.activate([
            websiteScroll.topAnchor.constraint(equalTo: websiteCard.topAnchor),
            websiteScroll.bottomAnchor.constraint(equalTo: websiteCard.bottomAnchor),
            websiteScroll.leadingAnchor.constraint(equalTo: websiteCard.leadingAnchor),
            websiteScroll.trailingAnchor.constraint(equalTo: websiteCard.trailingAnchor),
            websiteCard.heightAnchor.constraint(equalToConstant: 92),
        ])

        let addButton = NSButton(
            title: "Add Apps\u{2026}",
            target: self,
            action: #selector(addApps(_:))
        )
        addButton.bezelStyle = .rounded
        addButton.controlSize = .regular
        addButton.setAccessibilityIdentifier("hush.verified.addException")
        addButton.setAccessibilityLabel("Add Apps\u{2026}")
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        let footer = NSStackView(views: [addButton, NSView(), doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let content = NSStackView(views: [
            title,
            detail,
            automaticCard,
            personalTitle,
            listCard,
            websitesTitle,
            websiteEntry,
            websiteCard,
            footer,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 480),
            root.heightAnchor.constraint(equalToConstant: 546),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
        ])
        for fullWidthView in [
            detail,
            automaticCard,
            personalTitle,
            listCard,
            websitesTitle,
            websiteEntry,
            websiteCard,
            footer,
        ] {
            fullWidthView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        refreshList()
        refreshWebsiteList()
    }

    private func refreshList() {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let exceptions = Settings.shared.verifiedMessagesAppExceptions
        guard !exceptions.isEmpty else {
            let host = NSView()
            host.addSubview(emptyLabel)
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.heightAnchor.constraint(equalToConstant: 72),
                emptyLabel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            ])
            listStack.addArrangedSubview(host)
            host.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            return
        }

        for (index, exception) in exceptions.enumerated() {
            let row = makeExceptionRow(exception, showsSeparator: index < exceptions.count - 1)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func makeExceptionRow(
        _ exception: VerifiedMessageAppException,
        showsSeparator: Bool
    ) -> NSView {
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = applicationIcon(bundleIdentifier: exception.bundleIdentifier)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
        ])

        let name = NSTextField(labelWithString: exception.displayName)
        name.font = .systemFont(ofSize: 12.5, weight: .medium)
        let identifier = NSTextField(labelWithString: exception.bundleIdentifier)
        identifier.font = .systemFont(ofSize: 10.5)
        identifier.textColor = .tertiaryLabelColor
        let labels = NSStackView(views: [name, identifier])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let remove = NSButton(
            image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove")!,
            target: self,
            action: #selector(removeException(_:))
        )
        remove.bezelStyle = .inline
        remove.isBordered = false
        remove.contentTintColor = .secondaryLabelColor
        remove.identifier = NSUserInterfaceItemIdentifier(exception.bundleIdentifier)
        remove.setAccessibilityLabel("Remove \(exception.displayName)")

        let row = NSStackView(views: [icon, labels, NSView(), remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 10)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        if showsSeparator {
            let host = NSView()
            host.addSubview(row)
            let separator = ControlCenterSeparatorView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(separator)
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: host.topAnchor),
                row.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                separator.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 50),
                separator.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
                separator.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1),
            ])
            return host
        }
        return row
    }

    private func refreshWebsiteList() {
        websiteListStack.arrangedSubviews.forEach {
            websiteListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let exceptions = Settings.shared.verifiedMessagesWebsiteExceptions
        guard !exceptions.isEmpty else {
            let label = NSTextField(labelWithString: "No website exceptions")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            let host = NSView()
            host.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.heightAnchor.constraint(equalToConstant: 72),
                label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            ])
            websiteListStack.addArrangedSubview(host)
            host.widthAnchor.constraint(equalTo: websiteListStack.widthAnchor).isActive = true
            return
        }

        for (index, exception) in exceptions.enumerated() {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(true)
            icon.setAccessibilityIdentifier("hush.verified.websiteIconFallback.\(exception.host)")
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
            ])
            Task { [weak icon] in
                guard let data = await WebsiteIconLoader.shared.iconData(for: exception.host),
                      let image = NSImage(data: data),
                      let icon else { return }
                image.isTemplate = false
                icon.image = image
                icon.contentTintColor = nil
                icon.setAccessibilityIdentifier("hush.verified.websiteIcon.\(exception.host)")
                icon.setAccessibilityLabel("\(exception.host) website icon")
            }
            let hostLabel = NSTextField(labelWithString: exception.host)
            hostLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
            let remove = NSButton(
                image: NSImage(
                    systemSymbolName: "minus.circle.fill",
                    accessibilityDescription: "Remove"
                )!,
                target: self,
                action: #selector(removeWebsite(_:))
            )
            remove.bezelStyle = .inline
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.identifier = NSUserInterfaceItemIdentifier(exception.host)
            remove.setAccessibilityLabel("Remove \(exception.host)")
            let row = NSStackView(views: [icon, hostLabel, NSView(), remove])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 10)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
            websiteListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: websiteListStack.widthAnchor).isActive = true

            if index < exceptions.count - 1 {
                let separator = ControlCenterSeparatorView()
                websiteListStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: websiteListStack.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }
    }

    private func applicationIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @objc private func addApps(_ sender: NSButton) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose one or more apps"
        panel.message = "Select multiple apps with Command-click or Shift-click."
        panel.prompt = "Add Apps"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            var exceptions = Settings.shared.verifiedMessagesAppExceptions
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      !VerifiedMessageDestinationPolicy.isKnownTerminal(bundleIdentifier) else {
                    continue
                }
                let displayName = (bundle.object(
                    forInfoDictionaryKey: "CFBundleDisplayName"
                ) as? String) ?? (bundle.object(
                    forInfoDictionaryKey: "CFBundleName"
                ) as? String) ?? url.deletingPathExtension().lastPathComponent
                exceptions.append(VerifiedMessageAppException(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName
                ))
            }
            Settings.shared.verifiedMessagesAppExceptions = exceptions
            refreshList()
            onChange?()
        }
    }

    @objc private func removeException(_ sender: NSButton) {
        guard let bundleIdentifier = sender.identifier?.rawValue else { return }
        Settings.shared.verifiedMessagesAppExceptions.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        refreshList()
        onChange?()
    }

    @objc private func addWebsite(_ sender: Any) {
        guard let exception = VerifiedMessageWebsiteException(host: websiteField.stringValue) else {
            NSSound.beep()
            view.window?.makeFirstResponder(websiteField)
            return
        }
        var exceptions = Settings.shared.verifiedMessagesWebsiteExceptions
        exceptions.append(exception)
        Settings.shared.verifiedMessagesWebsiteExceptions = exceptions
        websiteField.stringValue = ""
        refreshWebsiteList()
        onChange?()
    }

    @objc private func removeWebsite(_ sender: NSButton) {
        guard let host = sender.identifier?.rawValue else { return }
        Settings.shared.verifiedMessagesWebsiteExceptions.removeAll { $0.host == host }
        refreshWebsiteList()
        onChange?()
    }

    @objc private func done(_ sender: NSButton) {
        onDone?()
    }
}

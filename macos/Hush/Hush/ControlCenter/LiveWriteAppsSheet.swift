import AppKit
import UniformTypeIdentifiers

/// The apps where Live Write stays off: the standard list, editable, in the same form as
/// Verified Messages' destination exceptions.
@MainActor
final class LiveWriteAppsViewController: NSViewController {
    var onDone: (() -> Void)?
    private let listStack = NSStackView()
    private var listHeight: NSLayoutConstraint?
    private static let appRowHeight: CGFloat = 48
    private static let websiteRowHeight: CGFloat = 40
    private let websiteStack = NSStackView()
    private let websiteField = NSTextField()
    private let emptyLabel = NSTextField(labelWithString: "Live Write writes in every app on this Mac")

    override func loadView() {
        let root = NSView()
        view = root
        let title = NSTextField(labelWithString: "Where Live Write Stays Off")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString: "Here your words go in as spoken. Terminals and code editors get commands and code, AI chats get your prompt, password managers get secrets. Only apps on this Mac are listed.")
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 0
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(listStack)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let card = ControlCenterCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)

        let add = NSButton(title: "Add Apps\u{2026}", target: self, action: #selector(addApps(_:)))
        add.bezelStyle = .rounded
        add.setAccessibilityIdentifier("hush.livewrite.apps.add")
        let reset = NSButton(title: "Reset to Standard", target: self, action: #selector(resetToStandard(_:)))
        reset.bezelStyle = .rounded
        reset.setAccessibilityIdentifier("hush.livewrite.apps.reset")
        let done = NSButton(title: "Done", target: self, action: #selector(finish(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [add, reset, NSView(), done])
        buttons.spacing = 8

        websiteStack.orientation = .vertical
        websiteStack.alignment = .leading
        websiteStack.spacing = 0
        let websiteCard = ControlCenterCardView()
        websiteCard.translatesAutoresizingMaskIntoConstraints = false
        websiteStack.translatesAutoresizingMaskIntoConstraints = false
        websiteCard.addSubview(websiteStack)
        websiteField.placeholderString = "example.com"
        websiteField.target = self
        websiteField.action = #selector(addWebsite(_:))
        websiteField.setAccessibilityLabel("Website where Live Write stays off")
        let addWebsite = NSButton(title: "Add", target: self, action: #selector(addWebsite(_:)))
        addWebsite.bezelStyle = .rounded
        let websiteEntry = NSStackView(views: [websiteField, addWebsite])
        websiteEntry.spacing = 8
        let appsHeading = NSTextField(labelWithString: "Apps")
        let websitesHeading = NSTextField(labelWithString: "Websites")
        for heading in [appsHeading, websitesHeading] {
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            heading.textColor = .secondaryLabelColor
        }

        let content = NSStackView(views: [title, detail, appsHeading, card, websitesHeading, websiteCard, websiteEntry, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            detail.widthAnchor.constraint(equalTo: content.widthAnchor),
            card.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor),

            websiteCard.widthAnchor.constraint(equalTo: content.widthAnchor),
            websiteEntry.widthAnchor.constraint(equalTo: content.widthAnchor),
            websiteStack.topAnchor.constraint(equalTo: websiteCard.topAnchor, constant: 4),
            websiteStack.bottomAnchor.constraint(equalTo: websiteCard.bottomAnchor, constant: -4),
            websiteStack.leadingAnchor.constraint(equalTo: websiteCard.leadingAnchor),
            websiteStack.trailingAnchor.constraint(equalTo: websiteCard.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listStack.topAnchor.constraint(equalTo: document.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        listHeight = card.heightAnchor.constraint(equalToConstant: 72)
        listHeight?.isActive = true
        refreshList()
        refreshWebsites()
    }

    /// The list grows with its rows and scrolls past five, so few apps leave no empty card.
    private func fitList(rows: Int) {
        listHeight?.constant = rows == 0 ? 72 : CGFloat(min(rows, 5)) * Self.appRowHeight + 8
    }

    private func refreshWebsites() {
        websiteStack.arrangedSubviews.forEach { websiteStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let websites = Settings.shared.liveWriteWebsiteExceptions
        for (index, website) in websites.enumerated() {
            let globe = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!)
            globe.contentTintColor = .secondaryLabelColor
            let name = NSTextField(labelWithString: website.host)
            name.font = .systemFont(ofSize: 12.5, weight: .medium)
            let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove")!,
                                  target: self, action: #selector(removeWebsite(_:)))
            remove.bezelStyle = .inline
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.identifier = NSUserInterfaceItemIdentifier(website.host)
            remove.setAccessibilityLabel("Remove \(website.host)")
            let row = NSStackView(views: [globe, name, NSView(), remove])
            row.alignment = .centerY
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 10)
            globe.translatesAutoresizingMaskIntoConstraints = false
            globe.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let host = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(row)
            var constraints = [
                row.topAnchor.constraint(equalTo: host.topAnchor),
                row.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ]
            if index < websites.count - 1 {
                // Indented like the app rows: the line starts under the text, not the icon.
                let separator = ControlCenterSeparatorView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(separator)
                constraints += [
                    separator.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 50),
                    separator.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
                    separator.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                    separator.heightAnchor.constraint(equalToConstant: 1),
                ]
            }
            NSLayoutConstraint.activate(constraints)
            websiteStack.addArrangedSubview(host)
            host.widthAnchor.constraint(equalTo: websiteStack.widthAnchor).isActive = true
            host.heightAnchor.constraint(equalToConstant: Self.websiteRowHeight).isActive = true
        }
    }

    @objc private func addWebsite(_ sender: Any) {
        guard let website = VerifiedMessageWebsiteException(host: websiteField.stringValue) else { NSSound.beep(); return }
        Settings.shared.liveWriteWebsiteExceptions += [website]
        websiteField.stringValue = ""
        refreshWebsites()
    }

    @objc private func removeWebsite(_ sender: NSButton) {
        guard let host = sender.identifier?.rawValue else { return }
        Settings.shared.liveWriteWebsiteExceptions.removeAll { $0.host == host }
        refreshWebsites()
    }

    private func refreshList() {
        listStack.arrangedSubviews.forEach { listStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let exceptions = LiveWriteApps.installed(Settings.shared.liveWriteAppExceptions) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        fitList(rows: exceptions.count)
        guard !exceptions.isEmpty else {
            emptyLabel.textColor = .secondaryLabelColor
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
            let row = makeRow(exception, showsSeparator: index < exceptions.count - 1)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: Self.appRowHeight).isActive = true
        }
    }

    private func makeRow(_ exception: LiveWriteAppException, showsSeparator: Bool) -> NSView {
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = Self.icon(for: exception.bundleIdentifier)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let name = NSTextField(labelWithString: exception.displayName)
        name.font = .systemFont(ofSize: 12.5, weight: .medium)
        let note = NSTextField(labelWithString: exception.bundleIdentifier)
        note.font = .systemFont(ofSize: 10.5)
        note.textColor = .tertiaryLabelColor
        let labels = NSStackView(views: [name, note])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove")!,
                              target: self, action: #selector(remove(_:)))
        remove.bezelStyle = .inline
        remove.isBordered = false
        remove.contentTintColor = .secondaryLabelColor
        remove.identifier = NSUserInterfaceItemIdentifier(exception.bundleIdentifier)
        remove.setAccessibilityLabel("Remove \(exception.displayName)")
        let row = NSStackView(views: [icon, labels, NSView(), remove])
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        guard showsSeparator else { return row }
        let host = NSView()
        let separator = ControlCenterSeparatorView()
        for view in [row, separator] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view) }
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

    private static func icon(for bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @objc private func addApps(_ sender: NSButton) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose one or more apps"
        panel.message = "Live Write stays off in the apps you choose."
        panel.prompt = "Add Apps"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let added = panel.urls.compactMap { url -> LiveWriteAppException? in
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                return LiveWriteAppException(bundleIdentifier: identifier, displayName: name)
            }
            Settings.shared.liveWriteAppExceptions += added
            refreshList()
        }
    }

    @objc private func remove(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        Settings.shared.liveWriteAppExceptions.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
        }
        refreshList()
    }

    @objc private func resetToStandard(_ sender: NSButton) {
        Settings.shared.resetLiveWriteAppExceptions()
        refreshList()
        refreshWebsites()
    }

    @objc private func finish(_ sender: NSButton) { onDone?() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

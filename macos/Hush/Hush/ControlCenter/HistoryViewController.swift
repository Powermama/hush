import AppKit
import Combine

@MainActor
final class HistoryViewController: ControlCenterPageViewController {
    private let previewMode: Bool
    private var subscriptions = Set<AnyCancellable>()
    private let searchField = NSSearchField()
    private let dateFilter = NSPopUpButton()
    private let retentionButton = NSPopUpButton()
    private let historyStack = NSStackView()
    private var range: ActivityRange = .thirtyDays

    init(previewMode: Bool) {
        self.previewMode = previewMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "Dictation history",
            detail: "Search, copy, or remove final text stored locally on this Mac."
        ))
        buildToolbar()
        buildList()
        buildPrivacyControls()
        if !previewMode {
            ActivityStore.shared.$history
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.reloadRows() }
                .store(in: &subscriptions)
        }
        reloadRows()
    }

    private func buildToolbar() {
        searchField.placeholderString = "Search dictations"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filtersChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true

        dateFilter.addItems(withTitles: ["Today", "7 days", "30 days", "All time"])
        dateFilter.selectItem(at: 2)
        dateFilter.target = self
        dateFilter.action = #selector(filtersChanged(_:))

        let toolbar = NSStackView(views: [searchField, NSView(), dateFilter])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 12
        addFullWidth(toolbar)
    }

    private func buildList() {
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 0
        addFullWidth(makeCard(content: historyStack))
    }

    private func buildPrivacyControls() {
        retentionButton.removeAllItems()
        for retention in Settings.HistoryRetention.allCases {
            retentionButton.addItem(withTitle: retention.displayName)
            retentionButton.lastItem?.representedObject = retention.rawValue
        }
        if let index = Settings.HistoryRetention.allCases.firstIndex(of: Settings.shared.historyRetention) {
            retentionButton.selectItem(at: index)
        }
        retentionButton.target = self
        retentionButton.action = #selector(retentionChanged(_:))

        let clear = NSButton(title: "Clear History...", target: self, action: #selector(clearHistory(_:)))
        clear.bezelStyle = .rounded
        clear.controlSize = .small

        let reset = NSButton(title: "Reset Activity...", target: self, action: #selector(resetActivity(_:)))
        reset.bezelStyle = .rounded
        reset.controlSize = .small

        let retentionRow = ControlCenterKeyValueRow(
            title: "Keep dictation text",
            subtitle: "Only final text created by hush is stored. Audio is never kept.",
            trailing: retentionButton
        )
        let actions = NSStackView(views: [clear, reset])
        actions.orientation = .horizontal
        actions.spacing = 8
        let actionsRow = ControlCenterKeyValueRow(
            title: "Local data",
            subtitle: "History and activity remain on this Mac.",
            trailing: actions,
            showsSeparator: false
        )
        let rows = NSStackView(views: [retentionRow, actionsRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        addFullWidth(sectionTitle("Privacy & retention"))
        addFullWidth(makeCard(content: rows))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
    }

    private func reloadRows() {
        historyStack.arrangedSubviews.forEach {
            historyStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = previewMode ? Self.previewHistory : ActivityStore.shared.history
        let filtered = source.filter { item in
            range.contains(item.createdAt)
                && (query.isEmpty
                    || item.text.localizedCaseInsensitiveContains(query)
                    || item.appName.localizedCaseInsensitiveContains(query))
        }

        if filtered.isEmpty {
            let text = Settings.shared.historyRetention == .off
                ? "Dictation history is off. Aggregate activity remains local."
                : query.isEmpty
                    ? "Completed hush dictations will appear here."
                    : "No dictations match your search."
            let empty = NSTextField(wrappingLabelWithString: text)
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            let host = NSView()
            empty.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(empty)
            NSLayoutConstraint.activate([
                host.heightAnchor.constraint(equalToConstant: 86),
                empty.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18),
                empty.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
                empty.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            ])
            historyStack.addArrangedSubview(host)
        } else {
            for (index, item) in filtered.prefix(200).enumerated() {
                let row = HistoryItemRow(item: item, showsSeparator: index < filtered.count - 1)
                row.onCopy = { Self.copy(item.text) }
                row.onDelete = { ActivityStore.shared.delete(item.id) }
                historyStack.addArrangedSubview(row)
            }
        }
        for row in historyStack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
        }
    }

    @objc private func filtersChanged(_ sender: Any?) {
        let ranges: [ActivityRange] = [.today, .sevenDays, .thirtyDays, .allTime]
        if ranges.indices.contains(dateFilter.indexOfSelectedItem) {
            range = ranges[dateFilter.indexOfSelectedItem]
        }
        reloadRows()
    }

    @objc private func retentionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let retention = Settings.HistoryRetention(rawValue: raw) else { return }
        Settings.shared.historyRetention = retention
        ActivityStore.shared.applyRetentionPolicy()
    }

    @objc private func clearHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear dictation history?"
        alert.informativeText = "This permanently removes stored hush text. Activity totals remain available."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ActivityStore.shared.clearHistory()
    }

    @objc private func resetActivity(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Reset activity metrics?"
        alert.informativeText = "Words, speech time, estimated time saved, dictation counts, and destinations will be reset. Dictation text remains available."
        alert.addButton(withTitle: "Reset Activity")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ActivityStore.shared.resetActivity()
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static var previewHistory: [DictationActivity] {
        [
            DictationActivity(id: UUID(), text: "I wanted to follow up on our shipping timeline and confirm the final launch date.", appName: "Mail", appBundleIdentifier: "com.apple.mail", createdAt: Date().addingTimeInterval(-120), duration: 11, wordCount: 15, modelName: "Large v3", personaName: "Business", providerName: "Qwen 3 1.7B", copiedToClipboard: false),
            DictationActivity(id: UUID(), text: "shipping the landing page today, I will send the preview when it is ready", appName: "Slack", appBundleIdentifier: "com.tinyspeck.slackmacgap", createdAt: Date().addingTimeInterval(-1080), duration: 8, wordCount: 13, modelName: "Large v3", personaName: "Slack DM", providerName: "Qwen 3 1.7B", copiedToClipboard: false),
            DictationActivity(id: UUID(), text: "Review the onboarding flow before the next release candidate.", appName: "Notes", appBundleIdentifier: "com.apple.Notes", createdAt: Date().addingTimeInterval(-3500), duration: 6, wordCount: 9, modelName: "Large v3", personaName: nil, providerName: nil, copiedToClipboard: false),
            DictationActivity(id: UUID(), text: "The dashboard should show the active transcription model and make local processing clear.", appName: "Clipboard", appBundleIdentifier: nil, createdAt: Date().addingTimeInterval(-7800), duration: 9, wordCount: 13, modelName: "Large v3", personaName: "Business", providerName: "Apple Intelligence", copiedToClipboard: true),
        ]
    }
}

@MainActor
private final class HistoryItemRow: NSView {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    init(item: DictationActivity, showsSeparator: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(wrappingLabelWithString: item.text.replacingOccurrences(of: "\n", with: " "))
        text.font = .systemFont(ofSize: 12.5)
        text.textColor = .labelColor
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byTruncatingTail
        text.alignment = .left

        var details = [item.appName, Self.dateFormatter.string(from: item.createdAt)]
        if item.isHushEditorOutput {
            details.append("Typed in hush")
        } else {
            details.append(item.duration.hushCompactDuration)
        }
        details.append("\(item.wordCount) words")
        if let persona = item.personaName { details.append(persona) }
        let metadata = NSTextField(labelWithString: details.joined(separator: " · "))
        metadata.font = .systemFont(ofSize: 10.5)
        metadata.textColor = .secondaryLabelColor
        metadata.lineBreakMode = .byTruncatingTail
        metadata.alignment = .left

        let menu = NSButton()
        menu.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        menu.bezelStyle = .inline
        menu.isBordered = false
        menu.contentTintColor = .secondaryLabelColor
        menu.target = self
        menu.action = #selector(menuTapped(_:))

        text.translatesAutoresizingMaskIntoConstraints = false
        metadata.translatesAutoresizingMaskIntoConstraints = false
        menu.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        addSubview(metadata)
        addSubview(menu)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: menu.leadingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            metadata.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: text.trailingAnchor),
            metadata.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 4),
            metadata.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -11),
            menu.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            menu.centerYAnchor.constraint(equalTo: centerYAnchor),
            menu.widthAnchor.constraint(equalToConstant: 28),
            menu.heightAnchor.constraint(equalToConstant: 28),
        ])
        if showsSeparator {
            let separator = ControlCenterSeparatorView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                separator.bottomAnchor.constraint(equalTo: bottomAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func menuTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: #selector(copyFromMenu(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete", action: #selector(deleteFromMenu(_:)), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    @objc private func copyFromMenu(_ sender: Any?) { onCopy?() }
    @objc private func deleteFromMenu(_ sender: Any?) { onDelete?() }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

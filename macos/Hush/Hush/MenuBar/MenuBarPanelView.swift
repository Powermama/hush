import AppKit

enum MenuPanelStatus: Equatable {
    case idle
    case loading(Int)
    case listening
    case transcribing
    case polishing(String)
    case inserted
    case error

    var title: String {
        switch self {
        case .idle:                  return "Idle"
        case .loading(let progress): return "Loading \(progress)%"
        case .listening:             return "Listening"
        case .transcribing:          return "Transcribing"
        case .polishing(let name):   return "Polishing \(name)"
        case .inserted:              return "Inserted"
        case .error:                 return "Error"
        }
    }

    var dotColor: NSColor {
        switch self {
        case .idle:                  return .tertiaryLabelColor
        case .loading, .transcribing,
             .polishing:            return DesignTokens.info
        case .listening, .error:     return DesignTokens.danger
        case .inserted:              return DesignTokens.good
        }
    }
}

@MainActor
final class MenuBarPanelView: NSView {
    static let panelWidth: CGFloat = 260

    private let onSettings: () -> Void
    private let onPermissions: () -> Void
    private let onPersona: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void
    private let onRecent: (RecentInsert) -> Void

    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Idle")
    private let hotkeyLabel = NSTextField(labelWithString: "hold fn anywhere")
    private let topSeparator = NSBox()
    private let recentHeader = NSTextField(labelWithString: "RECENT")
    private let controlsSeparator = NSBox()
    private let actionSeparator = NSBox()
    private lazy var personaRow = MenuActionRow(
        title: "Persona",
        trailing: "Off",
        action: { [weak self] in self?.onPersona() }
    )
    private lazy var permissionsRow = MenuActionRow(
        title: "Permissions",
        trailing: "Check",
        action: { [weak self] in self?.onPermissions() }
    )
    private lazy var settingsRow = MenuActionRow(
        title: "Settings...",
        trailing: "⌘,",
        action: { [weak self] in self?.onSettings() }
    )
    private lazy var quitRow = MenuActionRow(
        title: "Quit hush",
        trailing: "⌘Q",
        action: { [weak self] in self?.onQuit() }
    )
    private lazy var updateRow = MenuActionRow(
        title: "Check for Updates...",
        trailing: "",
        action: { [weak self] in self?.onCheckForUpdates() }
    )

    private var recentRows: [RecentInsertRow] = []
    private var emptyLabel: NSTextField?
    private var status: MenuPanelStatus = .idle

    override var isFlipped: Bool { true }

    init(
        onSettings: @escaping () -> Void,
        onPermissions: @escaping () -> Void,
        onPersona: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onRecent: @escaping (RecentInsert) -> Void
    ) {
        self.onSettings = onSettings
        self.onPermissions = onPermissions
        self.onPersona = onPersona
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
        self.onRecent = onRecent
        super.init(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 192))

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        addSubview(statusDot)

        statusLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        statusLabel.textColor = .labelColor
        addSubview(statusLabel)

        hotkeyLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        hotkeyLabel.textColor = .tertiaryLabelColor
        hotkeyLabel.alignment = .right
        hotkeyLabel.lineBreakMode = .byTruncatingHead
        addSubview(hotkeyLabel)

        configureSeparator(topSeparator)
        addSubview(topSeparator)

        recentHeader.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        recentHeader.textColor = .tertiaryLabelColor
        recentHeader.attributedStringValue = NSAttributedString(
            string: "RECENT",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.5,
            ]
        )
        addSubview(recentHeader)

        configureSeparator(controlsSeparator)
        addSubview(controlsSeparator)
        addSubview(personaRow)
        addSubview(permissionsRow)

        configureSeparator(actionSeparator)
        addSubview(actionSeparator)
        addSubview(settingsRow)
        addSubview(updateRow)
        addSubview(quitRow)

        setStatus(.idle)
        setRecentItems([])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setStatus(_ status: MenuPanelStatus) {
        self.status = status
        statusLabel.stringValue = status.title
        updateStatusDot()
    }

    func setHotkeyHint(_ text: String) {
        hotkeyLabel.stringValue = text
    }

    func setPersona(_ text: String) {
        personaRow.setTrailing(text)
    }

    func setPermissions(_ text: String, needsAttention: Bool) {
        permissionsRow.setTrailing(
            text,
            color: needsAttention ? DesignTokens.danger : DesignTokens.goodInk
        )
    }

    func setRecentItems(_ items: [RecentInsert]) {
        recentRows.forEach { $0.removeFromSuperview() }
        recentRows.removeAll()
        emptyLabel?.removeFromSuperview()
        emptyLabel = nil

        for item in items.prefix(3) {
            let row = RecentInsertRow(item: item) { [weak self] selected in
                self?.onRecent(selected)
            }
            recentRows.append(row)
            addSubview(row)
        }

        if recentRows.isEmpty {
            let label = NSTextField(labelWithString: "Your recent dictations appear here")
            label.font = .systemFont(ofSize: 11.5, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            emptyLabel = label
            addSubview(label)
        }

        let visibleRowCount = max(recentRows.count, 1)
        frame.size.height = 275 + CGFloat(visibleRowCount * 34)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let statusRowMidY: CGFloat = 23
        statusLabel.frame = NSRect(x: 31, y: statusRowMidY - 8.5, width: 103, height: 17)
        statusDot.frame = NSRect(x: 16, y: statusRowMidY - 3.5, width: 7, height: 7)
        statusDot.layer?.cornerRadius = 3.5
        hotkeyLabel.frame = NSRect(x: 132, y: statusRowMidY - 8.5, width: 112, height: 17)
        topSeparator.frame = NSRect(x: 14, y: 45, width: bounds.width - 28, height: 1)
        recentHeader.frame = NSRect(x: 16, y: 57, width: 100, height: 14)

        let rowsStart: CGFloat = 76
        if let emptyLabel {
            emptyLabel.frame = NSRect(x: 18, y: rowsStart + 7, width: bounds.width - 36, height: 19)
        } else {
            for (index, row) in recentRows.enumerated() {
                row.frame = NSRect(
                    x: 10,
                    y: rowsStart + CGFloat(index * 34),
                    width: bounds.width - 20,
                    height: 34
                )
            }
        }

        let visibleRowCount = max(recentRows.count, 1)
        let separatorY = rowsStart + CGFloat(visibleRowCount * 34) + 2
        controlsSeparator.frame = NSRect(x: 14, y: separatorY, width: bounds.width - 28, height: 1)
        personaRow.frame = NSRect(x: 8, y: separatorY + 8, width: bounds.width - 16, height: 34)
        permissionsRow.frame = NSRect(x: 8, y: separatorY + 42, width: bounds.width - 16, height: 34)
        actionSeparator.frame = NSRect(x: 14, y: separatorY + 83, width: bounds.width - 28, height: 1)
        settingsRow.frame = NSRect(x: 8, y: separatorY + 91, width: bounds.width - 16, height: 34)
        updateRow.frame = NSRect(x: 8, y: separatorY + 125, width: bounds.width - 16, height: 34)
        quitRow.frame = NSRect(x: 8, y: separatorY + 159, width: bounds.width - 16, height: 34)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStatusDot()
        recentHeader.attributedStringValue = NSAttributedString(
            string: "RECENT",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.5,
            ]
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case ",": onSettings(); return true
        case "q": onQuit(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
    }

    private func updateStatusDot() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            statusDot.layer?.backgroundColor = status.dotColor.cgColor
        }
    }
}

@MainActor
private final class RecentInsertRow: NSView {
    private let item: RecentInsert
    private let action: (RecentInsert) -> Void
    private let textLabel = NSTextField(labelWithString: "")
    private let appNameView: AppNameView
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground() } }

    override var isFlipped: Bool { true }

    init(item: RecentInsert, action: @escaping (RecentInsert) -> Void) {
        self.item = item
        self.action = action
        self.appNameView = AppNameView(title: item.appName)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous

        textLabel.stringValue = item.text.replacingOccurrences(of: "\n", with: " ")
        textLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        textLabel.textColor = .secondaryLabelColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.toolTip = item.text
        toolTip = item.text
        addSubview(textLabel)
        addSubview(appNameView)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy recent dictation from \(item.appName)")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let appNameWidth = appNameView.preferredWidth
        appNameView.frame = NSRect(
            x: bounds.width - appNameWidth - 6,
            y: 7,
            width: appNameWidth,
            height: 20
        )
        textLabel.frame = NSRect(x: 8, y: 7, width: max(20, appNameView.frame.minX - 16), height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        action(item)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isHovered
                ? NSColor.labelColor.withAlphaComponent(0.06).cgColor
                : NSColor.clear.cgColor
        }
    }
}

@MainActor
private final class AppNameView: NSView {
    private let label: NSTextField?
    private let imageView: NSImageView?
    let preferredWidth: CGFloat

    override var isFlipped: Bool { true }

    init(title: String) {
        let displayTitle = title.isEmpty ? "App" : title
        if displayTitle == "Clipboard" {
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: "Copied to clipboard"
            )
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            imageView.contentTintColor = .tertiaryLabelColor
            self.label = nil
            self.imageView = imageView
            self.preferredWidth = 24
        } else {
            let label = NSTextField(labelWithString: displayTitle)
            let font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
            let measured = (displayTitle as NSString).size(withAttributes: [.font: font]).width
            label.font = font
            label.textColor = .tertiaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            self.label = label
            self.imageView = nil
            self.preferredWidth = min(84, max(36, ceil(measured) + 12))
        }
        super.init(frame: .zero)

        if let label { addSubview(label) }
        if let imageView { addSubview(imageView) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label?.frame = bounds
        imageView?.frame = NSRect(
            x: bounds.midX - 7,
            y: bounds.midY - 7,
            width: 14,
            height: 14
        )
    }
}

@MainActor
private final class MenuActionRow: NSView {
    private let action: () -> Void
    private let titleLabel: NSTextField
    private let trailingLabel: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground() } }

    override var isFlipped: Bool { true }

    init(title: String, trailing: String, action: @escaping () -> Void) {
        self.action = action
        self.titleLabel = NSTextField(labelWithString: title)
        self.trailingLabel = NSTextField(labelWithString: trailing)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous

        titleLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        trailingLabel.font = .systemFont(ofSize: 11, weight: .regular)
        trailingLabel.textColor = .tertiaryLabelColor
        trailingLabel.alignment = .right
        trailingLabel.lineBreakMode = .byTruncatingHead
        addSubview(trailingLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTrailing(_ text: String, color: NSColor = .tertiaryLabelColor) {
        trailingLabel.stringValue = text
        trailingLabel.textColor = color
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 8, y: 7, width: bounds.width - 116, height: 21)
        trailingLabel.frame = NSRect(x: bounds.width - 104, y: 8, width: 96, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { action() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isHovered
                ? NSColor.labelColor.withAlphaComponent(0.07).cgColor
                : NSColor.clear.cgColor
        }
    }
}

import AppKit

enum HushDestination: Hashable {
    case dashboard
    case timeSaved(range: ActivityRange = .sevenDays)
    case activity(range: ActivityRange = .sevenDays)
    case history(recordID: UUID? = nil)
    case general
    case transcription
    case transcriptionEngine(SpeechEngine)
    case personas(focusEnableAI: Bool = false)
    case ai
    case assistant
    case interface
    case verifiedMessages
    case permissions(focusFirstMissing: Bool = false)
    case about

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .timeSaved: return "Time Saved"
        case .activity: return "Activity"
        case .history: return "History"
        case .general: return "General"
        case .transcription: return "Transcription"
        case .transcriptionEngine(let engine): return engine.familyName
        case .personas: return "Personas"
        case .ai: return "Hush AI"
        case .assistant: return "Assistant"
        case .interface: return "HUD & Menu"
        case .verifiedMessages: return "Verified Messages"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    /// Drill-in pages return to their parent through the header's back button.
    var parent: HushDestination? {
        switch self {
        case .personas, .assistant: return .ai
        case .timeSaved: return .dashboard
        case .transcriptionEngine: return .transcription
        default: return nil
        }
    }

    var identity: String {
        switch self {
        case .dashboard: return "dashboard"
        case .timeSaved: return "time-saved"
        case .activity: return "activity"
        case .history: return "history"
        case .general: return "general"
        case .transcription: return "transcription"
        case .transcriptionEngine: return "transcription-engine"
        case .personas: return "personas"
        case .ai: return "ai"
        case .assistant: return "assistant"
        case .interface: return "interface"
        case .verifiedMessages: return "verified-messages"
        case .permissions: return "permissions"
        case .about: return "about"
        }
    }
}

@MainActor
final class HushControlCenterViewController: NSViewController {
    private weak var coordinator: DictationCoordinator?
    private let previewMode: Bool
    private let sidebar = NSVisualEffectView()
    private let searchField = NSSearchField()
    private let navigationStack = NSStackView()
    private let detailHost = NSView()
    private let titleLabel = NSTextField(labelWithString: "Dashboard")
    private let backButton = NSButton()
    private let contentHost = NSView()
    private var navigationRows: [String: SidebarRowView] = [:]
    private var currentController: NSViewController?
    private var dashboardRange: ActivityRange = .sevenDays
    private(set) var destination: HushDestination = .dashboard

    var onDestinationChanged: ((HushDestination) -> Void)?

    init(coordinator: DictationCoordinator?, previewMode: Bool = false) {
        self.coordinator = coordinator
        self.previewMode = previewMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 720))
        root.wantsLayer = true
        view = root

        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        detailHost.wantsLayer = true
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detailHost)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: ControlCenterStyle.sidebarWidth),
            detailHost.topAnchor.constraint(equalTo: root.topAnchor),
            detailHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detailHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detailHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        buildSidebar()
        buildDetail()
        navigate(to: .dashboard)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The window would otherwise focus the sidebar search field and draw its
        // focus ring on open; search starts when the user clicks or types into it.
        view.window?.makeFirstResponder(nil)
    }

    func navigate(to destination: HushDestination) {
        loadViewIfNeeded()
        self.destination = destination
        titleLabel.stringValue = destination.title
        let selectedIdentity = destination.parent?.identity ?? destination.identity
        for (identity, row) in navigationRows { row.isSelected = identity == selectedIdentity }
        if let parent = destination.parent {
            backButton.title = parent.title
            backButton.toolTip = "Back to \(parent.title)"
            backButton.image = NSImage(
                systemSymbolName: "chevron.backward",
                accessibilityDescription: "Back to \(parent.title)"
            )
            backButton.isHidden = false
        } else {
            backButton.isHidden = true
        }

        let controller = makeController(for: destination)
        if let currentController {
            currentController.view.removeFromSuperview()
            currentController.removeFromParent()
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
        ])
        currentController = controller
        onDestinationChanged?(destination)
    }

    private func buildSidebar() {
        searchField.placeholderString = "Search hush"
        searchField.font = .systemFont(ofSize: 12.5)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        sidebar.addSubview(searchField)

        navigationStack.orientation = .vertical
        navigationStack.alignment = .leading
        navigationStack.spacing = 3
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        let navigationScroll = NSScrollView()
        navigationScroll.translatesAutoresizingMaskIntoConstraints = false
        navigationScroll.drawsBackground = false
        navigationScroll.hasVerticalScroller = true
        navigationScroll.autohidesScrollers = true
        let navigationDocument = ControlCenterFlippedDocumentView()
        navigationDocument.translatesAutoresizingMaskIntoConstraints = false
        navigationScroll.documentView = navigationDocument
        sidebar.addSubview(navigationScroll)
        navigationDocument.addSubview(navigationStack)
        NSLayoutConstraint.activate([
            navigationScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            navigationScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            navigationScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            navigationScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),
            navigationDocument.widthAnchor.constraint(equalTo: navigationScroll.contentView.widthAnchor),
            navigationStack.topAnchor.constraint(equalTo: navigationDocument.topAnchor),
            navigationStack.bottomAnchor.constraint(equalTo: navigationDocument.bottomAnchor),
            navigationStack.leadingAnchor.constraint(equalTo: navigationDocument.leadingAnchor, constant: 10),
            navigationStack.trailingAnchor.constraint(equalTo: navigationDocument.trailingAnchor, constant: -10),
        ])

        addNavigation(.dashboard, symbol: "chart.bar.xaxis")
        addNavigation(.activity(), symbol: "square.grid.2x2")
        addNavigation(.history(), symbol: "clock.arrow.circlepath")

        addGroupHeader("Workflow")
        addNavigation(.transcription, symbol: "waveform")
        addNavigation(.ai, symbol: "sparkles")
        addNavigation(.interface, symbol: "menubar.rectangle")

        addGroupHeader("Privacy")
        addNavigation(.verifiedMessages, symbol: "checkmark.seal.fill")
        addNavigation(.permissions(), symbol: "hand.raised.fill")

        addGroupHeader("App")
        addNavigation(.general, symbol: "gearshape.fill")
        addNavigation(.about, symbol: "info.circle.fill")

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func buildDetail() {
        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false
        detailHost.addSubview(header)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        backButton.title = "Dashboard"
        backButton.image = NSImage(
            systemSymbolName: "chevron.backward",
            accessibilityDescription: "Back to Dashboard"
        )
        backButton.imagePosition = .imageLeading
        backButton.font = .systemFont(ofSize: 13, weight: .medium)
        backButton.bezelStyle = .accessoryBarAction
        backButton.isBordered = false
        backButton.target = self
        backButton.action = #selector(navigateBack(_:))
        backButton.keyEquivalent = "["
        backButton.keyEquivalentModifierMask = [.command]
        backButton.toolTip = "Back to Dashboard"
        backButton.isHidden = true
        backButton.setAccessibilityIdentifier("control-center-back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(backButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        detailHost.addSubview(contentHost)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: detailHost.topAnchor),
            header.leadingAnchor.constraint(equalTo: detailHost.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: detailHost.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 1),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 1),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            contentHost.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentHost.bottomAnchor.constraint(equalTo: detailHost.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: detailHost.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: detailHost.trailingAnchor),
        ])
    }

    private func addNavigation(_ destination: HushDestination, symbol: String, badge: String? = nil) {
        let row = SidebarRowView(title: destination.title, symbol: symbol, badge: badge)
        row.onClick = { [weak self] in self?.navigate(to: destination) }
        navigationRows[destination.identity] = row
        navigationStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: navigationStack.widthAnchor).isActive = true
    }

    private func addGroupHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            host.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -4),
        ])
        navigationStack.addArrangedSubview(host)
        host.widthAnchor.constraint(equalTo: navigationStack.widthAnchor).isActive = true
    }

    private func makeController(for destination: HushDestination) -> NSViewController {
        switch destination {
        case .dashboard:
            return DashboardViewController(
                coordinator: coordinator,
                previewMode: previewMode,
                initialRange: dashboardRange,
                onNavigate: { [weak self] in self?.navigate(to: $0) },
                onRangeChanged: { [weak self] in self?.dashboardRange = $0 }
            )
        case .timeSaved(let range):
            dashboardRange = range
            return TimeSavedInsightsViewController(
                initialRange: range,
                previewMode: previewMode,
                onRangeChanged: { [weak self] in self?.dashboardRange = $0 }
            )
        case .activity(let range):
            return ActivityBreakdownViewController(
                initialRange: range,
                previewMode: previewMode
            )
        case .history:
            return HistoryViewController(previewMode: previewMode)
        case .general:
            return GeneralSettingsPageViewController(coordinator: coordinator)
        case .transcription:
            return TranscriptionSettingsPageViewController(
                coordinator: coordinator,
                onOpenEngine: { [weak self] in self?.navigate(to: .transcriptionEngine($0)) }
            )
        case .transcriptionEngine(let engine):
            return TranscriptionEngineModelsViewController(engine: engine, coordinator: coordinator)
        case .personas(let focusEnableAI):
            return PersonaSettingsPageViewController(focusEnableAI: focusEnableAI)
        case .ai:
            return HushAIPageViewController(coordinator: coordinator, onNavigate: { [weak self] in self?.navigate(to: $0) })
        case .assistant:
            return AssistantSettingsPageViewController(coordinator: coordinator, onNavigate: { [weak self] in self?.navigate(to: $0) })
        case .interface:
            return InterfaceSettingsPageViewController()
        case .verifiedMessages:
            return VerifiedMessagesSettingsPageViewController(coordinator: coordinator)
        case .permissions(let focusFirstMissing):
            return PermissionsSettingsPageViewController(focusFirstMissing: focusFirstMissing)
        case .about:
            return AboutSettingsPageViewController()
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for row in navigationRows.values {
            row.isHidden = !query.isEmpty && !row.searchText.contains(query)
        }
    }

    @objc private func navigateBack(_ sender: Any?) {
        navigate(to: destination.parent ?? .dashboard)
    }
}

@MainActor
private final class SidebarRowView: NSView {
    let searchText: String
    var onClick: (() -> Void)?
    var isSelected = false { didSet { updateBackground() } }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground() } }

    init(title: String, symbol: String, badge: String? = nil) {
        searchText = (title + " " + (badge ?? "") + (title == "Hush AI" ? " personas assistant beta screen recording models voice" : "")).lowercased()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        badgeLabel.stringValue = badge ?? ""
        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelected {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
                titleLabel.textColor = .white
                badgeLabel.textColor = .white
                iconView.contentTintColor = .white
            } else {
                layer?.backgroundColor = isHovered
                    ? NSColor.labelColor.withAlphaComponent(0.07).cgColor
                    : NSColor.clear.cgColor
                titleLabel.textColor = .labelColor
                badgeLabel.textColor = .secondaryLabelColor
                iconView.contentTintColor = .labelColor
            }
        }
    }
}

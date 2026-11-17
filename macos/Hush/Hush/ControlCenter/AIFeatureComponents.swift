import AppKit

/// A feature's icon the way System Settings shows one: a white symbol on a rounded,
/// tinted square, so Live Write and Assistant read as two products at a glance.
@MainActor
final class AIFeatureIcon: NSView {
    private let gradient = CAGradientLayer()
    private let image = NSImageView()

    init(symbol: String, colors: [NSColor], size: CGFloat = 40) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size * 0.24
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: size * 0.46, weight: .semibold)
        image.contentTintColor = .white
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    static let liveWrite = [DesignTokens.brand300, DesignTokens.brand500]
    static let assistant = [DesignTokens.auroraBlue, DesignTokens.info]
}

/// One AI feature: what it does, whether it is on, where it stands, and the one thing to
/// do next. The switch is the feature; status and action never hide behind a page.
@MainActor
final class AIFeatureSwitchCard: ControlCenterCardView {
    enum Tone { case ready, neutral, attention }

    var onToggle: ((Bool) -> Void)?
    var onAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?
    /// Set to show a chevron and make the card open the feature's page.
    var onOpen: (() -> Void)? { didSet { chevron.isHidden = onOpen == nil } }

    let toggle = NSSwitch()
    private let statusDot = NSView()
    private let status = NSTextField(labelWithString: "")
    private let action = NSButton(title: "", target: nil, action: nil)
    private let secondary = NSButton(title: "", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let chevron = NSButton()

    init(title: String, description: String, symbol: String, colors: [NSColor], badge: String? = nil, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        let titleRow = NSStackView(views: [heading])
        titleRow.spacing = 8
        if let badge {
            let tag = NSTextField(labelWithString: badge)
            tag.font = .systemFont(ofSize: 10.5, weight: .semibold)
            tag.textColor = .secondaryLabelColor
            titleRow.addArrangedSubview(tag)
        }
        let detail = NSTextField(wrappingLabelWithString: description)
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.setAccessibilityIdentifier("\(identifier).status")
        let statusRow = NSStackView(views: [statusDot, status])
        statusRow.spacing = 6
        statusRow.alignment = .centerY

        let labels = NSStackView(views: [titleRow, detail, statusRow])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        labels.setCustomSpacing(8, after: detail)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(title)
        toggle.setAccessibilityIdentifier("\(identifier).enabled")

        chevron.isBordered = false
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Open \(title)")
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.target = self
        chevron.action = #selector(opened)
        chevron.setAccessibilityIdentifier("\(identifier).open")
        chevron.isHidden = true

        let controls = NSStackView(views: [toggle, chevron])
        controls.alignment = .centerY
        controls.spacing = 10
        let top = NSStackView(views: [AIFeatureIcon(symbol: symbol, colors: colors), labels, NSView(), controls])
        top.alignment = .top
        top.spacing = 14

        action.bezelStyle = .rounded
        action.controlSize = .regular
        action.target = self
        action.action = #selector(acted)
        action.setAccessibilityIdentifier("\(identifier).action")
        secondary.bezelStyle = .rounded
        secondary.target = self
        secondary.action = #selector(secondaryActed)
        secondary.setAccessibilityIdentifier("\(identifier).secondary-action")
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let footer = NSStackView(views: [action, secondary, progress])
        footer.spacing = 12
        footer.alignment = .centerY

        let content = NSStackView(views: [top, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalTo: content.widthAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 54),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
        update(isOn: false, status: "", tone: .neutral)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `action` names the one next step, if any; `progress` shows a running download.
    func update(isOn: Bool, status text: String, tone: Tone, action title: String? = nil, secondary secondaryTitle: String? = nil, progress value: Double? = nil, toggleEnabled: Bool = true) {
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = toggleEnabled
        status.stringValue = text
        let color: NSColor = switch tone {
        case .ready: DesignTokens.goodInk
        case .attention: .systemOrange
        case .neutral: .secondaryLabelColor
        }
        status.textColor = tone == .neutral ? .secondaryLabelColor : color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            statusDot.layer?.backgroundColor = (tone == .neutral ? NSColor.tertiaryLabelColor : color).cgColor
        }
        action.title = title ?? ""
        action.isHidden = title == nil
        secondary.title = secondaryTitle ?? ""
        secondary.isHidden = secondaryTitle == nil
        progress.isHidden = value == nil
        progress.doubleValue = value ?? 0
        action.superview?.isHidden = title == nil && value == nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let onOpen, event.clickCount == 1 else { return super.mouseUp(with: event) }
        onOpen()
    }

    @objc private func toggled() { onToggle?(toggle.state == .on) }
    @objc private func acted() { onAction?() }
    @objc private func secondaryActed() { onSecondaryAction?() }
    @objc private func opened() { onOpen?() }
}

/// The page title of an AI feature: large name, one line of value, no decoration.
@MainActor
func aiPageHeader(title: String, detail: String) -> AIPageHeader { AIPageHeader(title: title, detail: detail) }

/// A page title with a one-line description that can change with the page's state.
@MainActor
final class AIPageHeader: NSStackView {
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    var detail: String {
        get { detailLabel.stringValue }
        set { detailLabel.stringValue = newValue }
    }

    init(title: String, detail: String) {
        super.init(frame: .zero)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 26, weight: .bold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.stringValue = detail
        addArrangedSubview(heading)
        addArrangedSubview(detailLabel)
        orientation = .vertical
        alignment = .leading
        spacing = 4
    }
    required init?(coder: NSCoder) { fatalError() }
}

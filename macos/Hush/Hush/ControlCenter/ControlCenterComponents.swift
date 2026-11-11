import AppKit

@MainActor
enum ControlCenterStyle {
    static let sidebarWidth: CGFloat = 236
    static let contentMaxWidth: CGFloat = 820
    static let pageInset: CGFloat = 30
    static let cardRadius: CGFloat = 16

    static var contentBackground: NSColor { .windowBackgroundColor }
    static var cardBackground: NSColor { .labelColor.withAlphaComponent(0.045) }
    static var cardBorder: NSColor { .labelColor.withAlphaComponent(0.075) }
    static var softFill: NSColor { .labelColor.withAlphaComponent(0.055) }
    static var separator: NSColor { .labelColor.withAlphaComponent(0.085) }
}

@MainActor
class ControlCenterCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ControlCenterStyle.cardRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = ControlCenterStyle.cardBackground.cgColor
            layer?.borderColor = ControlCenterStyle.cardBorder.cgColor
        }
    }
}

@MainActor
final class ControlCenterMetricCard: ControlCenterCardView {
    private let valueLabel = NSTextField(labelWithString: "0")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.maximumNumberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [valueLabel, titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 106),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -13),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(value: String, detail: String = "") {
        valueLabel.stringValue = value
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
        setAccessibilityElement(true)
        setAccessibilityLabel("\(titleLabel.stringValue), \(value)\(detail.isEmpty ? "" : ", \(detail)")")
    }
}

@MainActor
class ControlCenterPageViewController: NSViewController {
    let stack = NSStackView()
    let scrollView = NSScrollView()
    let documentView = ControlCenterFlippedDocumentView()

    override func loadView() {
        let root = ControlCenterBackgroundView()
        view = root

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .allowed
        root.addSubview(scrollView)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(
            top: 28,
            left: ControlCenterStyle.pageInset,
            bottom: 32,
            right: ControlCenterStyle.pageInset
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let maxWidth = stack.widthAnchor.constraint(lessThanOrEqualToConstant: ControlCenterStyle.contentMaxWidth)
        maxWidth.priority = .required
        let flexibleWidth = stack.widthAnchor.constraint(equalTo: documentView.widthAnchor)
        flexibleWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            flexibleWidth,
            maxWidth,
        ])
    }

    func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    func subtitle(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        return label
    }

    func pageIntroduction(title: String, detail: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        heading.textColor = .labelColor

        let explanation = NSTextField(wrappingLabelWithString: detail)
        explanation.font = .systemFont(ofSize: 11.5)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 2

        let labels = NSStackView(views: [heading, explanation])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        return labels
    }

    func makeCard(content: NSView, insets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)) -> ControlCenterCardView {
        let card = ControlCenterCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
        ])
        return card
    }

    func addFullWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * ControlCenterStyle.pageInset).isActive = true
    }

}

@MainActor
final class ControlCenterFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class ControlCenterBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateColor()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }
    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = ControlCenterStyle.contentBackground.cgColor
        }
    }
}

@MainActor
final class ControlCenterKeyValueRow: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let trailingHost = NSView()
    private let separator = ControlCenterSeparatorView()

    init(title: String, subtitle: String? = nil, trailing: NSView, showsSeparator: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.isHidden = subtitle == nil

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        trailing.translatesAutoresizingMaskIntoConstraints = false
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(labels)
        addSubview(trailing)

        separator.isHidden = !showsSeparator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        labels.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 52 : 62),
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -18),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Updates the explanatory line under the title. Rows whose subtitle changes at
    /// runtime should be created with a subtitle so their minimum height fits it.
    var subtitle: String? {
        get { subtitleLabel.isHidden ? nil : subtitleLabel.stringValue }
        set {
            subtitleLabel.stringValue = newValue ?? ""
            subtitleLabel.isHidden = newValue == nil
        }
    }

    var subtitleColor: NSColor {
        get { subtitleLabel.textColor ?? .secondaryLabelColor }
        set { subtitleLabel.textColor = newValue }
    }
}

@MainActor
final class ControlCenterSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = ControlCenterStyle.separator.cgColor
        }
    }
}

extension TimeInterval {
    var hushCompactDuration: String {
        if self < 60 { return "\(Int(self.rounded())) sec" }
        if self < 3600 { return "\(Int((self / 60).rounded())) min" }
        let hours = self / 3600
        return hours < 10 ? String(format: "%.1f hr", hours) : "\(Int(hours.rounded())) hr"
    }
}

import AppKit
import QuartzCore

/// Card-style row for a single AI provider in the Post-processing section.
/// Visual recipe mirrors `ModelRowView` so the Post-processing section
/// feels like a continuation of the existing Transcription models section:
///
///   ●  Title                                       [Action] [⋯]
///      Subtitle / status text
///      ▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱  (only while downloading)
///
/// One instance per `LLMProvider`. The owner (SettingsViewController)
/// stacks three of these vertically and wires `onUse` / `onCancel` /
/// `onDelete` callbacks.
@MainActor
final class ProviderRowView: NSView {

    let provider: LLMProvider

    enum DisplayState {
        /// Not the active provider. Subtitle is the descriptive blurb.
        case inactive(subtitle: String)
        /// Currently active and ready. Subtitle reports readiness.
        case active(subtitle: String)
        /// Model isn't on disk yet — primary button reads "Download"
        /// regardless of whether this is the currently active provider.
        /// Mirrors the Transcription Models pattern from `ModelRowView`.
        case needsDownload(subtitle: String, isActive: Bool)
        /// Downloading or preparing locally. A nil fraction uses the native
        /// indeterminate state until byte progress is available.
        case downloading(subtitle: String, progress: Double?)
        /// Active but the provider can't run — e.g. Apple Intelligence on
        /// macOS < 26 or Apple Intelligence disabled in System Settings.
        case unavailable(reason: String)
        /// Model is on disk + ready in memory, currently active. Subtitle
        /// shows size. Delete button revealed.
        case readyWithDelete(subtitle: String)
    }

    var onUse: ((LLMProvider) -> Void)?
    var onCancel: ((LLMProvider) -> Void)?
    var onDelete: ((LLMProvider) -> Void)?

    private let dotLayer = CALayer()
    private let dotPulse = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton: BrandButton
    private let deleteButton = NSButton()
    private let progressBar = NSProgressIndicator()
    private let progressHost = NSView()

    init(provider: LLMProvider) {
        self.provider = provider
        self.primaryButton = BrandButton(title: "Use", variant: .secondary, size: .sm)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        layer?.backgroundColor = DesignTokens.card.cgColor
        layer?.cornerRadius = DesignTokens.radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DesignTokens.paperBorder.cgColor

        setupDot()
        setupLabels()
        setupButtons()
        setupProgress()
        setupLayout()

        titleLabel.stringValue = provider.displayName
        apply(.inactive(subtitle: provider.blurb))
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ state: DisplayState) {
        let wasIndeterminate = progressBar.isIndeterminate
        progressBar.stopAnimation(nil)
        progressBar.isIndeterminate = false

        switch state {
        case .inactive(let s):
            // "Use" follows the same vocabulary as ModelRowView: brand
            // brand accent to invite the click. Hierarchy is action-intent.
            setDot(color: DesignTokens.inkMute, pulse: false)
            subtitleLabel.stringValue = s
            subtitleLabel.textColor = DesignTokens.inkDim
            primaryButton.title = "Use"
            primaryButton.setVariant(.brand, animated: false)
            primaryButton.isEnabled = true
            deleteButton.isHidden = true
            progressHost.isHidden = true
            applyBorder(active: false, danger: false)
        case .active(let s):
            setDot(color: DesignTokens.brand500, pulse: false)
            subtitleLabel.stringValue = s
            subtitleLabel.textColor = DesignTokens.goodInk
            primaryButton.title = "Active"
            primaryButton.setVariant(.success, animated: false)
            primaryButton.isEnabled = false
            deleteButton.isHidden = true
            progressHost.isHidden = true
            applyBorder(active: true, danger: false)
        case .needsDownload(let s, let isActive):
            // Mirrors ModelRowView's `.notDownloaded` row exactly: muted
            // dot, .secondary "Download" button. Brand border only when
            // this is the currently active provider — otherwise the card
            // sits at rest just like any other inactive option.
            setDot(color: DesignTokens.inkMute, pulse: false)
            subtitleLabel.stringValue = s
            subtitleLabel.textColor = DesignTokens.inkDim
            primaryButton.title = "Download"
            primaryButton.setVariant(.secondary, animated: false)
            primaryButton.isEnabled = true
            deleteButton.isHidden = true
            progressHost.isHidden = true
            applyBorder(active: isActive, danger: false)
        case .downloading(let s, let progress):
            setDot(color: DesignTokens.brand500, pulse: true)
            subtitleLabel.stringValue = s
            subtitleLabel.textColor = DesignTokens.ink
            primaryButton.title = "Cancel"
            primaryButton.setVariant(.ghost, animated: false)
            primaryButton.isEnabled = true
            deleteButton.isHidden = true
            progressHost.isHidden = false
            if let progress {
                let value = max(0, min(1, progress))
                if wasIndeterminate {
                    progressBar.doubleValue = value
                } else {
                    progressBar.animator().doubleValue = value
                }
            } else {
                progressBar.doubleValue = 0
                progressBar.isIndeterminate = true
                progressBar.startAnimation(nil)
            }
            applyBorder(active: true, danger: false)
        case .unavailable(let r):
            setDot(color: DesignTokens.danger, pulse: false)
            subtitleLabel.stringValue = r
            subtitleLabel.textColor = DesignTokens.danger
            primaryButton.title = "Use"
            primaryButton.setVariant(.secondary, animated: false)
            primaryButton.isEnabled = false
            deleteButton.isHidden = true
            progressHost.isHidden = true
            applyBorder(active: true, danger: true)
        case .readyWithDelete(let s):
            setDot(color: DesignTokens.brand500, pulse: false)
            subtitleLabel.stringValue = s
            subtitleLabel.textColor = DesignTokens.goodInk
            primaryButton.title = "Active"
            primaryButton.setVariant(.success, animated: false)
            primaryButton.isEnabled = false
            deleteButton.isHidden = false
            progressHost.isHidden = true
            applyBorder(active: true, danger: false)
        }
    }

    // MARK: - Setup

    private func setupDot() {
        dotPulse.cornerRadius = 8
        dotPulse.backgroundColor = DesignTokens.brand500.cgColor
        dotPulse.opacity = 0
        dotLayer.cornerRadius = 4
        layer?.addSublayer(dotPulse)
        layer?.addSublayer(dotLayer)
    }

    private func setupLabels() {
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = DesignTokens.ink
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.usesSingleLineMode = true
        // Low hugging priority + low compression resistance = the label
        // grows to fill the available width and truncates only when
        // there's truly no room. Pushes the action button hard against
        // the trailing edge of the card, matching ModelRowView.
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = DesignTokens.inkDim
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.cell?.usesSingleLineMode = false
        subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func setupButtons() {
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped(_:))

        deleteButton.bezelStyle = .regularSquare
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash",
                                      accessibilityDescription: "Delete model")
        deleteButton.contentTintColor = DesignTokens.inkMute
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        deleteButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        deleteButton.toolTip = "Delete from disk"
        deleteButton.isHidden = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped(_:))
    }

    private func setupProgress() {
        progressHost.translatesAutoresizingMaskIntoConstraints = false
        progressHost.heightAnchor.constraint(equalToConstant: 6).isActive = true
        progressHost.isHidden = true

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.usesThreadedAnimation = true
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressHost.addSubview(progressBar)
        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: progressHost.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: progressHost.trailingAnchor),
            progressBar.centerYAnchor.constraint(equalTo: progressHost.centerYAnchor)
        ])
    }

    private func setupLayout() {
        let dotHost = NSView()
        dotHost.translatesAutoresizingMaskIntoConstraints = false
        dotHost.widthAnchor.constraint(equalToConstant: 18).isActive = true
        dotHost.heightAnchor.constraint(equalToConstant: 18).isActive = true
        dotPulse.frame = NSRect(x: 1, y: 1, width: 16, height: 16)
        dotLayer.frame = NSRect(x: 5, y: 5, width: 8, height: 8)
        dotHost.wantsLayer = true
        dotHost.layer?.addSublayer(dotPulse)
        dotHost.layer?.addSublayer(dotLayer)

        let textCol = NSStackView(views: [titleLabel, subtitleLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 3
        textCol.distribution = .fill
        textCol.translatesAutoresizingMaskIntoConstraints = false
        // Mirror ModelRowView: textCol expands horizontally so the
        // action button gets pushed to the card's right edge.
        textCol.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actions = NSStackView(views: [primaryButton, deleteButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        actions.distribution = .fill
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.setContentHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(dotHost)
        addSubview(textCol)
        addSubview(actions)
        addSubview(progressHost)

        NSLayoutConstraint.activate([
            dotHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dotHost.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            textCol.leadingAnchor.constraint(equalTo: dotHost.trailingAnchor, constant: 10),
            textCol.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textCol.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -12),
            textCol.bottomAnchor.constraint(lessThanOrEqualTo: progressHost.topAnchor, constant: -8),

            // Pin to the card's centerY (not textCol's) — matches the
            // exact vertical placement ModelRowView uses for its right-
            // side buttons.
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressHost.leadingAnchor.constraint(equalTo: textCol.leadingAnchor),
            progressHost.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
            progressHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    // MARK: - State helpers

    private func setDot(color: NSColor, pulse: Bool) {
        dotLayer.backgroundColor = color.cgColor
        let key = "providerRow.dot.pulse"
        dotPulse.removeAnimation(forKey: key)
        if pulse {
            dotPulse.backgroundColor = color.withAlphaComponent(0.55).cgColor
            dotPulse.opacity = 1
            let group = CAAnimationGroup()
            group.duration = 1.4
            group.repeatCount = .greatestFiniteMagnitude
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.6
            scale.toValue = 1.4
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.55, 0.0]
            opacity.keyTimes = [0.0, 1.0]
            group.animations = [scale, opacity]
            dotPulse.add(group, forKey: key)
        } else {
            dotPulse.opacity = 0
        }
    }

    private func applyBorder(active: Bool, danger: Bool) {
        let color: NSColor
        let width: CGFloat
        switch (active, danger) {
        case (_, true):    color = DesignTokens.danger;       width = 1.5
        case (true, _):    color = DesignTokens.brand500;     width = 1.5
        case (false, _):   color = DesignTokens.paperBorder;  width = 1
        }
        layer?.borderColor = color.cgColor
        layer?.borderWidth = width
    }

    @objc private func primaryTapped(_ sender: Any?) {
        // Primary button does double duty: starts a download when in
        // `.needsDownload`, cancels when in `.downloading`, otherwise
        // selects this provider as active.
        if primaryButton.title == "Cancel" {
            onCancel?(provider)
        } else {
            onUse?(provider)
        }
    }

    @objc private func deleteTapped(_ sender: Any?) {
        onDelete?(provider)
    }
}

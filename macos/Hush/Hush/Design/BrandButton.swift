import AppKit

/// Brand-styled push button. Variants per handoff §10 + §8 onboarding CTAs:
///   - .brand     - cool aurora gradient, white text, brand glow shadow
///   - .secondary — surface-lighter, border, default text
///   - .ghost     — transparent, dimmed text
///   - .success   — green tint, "done" terminal state (used as disabled+done badge)
final class BrandButton: NSButton {

    enum Variant { case brand, secondary, ghost, success }
    enum Size { case sm, md }

    private(set) var variant: Variant
    private let sizeVariant: Size
    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CALayer()
    /// Pill radius — matches the landing page's `rounded-full` buttons.
    private let pill: CGFloat

    init(title: String, variant: Variant = .brand, size: Size = .md) {
        self.variant = variant
        self.sizeVariant = size
        let h: CGFloat = size == .sm ? 30 : 40
        self.pill = h / 2
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.translatesAutoresizingMaskIntoConstraints = false

        layer?.masksToBounds = false
        layer?.cornerRadius = pill
        layer?.cornerCurve = .continuous

        glowLayer.cornerRadius = pill
        glowLayer.cornerCurve = .continuous
        layer?.addSublayer(glowLayer)

        gradientLayer.cornerRadius = pill
        gradientLayer.cornerCurve = .continuous
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint   = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradientLayer)

        heightAnchor.constraint(equalToConstant: h).isActive = true

        applyVariant()
        configureTitleStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Switches the visual variant and re-applies the title styling. Animates the brand
    /// glow when transitioning into `.brand` (handoff §8 footer Done button activation).
    func setVariant(_ new: Variant, animated: Bool = true) {
        guard new != variant else { return }
        variant = new
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = DesignTokens.durBase
                ctx.timingFunction = DesignTokens.easeOut
                applyVariant()
            }
        } else {
            applyVariant()
        }
        configureTitleStyle()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        glowLayer.frame = bounds
        glowLayer.shadowPath = CGPath(roundedRect: bounds,
                                      cornerWidth: pill,
                                      cornerHeight: pill,
                                      transform: nil)
    }

    override func mouseDown(with event: NSEvent) {
        animateScale(0.98)
        super.mouseDown(with: event)
        animateScale(1.0)
    }

    private func animateScale(_ s: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DesignTokens.durFast
            ctx.timingFunction = DesignTokens.easeOut
            layer?.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        }
    }

    private func applyVariant() {
        switch variant {
        case .brand:
            // Cool aurora CTA, used for focused primary actions.
            gradientLayer.colors = DesignTokens.brandGradientColors()
            gradientLayer.isHidden = false
            layer?.borderWidth = 0
            layer?.backgroundColor = NSColor.clear.cgColor
            glowLayer.shadowColor = DesignTokens.brand500.cgColor
            glowLayer.shadowOpacity = 0.35
            glowLayer.shadowOffset = CGSize(width: 0, height: 4)
            glowLayer.shadowRadius = 16

        case .secondary:
            // Ink pill on paper — the landing page's primary button
            // (`bg-ink text-white shadow-lg`).
            gradientLayer.isHidden = true
            layer?.backgroundColor = DesignTokens.ink.cgColor
            layer?.borderWidth = 0
            glowLayer.shadowColor = NSColor.black.cgColor
            glowLayer.shadowOpacity = 0.14
            glowLayer.shadowOffset = CGSize(width: 0, height: 3)
            glowLayer.shadowRadius = 10

        case .ghost:
            // Subtle outline-only on paper.
            gradientLayer.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = DesignTokens.paperBorder.cgColor
            glowLayer.shadowOpacity = 0

        case .success:
            // Soft green pill — terminal "step done" badge.
            gradientLayer.isHidden = true
            layer?.backgroundColor = DesignTokens.good.withAlphaComponent(0.14).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = DesignTokens.good.withAlphaComponent(0.4).cgColor
            glowLayer.shadowOpacity = 0
        }
    }

    private func configureTitleStyle() {
        let color: NSColor
        switch variant {
        case .brand:     color = .white
        case .secondary: color = DesignTokens.text          // paper-cream on ink
        case .ghost:     color = DesignTokens.inkDim        // dim ink on paper
        case .success:   color = DesignTokens.goodInk       // dark green for legibility
        }
        let font = NSFont.systemFont(ofSize: sizeVariant == .sm ? 12 : 13, weight: .semibold)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: para
            ]
        )

        let pad: CGFloat = sizeVariant == .sm ? 30 : 46
        let textWidth = attributedTitle.size().width
        let w = textWidth + pad
        // Set as a soft minimum width so footer "Done" can take its natural size.
        for c in constraints where c.firstAttribute == .width && c.relation == .greaterThanOrEqual {
            removeConstraint(c)
        }
        widthAnchor.constraint(greaterThanOrEqualToConstant: w).isActive = true
    }

    override var title: String {
        didSet {
            configureTitleStyle()
            setAccessibilityLabel(title)
        }
    }

    /// Convenience for the "disabled = visually success/check" terminal state in onboarding.
    func setDoneState(label: String) {
        setVariant(.success, animated: true)
        title = label
        isEnabled = false
    }

    /// Apply our own disabled appearance instead of AppKit's default
    /// title tinting. AppKit dims the attributed-title text by reducing
    /// its opacity, which on a dark layer background (`.secondary` →
    /// `DesignTokens.ink`) renders as effectively black-on-black and is
    /// unreadable. Tinting the whole button (`alphaValue`) instead keeps
    /// the foreground/background contrast intact while still signalling
    /// "not active yet" to the user.
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = DesignTokens.durFast
                ctx.allowsImplicitAnimation = true
                self.alphaValue = isEnabled ? 1.0 : 0.45
            }
        }
    }
}

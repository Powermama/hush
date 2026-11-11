import AppKit
import QuartzCore

/// Brand-tinted iOS-style switch. Built from `CALayer`s rather than
/// `NSSwitch` because Apple doesn't expose a per-instance tint on
/// `NSSwitch` — its "on" colour is locked to the system accent (System
/// Settings → Appearance). Building a thin control gets us the brand
/// accent color we want everywhere else in the design system without forcing
/// users to change their Mac-wide accent colour.
///
/// API mirrors `NSSwitch`:
///   - `state: NSControl.StateValue`  (.on / .off)
///   - target / action fire on every toggle
///   - clickable + keyboard-accessible (Space toggles when focused)
///
/// Visual matches macOS standard switch dimensions (38 × 22, the size
/// AppKit uses inside Form / NSGridView layouts) so it slots into the
/// existing row idiom without re-spacing.
@MainActor
final class BrandSwitch: NSControl {

    // MARK: - Dimensions

    private static let trackWidth: CGFloat = 38
    private static let trackHeight: CGFloat = 22
    private static let thumbInset: CGFloat = 2

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.trackWidth, height: Self.trackHeight)
    }

    // MARK: - Layers

    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()

    // MARK: - State
    //
    // NSControl.state can't be overridden in pure Swift (it's a stored
    // property on the Obj-C side). We expose a Bool `isOn` instead —
    // matches SwiftUI Toggle vocabulary and avoids the override-rejection
    // trap. Call sites use `enableSwitch.isOn = ...` to read/write.

    var isOn: Bool = false {
        didSet { updateAppearance(animated: true) }
    }

    // Accessibility / keyboard focus
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    // MARK: - Init

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.trackWidth, height: Self.trackHeight))
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        trackLayer.frame = bounds
        trackLayer.cornerRadius = Self.trackHeight / 2
        trackLayer.cornerCurve = .continuous
        layer?.addSublayer(trackLayer)

        let thumbDiameter = Self.trackHeight - Self.thumbInset * 2
        thumbLayer.frame = NSRect(x: Self.thumbInset, y: Self.thumbInset,
                                   width: thumbDiameter, height: thumbDiameter)
        thumbLayer.cornerRadius = thumbDiameter / 2
        thumbLayer.cornerCurve = .continuous
        thumbLayer.backgroundColor = NSColor.white.cgColor
        // Subtle drop shadow so the thumb feels lifted off the track.
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.18
        thumbLayer.shadowOffset = NSSize(width: 0, height: -1)
        thumbLayer.shadowRadius = 1.5
        layer?.addSublayer(thumbLayer)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.trackWidth).isActive = true
        heightAnchor.constraint(equalToConstant: Self.trackHeight).isActive = true

        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Appearance

    private func updateAppearance(animated: Bool) {
        let onTrack  = DesignTokens.brand500.cgColor
        // Soft neutral for "off" — sits in the cream/ink palette so the
        // switch doesn't look broken next to disabled controls.
        let offTrack = DesignTokens.inkMute.withAlphaComponent(0.4).cgColor
        let targetTrack = isOn ? onTrack : offTrack

        let thumbDiameter = Self.trackHeight - Self.thumbInset * 2
        let thumbX: CGFloat = isOn
            ? Self.trackWidth - thumbDiameter - Self.thumbInset
            : Self.thumbInset
        let targetThumbFrame = NSRect(x: thumbX, y: Self.thumbInset,
                                       width: thumbDiameter, height: thumbDiameter)

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(DesignTokens.easeOut)
            trackLayer.backgroundColor = targetTrack
            thumbLayer.frame = targetThumbFrame
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trackLayer.backgroundColor = targetTrack
            thumbLayer.frame = targetThumbFrame
            CATransaction.commit()
        }
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        // Recompute thumb position whenever the control's frame changes
        // (rare — we have a fixed intrinsicContentSize — but cheap).
        updateAppearance(animated: false)
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        // Space toggles when the control has keyboard focus — matches
        // standard NSSwitch keyboard behaviour.
        if event.charactersIgnoringModifiers == " " {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    private func toggle() {
        isOn.toggle()
        sendAction(action, to: target)
    }

    // MARK: - Disabled state visuals

    override var isEnabled: Bool {
        didSet {
            layer?.opacity = isEnabled ? 1.0 : 0.5
        }
    }
}

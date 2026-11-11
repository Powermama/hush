import AppKit
import SwiftUI

/// Hosts the HUD foreground inside Apple's native material hierarchy.
///
/// The material owns the foreground through `contentView`, as required by
/// AppKit. There is no custom blur, tint, backdrop capture, or glass drawing.
@MainActor
final class HUDNativeMaterialView: NSView {
    static let cornerRadius: CGFloat = 18

    private let hostingView: NSHostingView<HushHUDRoot>

    init(model: HUDModel) {
        hostingView = NSHostingView(rootView: HushHUDRoot(model: model))
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityIdentifier("hush.nativeGlassSurface")

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = hostingView
            install(materialView: glass)
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = Self.cornerRadius
            material.layer?.cornerCurve = .continuous
            material.layer?.masksToBounds = true
            material.addSubview(hostingView)
            install(materialView: material)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func install(materialView: NSView) {
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        addSubview(materialView)
    }
}

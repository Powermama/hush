import AppKit
import SwiftUI
import Testing
@testable import Hush

@Suite("Native HUD material", .serialized)
@MainActor
struct HUDNativeMaterialViewTests {
    @Test("The HUD uses the native dynamic material for the current macOS version")
    func nativeMaterialOwnsForeground() throws {
        let materialHost = HUDNativeMaterialView(model: HUDModel())
        materialHost.frame = NSRect(x: 0, y: 0, width: 380, height: 72)
        materialHost.layoutSubtreeIfNeeded()

        #expect(materialHost.subviews.count == 1)

        if #available(macOS 26.0, *) {
            let glass = try #require(materialHost.subviews.first as? NSGlassEffectView)
            #expect(glass.style == .regular)
            #expect(glass.cornerRadius == 18)
            #expect(glass.tintColor == nil)
            #expect(glass.contentView is NSHostingView<HushHUDRoot>)
        } else {
            let material = try #require(materialHost.subviews.first as? NSVisualEffectView)
            #expect(material.material == .hudWindow)
            #expect(material.blendingMode == .behindWindow)
            #expect(material.state == .active)
            #expect(material.subviews.contains { $0 is NSHostingView<HushHUDRoot> })
        }
    }
}

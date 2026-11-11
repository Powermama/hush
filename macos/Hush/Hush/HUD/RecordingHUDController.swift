import AppKit
import OSLog
import SwiftUI

/// Owns the floating dictation pill. Positioning, lifetime, and entrance/exit
/// animation live here; the SwiftUI foreground is embedded in Apple's native
/// AppKit material and driven through `HUDModel`. Public API is unchanged from
/// the old AppKit view so the coordinator + menu don't care how it's drawn.
@MainActor
final class RecordingHUDController {
    private static let log = Logger(
        subsystem: "com.decentralfreedom.hush",
        category: "HUD"
    )

    /// App-facing HUD states. Mapped onto the HUD's visual states in `show`.
    enum State {
        case recording
        case transcribing
        case polishing(profileName: String, providerName: String)
        case signing
        case inserted(words: Int, app: String?, verified: Bool)
        case copiedToClipboard(verified: Bool)
        case needsAccessibility
        case error(String)
    }

    /// The visible pill is 380×72; the panel is inset larger so the SwiftUI
    /// drop-shadows have room to render without being clipped.
    private static let pillSize = NSSize(width: 380, height: 72)
    private static let inset: CGFloat = 60
    private static let panelSize = NSSize(width: pillSize.width + inset * 2,
                                          height: pillSize.height + inset * 2)

    private let model = HUDModel()
    private var window: HUDPanel?
    private var hideTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var recordingStartedAt: Date?
    private var visibilityGeneration: UInt = 0
    private var wantsVisible = false
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    deinit {
        elapsedTimer?.invalidate()
        hideTask?.cancel()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// Set by `AppDelegate` after the status item is installed; anchors the HUD
    /// under the menu-bar icon in "top" position mode.
    var statusItemFrameProvider: (() -> NSRect?)?

    func show(state: State) {
        ensureWindow()
        wantsVisible = true
        visibilityGeneration &+= 1

        // Starting a recording: if a previous notice/error is still on screen,
        // drop it instantly (off-screen) so it can't cross-fade under "Listening".
        if case .recording = state, window?.isVisible == true {
            hideTask?.cancel()
            window?.orderOut(nil)
        }

        place()

        switch state {
        case .recording:
            model.seconds = 0
            model.resetLevels()
            model.message = ""
            model.isError = false
            model.session &+= 1          // fresh HUD identity → no cross-fade from a stale notice
            model.state = .listening
            startElapsedTimer()
        case .transcribing:
            model.isVerified = false
            model.state = .processing
            stopElapsedTimer()
        case .polishing:
            model.isVerified = false
            model.state = .processing
            stopElapsedTimer()
        case .signing:
            model.isVerified = false
            model.state = .signing
            stopElapsedTimer()
        case .inserted(let words, let app, let verified):
            model.wordCount = words
            model.targetApp = app ?? "your app"
            model.isVerified = verified
            model.state = .inserted
            stopElapsedTimer()
        case .copiedToClipboard(let verified):
            model.isError = false
            model.message = verified
                ? "Verified text copied - press ⌘V to paste"
                : "Copied - press ⌘V to paste"
            model.state = .notice
            stopElapsedTimer()
        case .needsAccessibility:
            model.isError = true
            model.message = "Enable Accessibility to auto-paste"
            model.state = .notice
            stopElapsedTimer()
        case .error(let msg):
            model.isError = true
            model.message = msg
            model.state = .notice
            stopElapsedTimer()
        }

        hideTask?.cancel()
        if window?.isVisible == true {
            window?.orderFrontRegardless()
        } else {
            animateIn()
        }
        Self.log.debug("Showing HUD state \(state.logName, privacy: .public) on screen \(self.window?.screen?.localizedName ?? "unknown", privacy: .public)")
    }

    func update(level: Float) {
        model.pushLevel(CGFloat(level))
    }

    func hide(animated: Bool = true) {
        wantsVisible = false
        hideTask?.cancel()
        hideTask = nil
        stopElapsedTimer()
        guard let window, window.isVisible else { return }
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        if animated {
            let controller = self
            let hudWindow = window
            animateOut {
                Task { @MainActor in
                    guard controller.visibilityGeneration == generation else { return }
                    hudWindow.orderOut(nil)
                }
            }
        } else {
            window.orderOut(nil)
        }
    }

    func hideAfter(seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.hide() }
        }
    }

    /// Transient neutral message (e.g. "Loading model…").
    func flash(message: String) {
        ensureWindow()
        wantsVisible = true
        visibilityGeneration &+= 1
        place()
        model.isError = false
        model.message = message
        model.state = .notice
        stopElapsedTimer()
        if window?.isVisible == true {
            window?.orderFrontRegardless()
        } else {
            animateIn()
        }
        hideAfter(seconds: 1.4)
    }

    // MARK: - Window plumbing

    private func ensureWindow() {
        guard window == nil else { return }
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // A dictation HUD is a short-lived, noninteractive overlay. popUpMenu keeps it
        // above app windows and modal panels while remaining below system alerts.
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let material = HUDNativeMaterialView(model: model)
        material.frame = NSRect(
            x: Self.inset,
            y: Self.inset,
            width: Self.pillSize.width,
            height: Self.pillSize.height
        )
        if let content = panel.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            content.addSubview(material)
        }
        self.window = panel
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisiblePlacement() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshVisiblePlacement() }
        }
    }

    private func refreshVisiblePlacement() {
        // Visibility is session intent, not WindowServer's transient state during
        // a Space transition. A notification must never resurrect a dismissed HUD.
        guard wantsVisible, let window else { return }
        place()
        window.orderFrontRegardless()
    }

    /// Positions the panel so the *pill* (centred inside the inset panel) lands
    /// at the intended spot.
    private func place() {
        guard let window, let screen = targetScreen() else { return }
        let visible = screen.visibleFrame
        let pill = Self.pillSize
        let inset = Self.inset

        switch Settings.shared.hudPosition {
        case .bottom:
            let pillOriginX = visible.midX - pill.width / 2
            let pillOriginY = visible.minY + 40
            window.setFrameOrigin(NSPoint(x: pillOriginX - inset, y: pillOriginY - inset))
        case .top:
            let statusFrame = statusItemFrameProvider?()
            let centerX = statusFrame.flatMap { screen.frame.contains(NSPoint(x: $0.midX, y: $0.midY)) ? $0.midX : nil } ?? visible.midX
            var pillX = centerX - pill.width / 2
            pillX = max(visible.minX + 8, min(visible.maxX - pill.width - 8, pillX))
            let pillTopY = visible.maxY - 8 - pill.height
            window.setFrameOrigin(NSPoint(x: pillX - inset, y: pillTopY - inset))
        }
    }

    private func targetScreen() -> NSScreen? {
        // The menu bar can retain a frame on another display. Both placements
        // follow the user's current display; the icon is only an anchor there.
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func animateIn() {
        guard let window else { return }
        window.alphaValue = 0
        let target = window.frame
        var start = target
        start.origin.y -= 20
        window.setFrame(start, display: false)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DesignTokens.durBase
            ctx.timingFunction = DesignTokens.easeOut
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
            window.animator().setFrame(target, display: true)
        }
    }

    private func animateOut(_ completion: @escaping @Sendable () -> Void) {
        guard let window else { completion(); return }
        let start = window.frame
        var end = start
        end.origin.y += 8
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = DesignTokens.easeIn
            window.animator().alphaValue = 0
            window.animator().setFrame(end, display: true)
        }, completionHandler: completion)
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        recordingStartedAt = Date()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let started = self.recordingStartedAt else { return }
                self.model.seconds = Int(Date().timeIntervalSince(started))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartedAt = nil
    }
}

private extension RecordingHUDController.State {
    var logName: String {
        switch self {
        case .recording: "recording"
        case .transcribing: "transcribing"
        case .polishing: "polishing"
        case .signing: "signing"
        case .inserted: "inserted"
        case .copiedToClipboard: "copiedToClipboard"
        case .needsAccessibility: "needsAccessibility"
        case .error: "error"
        }
    }
}

@MainActor
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

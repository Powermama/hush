#if DEBUG
import AppKit

/// End-to-end visual journey for native cross-window material sampling.
/// Launch the Debug app with `--preview-native-hud-glass`.
@MainActor
final class HUDGlassDebugJourneyController {
    private let hud = RecordingHUDController()
    private let window: NSWindow
    private var statusTimer: Timer?
    private let spacesJourney = ProcessInfo.processInfo.arguments.contains("--hud-spaces")
    private let movingBackground = HUDMovingBackgroundView()

    init() {
        let screenFrame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window = NSWindow(
            contentRect: screenFrame,
            styleMask: spacesJourney ? [.titled, .closable, .resizable] : [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.isOpaque = true
        window.level = .normal
        window.collectionBehavior = spacesJourney ? [.fullScreenPrimary] : [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = movingBackground
        if spacesJourney {
            let button = NSButton(title: "Toggle full screen", target: window, action: #selector(NSWindow.toggleFullScreen(_:)))
            button.frame = NSRect(x: 48, y: 150, width: 180, height: 32)
            movingBackground.addSubview(button)
            let status = NSTextField(labelWithString: "Preparing")
            status.setAccessibilityIdentifier("hush.hudSpaceStatus")
            status.frame = NSRect(x: 48, y: 200, width: 650, height: 30)
            movingBackground.addSubview(status)
            statusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    let panel = NSApp.windows.first { $0 is HUDPanel }
                    let visible = panel?.isVisible == true && panel?.isOnActiveSpace == true && (panel?.alphaValue ?? 0) > 0.9
                    status.stringValue = "Full screen: \(window.styleMask.contains(.fullScreen)); HUD \(visible ? "visible" : "hidden")"
                }
            }
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        movingBackground.start()
        hud.show(state: spacesJourney ? .recording : .inserted(words: 34, app: "Motion Test", verified: false))
    }
    deinit { statusTimer?.invalidate() }
}

private final class HUDMovingBackgroundView: NSView {
    private var phase: CGFloat = 0
    private var timer: Timer?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let colors: [NSColor] = [
            .systemBlue,
            .systemPink,
            .systemIndigo,
            .systemPurple,
            .systemTeal,
        ]
        let stripeWidth: CGFloat = 180
        let firstStripe = Int(floor((dirtyRect.minX + phase) / stripeWidth)) - 1
        let lastStripe = Int(ceil((dirtyRect.maxX + phase) / stripeWidth)) + 1

        for index in firstStripe...lastStripe {
            let color = colors[((index % colors.count) + colors.count) % colors.count]
            color.setFill()
            let x = CGFloat(index) * stripeWidth - phase
            NSBezierPath(rect: NSRect(x: x, y: dirtyRect.minY, width: stripeWidth, height: dirtyRect.height)).fill()
        }

        let title = "Native Liquid Glass motion test"
        let detail = "The background moves. The real hush panel remains stationary."
        title.draw(
            at: NSPoint(x: 48, y: 48),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        detail.draw(
            at: NSPoint(x: 50, y: 92),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            ]
        )
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.phase = (self.phase + 2).truncatingRemainder(dividingBy: 900)
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}
#endif

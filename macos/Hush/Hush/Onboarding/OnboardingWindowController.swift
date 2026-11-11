import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(coordinator: DictationCoordinator, onFinish: @escaping () -> Void) {
        let vc = OnboardingViewController(coordinator: coordinator, onFinish: onFinish)
        let window = NSWindow(contentViewController: vc)
        window.title = "Welcome to hush"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1280, height: 860))
        window.minSize = NSSize(width: 980, height: 700)
        window.maxSize = NSSize(width: 1440, height: 960)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

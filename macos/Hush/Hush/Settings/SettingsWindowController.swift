import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let controlCenter: HushControlCenterViewController

    init(coordinator: DictationCoordinator) {
        let vc = HushControlCenterViewController(coordinator: coordinator)
        controlCenter = vc
        let window = NSWindow(contentViewController: vc)
        window.title = "hush"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.minSize = NSSize(width: 880, height: 600)
        window.isMovableByWindowBackground = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func show(destination: HushDestination) {
        controlCenter.navigate(to: destination)
        showWindow(nil)
    }
}

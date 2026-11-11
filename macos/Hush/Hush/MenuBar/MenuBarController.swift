import AppKit
import Combine

/// Owns the menu-bar icon and its compact custom menu panel.
@MainActor
final class MenuBarController: NSObject {
    private weak var coordinator: DictationCoordinator?
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var subscriptions = Set<AnyCancellable>()
    private var processingAnimationTimer: Timer?

    private lazy var panelView = MenuBarPanelView(
        onSettings: { [weak self] in
            self?.performAfterClosing { self?.onShowSettings?(.general) }
        },
        onPermissions: { [weak self] in
            self?.performAfterClosing { self?.onShowSettings?(.permissions(focusFirstMissing: true)) }
        },
        onPersona: { [weak self] in
            self?.handlePersonaAction()
        },
        onCheckForUpdates: { [weak self] in
            self?.performAfterClosing(self?.onCheckForUpdates)
        },
        onQuit: { [weak self] in
            self?.performAfterClosing(self?.onQuit)
        },
        onRecent: { [weak self] item in
            self?.copyRecentItem(item)
        }
    )

    var onShowSettings: ((HushDestination) -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Frame of the status-item button in screen coordinates. The HUD uses
    /// this to anchor itself below the icon when top positioning is enabled.
    func statusItemScreenFrame() -> NSRect? {
        statusItem.button?.window?.frame
    }

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func install() {
        applyAsset(named: "MenuBar-idle", template: true)
        statusItem.button?.setAccessibilityIdentifier("hush.menuBar")
        statusItem.button?.setAccessibilityLabel("hush menu")
        menu.delegate = self
        menu.minimumWidth = MenuBarPanelView.panelWidth
        let panelItem = NSMenuItem()
        panelItem.view = panelView
        menu.addItem(panelItem)
        #if DEBUG
        let diagnostics = NSMenuItem(title: "Development diagnostics", action: nil, keyEquivalent: "")
        let developmentMenu = NSMenu()
        let recording = NSMenuItem(title: "Record assistant turns this launch", action: #selector(toggleAssistantDiagnostics(_:)), keyEquivalent: "")
        recording.target = self
        recording.state = CoworkerDiagnostics.shared.enabled ? .on : .off
        developmentMenu.addItem(recording)
        let folder = NSMenuItem(title: "Open local traces", action: #selector(openAssistantDiagnostics), keyEquivalent: "")
        folder.target = self
        developmentMenu.addItem(folder)
        diagnostics.submenu = developmentMenu
        menu.addItem(.separator())
        menu.addItem(diagnostics)
        #endif
        statusItem.menu = menu

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--activate-persona-row-for-testing") {
            DispatchQueue.main.async { [weak self] in
                self?.handlePersonaAction()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--activate-update-row-for-testing") {
            DispatchQueue.main.async { [weak self] in
                self?.onCheckForUpdates?()
            }
        }
        #endif

        coordinator?.phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.reflect(phase: phase) }
            .store(in: &subscriptions)

        ActivityStore.shared.$recentInserts
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.panelView.setRecentItems(items) }
            .store(in: &subscriptions)

        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshPanelMetadata()
                self?.refreshTooltip()
            }
            .store(in: &subscriptions)

        refreshPanelMetadata()
    }

    private func reflect(phase: DictationCoordinator.Phase) {
        let asset: String
        let template: Bool
        let animateProcessing: Bool
        let panelStatus: MenuPanelStatus

        switch phase {
        case .idle:
            asset = "MenuBar-idle"
            template = true
            animateProcessing = false
            panelStatus = .idle
        case .modelLoading(let progress):
            asset = "MenuBar-processing"
            template = true
            animateProcessing = true
            panelStatus = .loading(Int((progress * 100).rounded()))
        case .recording:
            asset = "MenuBar-recording"
            template = false
            animateProcessing = false
            panelStatus = .listening
        case .transcribing:
            asset = "MenuBar-processing"
            template = true
            animateProcessing = true
            panelStatus = .transcribing
        case .postProcessing(let profileName):
            asset = "MenuBar-processing"
            template = true
            animateProcessing = true
            panelStatus = .polishing(profileName)
        case .inserted:
            asset = "MenuBar-idle"
            template = true
            animateProcessing = false
            panelStatus = .inserted
        case .error:
            asset = "MenuBar-disabled"
            template = false
            animateProcessing = false
            panelStatus = .error
        }

        applyAsset(named: asset, template: template)
        panelView.setStatus(panelStatus)
        if animateProcessing {
            startProcessingAnimation()
        } else {
            stopProcessingAnimation()
        }
    }

    #if DEBUG
    @objc private func toggleAssistantDiagnostics(_ sender: NSMenuItem) {
        CoworkerDiagnostics.shared.enabled.toggle()
        sender.state = CoworkerDiagnostics.shared.enabled ? .on : .off
    }

    @objc private func openAssistantDiagnostics() {
        let directory = CoworkerDiagnostics.directory
        if FileManager.default.fileExists(atPath: directory.path) { NSWorkspace.shared.open(directory) }
    }
    #endif

    private func refreshPanelMetadata() {
        let hotkey = Settings.shared.hotkey.displayName
        let normalizedHotkey = hotkey == "Fn" ? "fn" : hotkey.lowercased()
        let verb = Settings.shared.hotkeyMode == .pushToTalk ? "hold" : "press"
        panelView.setHotkeyHint("\(verb) \(normalizedHotkey) anywhere")

        if Settings.shared.activeDictationProfile == nil {
            panelView.setPersona("No persona")
        } else if LLMRuntime.shared.isActiveProviderReady {
            panelView.setPersona(Settings.shared.activeProfile.name)
        } else {
            panelView.setPersona("Setup needed")
        }

        let microphoneReady = PermissionsChecker.microphoneStatus == .authorized
        #if APP_STORE
        let accessibilityReady = true
        #else
        let accessibilityReady = !Settings.shared.autoInsert || PermissionsChecker.isAccessibilityGranted
        #endif
        let missingCount = [microphoneReady, accessibilityReady].filter { !$0 }.count
        if missingCount == 0 {
            panelView.setPermissions("Ready", needsAttention: false)
        } else {
            panelView.setPermissions(
                missingCount == 1 ? "1 needed" : "2 needed",
                needsAttention: true
            )
        }
    }

    private func handlePersonaAction() {
        performAfterClosing { [weak self] in
            self?.coordinator?.togglePersonaSelector()
        }
    }

    private func copyRecentItem(_ item: RecentInsert) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        menu.cancelTracking()
        coordinator?.hud.flash(message: "Copied")
    }

    private func performAfterClosing(_ action: (() -> Void)?) {
        menu.cancelTracking()
        DispatchQueue.main.async { action?() }
    }

    private func applyAsset(named: String, template: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(named: named)
        image?.isTemplate = template
        button.image = image
        button.contentTintColor = nil
        refreshTooltip()
    }

    private func refreshTooltip() {
        guard let button = statusItem.button else { return }
        let provider = Settings.shared.llmProvider
        button.toolTip = if provider == .off || Settings.shared.activeDictationProfile == nil {
            "hush · No persona"
        } else {
            "hush · \(Settings.shared.activeProfile.name)"
        }
    }

    private func startProcessingAnimation() {
        guard processingAnimationTimer == nil else { return }
        let button = statusItem.button
        button?.alphaValue = 1
        processingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            Task { @MainActor in
                guard let button else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.6
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    button.animator().alphaValue = button.alphaValue > 0.7 ? 0.4 : 1
                }
            }
        }
    }

    private func stopProcessingAnimation() {
        processingAnimationTimer?.invalidate()
        processingAnimationTimer = nil
        statusItem.button?.alphaValue = 1
    }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.refreshPanelMetadata()
            self.panelView.setRecentItems(ActivityStore.shared.recentInserts)
        }
    }
}

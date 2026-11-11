import Cocoa
import Combine
import OSLog

@main
enum HushMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // Hold a strong reference so the delegate isn't released before the runloop starts.
        // NSApplication only holds it weakly.
        objc_setAssociatedObject(app, &HushMain.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        app.delegate = delegate
        app.run()
    }
    private static var delegateKey: UInt8 = 0
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "App")
    private static let maximumServiceSelectionLength = 100_000

    private var menuBarController: MenuBarController?
    private var dictationCoordinator: DictationCoordinator?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var lastExternalApplication: NSRunningApplication?
    private lazy var updateManager = HushUpdateManager()
    private let assistantWindowController = AssistantCompanionController()
    #if DEBUG
    private var previewWindowController: NSWindowController?
    private var glassDebugJourneyController: HUDGlassDebugJourneyController?
    private var personaWheelDebugJourneyController: PersonaWheelDebugJourneyController?
    private var selectionEditorDebugJourney: HushSelectionEditor?
    private var selectionEditorPreviewVoiceIsListening = false
    #endif

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        // The opt-in model evaluation is text-only. Do not register hotkeys,
        // preload audio, show onboarding, or start background app services.
        if ProcessInfo.processInfo.environment["HUSH_TEST_HOST"] == "1"
            || ProcessInfo.processInfo.environment["HUSH_OPERATION_AB"] == "1" { return }
        if showPersonaWheelJourneyIfRequested() { return }
        if showNativeHUDGlassJourneyIfRequested() { return }
        if showSelectionEditorJourneyIfRequested() { return }
        if showAssistantJourneyIfRequested() { return }
        if showControlCenterPreviewIfRequested() { return }
        #endif

        let coordinator = DictationCoordinator()
        self.dictationCoordinator = coordinator
        AIModelLibrary.shared.coordinator = coordinator
        AIModelLibrary.shared.assistantIsWorking = { [weak self] in self?.assistantWindowController.isWorking == true }
        coordinator.onBeginAssistant = { [weak self] in
            guard let self else { return nil }
            guard self.assistantModelsInstalled() else { return nil }
            return self.assistantWindowController.beginListening(from: self.currentExternalApplication())
        }
        coordinator.onAssistantCaptureState = { [weak self] id, state in
            self?.assistantWindowController.captureState(state, turnID: id)
        }
        coordinator.onAssistantLevel = { [weak self] level in self?.assistantWindowController.updateLevel(level) }
        coordinator.onAssistantTranscript = { [weak self] id, text in
            self?.assistantWindowController.receiveTranscript(text, sessionID: id)
        }
        assistantWindowController.onSettings = { [weak self] in
            self?.showHush(destination: .assistant)
        }
        assistantWindowController.onMicrophone = { [weak coordinator] in coordinator?.toggleAssistantRecording() }
        assistantWindowController.onCancelRecording = { [weak coordinator] in coordinator?.cancelAssistantRecording() }
        coordinator.onShowPersonaSettings = { [weak self] in
            let needsSetup = Settings.shared.llmProvider == .off
                || !LLMRuntime.shared.isActiveProviderReady
            self?.showHush(destination: .personas(focusEnableAI: needsSetup))
        }
        startTrackingExternalApplications()

        let menuBar = MenuBarController(coordinator: coordinator)
        menuBar.onShowSettings = { [weak self] destination in self?.showHush(destination: destination) }
        menuBar.onShowOnboarding = { [weak self] in self?.showOnboarding() }
        menuBar.onCheckForUpdates = { [weak self] in self?.updateManager.checkForUpdates() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.install()
        self.menuBarController = menuBar

        // Let the HUD anchor itself under our menu-bar icon when the user picks the
        // "top of screen" position.
        coordinator.hud.statusItemFrameProvider = { [weak menuBar] in
            menuBar?.statusItemScreenFrame()
        }

        // Always boot the coordinator (loads the bundled model in the background, starts the
        // hotkey monitor). Onboarding shows on top of that flow if needed.
        coordinator.start()
        // Warm an already-downloaded selected writing model shortly after
        // launch. This never blocks startup and shares the same load task with
        // a prompt if the user opens Edit with AI immediately.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            LLMRuntime.shared.preload()
        }
        TypingActivityMonitor.shared.startObservingSettings()
        // Apple may deliver a service request as soon as this is assigned, so register
        // only after the coordinator and source-app tracking are fully ready.
        NSApp.servicesProvider = self

        if !Settings.shared.didCompleteOnboarding {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
        #if DEBUG
        // UI journeys open the real settings window, backed by the live coordinator.
        if ProcessInfo.processInfo.arguments.contains("--open-ai-settings") {
            DispatchQueue.main.async { [weak self] in self?.showHush(destination: .ai) }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-transcription-settings") {
            DispatchQueue.main.async { [weak self] in self?.showHush(destination: .transcription) }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showAssistant() {
        guard dictationCoordinator?.canOpenAssistant == true else {
            dictationCoordinator?.hud.flash(message: "Finish the current recording first")
            return
        }
        guard assistantModelsInstalled() else { return }
        assistantWindowController.open(from: currentExternalApplication())
    }

    private func assistantModelsInstalled() -> Bool {
        guard !AIModelLibrary.shared.isRemoving, !AssistantSetupFlow.shared.isRunning,
              AssistantSetupSnapshot.modelsInstalled else {
            showHush(destination: .assistant)
            return false
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        TypingActivityMonitor.shared.stopAndFlush()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Treats the Services request as explicit user intent, then uses the same
    /// fail-closed contextual resolver as the global Compose shortcut. Arbitrary
    /// selected text is never preloaded or claimed as Hush-authored source.
    @objc func editSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some text first"
            return
        }
        guard selectedText.count <= Self.maximumServiceSelectionLength else {
            error.pointee = "The selected text is too long to edit with hush"
            return
        }
        guard let sourceApplication = currentExternalApplication() else {
            error.pointee = "hush could not identify the app containing the selection"
            return
        }

        Self.log.notice(
            "Received a Services selection of \(selectedText.count) characters from \(sourceApplication.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        dictationCoordinator?.editSelectionWithHush(
            sourceApplication: sourceApplication
        )
    }

    private func startTrackingExternalApplications() {
        if let frontmost = currentExternalApplication() {
            lastExternalApplication = frontmost
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        lastExternalApplication = application
    }

    private func currentExternalApplication() -> NSRunningApplication? {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != currentProcessID {
            return frontmost
        }
        return lastExternalApplication
    }

    private func showHush(destination: HushDestination) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(coordinator: dictationCoordinator!)
        }
        NSApp.setActivationPolicy(.regular)
        guard let win = settingsWindowController?.window else { return }
        Self.centerOnActiveScreen(win)
        settingsWindowController?.show(destination: destination)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(coordinator: dictationCoordinator!) { [weak self] in
                guard let self else { return }
                Settings.shared.didCompleteOnboarding = true
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
                self.dictationCoordinator?.start()
                self.showHush(destination: .dashboard)
            }
        }
        NSApp.setActivationPolicy(.regular)
        guard let win = onboardingWindowController?.window else { return }
        Self.centerOnActiveScreen(win)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func centerOnActiveScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    #if DEBUG
    private func showPersonaWheelJourneyIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains(where: {
            $0.hasPrefix("--preview-persona-wheel")
        }) else {
            return false
        }
        let controller = PersonaWheelDebugJourneyController()
        personaWheelDebugJourneyController = controller
        controller.show()
        return true
    }

    private func showNativeHUDGlassJourneyIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--preview-native-hud-glass") else {
            return false
        }
        let controller = HUDGlassDebugJourneyController()
        glassDebugJourneyController = controller
        controller.show()
        return true
    }

    private func showSelectionEditorJourneyIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--preview-selection-editor") else {
            return false
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-light-appearance") {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if ProcessInfo.processInfo.arguments.contains("--preview-dark-appearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let editor = HushSelectionEditor { text, instruction, _, _ in
            try await Task.sleep(for: .milliseconds(320))
            if instruction.localizedCaseInsensitiveContains("short") {
                return "People can test the microphone during onboarding, making hush easier to understand."
            }
            if instruction.localizedCaseInsensitiveContains("smart") {
                return "People can test the microphone directly in onboarding, creating a more intuitive and immediately understandable product experience."
            }
            if instruction.localizedCaseInsensitiveContains("friendly") {
                return "People can try the microphone during onboarding, so hush feels natural from the very first moment."
            }
            if instruction.localizedCaseInsensitiveContains("what would you improve") {
                return "<message>I would make the opening more direct, shorten the middle sentence, and end with the user benefit so the idea feels more confident.</message>"
            }
            if instruction.localizedCaseInsensitiveContains("translate to english") {
                return "<output>So, I will now check whether everything works and whether the text can be translated into English. I will also review cultural references and idioms that may need to be adapted"
            }
            return text
        }
        editor.onToggleVoiceInput = { [weak self, weak editor] in
            guard let self, let editor else { return }
            selectionEditorPreviewVoiceIsListening.toggle()
            if selectionEditorPreviewVoiceIsListening {
                editor.updateVoiceInputState(.listening)
                [
                    0.10, 0.16, 0.24, 0.38, 0.58, 0.76, 0.46,
                    0.30, 0.18, 0.28, 0.52, 0.84, 0.62, 0.40,
                    0.22, 0.34, 0.66, 0.90, 0.70, 0.42, 0.26,
                    0.18, 0.32, 0.56, 0.74, 0.48, 0.28, 0.14,
                ].forEach(editor.updateVoiceInputLevel)
            } else {
                editor.updateVoiceInputState(.transcribing)
                Task {
                    try? await Task.sleep(for: .milliseconds(1_600))
                    editor.updateVoiceInputState(.idle)
                }
            }
        }
        selectionEditorDebugJourney = editor
        let context = HushSelectionContext(
            originalText: "After that, people can test the microphone right away inside the flow. It feels more interactive now and should make the product easier to understand.",
            applicationName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 0,
            destination: .clipboard,
            origin: .recentHushOutput
        )
        Task {
            _ = await editor.present(
                context: context,
                language: Settings.defaultLanguage,
                provider: .appleIntelligence,
                profiles: Profile.seededProfiles,
                activeProfile: Profile.seededProfiles[0],
                origin: .recentHushOutput
            )
        }
        return true
    }

    private func showControlCenterPreviewIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let destination: HushDestination
        if arguments.contains("--preview-dashboard") {
            destination = .dashboard
        } else if arguments.contains("--preview-hush-ai") {
            destination = .ai
        } else if arguments.contains("--preview-assistant-settings") {
            destination = .assistant
        } else if arguments.contains("--preview-personas") {
            destination = .personas()
        } else if arguments.contains("--preview-time-saved") {
            destination = .timeSaved()
        } else if arguments.contains("--preview-activity") {
            destination = .activity()
        } else if arguments.contains("--preview-history") {
            destination = .history()
        } else if arguments.contains("--preview-hud") {
            destination = .interface
        } else if arguments.contains("--preview-verified-messages") {
            destination = .verifiedMessages
        } else if arguments.contains("--preview-transcription-parakeet") {
            destination = .transcriptionEngine(.fluidAudio)
        } else if arguments.contains("--preview-transcription-whisper") {
            destination = .transcriptionEngine(.whisperKit)
        } else if arguments.contains("--preview-transcription") {
            destination = .transcription
        } else {
            return false
        }

        if arguments.contains("--preview-dark-appearance") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if arguments.contains("--preview-light-appearance") { NSApp.appearance = NSAppearance(named: .aqua) }
        if arguments.contains("--preview-kokoro-download") {
            CoworkerVoice.shared.setupState.send(.preparing)
            CoworkerVoice.shared.setupProgress.send(.file(3, 62))
        }
        let controller = HushControlCenterViewController(coordinator: nil, previewMode: true)
        let window = NSWindow(contentViewController: controller)
        window.title = "hush Preview"
        window.isRestorable = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(arguments.contains("--preview-compact-window") ? NSSize(width: 880, height: 600) : NSSize(width: 1040, height: 720))
        window.minSize = NSSize(width: 880, height: 600)
        Self.centerOnActiveScreen(window)
        controller.navigate(to: destination)
        let windowController = NSWindowController(window: window)
        previewWindowController = windowController
        NSApp.setActivationPolicy(.regular)
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for otherWindow in NSApp.windows where otherWindow !== window {
                otherWindow.isRestorable = false
                otherWindow.close()
            }
            controller.navigate(to: destination)
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
    #endif
}

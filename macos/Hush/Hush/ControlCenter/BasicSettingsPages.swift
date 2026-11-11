import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class GeneralSettingsPageViewController: ControlCenterPageViewController {
    private weak var coordinator: DictationCoordinator?
    private let hotkeyControl = HotkeyRecorderControl(combo: Settings.shared.hotkey)
    private let personaHotkeyControl = HotkeyRecorderControl(combo: Settings.shared.personaHotkey)
    private let composeHotkeyControl = HotkeyRecorderControl(combo: Settings.shared.composeHotkey)
    private let modeControl = NSSegmentedControl(labels: ["Hold", "Toggle"], trackingMode: .selectOne, target: nil, action: nil)
    private let languageButton = NSPopUpButton()
    private let switchToWhisperButton = NSButton()
    private let qualityButton = NSPopUpButton()
    private var languageRow: ControlCenterKeyValueRow?
    private var qualityRow: ControlCenterKeyValueRow?
    private var subscriptions = Set<AnyCancellable>()
    private let autoPasteSwitch = NSSwitch()
    private let restoreClipboardSwitch = NSSwitch()

    init(coordinator: DictationCoordinator?) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "Dictation controls",
            detail: "Choose how dictation starts, listens, and returns text to the app you are using."
        ))
        buildShortcutCard()
        buildBehaviorCard()
        configureControls()
        Settings.shared.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    private func buildShortcutCard() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Dictation shortcut",
            subtitle: "Press anywhere to start hush.",
            trailing: hotkeyControl
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Persona selector",
            subtitle: "Open the persona wheel without starting a recording.",
            trailing: personaHotkeyControl
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Compose shortcut",
            subtitle: "Edit a selection, reopen a hush message, or start fresh.",
            trailing: composeHotkeyControl
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Recording mode",
            subtitle: "Hold to speak or press once to start and stop.",
            trailing: modeControl
        ))
        let languageControls = NSStackView(views: [switchToWhisperButton, languageButton])
        languageControls.orientation = .horizontal
        languageControls.alignment = .centerY
        languageControls.spacing = 8
        let languageRow = ControlCenterKeyValueRow(
            title: "Spoken language",
            subtitle: Self.languageSubtitle(language: Settings.shared.language, modelID: Settings.shared.modelID).text,
            trailing: languageControls
        )
        self.languageRow = languageRow
        rows.addArrangedSubview(languageRow)
        let qualityRow = ControlCenterKeyValueRow(
            title: "Recognition quality",
            subtitle: Self.qualitySubtitle(for: SpeechEngine.engine(for: Settings.shared.modelID)),
            trailing: qualityButton,
            showsSeparator: false
        )
        self.qualityRow = qualityRow
        rows.addArrangedSubview(qualityRow)
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("Dictation"))
        addFullWidth(makeCard(content: rows))
    }

    private func buildBehaviorCard() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Auto-paste",
            subtitle: "Insert completed text into the focused app.",
            trailing: autoPasteSwitch
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Restore clipboard",
            subtitle: "Put the previous clipboard contents back after auto-paste.",
            trailing: restoreClipboardSwitch,
            showsSeparator: false
        ))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("After dictation"))
        addFullWidth(makeCard(content: rows))

        #if APP_STORE
        addFullWidth(subtitle("The Mac App Store build copies text to the clipboard instead of auto-pasting."))
        #else
        addFullWidth(subtitle("Auto-paste requires Accessibility permission. Clipboard-only output remains available without it."))
        #endif
    }

    private func configureControls() {
        hotkeyControl.onChange = { [weak self] combo in
            guard combo != Settings.shared.composeHotkey,
                  combo != Settings.shared.personaHotkey else {
                NSSound.beep()
                self?.hotkeyControl.combo = Settings.shared.hotkey
                return
            }
            Settings.shared.hotkey = combo
            self?.coordinator?.hotkey.update(combo: combo)
        }
        personaHotkeyControl.onChange = { [weak self] combo in
            guard combo != Settings.shared.hotkey,
                  combo != Settings.shared.composeHotkey else {
                NSSound.beep()
                self?.personaHotkeyControl.combo = Settings.shared.personaHotkey
                return
            }
            Settings.shared.personaHotkey = combo
            self?.coordinator?.personaHotkey.update(combo: combo)
        }
        composeHotkeyControl.onChange = { [weak self] combo in
            guard combo != Settings.shared.hotkey,
                  combo != Settings.shared.personaHotkey else {
                NSSound.beep()
                self?.composeHotkeyControl.combo = Settings.shared.composeHotkey
                return
            }
            Settings.shared.composeHotkey = combo
            self?.coordinator?.composeHotkey.update(combo: combo)
        }
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))

        for option in LanguageOption.popular {
            languageButton.addItem(withTitle: option.displayName)
            languageButton.lastItem?.representedObject = option.code
        }
        languageButton.target = self
        languageButton.action = #selector(languageChanged(_:))

        for quality in Settings.TranscriptionQuality.allCases {
            qualityButton.addItem(withTitle: quality.displayName)
            qualityButton.lastItem?.representedObject = quality.rawValue
        }
        qualityButton.target = self
        qualityButton.action = #selector(qualityChanged(_:))

        switchToWhisperButton.title = "Switch to Whisper"
        switchToWhisperButton.bezelStyle = .rounded
        switchToWhisperButton.controlSize = .small
        switchToWhisperButton.target = self
        switchToWhisperButton.action = #selector(switchToWhisper(_:))

        autoPasteSwitch.target = self
        autoPasteSwitch.action = #selector(autoPasteChanged(_:))
        restoreClipboardSwitch.target = self
        restoreClipboardSwitch.action = #selector(restoreClipboardChanged(_:))
    }

    private func refresh() {
        modeControl.selectedSegment = Settings.shared.hotkeyMode == .pushToTalk ? 0 : 1
        languageButton.selectItem(at: LanguageOption.popular.firstIndex { $0.code == Settings.shared.language } ?? 0)
        qualityButton.selectItem(at: Settings.TranscriptionQuality.allCases.firstIndex(of: Settings.shared.transcriptionQuality) ?? 1)
        let engine = SpeechEngine.engine(for: Settings.shared.modelID)
        qualityButton.isEnabled = engine == .whisperKit
        qualityRow?.subtitle = Self.qualitySubtitle(for: engine)
        let language = Self.languageSubtitle(language: Settings.shared.language, modelID: Settings.shared.modelID)
        languageRow?.subtitle = language.text
        languageRow?.subtitleColor = language.isUnsupported ? DesignTokens.danger : .secondaryLabelColor
        switchToWhisperButton.isHidden = !language.isUnsupported
        autoPasteSwitch.state = Settings.shared.autoInsert ? .on : .off
        restoreClipboardSwitch.state = Settings.shared.restoreClipboard ? .on : .off
        restoreClipboardSwitch.isEnabled = Settings.shared.autoInsert
        #if APP_STORE
        autoPasteSwitch.isEnabled = false
        autoPasteSwitch.state = .off
        #endif
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        Settings.shared.hotkeyMode = sender.selectedSegment == 0 ? .pushToTalk : .toggle
    }
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let code = sender.selectedItem?.representedObject as? String else { return }
        Settings.shared.language = code
    }
    @objc private func switchToWhisper(_ sender: Any?) {
        Settings.shared.modelID = Self.bestAvailableWhisperModelID()
        Task { await coordinator?.prepareModelInBackground() }
    }

    /// The most capable Whisper model already on this Mac, so switching never downloads.
    static func bestAvailableWhisperModelID() -> String {
        let available = ModelManager.availableIDs()
        let candidates = ModelCatalogService.shared.models.value
            .filter { $0.engine == .whisperKit && $0.multilingual && available.contains($0.id) }
            .sorted { ($0.approximateSizeMB ?? 0) > ($1.approximateSizeMB ?? 0) }
        return candidates.first?.id ?? ModelInfo.defaultModelID
    }

    static func qualitySubtitle(for engine: SpeechEngine) -> String {
        switch engine {
        case .whisperKit: return "Balanced retries only when decoding appears unreliable."
        case .fluidAudio: return "Parakeet always decodes at full quality."
        }
    }

    static func languageSubtitle(language: String, modelID: String) -> (text: String, isUnsupported: Bool) {
        let engine = SpeechEngine.engine(for: modelID)
        let supported = ModelInfo.info(for: modelID)?.supports(language: language)
            ?? (engine == .whisperKit || ParakeetModel.supportedLanguages.contains(language) || language == "auto")
        if !supported {
            return ("\(LanguageOption.displayName(for: language)) is not supported by \(engine.familyName).", true)
        }
        if engine == .fluidAudio, language == LanguageOption.auto.code {
            return ("Parakeet detects 25 European languages automatically.", false)
        }
        return ("Used by the active \(engine.familyName) model.", false)
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let quality = Settings.TranscriptionQuality(rawValue: raw) else { return }
        Settings.shared.transcriptionQuality = quality
    }
    @objc private func autoPasteChanged(_ sender: NSSwitch) {
        Settings.shared.autoInsert = sender.state == .on
        refresh()
    }
    @objc private func restoreClipboardChanged(_ sender: NSSwitch) {
        Settings.shared.restoreClipboard = sender.state == .on
    }
}

@MainActor
final class InterfaceSettingsPageViewController: ControlCenterPageViewController {
    private let showHUDSwitch = NSSwitch()
    private let positionControl = NSSegmentedControl(labels: ["Bottom", "Top"], trackingMode: .selectOne, target: nil, action: nil)
    private let hudStateControl = NSSegmentedControl(
        labels: ["Listening", "Processing", "Signing", "Inserted"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let hudPreview = HUDSettingsPreviewView()

    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "HUD & Menu",
            detail: "Choose where the floating HUD sits and preview every live state."
        ))
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Show floating HUD",
            subtitle: "Display recording and processing state while dictating.",
            trailing: showHUDSwitch
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "HUD position",
            trailing: positionControl
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Preview state",
            subtitle: "Click through the states shown while dictating.",
            trailing: hudStateControl,
            showsSeparator: false
        ))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("Floating HUD"))
        addFullWidth(makeCard(content: rows))

        hudPreview.translatesAutoresizingMaskIntoConstraints = false
        hudPreview.heightAnchor.constraint(equalToConstant: 300).isActive = true
        addFullWidth(hudPreview)

        showHUDSwitch.target = self
        showHUDSwitch.action = #selector(showHUDChanged(_:))
        positionControl.target = self
        positionControl.action = #selector(positionChanged(_:))
        hudStateControl.target = self
        hudStateControl.action = #selector(hudStateChanged(_:))
        hudStateControl.selectedSegment = 0
        refresh()
    }

    private func refresh() {
        showHUDSwitch.state = Settings.shared.showHUD ? .on : .off
        positionControl.selectedSegment = Settings.shared.hudPosition == .bottom ? 0 : 1
        positionControl.isEnabled = Settings.shared.showHUD
        hudPreview.position = Settings.shared.hudPosition
        hudPreview.isEnabled = Settings.shared.showHUD
        hudPreview.isVerified = Settings.shared.verifiedMessagesEnabled
    }

    @objc private func showHUDChanged(_ sender: NSSwitch) {
        Settings.shared.showHUD = sender.state == .on
        refresh()
    }
    @objc private func positionChanged(_ sender: NSSegmentedControl) {
        Settings.shared.hudPosition = sender.selectedSegment == 0 ? .bottom : .top
        refresh()
    }
    @objc private func hudStateChanged(_ sender: NSSegmentedControl) {
        let states: [HushState] = [.listening, .processing, .signing, .inserted]
        guard states.indices.contains(sender.selectedSegment) else { return }
        hudPreview.state = states[sender.selectedSegment]
    }
}

@MainActor
private final class HUDSettingsPreviewView: ControlCenterCardView {
    var position: Settings.HUDPosition = .bottom { didSet { updatePreview() } }
    var isEnabled = true { didSet { updatePreview() } }
    var isVerified = false { didSet { updatePreview() } }
    var state: HushState = .listening { didSet { updatePreview() } }

    private let model: HUDModel
    private let materialView: HUDNativeMaterialView
    private let backgroundHost = NSHostingView(rootView: HUDSettingsPreviewBackground())
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!

    private static let levels: [CGFloat] = [
        0.04, 0.08, 0.16, 0.28, 0.52, 0.76, 0.44,
        0.22, 0.36, 0.68, 0.88, 0.60, 0.31, 0.18,
        0.26, 0.48, 0.72, 0.55, 0.34, 0.64, 0.82,
        0.46, 0.24, 0.38, 0.58, 0.30, 0.14, 0.06,
    ]

    override init(frame frameRect: NSRect) {
        let model = HUDModel()
        self.model = model
        materialView = HUDNativeMaterialView(model: model)
        super.init(frame: frameRect)

        backgroundHost.translatesAutoresizingMaskIntoConstraints = false
        materialView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundHost)
        addSubview(materialView)

        topConstraint = materialView.topAnchor.constraint(equalTo: topAnchor, constant: 34)
        bottomConstraint = materialView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -34)
        NSLayoutConstraint.activate([
            backgroundHost.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            backgroundHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            backgroundHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backgroundHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            materialView.centerXAnchor.constraint(equalTo: centerXAnchor),
            materialView.widthAnchor.constraint(equalToConstant: 380),
            materialView.heightAnchor.constraint(equalToConstant: 72),
            bottomConstraint,
        ])
        updatePreview(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updatePreview(animated: Bool = true) {
        model.state = state
        model.seconds = 8
        model.wordCount = 34
        model.targetApp = "Mail"
        model.isVerified = isVerified && state == .inserted
        model.levels = Self.levels
        materialView.alphaValue = isEnabled ? 1 : 0.42

        let showAtTop = position == .top
        NSLayoutConstraint.deactivate([topConstraint, bottomConstraint])
        NSLayoutConstraint.activate([showAtTop ? topConstraint : bottomConstraint])
        guard animated, window != nil else {
            needsLayout = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.durBase
            context.timingFunction = DesignTokens.easeOut
            context.allowsImplicitAnimation = true
            animator().layoutSubtreeIfNeeded()
        }
    }
}

private struct HUDSettingsPreviewBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.09, blue: 0.15),
                            Color(red: 0.19, green: 0.12, blue: 0.25),
                            Color(red: 0.48, green: 0.24, blue: 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(nsColor: DesignTokens.lilac).opacity(0.18))
                        .frame(width: 210, height: 210)
                        .blur(radius: 34)
                        .offset(x: 40, y: -90)
                }
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview background for the hush HUD")
    }
}

@MainActor
final class PermissionsSettingsPageViewController: ControlCenterPageViewController {
    private let focusFirstMissing: Bool
    private let overallStatus = NSTextField(labelWithString: "")
    private let microphoneStatus = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private var timer: Timer?

    init(focusFirstMissing: Bool) {
        self.focusFirstMissing = focusFirstMissing
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "Permissions",
            detail: "See exactly which macOS permissions hush can use and why."
        ))
        overallStatus.font = .systemFont(ofSize: 22, weight: .semibold)
        overallStatus.textColor = .labelColor
        let overallDetail = subtitle("Your microphone captures dictation. Accessibility lets Hush insert it into other apps. Screen access for Assistant Beta is managed in Hush AI > Assistant.")
        let overallStack = NSStackView(views: [overallStatus, overallDetail])
        overallStack.orientation = .vertical
        overallStack.alignment = .leading
        overallStack.spacing = 5
        addFullWidth(makeCard(content: overallStack, insets: .init(top: 18, left: 18, bottom: 18, right: 18)))

        let microphoneButton = NSButton(title: "Open Settings", target: self, action: #selector(openMicrophone(_:)))
        microphoneButton.bezelStyle = .rounded
        let microphoneTrailing = NSStackView(views: [microphoneStatus, microphoneButton])
        microphoneTrailing.orientation = .horizontal
        microphoneTrailing.alignment = .centerY
        microphoneTrailing.spacing = 10

        let accessibilityButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibility(_:)))
        accessibilityButton.bezelStyle = .rounded
        let accessibilityTrailing = NSStackView(views: [accessibilityStatus, accessibilityButton])
        accessibilityTrailing.orientation = .horizontal
        accessibilityTrailing.alignment = .centerY
        accessibilityTrailing.spacing = 10

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Microphone",
            subtitle: "Required to record your voice.",
            trailing: microphoneTrailing
        ))
        rows.addArrangedSubview(ControlCenterKeyValueRow(
            title: "Accessibility",
            subtitle: "Read controls and edit text in other apps.",
            trailing: accessibilityTrailing,
            showsSeparator: false
        ))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("System permissions"))
        addFullWidth(makeCard(content: rows))
        refresh()
        if focusFirstMissing {
            let button = PermissionsChecker.microphoneStatus != .authorized ? microphoneButton :
                accessibilityButton
            DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(button) }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let microphoneReady = PermissionsChecker.microphoneStatus == .authorized
        #if APP_STORE
        let accessibilityReady = true
        #else
        let accessibilityReady = PermissionsChecker.isAccessibilityGranted
        #endif
        let ready = microphoneReady && accessibilityReady
        overallStatus.stringValue = ready ? "Ready for dictation" : "Action needed"
        overallStatus.textColor = ready ? DesignTokens.goodInk : .secondaryLabelColor
        microphoneStatus.stringValue = microphoneReady ? "Granted" : "Not granted"
        microphoneStatus.textColor = microphoneReady ? DesignTokens.goodInk : DesignTokens.danger
        accessibilityStatus.stringValue = PermissionsChecker.isAccessibilityGranted ? "Granted" : "Not granted"
        accessibilityStatus.textColor = PermissionsChecker.isAccessibilityGranted ? DesignTokens.goodInk : DesignTokens.danger
    }

    @objc private func openMicrophone(_ sender: Any?) {
        if PermissionsChecker.microphoneStatus == .notDetermined {
            Task { _ = await PermissionsChecker.requestMicrophone(); refresh() }
        } else {
            PermissionsChecker.openMicrophoneSettings()
        }
    }
    @objc private func openAccessibility(_ sender: Any?) { PermissionsChecker.openAccessibilitySettings() }
}

@MainActor
final class AboutSettingsPageViewController: ControlCenterPageViewController {
    override func loadView() {
        super.loadView()
        addFullWidth(pageIntroduction(
            title: "About hush",
            detail: "Version, processing, and privacy details at a glance."
        ))
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 74).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 74).isActive = true

        let name = NSTextField(labelWithString: "hush")
        name.font = .systemFont(ofSize: 26, weight: .bold)
        name.textColor = .labelColor
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let channel = Bundle.main.infoDictionary?["HushReleaseChannel"] as? String ?? ""
        let releaseName = channel.isEmpty ? version : "\(version) \(channel)"
        let versionLabel = NSTextField(labelWithString: build.isEmpty ? releaseName : "Version \(releaseName) (build \(build))")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [name, versionLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let identity = NSStackView(views: [icon, labels])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 18
        addFullWidth(makeCard(content: identity, insets: .init(top: 22, left: 22, bottom: 22, right: 22)))

        let local = NSTextField(labelWithString: "On this Mac")
        local.font = .systemFont(ofSize: 12, weight: .medium)
        local.textColor = DesignTokens.goodInk
        let account = NSTextField(labelWithString: "Not required")
        account.font = .systemFont(ofSize: 12, weight: .medium)
        account.textColor = .secondaryLabelColor
        let telemetry = NSTextField(labelWithString: "None")
        telemetry.font = .systemFont(ofSize: 12, weight: .medium)
        telemetry.textColor = .secondaryLabelColor
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.addArrangedSubview(ControlCenterKeyValueRow(title: "Audio processing", trailing: local))
        rows.addArrangedSubview(ControlCenterKeyValueRow(title: "Account", trailing: account))
        rows.addArrangedSubview(ControlCenterKeyValueRow(title: "Telemetry", trailing: telemetry, showsSeparator: false))
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("Privacy"))
        addFullWidth(makeCard(content: rows))

        let credits = NSStackView()
        credits.orientation = .vertical
        credits.alignment = .leading
        credits.spacing = 0
        let entries: [(String, String, String)] = [
            ("Parakeet Ultra and Redux", "Moondream, from NVIDIA Parakeet TDT v3 · CC-BY-4.0", "https://huggingface.co/moondream/parakeet-ultra"),
            ("FluidAudio", "FluidInference · Apache-2.0", "https://github.com/FluidInference/FluidAudio"),
            ("Whisper", "OpenAI · MIT", "https://github.com/openai/whisper"),
            ("WhisperKit", "Argmax · MIT", "https://github.com/argmaxinc/argmax-oss-swift"),
        ]
        for (index, entry) in entries.enumerated() {
            let link = NSButton(title: "View", target: self, action: #selector(openCredit(_:)))
            link.bezelStyle = .inline
            link.controlSize = .small
            link.toolTip = entry.2
            link.identifier = NSUserInterfaceItemIdentifier(entry.2)
            link.setAccessibilityLabel("View \(entry.0) license")
            credits.addArrangedSubview(ControlCenterKeyValueRow(
                title: entry.0,
                subtitle: entry.1,
                trailing: link,
                showsSeparator: index < entries.count - 1
            ))
        }
        for row in credits.arrangedSubviews { row.widthAnchor.constraint(equalTo: credits.widthAnchor).isActive = true }
        addFullWidth(sectionTitle("Speech recognition"))
        addFullWidth(makeCard(content: credits))
    }

    @objc private func openCredit(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

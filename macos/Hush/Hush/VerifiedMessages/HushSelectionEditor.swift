import AppKit
import HushProvenance
import SwiftUI

struct HushSelectionEdit: Sendable {
    let context: HushSelectionContext
    let sourceText: String
    let finalText: String
    let origin: HushSelectionContext.Origin
    let usedLocalAI: Bool
    let containsManualEdits: Bool
    let personaName: String?
    let providerName: String?
    let voiceSegments: [ProofManifest.VoiceSegment]
    let startedAt: Date
    let refinedAt: Date?
}

struct HushEditorRecordingTarget: Sendable {
    let sessionID: UUID
    let applicationName: String
    let bundleIdentifier: String?
}

enum HushEditorVoiceInputState: Equatable {
    case idle
    case listening
    case transcribing
    case error(String)
}

typealias HushConversationalEditGenerator = @MainActor @Sendable (
    _ text: String,
    _ instruction: String,
    _ persona: Profile?,
    _ provider: LLMProvider
) async throws -> String

typealias HushEditingSessionFactory = @MainActor @Sendable (
    _ provider: LLMProvider
) -> any HushConversationalEditingSession

@MainActor
private final class HushClosureEditingSession: HushConversationalEditingSession {
    private let provider: LLMProvider
    private let generator: HushConversationalEditGenerator

    init(provider: LLMProvider, generator: @escaping HushConversationalEditGenerator) {
        self.provider = provider
        self.generator = generator
    }

    func prewarm() {}

    func edit(
        text: String,
        instruction: String,
        persona: Profile?,
        onPartialResult: @escaping @MainActor (HushEditStreamResult) -> Void
    ) async throws -> HushEditStreamResult {
        let explanation: String
        if instruction.localizedCaseInsensitiveContains("short") {
            explanation = "I made it shorter while keeping the original meaning."
        } else if instruction.localizedCaseInsensitiveContains("friend") {
            explanation = "I made the tone friendlier and more natural."
        } else {
            explanation = "I applied your change while preserving the message."
        }
        onPartialResult(HushEditStreamResult(
            assistantMessage: explanation,
            text: "",
            outputTokenCount: nil
        ))
        let output = try await generator(text, instruction, persona, provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.localizedCaseInsensitiveContains("<message>")
            || output.localizedCaseInsensitiveContains("<output>") {
            guard LLMRuntime.completedEditResponseIsWellFormed(output) else {
                throw LLMRuntime.Error.incompleteResponse
            }
            let result = LLMRuntime.extractCompletedEdit(
                output,
                outputTokenCount: nil,
                instruction: instruction
            )
            onPartialResult(result)
            return result
        }
        let words = output.split(separator: " ", omittingEmptySubsequences: true)
        for index in words.indices {
            try Task.checkCancellation()
            let partial = words[...index].joined(separator: " ")
            onPartialResult(HushEditStreamResult(
                assistantMessage: explanation,
                text: partial,
                outputTokenCount: nil
            ))
            if index != words.indices.last {
                try await Task.sleep(for: .milliseconds(18))
            }
        }
        return HushEditStreamResult(
            assistantMessage: explanation,
            text: output,
            outputTokenCount: words.count
        )
    }
}

@MainActor
final class HushSelectionEditor {
    private var windowController: NSWindowController?
    private var editorViewController: HushSelectionEditorViewController?
    private var continuation: CheckedContinuation<HushSelectionEdit?, Never>?
    private let editingSessionFactory: HushEditingSessionFactory
    var onToggleVoiceInput: (() -> Void)?
    var isPresented: Bool { windowController?.window?.isVisible == true }

    init(editingSessionFactory: @escaping HushEditingSessionFactory = { provider in
        LLMRuntime.shared.makeConversationalEditingSession(provider: provider)
    }) {
        self.editingSessionFactory = editingSessionFactory
    }

    init(editGenerator: @escaping HushConversationalEditGenerator) {
        self.editingSessionFactory = { provider in
            HushClosureEditingSession(provider: provider, generator: editGenerator)
        }
    }

    var focusedRecordingTarget: HushEditorRecordingTarget? {
        guard windowController?.window?.isKeyWindow == true,
              let controller = editorViewController else { return nil }
        return HushEditorRecordingTarget(
            sessionID: controller.sessionID,
            applicationName: controller.context.applicationName,
            bundleIdentifier: controller.context.bundleIdentifier
        )
    }

    func insertVoiceSegment(
        _ segment: ProofManifest.VoiceSegment,
        intoSession sessionID: UUID
    ) -> Bool {
        guard editorViewController?.sessionID == sessionID,
              windowController?.window != nil else { return false }
        editorViewController?.insertVoiceSegment(segment)
        return true
    }

    func updateVoiceInputState(_ state: HushEditorVoiceInputState) {
        editorViewController?.updateVoiceInputState(state)
    }

    func updateVoiceInputLevel(_ level: Float) {
        editorViewController?.updateVoiceInputLevel(level)
    }

    func present(
        context: HushSelectionContext,
        language: String,
        provider: LLMProvider,
        profiles: [Profile],
        activeProfile: Profile,
        origin: HushSelectionContext.Origin
    ) async -> HushSelectionEdit? {
        guard continuation == nil else {
            windowController?.window?.makeKeyAndOrderFront(nil)
            return nil
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let controller = HushSelectionEditorViewController(
                sessionID: UUID(),
                context: context,
                language: language,
                provider: provider,
                profiles: profiles,
                activeProfile: activeProfile,
                origin: origin,
                editingSessionFactory: editingSessionFactory,
                onToggleVoiceInput: { [weak self] in self?.onToggleVoiceInput?() },
                onComplete: { [weak self] result in self?.finish(with: result) }
            )
            let window = NSPanel(contentViewController: controller)
            window.title = origin == .newDraft ? "Compose" : "Edit"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.setContentSize(NSSize(width: 940, height: 700))
            window.minSize = NSSize(width: 800, height: 620)
            window.center()
            window.delegate = controller
            let windowController = NSWindowController(window: window)
            self.editorViewController = controller
            self.windowController = windowController
            NSApp.setActivationPolicy(.regular)
            windowController.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(with result: HushSelectionEdit?) {
        windowController?.close()
        windowController = nil
        editorViewController = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class HushSemanticSurfaceView: NSView {
    var fillColor: NSColor {
        didSet { updateColors() }
    }

    var strokeColor: NSColor? {
        didSet { updateColors() }
    }

    init(
        fillColor: NSColor,
        strokeColor: NSColor? = nil,
        cornerRadius: CGFloat
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = strokeColor == nil ? 0 : 1
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
            layer?.borderColor = strokeColor?.cgColor
            layer?.borderWidth = strokeColor == nil ? 0 : 1
        }
    }
}

@MainActor
final class HushSelectionEditorViewController: NSViewController, NSWindowDelegate, NSTextViewDelegate {
    let sessionID: UUID
    fileprivate let context: HushSelectionContext

    private let language: String
    private var provider: LLMProvider
    private let profiles: [Profile]
    private let activeProfile: Profile
    private let origin: HushSelectionContext.Origin
    private let editingSessionFactory: HushEditingSessionFactory
    private var editingSession: any HushConversationalEditingSession
    private let onComplete: (HushSelectionEdit?) -> Void
    private let onToggleVoiceInput: () -> Void
    private let startedAt = Date()
    private let state: HushSelectionEditorState
    private let restorationText: String

    private let modeControl = NSSegmentedControl(
        labels: ["Compose", "Edit with AI"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let composeContainer = NSView()
    private let aiContainer = NSView()
    private let composeTextView = NSTextView()
    private let composeWordCount = NSTextField(labelWithString: "")
    private let restoreButton = NSButton()
    private let primaryButton = BrandButton(title: "Accept changes")
    private let openAIButton = NSButton()
    private let chatScroll = NSScrollView()
    private let chatDocument = HushFlippedView()
    private let chatStack = NSStackView()
    private let instructionTextView = HushPromptTextView()
    private let instructionScroll = NSScrollView()
    private let instructionPlaceholder = NSTextField(labelWithString: "Tell hush what should change…")
    private let conversationModelPicker = NSButton()
    private let conversationModelMenu = NSMenu()
    private let microphoneButton = NSButton()
    private let voiceMeter = HushInlineVoiceMeter()
    private let voiceStatus = NSTextField(labelWithString: "")
    private weak var streamingArtifactText: NSTextField?
    private weak var streamingArtifactWordCount: NSTextField?
    private weak var streamingArtifactStatus: NSTextField?
    private weak var streamingArtifactCard: NSView?
    private weak var streamingThinkingButton: NSButton?
    private weak var streamingAssistantWrapper: NSView?
    private weak var streamingAssistantMessage: NSTextField?
    private weak var streamingAssistantMetadata: NSTextField?
    private var isApplyingProgrammaticChange = false
    private var isGenerating = false
    private var isCompleting = false
    private var pendingInstruction: String?
    private var pendingPartialText = ""
    private var generationHasAssistantOutput = false
    private var generationHasArtifactOutput = false
    private var generationTask: Task<Void, Never>?
    private var generationStartedAt: Date?
    private var generationProgressTimer: Timer?
    private var promptCardHeightConstraint: NSLayoutConstraint?
    private var selectedConversationProfile: Profile?
    private var voiceInputState: HushEditorVoiceInputState = .idle
    private var voiceSegments: [ProofManifest.VoiceSegment] = []

    init(
        sessionID: UUID,
        context: HushSelectionContext,
        language: String,
        provider: LLMProvider,
        profiles: [Profile],
        activeProfile: Profile,
        origin: HushSelectionContext.Origin,
        editingSessionFactory: @escaping HushEditingSessionFactory,
        onToggleVoiceInput: @escaping () -> Void,
        onComplete: @escaping (HushSelectionEdit?) -> Void
    ) {
        self.sessionID = sessionID
        self.context = context
        self.language = language
        self.provider = provider
        self.profiles = profiles
        self.activeProfile = activeProfile
        self.origin = origin
        self.editingSessionFactory = editingSessionFactory
        self.editingSession = editingSessionFactory(provider)
        self.onToggleVoiceInput = onToggleVoiceInput
        self.onComplete = onComplete
        self.state = HushSelectionEditorState(originalText: context.originalText)
        let prior = context.refinementSourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.restorationText = prior?.isEmpty == false ? prior! : context.originalText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .withinWindow
        root.state = .active
        view = root

        let header = makeHeader()
        let footer = makeFooter()
        root.addSubview(header)
        root.addSubview(composeContainer)
        root.addSubview(aiContainer)
        root.addSubview(footer)
        [header, composeContainer, aiContainer, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        buildComposeMode()
        buildAIMode()
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 58),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 74),

            composeContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            composeContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            composeContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            composeContainer.bottomAnchor.constraint(equalTo: footer.topAnchor),
            aiContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            aiContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            aiContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            aiContainer.bottomAnchor.constraint(equalTo: footer.topAnchor),
        ])
        selectMode(.compose, focus: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(composeTextView)
        composeTextView.setSelectedRange(NSRange(location: composeTextView.string.utf16.count, length: 0))
    }

    private func makeHeader() -> NSView {
        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active

        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .automatic
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.setWidth(116, forSegment: 0)
        modeControl.setWidth(126, forSegment: 1)
        modeControl.setEnabled(provider != .off, forSegment: 1)
        modeControl.toolTip = provider == .off
            ? "Enable a local AI engine in Personas to use conversational editing."
            : "Switch between direct editing and local AI"
        modeControl.setAccessibilityIdentifier("hush.editor.mode")
        modeControl.setAccessibilityLabel("Composer mode")
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(modeControl)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)

        NSLayoutConstraint.activate([
            modeControl.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            modeControl.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 5),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        return header
    }

    private func makeFooter() -> NSView {
        let footer = NSVisualEffectView()
        footer.material = .headerView
        footer.blendingMode = .withinWindow
        footer.state = .active

        let privacy = NSTextField(labelWithString: "Private on this Mac. Only the version you accept is inserted.")
        privacy.font = .systemFont(ofSize: 11.5)
        privacy.textColor = .secondaryLabelColor
        privacy.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(privacy)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(cancel)

        primaryButton.title = origin == .newDraft ? "Insert message" : "Accept changes"
        primaryButton.target = self
        primaryButton.action = #selector(acceptCurrentText)
        primaryButton.keyEquivalent = "\r"
        primaryButton.setAccessibilityIdentifier("hush.editor.accept")
        footer.addSubview(primaryButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            privacy.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 32),
            privacy.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -30),
            primaryButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -12),
            cancel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
    }

    private func buildComposeMode() {
        let destination = NSTextField(labelWithString: origin == .newDraft
            ? "New message in \(context.applicationName)"
            : "Editing in \(context.applicationName)")
        destination.font = .systemFont(ofSize: 12, weight: .medium)
        destination.textColor = .secondaryLabelColor
        destination.translatesAutoresizingMaskIntoConstraints = false
        composeContainer.addSubview(destination)

        let editorCard = makeCard()
        composeContainer.addSubview(editorCard)
        let cardTitle = NSTextField(labelWithString: origin == .newDraft ? "Draft" : "Current text")
        cardTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        composeWordCount.font = .systemFont(ofSize: 11.5, weight: .medium)
        composeWordCount.textColor = .secondaryLabelColor
        let cardHeader = NSStackView(views: [cardTitle, NSView(), composeWordCount])
        cardHeader.orientation = .horizontal
        cardHeader.alignment = .centerY
        cardHeader.translatesAutoresizingMaskIntoConstraints = false
        editorCard.addSubview(cardHeader)

        let editorScroll = NSScrollView()
        editorScroll.borderType = .noBorder
        editorScroll.hasVerticalScroller = true
        editorScroll.drawsBackground = false
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorCard.addSubview(editorScroll)
        composeTextView.string = context.originalText
        composeTextView.font = .systemFont(ofSize: 16)
        composeTextView.textContainerInset = NSSize(width: 16, height: 14)
        composeTextView.isRichText = false
        composeTextView.isAutomaticQuoteSubstitutionEnabled = false
        composeTextView.isAutomaticDashSubstitutionEnabled = false
        composeTextView.isAutomaticTextReplacementEnabled = false
        composeTextView.allowsUndo = true
        composeTextView.backgroundColor = .clear
        composeTextView.textColor = .textColor
        composeTextView.delegate = self
        composeTextView.setAccessibilityIdentifier("hush.editor.compose.text")
        editorScroll.documentView = composeTextView

        let cardFooter = NSView()
        cardFooter.translatesAutoresizingMaskIntoConstraints = false
        editorCard.addSubview(cardFooter)
        let saved = NSTextField(labelWithString: "Your current version is saved while this window is open.")
        saved.font = .systemFont(ofSize: 10.5)
        saved.textColor = .tertiaryLabelColor
        saved.translatesAutoresizingMaskIntoConstraints = false
        cardFooter.addSubview(saved)
        restoreButton.title = context.refinementSourceText == nil ? "Restore opening text" : "Restore original"
        restoreButton.bezelStyle = .inline
        restoreButton.isBordered = false
        restoreButton.contentTintColor = DesignTokens.brand500
        restoreButton.font = .systemFont(ofSize: 11.5, weight: .semibold)
        restoreButton.target = self
        restoreButton.action = #selector(restoreOriginal)
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        cardFooter.addSubview(restoreButton)

        openAIButton.title = "Edit with AI"
        openAIButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        openAIButton.imagePosition = .imageLeading
        openAIButton.bezelStyle = .rounded
        openAIButton.controlSize = .large
        openAIButton.target = self
        openAIButton.action = #selector(openAIEditing)
        openAIButton.isEnabled = provider != .off
        openAIButton.toolTip = provider == .off
            ? "Enable a local AI engine in Personas to edit conversationally."
            : "Open the private AI editor"
        openAIButton.setAccessibilityIdentifier("hush.editor.open-ai")
        openAIButton.translatesAutoresizingMaskIntoConstraints = false
        composeContainer.addSubview(openAIButton)

        editorCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            destination.topAnchor.constraint(equalTo: composeContainer.topAnchor, constant: 22),
            destination.leadingAnchor.constraint(equalTo: composeContainer.leadingAnchor, constant: 40),
            editorCard.topAnchor.constraint(equalTo: destination.bottomAnchor, constant: 14),
            editorCard.leadingAnchor.constraint(equalTo: composeContainer.leadingAnchor, constant: 40),
            editorCard.trailingAnchor.constraint(equalTo: composeContainer.trailingAnchor, constant: -40),
            editorCard.bottomAnchor.constraint(equalTo: openAIButton.topAnchor, constant: -16),
            cardHeader.topAnchor.constraint(equalTo: editorCard.topAnchor, constant: 15),
            cardHeader.leadingAnchor.constraint(equalTo: editorCard.leadingAnchor, constant: 18),
            cardHeader.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor, constant: -18),
            cardHeader.heightAnchor.constraint(equalToConstant: 24),
            editorScroll.topAnchor.constraint(equalTo: cardHeader.bottomAnchor, constant: 10),
            editorScroll.leadingAnchor.constraint(equalTo: editorCard.leadingAnchor, constant: 1),
            editorScroll.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor, constant: -1),
            editorScroll.bottomAnchor.constraint(equalTo: cardFooter.topAnchor),
            cardFooter.leadingAnchor.constraint(equalTo: editorCard.leadingAnchor),
            cardFooter.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor),
            cardFooter.bottomAnchor.constraint(equalTo: editorCard.bottomAnchor),
            cardFooter.heightAnchor.constraint(equalToConstant: 42),
            saved.leadingAnchor.constraint(equalTo: cardFooter.leadingAnchor, constant: 18),
            saved.centerYAnchor.constraint(equalTo: cardFooter.centerYAnchor),
            restoreButton.trailingAnchor.constraint(equalTo: cardFooter.trailingAnchor, constant: -16),
            restoreButton.centerYAnchor.constraint(equalTo: cardFooter.centerYAnchor),

            openAIButton.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor),
            openAIButton.bottomAnchor.constraint(equalTo: composeContainer.bottomAnchor, constant: -18),
        ])
        updateComposeMetadata()
    }

    private func buildAIMode() {
        let destination = NSTextField(labelWithString: "Editing in \(context.applicationName)")
        destination.font = .systemFont(ofSize: 12, weight: .medium)
        destination.textColor = .secondaryLabelColor
        destination.translatesAutoresizingMaskIntoConstraints = false
        aiContainer.addSubview(destination)

        chatScroll.borderType = .noBorder
        chatScroll.hasVerticalScroller = true
        chatScroll.drawsBackground = false
        chatScroll.translatesAutoresizingMaskIntoConstraints = false
        aiContainer.addSubview(chatScroll)
        chatDocument.translatesAutoresizingMaskIntoConstraints = false
        chatScroll.documentView = chatDocument
        chatStack.orientation = .vertical
        chatStack.alignment = .leading
        chatStack.spacing = 14
        chatStack.translatesAutoresizingMaskIntoConstraints = false
        chatDocument.addSubview(chatStack)

        let promptCard = makeCard(tint: NSColor.controlBackgroundColor.withAlphaComponent(0.92))
        aiContainer.addSubview(promptCard)
        instructionScroll.borderType = .noBorder
        instructionScroll.drawsBackground = false
        instructionScroll.hasVerticalScroller = false
        instructionScroll.translatesAutoresizingMaskIntoConstraints = false
        promptCard.addSubview(instructionScroll)
        instructionTextView.font = .systemFont(ofSize: 14)
        instructionTextView.textContainerInset = NSSize(width: 16, height: 19)
        instructionTextView.textContainer?.lineFragmentPadding = 0
        instructionTextView.backgroundColor = .clear
        instructionTextView.textColor = .textColor
        instructionTextView.isRichText = false
        instructionTextView.delegate = self
        instructionTextView.onSubmit = { [weak self] in self?.sendInstruction() }
        instructionTextView.setAccessibilityIdentifier("hush.editor.ai.prompt")
        instructionScroll.documentView = instructionTextView
        instructionPlaceholder.stringValue = "Message hush…"
        instructionPlaceholder.font = .systemFont(ofSize: 14)
        instructionPlaceholder.textColor = .placeholderTextColor
        instructionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        promptCard.addSubview(instructionPlaceholder)

        microphoneButton.title = ""
        microphoneButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice input")
        microphoneButton.imagePosition = .imageOnly
        microphoneButton.bezelStyle = .circular
        microphoneButton.controlSize = .large
        microphoneButton.target = self
        microphoneButton.action = #selector(toggleVoiceInput)
        microphoneButton.toolTip = "Dictate into this conversation"
        microphoneButton.setAccessibilityIdentifier("hush.editor.ai.microphone")

        voiceMeter.isHidden = true
        voiceMeter.translatesAutoresizingMaskIntoConstraints = false
        promptCard.addSubview(voiceMeter)
        voiceStatus.font = .systemFont(ofSize: 13, weight: .medium)
        voiceStatus.textColor = .secondaryLabelColor
        voiceStatus.isHidden = true
        voiceStatus.setAccessibilityIdentifier("hush.editor.ai.voice.status")
        voiceStatus.translatesAutoresizingMaskIntoConstraints = false
        promptCard.addSubview(voiceStatus)

        configureConversationModelPicker()
        let promptActions = NSStackView(views: [conversationModelPicker, microphoneButton])
        promptActions.orientation = .horizontal
        promptActions.alignment = .centerY
        promptActions.spacing = 6
        promptActions.translatesAutoresizingMaskIntoConstraints = false
        promptCard.addSubview(promptActions)

        promptCard.translatesAutoresizingMaskIntoConstraints = false
        let promptHeight = promptCard.heightAnchor.constraint(equalToConstant: 64)
        promptCardHeightConstraint = promptHeight
        NSLayoutConstraint.activate([
            destination.topAnchor.constraint(equalTo: aiContainer.topAnchor, constant: 18),
            destination.leadingAnchor.constraint(equalTo: aiContainer.leadingAnchor, constant: 40),

            chatScroll.topAnchor.constraint(equalTo: destination.bottomAnchor, constant: 14),
            chatScroll.leadingAnchor.constraint(equalTo: destination.leadingAnchor),
            chatScroll.trailingAnchor.constraint(equalTo: aiContainer.trailingAnchor, constant: -40),
            chatScroll.bottomAnchor.constraint(equalTo: promptCard.topAnchor, constant: -14),
            chatDocument.topAnchor.constraint(equalTo: chatScroll.contentView.topAnchor),
            chatDocument.leadingAnchor.constraint(equalTo: chatScroll.contentView.leadingAnchor),
            chatDocument.trailingAnchor.constraint(equalTo: chatScroll.contentView.trailingAnchor),
            chatDocument.widthAnchor.constraint(equalTo: chatScroll.contentView.widthAnchor),
            chatStack.topAnchor.constraint(equalTo: chatDocument.topAnchor, constant: 2),
            chatStack.leadingAnchor.constraint(equalTo: chatDocument.leadingAnchor),
            chatStack.trailingAnchor.constraint(equalTo: chatDocument.trailingAnchor),
            chatStack.bottomAnchor.constraint(equalTo: chatDocument.bottomAnchor, constant: -8),

            promptCard.leadingAnchor.constraint(equalTo: destination.leadingAnchor),
            promptCard.trailingAnchor.constraint(equalTo: chatScroll.trailingAnchor),
            promptCard.bottomAnchor.constraint(equalTo: aiContainer.bottomAnchor, constant: -14),
            promptHeight,
            microphoneButton.widthAnchor.constraint(equalToConstant: 34),
            microphoneButton.heightAnchor.constraint(equalToConstant: 34),
            instructionScroll.leadingAnchor.constraint(equalTo: promptCard.leadingAnchor, constant: 7),
            instructionScroll.topAnchor.constraint(equalTo: promptCard.topAnchor, constant: 4),
            instructionScroll.bottomAnchor.constraint(equalTo: promptCard.bottomAnchor, constant: -4),
            instructionScroll.trailingAnchor.constraint(equalTo: promptActions.leadingAnchor, constant: -8),
            // Keep the placeholder just after the caret, matching a native composer.
            instructionPlaceholder.leadingAnchor.constraint(equalTo: instructionScroll.leadingAnchor, constant: 18),
            instructionPlaceholder.centerYAnchor.constraint(equalTo: promptCard.centerYAnchor),
            voiceMeter.leadingAnchor.constraint(equalTo: promptCard.leadingAnchor, constant: 18),
            voiceMeter.centerYAnchor.constraint(equalTo: promptCard.centerYAnchor),
            voiceMeter.widthAnchor.constraint(equalToConstant: 180),
            voiceMeter.heightAnchor.constraint(equalToConstant: 38),
            voiceStatus.leadingAnchor.constraint(equalTo: voiceMeter.trailingAnchor, constant: 10),
            voiceStatus.centerYAnchor.constraint(equalTo: promptCard.centerYAnchor),
            voiceStatus.trailingAnchor.constraint(lessThanOrEqualTo: promptActions.leadingAnchor, constant: -12),
            promptActions.trailingAnchor.constraint(equalTo: promptCard.trailingAnchor, constant: -10),
            promptActions.centerYAnchor.constraint(equalTo: promptCard.centerYAnchor),
        ])
        rebuildConversation()
    }

    private func rebuildConversation() {
        chatStack.arrangedSubviews.forEach {
            chatStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        streamingArtifactText = nil
        streamingArtifactWordCount = nil
        streamingArtifactStatus = nil
        streamingArtifactCard = nil
        streamingThinkingButton = nil
        streamingAssistantWrapper = nil
        streamingAssistantMessage = nil
        streamingAssistantMetadata = nil

        if state.conversationTurns.isEmpty, pendingInstruction == nil {
            chatStack.addArrangedSubview(makeInitialConversationPrompt())
        }
        conversationModelPicker.isEnabled = state.conversationTurns.isEmpty && !isGenerating
        conversationModelPicker.toolTip = state.conversationTurns.isEmpty
            ? "Choose the on-device model for this conversation"
            : "The model stays fixed for this conversation"
        for turn in state.conversationTurns {
            chatStack.addArrangedSubview(makeUserBubble(turn.instruction))
            chatStack.addArrangedSubview(makeThinkingDisclosure(
                duration: turn.generationDuration,
                createdArtifact: turn.revisionID != nil,
                instruction: turn.instruction,
                accessibilityID: "hush.editor.ai.thinking.\(turn.id.uuidString)"
            ))
            chatStack.addArrangedSubview(makeAssistantStatus(
                turn.assistantMessage,
                metadata: responseMetadata(
                    tokens: turn.outputTokenCount,
                    duration: turn.generationDuration
                )
            ))
            if let revisionID = turn.revisionID,
               let revision = state.revision(id: revisionID) {
                chatStack.addArrangedSubview(makeArtifact(
                    title: "Updated text",
                    text: revision.text,
                    version: revision.number,
                    revisionID: revision.id,
                    isCurrent: revision.id == state.activeRevisionID && pendingInstruction == nil
                ))
            }
        }
        if let pendingInstruction {
            chatStack.addArrangedSubview(makeUserBubble(pendingInstruction))
            chatStack.addArrangedSubview(makeThinkingDisclosure(
                duration: nil,
                createdArtifact: false,
                instruction: pendingInstruction,
                accessibilityID: "hush.editor.ai.thinking.active",
                isActive: true
            ))
            chatStack.addArrangedSubview(makeStreamingAssistantMessage())
            chatStack.addArrangedSubview(makeStreamingArtifact())
        }
        for child in chatStack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: chatStack.widthAnchor).isActive = true
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chatDocument.layoutSubtreeIfNeeded()
            let bottom = max(0, self.chatDocument.bounds.height - self.chatScroll.contentView.bounds.height)
            self.chatScroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            self.chatScroll.reflectScrolledClipView(self.chatScroll.contentView)
        }
    }

    private func makeAssistantStatus(_ text: String, metadata: String? = nil) -> NSView {
        let wrapper = NSView()
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 15.5, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.setAccessibilityLabel(text)
        let row = NSStackView(views: [label])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 6
        if let metadata, !metadata.isEmpty {
            let detail = NSTextField(labelWithString: metadata)
            detail.font = .systemFont(ofSize: 10.5, weight: .medium)
            detail.textColor = .tertiaryLabelColor
            row.addArrangedSubview(detail)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
            row.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
        ])
        return wrapper
    }

    private func makeThinkingDisclosure(
        duration: TimeInterval?,
        createdArtifact: Bool,
        instruction: String,
        accessibilityID: String,
        isActive: Bool = false
    ) -> NSView {
        let wrapper = NSView()
        let title = if isActive {
            HushThinkingPresentation.LiveStage.reviewingContext.rawValue
        } else if let duration {
            "Thought for \(String(format: "%.1fs", duration))"
        } else {
            "Thought locally"
        }
        let button = NSButton(title: title, target: self, action: #selector(toggleThinkingDetails(_:)))
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityIdentifier(accessibilityID)
        button.setAccessibilityLabel(isActive ? "Reviewing context locally" : title)

        let detailText = isActive
            ? "Preparing a response locally. Private model reasoning stays hidden."
            : HushThinkingPresentation.completedSummary(
                instruction: instruction,
                createdArtifact: createdArtifact
            )
        let detail = NSTextField(wrappingLabelWithString: detailText)
        detail.identifier = NSUserInterfaceItemIdentifier("hush.editor.ai.thinking.detail")
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .tertiaryLabelColor
        detail.maximumNumberOfLines = 0
        detail.isHidden = true

        let content = NSStackView(views: [button, detail])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        if isActive { streamingThinkingButton = button }
        return wrapper
    }

    @objc private func toggleThinkingDetails(_ sender: NSButton) {
        guard let stack = sender.superview as? NSStackView,
              let detail = stack.arrangedSubviews.first(where: {
                  $0.identifier?.rawValue == "hush.editor.ai.thinking.detail"
              }) else { return }
        detail.isHidden.toggle()
        sender.image = NSImage(
            systemSymbolName: detail.isHidden ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        chatDocument.needsLayout = true
    }

    private func makeInitialConversationPrompt() -> NSView {
        let wrapper = NSView()
        wrapper.setAccessibilityIdentifier("hush.editor.ai.persona-setup")

        let title = NSTextField(labelWithString: "What would you like to do with this text?")
        title.font = .systemFont(ofSize: 15.5, weight: .regular)
        title.textColor = .labelColor
        title.maximumNumberOfLines = 0

        let rankedProfiles = PersonaSuggestionRanker.ranked(
            profiles: profiles,
            activeProfileID: activeProfile.id,
            applicationName: context.applicationName,
            bundleIdentifier: context.bundleIdentifier,
            websiteHost: context.websiteHost,
            text: state.currentText
        )
        let visibleProfiles = Array(rankedProfiles.prefix(3))
        let contextualDetail = PersonaSuggestionRanker.openingDetail(
            applicationName: context.applicationName,
            bundleIdentifier: context.bundleIdentifier,
            text: state.currentText,
            bestProfileName: visibleProfiles.first?.name,
            selectedProfileName: selectedConversationProfile?.name
        )
        let detail = NSTextField(labelWithString: contextualDetail)
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .tertiaryLabelColor
        detail.setAccessibilityIdentifier("hush.editor.ai.context")
        let heading = NSStackView(views: [title, detail])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 5
        heading.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(heading)

        let choices = NSStackView()
        choices.orientation = .horizontal
        choices.alignment = .centerY
        choices.spacing = 7
        choices.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(choices)

        choices.addArrangedSubview(makePersonaChoiceButton(
            title: "No persona",
            symbol: "text.quote",
            profileIndex: nil
        ))

        let visibleIDs = Set(visibleProfiles.map(\.id))
        for profile in visibleProfiles {
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { continue }
            choices.addArrangedSubview(makePersonaChoiceButton(
                title: profile.name,
                symbol: PersonaIconResolver.symbol(for: profile),
                profileIndex: index
            ))
        }

        let overflowProfiles = rankedProfiles.filter { !visibleIDs.contains($0.id) }
        if !overflowProfiles.isEmpty {
            let more = NSPopUpButton(frame: .zero, pullsDown: false)
            more.addItem(withTitle: "More…")
            more.item(at: 0)?.tag = 0
            for profile in overflowProfiles {
                guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { continue }
                more.addItem(withTitle: profile.name)
                more.lastItem?.tag = index + 1
            }
            if let selectedConversationProfile,
               let index = profiles.firstIndex(of: selectedConversationProfile),
               !visibleIDs.contains(selectedConversationProfile.id) {
                more.selectItem(withTag: index + 1)
            }
            more.bezelStyle = .rounded
            more.controlSize = .small
            more.target = self
            more.action = #selector(selectOverflowPersona(_:))
            more.setAccessibilityIdentifier("hush.editor.ai.persona-more")
            choices.addArrangedSubview(more)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
            heading.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            heading.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            choices.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            choices.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            choices.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -16),
            choices.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
        ])
        return wrapper
    }

    private func configureConversationModelPicker() {
        conversationModelMenu.removeAllItems()
        var providers = LLMProvider.engineCatalog.filter {
            $0 == provider || LLMRuntime.shared.isReady(provider: $0)
        }
        if !providers.contains(provider), provider != .off {
            providers.insert(provider, at: 0)
        }
        for candidate in providers {
            let item = NSMenuItem(
                title: candidate.displayName,
                action: #selector(selectConversationModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = LLMProvider.engineCatalog.firstIndex(of: candidate).map { $0 + 1 } ?? 0
            item.state = candidate == provider ? .on : .off
            item.image = NSImage(
                systemSymbolName: candidate == .appleIntelligence ? "apple.logo" : "cpu",
                accessibilityDescription: nil
            )
            conversationModelMenu.addItem(item)
        }
        conversationModelPicker.title = provider.displayName
        conversationModelPicker.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )
        conversationModelPicker.imagePosition = .imageTrailing
        conversationModelPicker.bezelStyle = .inline
        conversationModelPicker.isBordered = false
        conversationModelPicker.controlSize = .small
        conversationModelPicker.font = .systemFont(ofSize: 12, weight: .medium)
        conversationModelPicker.contentTintColor = .secondaryLabelColor
        conversationModelPicker.target = self
        conversationModelPicker.action = #selector(showConversationModelMenu(_:))
        conversationModelPicker.toolTip = "Choose the on-device model for this conversation"
        conversationModelPicker.setAccessibilityIdentifier("hush.editor.ai.model")
        conversationModelPicker.setAccessibilityLabel("AI model, \(provider.displayName)")
    }

    @objc private func showConversationModelMenu(_ sender: NSButton) {
        let selectedItem = conversationModelMenu.items.first(where: { $0.state == .on })
        conversationModelMenu.popUp(
            positioning: selectedItem,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 6),
            in: sender
        )
    }

    @objc private func selectConversationModel(_ sender: NSMenuItem) {
        let index = sender.tag - 1
        guard state.conversationTurns.isEmpty,
              !isGenerating,
              LLMProvider.engineCatalog.indices.contains(index) else { return }
        let selection = LLMProvider.engineCatalog[index]
        guard selection != provider else { return }
        provider = selection
        editingSession = editingSessionFactory(selection)
        editingSession.prewarm()
        configureConversationModelPicker()
    }

    private func makePersonaChoiceButton(
        title: String,
        symbol: String,
        profileIndex: Int?
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(selectConversationPersona(_:)))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setButtonType(.toggle)
        button.tag = profileIndex.map { $0 + 1 } ?? 0
        let isSelected = if let profileIndex {
            selectedConversationProfile?.id == profiles[profileIndex].id
        } else {
            selectedConversationProfile == nil
        }
        button.state = isSelected ? .on : .off
        button.contentTintColor = isSelected ? DesignTokens.brand500 : .secondaryLabelColor
        button.setAccessibilityIdentifier(
            profileIndex.map { "hush.editor.ai.persona.\(profiles[$0].id.uuidString)" }
                ?? "hush.editor.ai.persona.none"
        )
        return button
    }

    @objc private func selectConversationPersona(_ sender: NSButton) {
        selectedConversationProfile = sender.tag == 0 ? nil : profiles[sender.tag - 1]
        rebuildConversation()
    }

    @objc private func selectOverflowPersona(_ sender: NSPopUpButton) {
        guard sender.selectedTag() > 0 else { return }
        selectedConversationProfile = profiles[sender.selectedTag() - 1]
        rebuildConversation()
    }

    private func makeStreamingAssistantMessage() -> NSView {
        let wrapper = makeAssistantStatus("", metadata: "0.0s · On this Mac")
        wrapper.isHidden = true
        streamingAssistantWrapper = wrapper
        if let row = wrapper.subviews.compactMap({ $0 as? NSStackView }).first,
           let label = row.arrangedSubviews.compactMap({ $0 as? NSTextField }).first {
            streamingAssistantMessage = label
            streamingAssistantMetadata = row.arrangedSubviews
                .compactMap { $0 as? NSTextField }
                .dropFirst()
                .first
        }
        return wrapper
    }

    private func responseMetadata(tokens: Int?, duration: TimeInterval?) -> String? {
        var pieces: [String] = []
        if let tokens { pieces.append("\(tokens) tokens") }
        if let duration { pieces.append(String(format: "%.1fs", duration)) }
        if !pieces.isEmpty { pieces.append("On this Mac") }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private func makeArtifact(
        title: String,
        text: String,
        version: Int?,
        revisionID: UUID?,
        isCurrent: Bool
    ) -> NSView {
        let card = makeCard(
            tint: isCurrent ? DesignTokens.brand500.withAlphaComponent(0.055) : nil,
            borderColor: isCurrent
                ? DesignTokens.brand500.withAlphaComponent(0.34)
                : NSColor.separatorColor.withAlphaComponent(0.55)
        )

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12.5, weight: .semibold)
        let count = NSTextField(labelWithString: "\(wordCount(text)) words")
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        let header = NSStackView(views: [heading, count, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        if isCurrent {
            let current = badge("Current")
            header.addArrangedSubview(current)
        } else if let revisionID {
            let use = NSButton(title: "Use this", target: self, action: #selector(useRevision(_:)))
            use.bezelStyle = .inline
            use.isBordered = false
            use.contentTintColor = DesignTokens.brand500
            use.font = .systemFont(ofSize: 11.5, weight: .semibold)
            use.identifier = NSUserInterfaceItemIdentifier(revisionID.uuidString)
            header.addArrangedSubview(use)
        }
        let edit = NSButton(title: "Edit", target: self, action: #selector(editArtifact(_:)))
        edit.bezelStyle = .rounded
        edit.controlSize = .small
        edit.identifier = NSUserInterfaceItemIdentifier(revisionID?.uuidString ?? "source")
        header.addArrangedSubview(edit)
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        let body = NSTextField(wrappingLabelWithString: text.isEmpty ? "Start in Compose, then ask hush to shape it." : text)
        body.font = .systemFont(ofSize: 14)
        body.textColor = text.isEmpty ? .tertiaryLabelColor : .labelColor
        body.isSelectable = !text.isEmpty
        body.maximumNumberOfLines = 14
        body.setAccessibilityIdentifier(version.map { "hush.editor.ai.artifact.\($0)" } ?? "hush.editor.ai.artifact.source")
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)

        var footerText = version.map { "Version \($0)" } ?? "Source"
        if let revisionID,
           let revision = state.revisions.first(where: { $0.id == revisionID }) {
            if let tokens = revision.outputTokenCount {
                footerText += " · \(tokens) tokens"
            }
            if let duration = revision.generationDuration {
                footerText += " · \(String(format: "%.1fs", duration))"
            }
            footerText += " · On this Mac"
        }
        let footer = NSTextField(labelWithString: footerText)
        footer.font = .systemFont(ofSize: 10.5)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .right
        if let version {
            footer.setAccessibilityIdentifier("hush.editor.ai.artifact.\(version).metadata")
            footer.setAccessibilityLabel(footerText)
        }
        footer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            footer.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
        ])
        return card
    }

    private func makeStreamingArtifact() -> NSView {
        let card = makeCard(
            tint: DesignTokens.brand500.withAlphaComponent(0.045),
            borderColor: DesignTokens.brand500.withAlphaComponent(0.32)
        )

        let heading = NSTextField(labelWithString: "Updated text")
        heading.font = .systemFont(ofSize: 12.5, weight: .semibold)
        let count = NSTextField(labelWithString: "0 words")
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        let header = NSStackView(views: [heading, count, NSView(), badge("Writing")])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        let body = NSTextField(wrappingLabelWithString: pendingPartialText.isEmpty
            ? "Starting the local model…"
            : pendingPartialText)
        body.font = .systemFont(ofSize: 14)
        body.textColor = pendingPartialText.isEmpty ? .tertiaryLabelColor : .labelColor
        body.isSelectable = true
        body.maximumNumberOfLines = 14
        body.setAccessibilityIdentifier("hush.editor.ai.streaming-artifact")
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)

        let status = NSTextField(labelWithString: "Streaming locally · 0.0s")
        status.font = .systemFont(ofSize: 10.5, weight: .medium)
        status.textColor = DesignTokens.brand500
        status.setAccessibilityIdentifier("hush.editor.ai.streaming-status")
        status.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(status)

        streamingArtifactText = body
        streamingArtifactWordCount = count
        streamingArtifactStatus = status
        streamingArtifactCard = card
        card.isHidden = pendingPartialText.isEmpty
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            status.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
        ])
        return card
    }

    private func updateStreamingArtifact(with result: HushEditStreamResult) {
        pendingPartialText = result.text
        if !result.assistantMessage.isEmpty {
            generationHasAssistantOutput = true
            streamingAssistantWrapper?.isHidden = false
            streamingAssistantMessage?.stringValue = result.assistantMessage
        }
        if !result.text.isEmpty {
            generationHasArtifactOutput = true
            streamingArtifactCard?.isHidden = false
            streamingArtifactText?.stringValue = result.text
            streamingArtifactText?.textColor = .labelColor
            streamingArtifactWordCount?.stringValue = "\(wordCount(result.text)) words"
        }
        updateGenerationProgress()
        chatDocument.needsLayout = true
    }

    @objc private func updateGenerationProgress() {
        guard let generationStartedAt else { return }
        let elapsed = Date().timeIntervalSince(generationStartedAt)
        let stage = HushThinkingPresentation.liveStage(
            elapsed: elapsed,
            hasAssistantOutput: generationHasAssistantOutput,
            hasArtifactOutput: generationHasArtifactOutput
        )
        let dotCount = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0
            : Int(elapsed / 0.45).quotientAndRemainder(dividingBy: 4).remainder
        let animatedTitle = stage.rawValue + String(repeating: ".", count: dotCount)
        streamingThinkingButton?.title = animatedTitle
        streamingThinkingButton?.setAccessibilityLabel("\(stage.rawValue) locally")
        streamingAssistantMetadata?.stringValue = "\(String(format: "%.1fs", elapsed)) · On this Mac"
        streamingArtifactStatus?.stringValue = "Streaming locally · \(String(format: "%.1fs", elapsed))"
    }

    private func stopGenerationProgress() -> TimeInterval? {
        generationProgressTimer?.invalidate()
        generationProgressTimer = nil
        guard let generationStartedAt else { return nil }
        self.generationStartedAt = nil
        return Date().timeIntervalSince(generationStartedAt)
    }

    private func makeUserBubble(_ instruction: String) -> NSView {
        let wrapper = NSView()
        let bubble = HushSemanticSurfaceView(
            fillColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.11),
            cornerRadius: 16
        )
        let label = NSTextField(wrappingLabelWithString: instruction)
        label.font = .systemFont(ofSize: 13.5)
        bubble.addSubview(label)
        wrapper.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: wrapper.topAnchor),
            bubble.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor, multiplier: 0.64),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
        ])
        return wrapper
    }

    private func makeCard(
        tint: NSColor? = nil,
        borderColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.55)
    ) -> HushSemanticSurfaceView {
        let card = HushSemanticSurfaceView(
            fillColor: tint ?? .controlBackgroundColor,
            strokeColor: borderColor,
            cornerRadius: 16
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 27, weight: .bold)
        label.textColor = .labelColor
        return label
    }

    private func makeSubtitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func badge(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: "  \(text)  ")
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = DesignTokens.brand500
        label.wantsLayer = true
        label.layer?.backgroundColor = DesignTokens.brand500.withAlphaComponent(0.11).cgColor
        label.layer?.cornerRadius = 9
        label.alignment = .center
        return label
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        selectMode(sender.selectedSegment == 0 ? .compose : .editWithAI, focus: true)
    }

    @objc private func openAIEditing() { selectMode(.editWithAI, focus: true) }

    private func selectMode(_ mode: HushSelectionEditorState.Mode, focus: Bool) {
        state.selectMode(mode)
        modeControl.selectedSegment = mode.rawValue
        composeContainer.isHidden = mode != .compose
        aiContainer.isHidden = mode != .editWithAI
        primaryButton.title = mode == .compose
            ? (origin == .newDraft ? "Insert message" : "Accept changes")
            : "Accept current text"
        primaryButton.setAccessibilityLabel(primaryButton.title)
        modeControl.setAccessibilityValue(mode == .compose ? "Compose" : "Edit with AI")
        if mode == .editWithAI {
            editingSession.prewarm()
            rebuildConversation()
            if focus { view.window?.makeFirstResponder(instructionTextView) }
        } else if focus {
            setComposeText(state.currentText)
            view.window?.makeFirstResponder(composeTextView)
        }
    }

    func textDidChange(_ notification: Notification) {
        if notification.object as AnyObject? === composeTextView {
            guard !isApplyingProgrammaticChange else { return }
            state.setManualText(composeTextView.string)
            updateComposeMetadata()
        } else if notification.object as AnyObject? === instructionTextView {
            instructionPlaceholder.isHidden = !instructionTextView.string.isEmpty
            updatePromptHeight()
        }
    }

    @objc private func restoreOriginal() {
        state.restoreOriginal(to: restorationText)
        setComposeText(restorationText)
        rebuildConversation()
    }

    @objc private func useRevision(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        state.useRevision(id: id)
        setComposeText(state.currentText)
        rebuildConversation()
    }

    @objc private func editArtifact(_ sender: NSButton) {
        if let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) {
            state.useRevision(id: id)
        } else if let source = state.revisions.first?.inputText {
            state.setProgrammaticText(source)
        }
        setComposeText(state.currentText)
        selectMode(.compose, focus: true)
    }

    @objc private func toggleVoiceInput() {
        guard voiceInputState != .transcribing else { return }
        onToggleVoiceInput()
    }

    func updateVoiceInputState(_ state: HushEditorVoiceInputState) {
        voiceInputState = state
        switch state {
        case .idle:
            voiceMeter.setState(.listening, resetLevels: true)
            microphoneButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice input")
            microphoneButton.contentTintColor = .secondaryLabelColor
            microphoneButton.toolTip = "Dictate into this conversation"
            microphoneButton.setAccessibilityLabel("Start voice input")
            microphoneButton.isEnabled = true
            microphoneButton.isHidden = false
            voiceMeter.isHidden = true
            voiceStatus.isHidden = true
            voiceStatus.setAccessibilityLabel("")
            instructionTextView.isEditable = true
            instructionTextView.isHidden = false
            instructionPlaceholder.isHidden = !instructionTextView.string.isEmpty
        case .listening:
            voiceMeter.setState(.listening, resetLevels: true)
            microphoneButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")
            microphoneButton.contentTintColor = .systemRed
            microphoneButton.toolTip = "Stop and transcribe"
            microphoneButton.setAccessibilityLabel("Stop voice input")
            microphoneButton.isEnabled = true
            microphoneButton.isHidden = false
            voiceMeter.isHidden = false
            voiceStatus.stringValue = "Listening…"
            voiceStatus.setAccessibilityLabel("Listening…")
            voiceStatus.textColor = .labelColor
            voiceStatus.isHidden = false
            instructionTextView.isHidden = true
            instructionPlaceholder.isHidden = true
        case .transcribing:
            voiceMeter.setState(.processing)
            microphoneButton.setAccessibilityLabel("Transcribing voice input")
            microphoneButton.isEnabled = false
            microphoneButton.isHidden = true
            voiceMeter.isHidden = false
            voiceStatus.stringValue = "Transcribing on this Mac…"
            voiceStatus.setAccessibilityLabel("Transcribing on this Mac…")
            voiceStatus.textColor = .secondaryLabelColor
            voiceStatus.isHidden = false
            instructionTextView.isHidden = true
            instructionPlaceholder.isHidden = true
        case .error(let message):
            voiceMeter.setState(.listening, resetLevels: true)
            microphoneButton.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Voice input error")
            microphoneButton.contentTintColor = .systemRed
            microphoneButton.setAccessibilityLabel(message)
            microphoneButton.isEnabled = true
            microphoneButton.isHidden = false
            voiceMeter.isHidden = true
            voiceStatus.stringValue = message
            voiceStatus.setAccessibilityLabel(message)
            voiceStatus.textColor = .systemRed
            voiceStatus.isHidden = false
            instructionTextView.isHidden = true
            instructionPlaceholder.isHidden = true
        }
        updatePromptHeight()
    }

    func updateVoiceInputLevel(_ level: Float) {
        guard voiceInputState == .listening else { return }
        voiceMeter.level = level
    }

    private func sendInstruction() {
        let instruction = instructionTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = state.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !input.isEmpty, !isGenerating else {
            NSSound.beep()
            return
        }
        let persona = selectedConversationProfile
        isGenerating = true
        pendingInstruction = instruction
        pendingPartialText = ""
        generationHasAssistantOutput = false
        generationHasArtifactOutput = false
        generationStartedAt = Date()
        generationProgressTimer?.invalidate()
        generationProgressTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updateGenerationProgress),
            userInfo: nil,
            repeats: true
        )
        instructionTextView.string = ""
        instructionPlaceholder.isHidden = false
        rebuildConversation()
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await editingSession.edit(
                    text: input,
                    instruction: instruction,
                    persona: persona,
                    onPartialResult: { [weak self] partial in
                        guard let self, self.isGenerating else { return }
                        self.updateStreamingArtifact(with: partial)
                    }
                )
                let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let assistantMessage = result.assistantMessage
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty || !assistantMessage.isEmpty else {
                    throw HushEditorError.emptyResult
                }
                let duration = stopGenerationProgress()
                if output.isEmpty {
                    state.appendConversationResponse(
                        instruction: instruction,
                        assistantMessage: assistantMessage,
                        outputTokenCount: result.outputTokenCount,
                        generationDuration: duration
                    )
                } else {
                    state.appendRevision(
                        text: output,
                        instruction: instruction,
                        assistantMessage: assistantMessage.isEmpty
                            ? "I created a new version for you."
                            : assistantMessage,
                        inputText: input,
                        persona: persona,
                        providerName: provider.displayName,
                        outputTokenCount: result.outputTokenCount,
                        generationDuration: duration
                    )
                    setComposeText(output)
                }
                isGenerating = false
                pendingInstruction = nil
                pendingPartialText = ""
                generationHasAssistantOutput = false
                generationHasArtifactOutput = false
                rebuildConversation()
                textDidChange(Notification(name: NSText.didChangeNotification, object: instructionTextView))
                view.window?.makeFirstResponder(instructionTextView)
            } catch {
                guard !Task.isCancelled else { return }
                _ = stopGenerationProgress()
                isGenerating = false
                pendingInstruction = nil
                pendingPartialText = ""
                generationHasAssistantOutput = false
                generationHasArtifactOutput = false
                rebuildConversation()
                textDidChange(Notification(name: NSText.didChangeNotification, object: instructionTextView))
                presentEditorError(error)
            }
        }
    }

    func insertVoiceSegment(_ segment: ProofManifest.VoiceSegment) {
        let transcript = segment.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        if state.mode == .editWithAI {
            insertTranscript(transcript, into: instructionTextView)
            textDidChange(Notification(name: NSText.didChangeNotification, object: instructionTextView))
            view.window?.makeFirstResponder(instructionTextView)
            return
        }

        let current = state.currentText as NSString
        let selection = state.mode == .compose
            ? composeTextView.selectedRange()
            : NSRange(location: current.length, length: 0)
        var insertion = transcript
        if selection.location > 0 {
            let previous = current.substring(with: NSRange(location: selection.location - 1, length: 1))
            if previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
               !Self.leadingPunctuation.contains(insertion.first!) {
                insertion = " " + insertion
            }
        }
        if NSMaxRange(selection) < current.length {
            let next = current.substring(with: NSRange(location: NSMaxRange(selection), length: 1))
            if next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
               insertion.last?.isWhitespace == false {
                insertion += " "
            }
        }
        let changed = current.replacingCharacters(in: selection, with: insertion)
        state.replaceWithVoiceEditedText(changed)
        voiceSegments.append(segment)
        setComposeText(changed)
        rebuildConversation()
    }

    private func insertTranscript(_ transcript: String, into textView: NSTextView) {
        let current = textView.string as NSString
        let selection = textView.selectedRange()
        var insertion = transcript
        if selection.location > 0 {
            let previous = current.substring(with: NSRange(location: selection.location - 1, length: 1))
            if previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
               !Self.leadingPunctuation.contains(insertion.first!) {
                insertion = " " + insertion
            }
        }
        if NSMaxRange(selection) < current.length {
            let next = current.substring(with: NSRange(location: NSMaxRange(selection), length: 1))
            if next.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
               insertion.last?.isWhitespace == false {
                insertion += " "
            }
        }
        textView.string = current.replacingCharacters(in: selection, with: insertion)
        textView.setSelectedRange(NSRange(
            location: selection.location + (insertion as NSString).length,
            length: 0
        ))
    }

    private func setComposeText(_ text: String) {
        isApplyingProgrammaticChange = true
        composeTextView.string = text
        isApplyingProgrammaticChange = false
        updateComposeMetadata()
    }

    private func updateComposeMetadata() {
        composeWordCount.stringValue = "\(wordCount(composeTextView.string)) words"
        restoreButton.isHidden = composeTextView.string == restorationText && state.revisions.isEmpty
        primaryButton.isEnabled = !state.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updatePromptHeight() {
        guard let promptCardHeightConstraint else { return }
        let minimumHeight: CGFloat = 64
        let maximumHeight: CGFloat = 168
        let contentHeight: CGFloat
        if voiceInputState == .idle,
           let layoutManager = instructionTextView.layoutManager,
           let textContainer = instructionTextView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
                + instructionTextView.textContainerInset.height * 2
        } else {
            contentHeight = minimumHeight
        }
        let targetHeight = min(maximumHeight, max(minimumHeight, contentHeight))
        instructionScroll.hasVerticalScroller = contentHeight > maximumHeight
        guard abs(promptCardHeightConstraint.constant - targetHeight) > 0.5 else { return }
        promptCardHeightConstraint.constant = targetHeight
        aiContainer.layoutSubtreeIfNeeded()
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    @objc private func acceptCurrentText() {
        let output = state.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { NSSound.beep(); return }
        let revision = state.activeRevision
        complete(HushSelectionEdit(
            context: context,
            sourceText: revision?.inputText ?? (origin == .newDraft ? output : context.originalText),
            finalText: output,
            origin: origin,
            usedLocalAI: state.usedLocalAI,
            containsManualEdits: state.containsManualEdits,
            personaName: revision?.persona?.name,
            providerName: revision?.providerName,
            voiceSegments: voiceSegments,
            startedAt: startedAt,
            refinedAt: revision?.createdAt
        ))
    }

    @objc private func cancel() { complete(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        complete(nil)
        return false
    }

    private func complete(_ result: HushSelectionEdit?) {
        guard !isCompleting else { return }
        isCompleting = true
        generationTask?.cancel()
        generationTask = nil
        _ = stopGenerationProgress()
        onComplete(result)
    }

    private func presentEditorError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window { alert.beginSheetModal(for: window) }
    }

    private static let leadingPunctuation: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}"]
}

@MainActor
private final class HushInlineVoiceMeter: NSView {
    private let model = HUDModel()
    private lazy var hostingView = NSHostingView(rootView: HushInlineVoiceActivity(model: model))

    var level: Float = 0 {
        didSet { model.pushLevel(CGFloat(level)) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 38) }

    func setState(_ state: HushState, resetLevels: Bool = false) {
        if resetLevels { model.resetLevels() }
        model.state = state
    }
}

private struct HushInlineVoiceActivity: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HushWaveform(state: model.state, levels: model.levels)
            .frame(width: 180, height: 38)
            .accessibilityHidden(true)
    }
}

private final class HushPromptTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36,
           !modifiers.contains(.shift),
           !modifiers.contains(.option),
           !modifiers.contains(.control) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class HushFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private enum HushEditorError: LocalizedError {
    case emptyResult

    var errorDescription: String? {
        "The local AI returned an empty edit. Your current text has not changed."
    }
}

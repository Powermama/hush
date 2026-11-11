import AppKit
import Combine
import HushProvenance
import OSLog

enum OnboardingPracticeError: LocalizedError {
    case busy
    case modelNotReady
    case notRecording
    case tooShort

    var errorDescription: String? {
        switch self {
        case .busy: return "Finish the current recording first."
        case .modelNotReady: return "The local speech model is still preparing."
        case .notRecording: return "Start a practice recording first."
        case .tooShort: return "Speak for a little longer, then try again."
        }
    }
}

/// Top-level orchestrator. Holds the long-lived components and routes the
/// hotkey → record → transcribe → insert pipeline.
@MainActor
final class DictationCoordinator {

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "Coordinator")

    enum Phase: Equatable {
        case idle
        case modelLoading(progress: Double)
        case recording
        case transcribing
        /// Whisper has finished; the active profile's LLM is now rewriting the
        /// transcript. Only emitted when the active profile is `.llm`-mode —
        /// Raw-profile dictations skip straight from `.transcribing` to
        /// `.inserted` (zero new UX for default users; see PRD §14.7).
        case postProcessing(profileName: String)
        case inserted
        case error(String)
    }

    let hotkey = HotkeyManager()
    let composeHotkey = HotkeyManager()
    let personaHotkey = HotkeyManager()
    let recorder = AudioRecorder()
    let inserter = TextInserter()
    let hud = RecordingHUDController()
    let personaWheel = PersonaWheelController()
    private let selectionCapture = SelectionCapture()
    private let selectionEditor = HushSelectionEditor()
    private let verifiedMessages = VerifiedMessageCoordinator()
    private(set) var transcriber: Transcriber
    private let makeTranscriber: @MainActor (String) -> Transcriber
    /// Active post-processor. Swapped in `applySettings()` whenever the user
    /// picks a different profile. Default = `BasicPostProcessor()` so a fresh
    /// install (no stored `activeProfileID`) behaves exactly like pre-profile
    /// builds: trim + dedupe-spaces, no LLM.
    private(set) var postProcessor: TextPostProcessor = BasicPostProcessor()

    /// Published phase for UI subscribers (HUD, settings, menu bar).
    let phase = CurrentValueSubject<Phase, Never>(.idle)

    private var subscriptions = Set<AnyCancellable>()
    private(set) var isModelReady = false
    private(set) var loadedModelID: String?
    private var modelPreparationTask: Task<Void, Never>?
    private var preparingModelID: String?
    private var modelPreparationGeneration = 0
    private var isStarted = false
    var canManageModels: Bool {
        guard transcribeTask == nil, recorder.state != .recording, !onboardingPracticeActive,
              modelPreparationTask == nil, !selectionEditor.isPresented else { return false }
        return true
    }

    func releaseModelForRemoval(_ id: String) async throws {
        guard canManageModels else { throw AIModelLibrary.LibraryError.busy }
        guard loadedModelID == id else { return }
        isModelReady = false
        loadedModelID = nil
        await transcriber.unload()
    }
    private var transcribeTask: Task<Void, Never>?
    private var onboardingPracticeActive = false
    var onOnboardingPracticeLevel: ((Float) -> Void)?
    private var recordingEditorTarget: HushEditorRecordingTarget?
    private var recordingStartedAt: Date?
    private var recordingPersona: RecordingPersona?
    private var recordingAssistantSessionID: UUID?
    private var pendingAssistantSessionID: UUID?

    var onShowPersonaSettings: (() -> Void)?
    var onBeginAssistant: (() -> UUID?)?
    var onAssistantCaptureState: ((UUID, String) -> Void)?
    var onAssistantLevel: ((Float) -> Void)?
    var onAssistantTranscript: ((UUID, String) -> Void)?
    var canOpenAssistant: Bool { !onboardingPracticeActive && transcribeTask == nil && recorder.state != .recording }

    private struct RecordingPersona: Sendable {
        let profile: Profile
        let provider: LLMProvider
    }

    init(makeTranscriber: @escaping @MainActor (String) -> Transcriber = TranscriberFactory.make(for:)) {
        self.makeTranscriber = makeTranscriber
        self.transcriber = makeTranscriber(Settings.shared.modelID)
        bind()
    }

    private func bind() {
        Settings.shared.didChange
            .sink { [weak self] in self?.applySettings() }
            .store(in: &subscriptions)

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkey.onAssistantChord = { [weak self] in self?.openAssistantFromChord() }
        hotkey.onAssistantRelease = { [weak self] in self?.releaseAssistantChord() }
        composeHotkey.onPress = { [weak self] in self?.composeWithHush() }
        personaHotkey.onPress = { [weak self] in self?.togglePersonaSelector() }
        selectionEditor.onToggleVoiceInput = { [weak self] in self?.toggleComposerVoiceInput() }

        // Audio level updates flow straight to the HUD — they're a per-buffer
        // signal (10–40 Hz) that no other subscriber consumes. Re-emitting them
        // through `phase` made the menu-bar controller re-render its icon /
        // tooltip at audio rate for nothing. The HUD waveform itself is the
        // only meaningful consumer; it gates by its own `.live` style internally.
        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            if self.recordingAssistantSessionID != nil {
                self.onAssistantLevel?(level)
            } else if self.recordingEditorTarget != nil {
                self.selectionEditor.updateVoiceInputLevel(level)
            } else {
                self.hud.update(level: level)
            }
            if self.onboardingPracticeActive {
                self.onOnboardingPracticeLevel?(level)
            }
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        applySettings()
        hotkey.start()
        composeHotkey.start()
        personaHotkey.start()
        Task { await prepareModelInBackground() }
    }

    func stop() {
        isStarted = false
        hotkey.stop()
        composeHotkey.stop()
        personaHotkey.stop()
        personaWheel.hide()
        if onboardingPracticeActive {
            _ = recorder.stop()
            onboardingPracticeActive = false
        }
        onOnboardingPracticeLevel = nil
        transcribeTask?.cancel()
        transcribeTask = nil
        modelPreparationGeneration += 1
        modelPreparationTask?.cancel()
        modelPreparationTask = nil
        preparingModelID = nil
        isModelReady = false
        loadedModelID = nil
        recordingEditorTarget = nil
        recordingStartedAt = nil
        recordingPersona = nil
        recordingAssistantSessionID = nil
    }

    func prepareVerifiedMessages() async throws {
        try await verifiedMessages.prepareRegistration()
    }

    /// Records a private practice clip for onboarding without inserting text,
    /// creating history, or publishing a proof. The same recorder and local
    /// speech model used by normal dictation are exercised so the tutorial is
    /// representative of the product rather than a decorative demo.
    func beginOnboardingPractice() throws {
        guard transcribeTask == nil, recorder.state != .recording else {
            throw OnboardingPracticeError.busy
        }
        guard isModelReady else { throw OnboardingPracticeError.modelNotReady }
        try recorder.start()
        onboardingPracticeActive = true
        hud.show(state: .recording)
    }

    func finishOnboardingPractice() async throws -> String {
        guard onboardingPracticeActive, recorder.state == .recording else {
            throw OnboardingPracticeError.notRecording
        }
        onboardingPracticeActive = false
        let samples = recorder.stop()
        hud.show(state: .transcribing)
        let duration = Double(samples.count) / AudioRecorder.targetSampleRate
        guard duration >= 0.4 else {
            hud.hide()
            throw OnboardingPracticeError.tooShort
        }

        do {
            guard let raw = try await transcriber.transcribe(
                samples: samples,
                language: Settings.shared.language,
                fallbackCount: Settings.shared.transcriptionQuality.fallbackCount
            ) else {
                throw TranscriberError.empty
            }
            let result = try await BasicPostProcessor().process(raw, language: Settings.shared.language)
            hud.hide()
            return result
        } catch {
            hud.hide()
            throw error
        }
    }

    func cancelOnboardingPractice() {
        guard onboardingPracticeActive else { return }
        _ = recorder.stop()
        onboardingPracticeActive = false
        hud.hide()
    }

    func editSelectionWithHush(sourceApplication: NSRunningApplication? = nil) {
        openHushEditor(sourceApplication: sourceApplication)
    }

    func composeWithHush() {
        openHushEditor()
    }

    private func openHushEditor(sourceApplication: NSRunningApplication? = nil) {
        guard recorder.state != .recording else {
            hud.flash(message: "Finish dictation first")
            return
        }
        let context = selectionCapture.resolveEditorContext(
            recentActivities: ActivityStore.shared.history,
            sourceApplication: sourceApplication
        )
        Task { await presentSelectionEditor(context: context) }
    }

    private func presentSelectionEditor(context: HushSelectionContext) async {
        guard let edit = await selectionEditor.present(
            context: context,
            language: Settings.shared.language,
            provider: Settings.shared.llmProvider,
            profiles: Settings.shared.profiles,
            activeProfile: Settings.shared.activeProfile,
            origin: context.origin
        ) else { return }

        let signingHUDTask: Task<Void, Never>? = if Settings.shared.verifiedMessagesEnabled,
                                                    Settings.shared.showHUD {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.hud.show(state: .signing)
            }
        } else {
            nil
        }
        let proofOrigin: VerifiedMessageDraft.Origin = switch edit.origin {
        case .newDraft: .newDraft
        case .recentHushOutput: .recentHushOutput
        }
        let verifiedText = await verifiedMessages.textWithProof(for: VerifiedMessageDraft(
            origin: proofOrigin,
            samples: [],
            rawText: edit.sourceText,
            finalText: edit.finalText,
            language: Settings.shared.language,
            modelID: "hush-editor",
            modelName: "hush Editor",
            personaName: edit.personaName,
            providerName: edit.providerName,
            destinationBundleIdentifier: context.bundleIdentifier,
            destinationApplicationName: context.applicationName,
            destinationIsSecureField: context.isSecureField,
            destinationWebsiteHost: context.websiteHost,
            destinationIsBrowserAddressOrSearchField: context.isBrowserAddressOrSearchField,
            containsManualEdits: edit.containsManualEdits,
            voiceSegments: edit.voiceSegments,
            parentProofId: context.parentProofId,
            parentProofCommitment: context.parentProofCommitment,
            parentProvenanceEvents: context.parentProvenanceEvents,
            composerStartedAt: edit.startedAt,
            refinedAt: edit.refinedAt
        ))
        signingHUDTask?.cancel()

        let destinationIsSafe = await selectionCapture.prepareDestination(context)
        let outcome = inserter.insert(
            verifiedText.insertionContent,
            automatically: destinationIsSafe
        )
        let destinationName: String
        let destinationBundleIdentifier: String?
        switch outcome {
        case .insertedAutomatically:
            destinationName = context.applicationName
            destinationBundleIdentifier = context.bundleIdentifier
        case .copiedToClipboard, .missingAccessibilityPermission:
            destinationName = "Clipboard"
            destinationBundleIdentifier = nil
        }
        ActivityStore.shared.recordEditorOutput(
            text: edit.finalText,
            appName: destinationName,
            appBundleIdentifier: destinationBundleIdentifier,
            personaName: edit.personaName,
            providerName: edit.providerName,
            copiedToClipboard: outcome != .insertedAutomatically,
            proofId: verifiedText.proofId,
            proofCommitment: verifiedText.proofCommitment,
            provenanceEvents: verifiedText.provenanceEvents,
            sourceText: edit.sourceText
        )

        if let warning = verifiedText.publicationWarning {
            hud.flash(message: warning)
            return
        }
        if outcome == .insertedAutomatically,
           let suppression = verifiedText.destinationSuppression,
           shouldShowSuppressionNotice(
            suppression,
            destinationBundleIdentifier: context.bundleIdentifier
           ) {
            hud.flash(message: suppression.notice)
            return
        }
        switch outcome {
        case .insertedAutomatically:
            hud.show(state: .inserted(
                words: edit.finalText.split { $0.isWhitespace }.count,
                app: context.applicationName,
                verified: verifiedText.isVerified
            ))
            hud.hideAfter(seconds: 1.9)
        case .copiedToClipboard:
            hud.flash(message: destinationIsSafe ? "Message copied" : "Source changed - message copied")
        case .missingAccessibilityPermission:
            hud.flash(message: "Edited text copied - enable Accessibility to replace")
        }
    }

    private func applySettings() {
        hotkey.update(combo: Settings.shared.hotkey)
        composeHotkey.update(combo: Settings.shared.composeHotkey)
        personaHotkey.update(combo: Settings.shared.personaHotkey)
        // Rebuild the post-processor whenever settings change - covers the
        // user switching profiles from the menu bar or editing a profile's
        // prompt in Settings. Cheap: `LLMPostProcessor.make` is a value-type
        // factory, no model loading happens here.
        if let profile = Settings.shared.activeDictationProfile {
            postProcessor = LLMPostProcessor.make(
                for: profile,
                provider: Settings.shared.llmProvider
            )
        } else {
            postProcessor = BasicPostProcessor()
        }
    }

    /// Translate raw Core Audio / AVFoundation errors into something a user can act on.
    /// AVAudioEngine surfaces OSStatus codes via `(com.apple.coreaudio.avfaudio error N.)`
    /// strings that are meaningless without a reference table.
    private static func friendlyAudioErrorMessage(for error: NSError) -> String {
        switch error.code {
        case -10868:
            // kAudioFormatUnsupportedFormatError — most often a transient route
            // change (BT pairing, another app releasing the mic). We already retry
            // once internally; reaching this branch means the second try also failed.
            return "Mic unavailable — try again"
        case -10851, -10877:
            // kAudioUnitErr_InvalidProperty / NoConnection — input device gone away.
            return "Mic disconnected"
        case -10863:
            // kAudioHardwareNotRunningError
            return "Audio system not ready — try again"
        default:
            return "Couldn't start recording"
        }
    }

    func prepareModelInBackground() async {
        let id = Settings.shared.modelID
        if isModelReady, loadedModelID == id {
            if case .modelLoading = phase.value { phase.send(.idle) }
            return
        }

        if let existing = modelPreparationTask, preparingModelID == id {
            await existing.value
            return
        }

        // WhisperKit's Hub downloader is not safe for overlapping writes. If the user
        // switches models while one is preparing, cancel and fully drain the old task
        // before touching either model or tokenizer cache again.
        if let existing = modelPreparationTask {
            modelPreparationGeneration += 1
            existing.cancel()
            await existing.value
            guard Settings.shared.modelID == id else { return }
        }

        modelPreparationGeneration += 1
        let generation = modelPreparationGeneration
        preparingModelID = id
        isModelReady = false
        loadedModelID = nil

        // A cancelled WhisperKit initializer may finish unwinding after cancellation.
        // A fresh backend prevents that obsolete instance from overwriting the model
        // selected by the user.
        let oldTranscriber = transcriber
        let candidate = makeTranscriber(id)
        transcriber = candidate
        await oldTranscriber.unload()

        Self.log.info("Preparing model \(id, privacy: .public)")
        phase.send(.modelLoading(progress: 0))

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await candidate.prepare(modelID: id) { [weak self] progress in
                    guard let self,
                          self.modelPreparationGeneration == generation,
                          Settings.shared.modelID == id else { return }
                    self.phase.send(.modelLoading(progress: progress))
                }
                try Task.checkCancellation()
                guard self.modelPreparationGeneration == generation,
                      Settings.shared.modelID == id else { return }
                self.isModelReady = true
                self.loadedModelID = id
                self.phase.send(.idle)
            } catch is CancellationError {
                Self.log.info("Cancelled obsolete model preparation for \(id, privacy: .public)")
            } catch {
                guard self.modelPreparationGeneration == generation,
                      Settings.shared.modelID == id else { return }
                self.isModelReady = false
                self.loadedModelID = nil
                Self.log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
                self.phase.send(.error(error.localizedDescription))
            }
        }
        modelPreparationTask = task
        await task.value
        if modelPreparationGeneration == generation {
            modelPreparationTask = nil
            preparingModelID = nil
        }
    }

    // MARK: Hotkey routing

    func togglePersonaSelector() {
        let personasAvailable = Settings.shared.llmProvider != .off
            && LLMRuntime.shared.isActiveProviderReady
        #if DEBUG
        let forceAvailable = ProcessInfo.processInfo.arguments.contains(
            "--persona-selector-ready-for-testing"
        )
        #else
        let forceAvailable = false
        #endif

        guard personasAvailable || forceAvailable else {
            personaWheel.hide()
            onShowPersonaSettings?()
            return
        }

        personaWheel.toggle(
            profiles: Settings.shared.profiles,
            activeProfileID: Settings.shared.activeProfileID,
            personaEnabled: Settings.shared.activeDictationProfile != nil,
            personasAvailable: true
        ) { [weak self] selection in
            switch selection {
            case .noPersona:
                Settings.shared.dictationPersonaEnabled = false
                self?.hud.flash(message: "No persona active")
            case .profile(let profile):
                Settings.shared.activeProfileID = profile.id
                self?.hud.flash(message: "\(profile.name) active")
            }
        }
    }

    private func hotkeyPressed() {
        switch Settings.shared.hotkeyMode {
        case .pushToTalk:
            beginRecording()
        case .toggle:
            if recorder.state == .recording {
                endRecordingAndTranscribe()
            } else {
                beginRecording()
            }
        }
        // PRD §8.2 — the hotkey press IS the LLM prefetch signal. Kick off
        // Qwen weight-loading in the background while the user starts
        // speaking, so for any dictation longer than ~3 s the cold-load
        // cost (3–6 s) is fully absorbed by the recording window. No-op
        // when the provider is `.off`, or when Apple Intelligence is picked
        // (system manages its own warm state), or when Qwen weights aren't
        // downloaded yet.
        if Settings.shared.activeDictationProfile != nil {
            LLMRuntime.shared.preload()
        }
    }

    private func openAssistantFromChord() {
        guard !onboardingPracticeActive, transcribeTask == nil, recordingEditorTarget == nil else {
            hud.flash(message: "Finish the current recording first")
            return
        }
        // Fn can arrive before Control. Discard that partial dictation before
        // opening the assistant; releasing the chord must never paste it.
        if recorder.state == .recording {
            _ = recorder.stop()
            recordingStartedAt = nil
            recordingPersona = nil
            recordingAssistantSessionID = nil
            hud.hide()
            phase.send(.idle)
        }
        guard let id = onBeginAssistant?() else { return }
        pendingAssistantSessionID = id
        beginRecording(assistantID: id)
    }

    private func releaseAssistantChord() {
        if recordingAssistantSessionID != nil, recorder.state == .recording { endRecordingAndTranscribe() }
        else if let id = pendingAssistantSessionID {
            onAssistantCaptureState?(id, "Hold ⌃ Fn when the microphone is ready.")
        }
        pendingAssistantSessionID = nil
    }

    func toggleAssistantRecording() {
        if recordingAssistantSessionID != nil, recorder.state == .recording {
            releaseAssistantChord()
        } else { openAssistantFromChord() }
    }

    func cancelAssistantRecording() {
        pendingAssistantSessionID = nil
        guard recordingAssistantSessionID != nil else { return }
        if recorder.state == .recording { _ = recorder.stop() }
        recordingAssistantSessionID = nil
        recordingStartedAt = nil
        recordingPersona = nil
        hud.hide()
        phase.send(.idle)
    }

    private func hotkeyReleased() {
        guard Settings.shared.hotkeyMode == .pushToTalk else { return }
        // Read the recorder's own state — the phase may not have caught up yet on a very
        // quick tap (the engine takes a few ms to deliver the first level update).
        if recorder.state == .recording { endRecordingAndTranscribe() }
    }

    // MARK: Recording

    private func toggleComposerVoiceInput() {
        guard let target = selectionEditor.focusedRecordingTarget else { return }
        if recorder.state == .recording {
            guard recordingEditorTarget?.sessionID == target.sessionID else {
                showComposerVoiceError("Another recording is already active")
                return
            }
            endRecordingAndTranscribe()
        } else {
            beginRecording()
        }
    }

    private func showComposerVoiceError(_ message: String) {
        selectionEditor.updateVoiceInputState(.error(message))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard let self, self.recorder.state != .recording else { return }
            self.selectionEditor.updateVoiceInputState(.idle)
        }
    }

    private func beginRecording(assistantID: UUID? = nil) {
        guard !AIModelLibrary.shared.isRemoving else { return }
        let editorTarget = assistantID == nil ? selectionEditor.focusedRecordingTarget : nil
        let assistantTarget = assistantID
        if let assistantID, pendingAssistantSessionID != assistantID { return }
        guard !onboardingPracticeActive else {
            if editorTarget != nil { showComposerVoiceError("Finish the practice recording first") }
            else { hud.flash(message: "Finish the practice recording first") }
            return
        }
        guard transcribeTask == nil else {
            if editorTarget != nil { showComposerVoiceError("Finishing the previous recording") }
            else { hud.flash(message: "Finishing previous recording") }
            return
        }
        guard isModelReady else {
            if let assistantTarget { onAssistantCaptureState?(assistantTarget, "Parakeet is still loading. Try again when it is ready.") }
            else if editorTarget != nil { showComposerVoiceError("The speech model is still loading") }
            else { hud.flash(message: "Loading model…") }
            return
        }
        guard PermissionsChecker.microphoneStatus == .authorized else {
            Task {
                let ok = await PermissionsChecker.requestMicrophone()
                if ok { self.beginRecording(assistantID: assistantID) }
                else if let assistantTarget { self.onAssistantCaptureState?(assistantTarget, "Allow microphone access in System Settings to talk to Hush.") }
                else if editorTarget != nil { self.showComposerVoiceError("Microphone access is required") }
                else { self.hud.flash(message: "Microphone access denied") }
            }
            return
        }

        do {
            recordingEditorTarget = editorTarget
            recordingAssistantSessionID = assistantTarget
            if recordingEditorTarget == nil, assistantTarget == nil,
               let profile = Settings.shared.activeDictationProfile {
                recordingPersona = RecordingPersona(
                    profile: profile,
                    provider: Settings.shared.llmProvider
                )
            } else {
                recordingPersona = nil
            }
            try recorder.start()
            recordingStartedAt = Date()
            // Go straight to "Listening" — the first audible buffer typically arrives
            // <100 ms after `engine.start()` on built-in / wired mics, and showing an
            // intermediate "Connecting…" state for that window felt sluggish next to
            // tools like the original Whisper. On Bluetooth (SCO) the user may lose
            // ~200–400 ms of leading speech while the voice profile is being set up,
            // but that's the same trade-off every other dictation app makes.
            phase.send(.recording)
            if let assistantTarget {
                hud.hide()
                onAssistantCaptureState?(assistantTarget, "listening")
            } else if editorTarget != nil {
                hud.hide()
                selectionEditor.updateVoiceInputState(.listening)
            } else if Settings.shared.showHUD {
                hud.show(state: .recording)
            }
        } catch {
            recordingEditorTarget = nil
            recordingAssistantSessionID = nil
            recordingStartedAt = nil
            recordingPersona = nil
            let nsError = error as NSError
            Self.log.error("recorder.start failed: code=\(nsError.code) domain=\(nsError.domain, privacy: .public) desc=\(error.localizedDescription, privacy: .public)")
            let friendly = Self.friendlyAudioErrorMessage(for: nsError)
            phase.send(.error(friendly))
            if let assistantTarget {
                onAssistantCaptureState?(assistantTarget, friendly)
            } else if editorTarget != nil {
                showComposerVoiceError(friendly)
            } else {
                hud.show(state: .error(friendly))
                hud.hideAfter(seconds: 1.9)
            }
            phase.send(.idle)
        }
    }

    private func endRecordingAndTranscribe() {
        let captureStartedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil
        let samples = recorder.stop()
        let editorTarget = recordingEditorTarget
        recordingEditorTarget = nil
        let assistantTarget = recordingAssistantSessionID
        recordingAssistantSessionID = nil
        let persona = recordingPersona
        recordingPersona = nil
        let durationSec = Double(samples.count) / AudioRecorder.targetSampleRate
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        Self.log.info("endRecording: \(samples.count) samples (\(String(format: "%.2f", durationSec))s)")

        // Whisper needs a real chunk of audio to detect speech reliably. A 100 ms tap on
        // the hotkey produces under that, and the model returns empty — surface a hint
        // instead of "Silence" so the user knows to hold longer.
        if durationSec < 0.4 {
            phase.send(.error("Hold longer"))
            if let assistantTarget {
                onAssistantCaptureState?(assistantTarget, "Hold ⌃ Fn while you speak, then release.")
            } else if editorTarget != nil {
                showComposerVoiceError("Keep speaking a little longer")
            } else {
                hud.show(state: .error("Hold the hotkey while you speak"))
                hud.hideAfter(seconds: 1.9)
            }
            phase.send(.idle)
            return
        }

        let language = Settings.shared.language
        let fallbackCount = Settings.shared.transcriptionQuality.fallbackCount
        phase.send(.transcribing)
        if let assistantTarget {
            onAssistantCaptureState?(assistantTarget, "transcribing")
        } else if editorTarget != nil {
            selectionEditor.updateVoiceInputState(.transcribing)
        } else if Settings.shared.showHUD {
            hud.show(state: .transcribing)
        }

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            await self.runTranscription(
                samples: samples,
                language: language,
                fallbackCount: fallbackCount,
                pipelineStart: pipelineStart,
                captureStartedAt: captureStartedAt,
                editorTarget: editorTarget,
                assistantTarget: assistantTarget,
                persona: persona
            )
            self.transcribeTask = nil
        }
    }

    private func runTranscription(samples: [Float], language: String,
                                   fallbackCount: Int,
                                   pipelineStart: CFAbsoluteTime,
                                   captureStartedAt: Date,
                                   editorTarget: HushEditorRecordingTarget?,
                                   assistantTarget: UUID?,
                                   persona: RecordingPersona?) async {
        do {
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            guard let raw = try await transcriber.transcribe(samples: samples, language: language, fallbackCount: fallbackCount) else {
                Self.log.notice("Transcribe returned empty for \(samples.count) samples (lang=\(language, privacy: .public))")
                phase.send(.error("No speech detected"))
                if let assistantTarget {
                    onAssistantCaptureState?(assistantTarget, "I didn't hear speech. Hold ⌃ Fn and try again.")
                } else if editorTarget != nil {
                    showComposerVoiceError("No speech detected")
                } else {
                    hud.show(state: .error("No speech detected"))
                    hud.hideAfter(seconds: 1.9)
                }
                phase.send(.idle)
                return
            }
            let transcribeSec = CFAbsoluteTimeGetCurrent() - transcribeStart
            if let assistantTarget {
                // Bound command input never enters the insertion, persona, history,
                // or Verified Messages pipelines. A closed session discards it.
                onAssistantTranscript?(assistantTarget, raw)
                hud.hide()
                phase.send(.idle)
                return
            }
            Self.log.info("Transcribe ok: \"\(raw, privacy: .public)\"")

            if let editorTarget {
                await completeComposerVoiceSegment(
                    rawText: raw,
                    samples: samples,
                    language: language,
                    captureStartedAt: captureStartedAt,
                    target: editorTarget
                )
                return
            }

            // Only emit the new `.postProcessing` phase when an AI provider
            // is on. Users with `llmProvider == .off` see exactly the same
            // phase sequence as before — `.transcribing → .inserted`. This
            // is the load-bearing invariant from PRD §14.7: zero new UX for
            // the default user.
            let profile = persona?.profile
            let provider = persona?.provider ?? .off
            let llmActive = profile != nil
            let postStart = CFAbsoluteTimeGetCurrent()
            if let profile {
                phase.send(.postProcessing(profileName: profile.name))
                if Settings.shared.showHUD {
                    hud.show(state: .polishing(
                        profileName: profile.name,
                        providerName: provider.displayName
                    ))
                }
            }
            let processed: String
            var completionWarningMessage: String?
            do {
                if let profile {
                    processed = try await LLMPostProcessor.make(
                        for: profile,
                        provider: provider
                    ).process(raw, language: language)
                } else {
                    processed = try await BasicPostProcessor().process(raw, language: language)
                }
            } catch let llmError as LLMPostProcessor.Error {
                // Graceful degradation: paste the raw transcript and stash a
                // user-visible message we'll surface AFTER the paste lands,
                // so the user sees what happened instead of a confusing
                // "Inserted" with mysteriously-unmodified text.
                Self.log.notice("Post-process failed (\(String(describing: llmError), privacy: .public)) — pasting raw.")
                processed = (try? await BasicPostProcessor().process(raw, language: language)) ?? raw
                completionWarningMessage = llmError.errorDescription
            } catch {
                Self.log.error("Post-process failed: \(error.localizedDescription, privacy: .public)")
                processed = (try? await BasicPostProcessor().process(raw, language: language)) ?? raw
            }
            let postSec = CFAbsoluteTimeGetCurrent() - postStart

            let words = processed.split { $0.isWhitespace }.count
            let frontApplication = NSWorkspace.shared.frontmostApplication
            let frontApp = frontApplication?.localizedName
            let destinationContext = FocusedDestinationInspector.context(for: frontApplication)

            let signingHUDTask: Task<Void, Never>? = if Settings.shared.verifiedMessagesEnabled,
                                                        Settings.shared.showHUD {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    self?.hud.show(state: .signing)
                }
            } else {
                nil
            }
            let verifiedText = await verifiedMessages.textWithProof(for: VerifiedMessageDraft(
                origin: .voice,
                samples: samples,
                rawText: raw,
                finalText: processed,
                language: language,
                modelID: Settings.shared.modelID,
                modelName: ModelInfo.info(for: Settings.shared.modelID)?.displayName
                    ?? ModelInfo.deriveDisplayName(from: Settings.shared.modelID),
                personaName: profile?.name,
                providerName: llmActive ? provider.displayName : nil,
                destinationBundleIdentifier: frontApplication?.bundleIdentifier,
                destinationApplicationName: frontApp,
                destinationIsSecureField: destinationContext.isSecureField,
                destinationWebsiteHost: destinationContext.websiteHost,
                destinationIsBrowserAddressOrSearchField:
                    destinationContext.isBrowserAddressOrSearchField,
                containsManualEdits: false,
                captureStartedAt: captureStartedAt
            ))
            signingHUDTask?.cancel()
            if let warning = verifiedText.publicationWarning {
                completionWarningMessage = warning
            }
            let insertStart = CFAbsoluteTimeGetCurrent()
            let outcome = inserter.insert(verifiedText.insertionContent)
            let insertSec = CFAbsoluteTimeGetCurrent() - insertStart
            let recentDestination: String
            switch outcome {
            case .insertedAutomatically:
                recentDestination = frontApp ?? "App"
            case .copiedToClipboard, .missingAccessibilityPermission:
                recentDestination = "Clipboard"
            }
            let totalSec = CFAbsoluteTimeGetCurrent() - pipelineStart
            let audioSec = Double(samples.count) / AudioRecorder.targetSampleRate
            ActivityStore.shared.record(
                text: processed,
                appName: recentDestination,
                appBundleIdentifier: outcome == .insertedAutomatically
                    ? frontApplication?.bundleIdentifier
                    : nil,
                duration: audioSec,
                modelID: Settings.shared.modelID,
                modelName: ModelInfo.info(for: Settings.shared.modelID)?.displayName
                    ?? ModelInfo.deriveDisplayName(from: Settings.shared.modelID),
                personaName: profile?.name,
                providerName: llmActive ? provider.displayName : nil,
                copiedToClipboard: outcome != .insertedAutomatically,
                proofId: verifiedText.proofId,
                proofCommitment: verifiedText.proofCommitment,
                provenanceEvents: verifiedText.provenanceEvents,
                sourceText: raw
            )
            // Single-line summary at `.notice` so it shows in Xcode console and
            // Console.app by default (no need to enable "Info messages").
            Self.log.notice("⏱️ pipeline: total=\(totalSec, format: .fixed(precision: 2))s (transcribe=\(transcribeSec, format: .fixed(precision: 2))s · post=\(postSec, format: .fixed(precision: 2))s · insert=\(insertSec, format: .fixed(precision: 2))s) for \(audioSec, format: .fixed(precision: 2))s audio")

            switch outcome {
            case .insertedAutomatically:
                phase.send(.inserted)
                // If the LLM post-process bailed, the paste went through with
                // the raw transcript — surface a clear, single-line notice
                // instead of the normal "Inserted in <App>" state so the user
                // understands why the output wasn't rewritten. Same trick
                // used elsewhere in the codebase via `hud.flash`.
                if let msg = completionWarningMessage {
                    hud.show(state: .error(msg))
                } else if let suppression = verifiedText.destinationSuppression,
                          shouldShowSuppressionNotice(
                            suppression,
                            destinationBundleIdentifier: frontApplication?.bundleIdentifier
                          ) {
                    hud.flash(message: suppression.notice)
                } else {
                    hud.show(state: .inserted(
                        words: words,
                        app: frontApp,
                        verified: verifiedText.isVerified
                    ))
                }
            case .copiedToClipboard:
                phase.send(.inserted)
                if let msg = completionWarningMessage {
                    hud.show(state: .error(msg))
                } else {
                    hud.show(state: .copiedToClipboard(verified: verifiedText.isVerified))
                }
            case .missingAccessibilityPermission:
                phase.send(.inserted)
                hud.show(state: .needsAccessibility)
            }
            hud.hideAfter(seconds: completionWarningMessage == nil ? 1.9 : 2.6)
            phase.send(.idle)
        } catch {
            Self.log.error("Transcribe failed: \(error.localizedDescription, privacy: .public)")
            phase.send(.error(error.localizedDescription))
            if let assistantTarget {
                onAssistantCaptureState?(assistantTarget, error.localizedDescription)
            } else if editorTarget != nil {
                showComposerVoiceError(error.localizedDescription)
            } else {
                hud.show(state: .error(error.localizedDescription))
                hud.hideAfter(seconds: 1.5)
            }
            phase.send(.idle)
        }
    }

    private func shouldShowSuppressionNotice(
        _ suppression: VerifiedMessageDestinationSuppression,
        destinationBundleIdentifier: String?
    ) -> Bool {
        let identifier: String
        if let destinationBundleIdentifier {
            identifier = destinationBundleIdentifier.lowercased()
        } else {
            identifier = switch suppression {
            case .secureField: "secure-field"
            case .browserAddressOrSearch: "browser-address-or-search"
            case .website(let host): "website:\(host.lowercased())"
            case .terminal(let applicationName), .exception(let applicationName):
                "application:\(applicationName.lowercased())"
            }
        }
        return Settings.shared.shouldShowVerifiedMessageSuppressionNotice(for: identifier)
    }

    private func completeComposerVoiceSegment(
        rawText: String,
        samples: [Float],
        language: String,
        captureStartedAt: Date,
        target: HushEditorRecordingTarget
    ) async {
        let transcript = (try? await BasicPostProcessor().process(rawText, language: language))
            ?? rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Double(samples.count) / AudioRecorder.targetSampleRate
        let modelID = Settings.shared.modelID
        let modelName = ModelInfo.info(for: modelID)?.displayName
            ?? ModelInfo.deriveDisplayName(from: modelID)
        let segment = ProofManifest.VoiceSegment(
            id: UUID().uuidString.lowercased(),
            capturedAt: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                .format(captureStartedAt),
            durationMs: Int(duration * 1_000),
            sampleRate: Int(AudioRecorder.targetSampleRate),
            audioSha256: ProofAudioHasher.hash(
                samples: samples,
                sampleRate: Int(AudioRecorder.targetSampleRate)
            ),
            transcript: transcript,
            modelId: modelID,
            modelDisplayName: modelName,
            language: language
        )

        if selectionEditor.insertVoiceSegment(segment, intoSession: target.sessionID) {
            ActivityStore.shared.recordComposerVoiceSegment(
                text: transcript,
                duration: duration,
                destinationName: target.applicationName,
                destinationBundleIdentifier: target.bundleIdentifier
            )
            phase.send(.inserted)
            selectionEditor.updateVoiceInputState(.idle)
        } else {
            _ = inserter.insert(
                TextInsertionContent(plainText: transcript),
                automatically: false
            )
            phase.send(.inserted)
            hud.flash(message: "Composer closed - transcript copied")
        }
        phase.send(.idle)
    }
}

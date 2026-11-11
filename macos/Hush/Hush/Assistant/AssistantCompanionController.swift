import AppKit
import Combine
import SwiftUI

@MainActor
final class AssistantCompanionController: NSObject, ObservableObject {
    enum Phase { case ready, listening, transcribing, thinking, speaking, review, acting, stopped }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var status = "Hold ⌃ Fn and tell me what you need." {
        didSet { if status != oldValue { stageStartedAt = Date() } }
    }
    @Published private(set) var stageStartedAt = Date()
    @Published private(set) var response = ""
    @Published private(set) var spokenText = ""
    @Published private(set) var sourceName = "Your Mac"
    @Published private(set) var voiceStatus = "Kokoro · English · On this Mac"
    @Published private(set) var level: Float = 0
    @Published private(set) var pending: CoworkerReply?
    @Published var expanded = false
    @Published private(set) var waitingForInput = false
    @Published var voiceEnabled: Bool
    var onSettings: (() -> Void)?
    var onMicrophone: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    private(set) var recordingTurnID: UUID?
    private(set) var history: [CoworkerTurn] = []
    private var context: CoworkerContext?
    private var pendingContext: CoworkerContext?
    private var sourceApplication: NSRunningApplication?
    private let generator: any CoworkerGenerating
    private let voice: any CoworkerSpeaking
    private let contextCapture: (NSRunningApplication?) -> CoworkerContext
    private let usesLocalModels: Bool
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var operationID = UUID()
    private var conversationID = UUID()
    private var lastInteraction = Date.distantPast
    private var panel: CompanionPanel?
    private var pointer: NSPanel?
    private var highlight: NSPanel?
    private var anchor = NSPoint.zero
    private var pointerAnchor = NSPoint.zero
    private var mutationInFlight = false
    private var lastEdit: (any CoworkerRevisionDestination)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastRequest = ""
    private var progress: CoworkerProgress?
    private var subscriptions = Set<AnyCancellable>()
    #if DEBUG
    private var diagnosticTrace: CoworkerTrace?
    #endif

    init(generator: (any CoworkerGenerating)? = nil,
         voice: (any CoworkerSpeaking)? = nil,
         capture: ((NSRunningApplication?) -> CoworkerContext)? = nil,
         voiceEnabled: Bool? = nil) {
        self.generator = generator ?? CoworkerLocalGenerator()
        self.voice = voice ?? CoworkerVoice.shared
        self.contextCapture = capture ?? CoworkerContext.capture
        self.usesLocalModels = generator == nil
        self.voiceEnabled = voiceEnabled ?? (UserDefaults.standard.object(forKey: "assistant.voiceEnabled") as? Bool ?? true)
        super.init()
        self.voice.onStatus = { [weak self] text in self?.voiceStatus = text }
        self.voice.onUtterance = { [weak self] text in
            guard let self else { return }
            self.spokenText = text ?? ""
            #if DEBUG
            self.diagnosticTrace?.event(text == nil ? "voice.utterance_ended" : "voice.utterance_started",
                                       text.map { ["text": $0] } ?? [:])
            #endif
            if text != nil, self.phase == .speaking { self.status = "Speaking" }
        }
        objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.resize() }
        }.store(in: &subscriptions)
    }

    var canRecordRequest: Bool { !mutationInFlight }
    var isWorking: Bool { [.listening, .transcribing, .thinking, .speaking, .acting].contains(phase) }
    func progressCaption(at now: Date) -> String {
        guard isWorking else { return "Hush · hold ⌃ Fn to talk" }
        var parts = ["Hush", sourceName]
        if [.thinking, .acting].contains(phase), let progress, !progress.checkpoints.isEmpty {
            parts.append("Step \(progress.checkpoints.count + 1)")
        }
        let seconds = max(0, Int(now.timeIntervalSince(stageStartedAt)))
        if seconds >= 2, [.thinking, .acting, .transcribing].contains(phase) { parts.append("\(seconds)s") }
        return parts.joined(separator: " · ")
    }
    var needsAccessibility: Bool { !AXIsProcessTrusted() }

    func open(from application: NSRunningApplication?) {
        guard !mutationInFlight else { stop(endingConversation: false); return }
        interrupt()
        if Date().timeIntervalSince(lastInteraction) > 900 { clearConversation() }
        sourceApplication = application
        sourceName = application?.localizedName ?? "Your Mac"
        lastInteraction = Date()
        phase = .ready
        status = "Ready when you are"
        show()
        if usesLocalModels { LLMRuntime.shared.preload(provider: CoworkerModelSettings.provider) }
        if voiceEnabled { Task { [voice] in try? await voice.prepare() } }
    }

    func beginListening(from application: NSRunningApplication?) -> UUID? {
        guard canRecordRequest else { return nil }
        #if DEBUG
        diagnosticTrace?.finish("interrupted_by_new_turn")
        #endif
        open(from: application)
        let id = UUID()
        #if DEBUG
        diagnosticTrace = CoworkerDiagnostics.shared.begin(id: id, application: application)
        #endif
        recordingTurnID = id
        expanded = false
        waitingForInput = false
        panel?.orderOut(nil)
        if panel?.isKeyWindow == true { sourceApplication?.activate() }
        phase = .listening
        status = "Listening…"
        response = ""
        level = 0
        // Start microphone capture before reading another process's AX tree.
        // The source application is bound above; the surface never takes its focus.
        context = nil
        Task { @MainActor [weak self] in
            guard let self, self.recordingTurnID == id else { return }
            self.context = self.contextCapture(application)
            #if DEBUG
            self.recordDiagnosticContext(self.context)
            #endif
        }
        return id
    }

    func captureState(_ state: String, turnID: UUID) {
        guard recordingTurnID == turnID else { return }
        #if DEBUG
        diagnosticTrace?.event("audio.state", ["state": state])
        #endif
        if state == "transcribing" { phase = .transcribing; status = "Understanding…"; level = 0 }
        else if state != "listening" {
            recordingTurnID = nil
            phase = .ready
            status = "A moment, please"
            response = state
            waitingForInput = true
            expanded = true
            #if DEBUG
            diagnosticTrace?.finish("audio_failed")
            #endif
        }
    }

    func updateLevel(_ value: Float) { if phase == .listening { level = value } }

    func receiveTranscript(_ text: String, sessionID: UUID) {
        guard recordingTurnID == sessionID else { return }
        #if DEBUG
        diagnosticTrace?.artifact(.transcript, text: text)
        diagnosticTrace?.event("transcription.completed", ["characters": String(text.count)])
        #endif
        recordingTurnID = nil
        submit(text)
    }

    func submit(_ text: String, continuing: Bool = false) {
        guard !mutationInFlight else { return }
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, request.utf8.count <= 4_000 else { status = "Try a shorter request."; phase = .ready; return }
        let affirmation = request.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if !continuing, let pending, pending.action != .diagram,
           ["yes", "yes please", "do it", "insert it", "apply it", "go ahead", "ja", "mach das"].contains(affirmation) {
            pendingContext = context ?? contextCapture(sourceApplication)
            applyPending()
            return
        }
        interrupt()
        if !continuing { progress = CoworkerProgress(goal: request, conversation: history) }
        lastRequest = request
        lastInteraction = Date()
        pending = nil
        expanded = false
        waitingForInput = false
        phase = .thinking
        status = "Thinking…"
        response = ""
        let observation = (context ?? contextCapture(sourceApplication))
        context = observation
        var input = CoworkerRequest(text: request, observation: observation.observation,
                                   history: progress?.conversation ?? history, now: Date(), timeZone: .current)
        input.checkpoints = progress?.checkpoints ?? []
        #if DEBUG
        input.diagnosticTrace = diagnosticTrace
        diagnosticTrace?.beginStep(input.checkpoints.count)
        recordDiagnosticContext(observation)
        let trace = diagnosticTrace
        trace?.event("request.accepted", ["history_turns": String(history.count)])
        #endif
        let operation = operationID
        input.onStage = { [weak self] stage in
            guard let self, self.operationID == operation, self.phase == .thinking else { return }
            self.status = stage.rawValue
            if stage == .choosingAction { self.armDecisionDeadline(operation, seconds: 60) }
        }
        armDecisionDeadline(operation, seconds: 120)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try progress?.checkBudget()
                var input = input
                let candidate = continuing ? nil : CoworkerDirectCommand.reply(to: request)
                let direct = candidate.flatMap { reply in
                    input.observation.availableActions.map { $0.contains(reply.action) ? reply : nil } ?? reply
                }
                if direct == nil, generator.supportsImages, CoworkerScreenObserver.isUseful(request: request, observation: input.observation) {
                    #if DEBUG
                    trace?.event("screen.capture_started")
                    #endif
                    status = "Looking at this window"
                    input.screenshot = try await CoworkerScreenObserver.capture(observation)
                    #if DEBUG
                    trace?.artifact(.screenshot, input.screenshot!)
                    trace?.event("screen.capture_completed", ["bytes": String(input.screenshot?.count ?? 0)])
                    #endif
                    try Task.checkCancellation()
                    guard operationID == operation else { return }
                    status = "Thinking…"
                }
                let reply: CoworkerReply
                #if DEBUG
                trace?.encoded(.replay, CoworkerReplaySnapshot(input, provider: CoworkerModelSettings.provider))
                trace?.event("routing", ["route": direct == nil ? "model" : "native_command", "screenshot_used": String(input.screenshot != nil)])
                #endif
                if let direct { reply = direct }
                else { reply = try await generator.validatedResponse(to: input) }
                try Task.checkCancellation()
                guard operationID == operation else { return }
                if ![.answer, .diagram].contains(reply.action) {
                    try progress?.admit(reply, observation: input.observation)
                }
                #if DEBUG
                trace?.encoded(.reply, reply)
                trace?.event("reply.accepted", ["action": reply.action.rawValue, "target": String(reply.target)])
                #endif
                deadline?.cancel()
                response = reply.message
                let unverifiedCompletion = continuing && reply.action == .answer && !reply.message.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
                if unverifiedCompletion, let last = progress?.checkpoints.last {
                    // A model's terminal prose cannot certify that the remaining goal was
                    // completed. Report only a native receipt, then return control by voice.
                    response = "The last confirmed step was: \(last.result) What would you like next?"
                }
                pending = reply.action == .answer ? nil : reply
                pendingContext = observation
                status = "Listening to you"
                phase = pending == nil ? .ready : .review
                if continuing, let previous = history.popLast() {
                    history.append(.init(request: previous.request, response: response,
                        artifact: reply.content.isEmpty ? previous.artifact : String(reply.content.prefix(3_000)), outcome: previous.outcome))
                } else {
                    history.append(.init(request: request, response: response,
                        artifact: String(reply.content.prefix(3_000)), outcome: "Proposed only; no action performed."))
                }
                history = Array(history.suffix(4))
                if ![.answer, .diagram].contains(reply.action) {
                    applyPending()
                    return
                }
                waitingForInput = unverifiedCompletion || reply.message.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
                expanded = reply.action == .diagram || !voiceEnabled
                if voiceEnabled {
                    phase = .speaking
                    status = "Preparing voice"
                    #if DEBUG
                    trace?.event("voice.started")
                    #endif
                    do { try await voice.speak(response) }
                    catch is CancellationError { return }
                    catch {
                        voiceStatus = error.localizedDescription; expanded = true
                        #if DEBUG
                        trace?.failure("voice.failed", error)
                        #endif
                    }
                    guard operationID == operation else { return }
                    phase = pending == nil ? .ready : .review
                }
                status = waitingForInput ? "Your turn" : "Anything else?"
                scheduleHide()
                #if DEBUG
                trace?.finish(waitingForInput ? "awaiting_voice_answer" : "answered")
                #endif
            } catch {
                #if DEBUG
                trace?.failure("generation.failed", error)
                trace?.finish(Task.isCancelled ? "cancelled" : "failed")
                #endif
                guard operationID == operation, !Task.isCancelled else { return }
                deadline?.cancel()
                phase = .ready
                status = "Let's adjust that"
                response = error.localizedDescription
                waitingForInput = true
                expanded = true
                if voiceEnabled {
                    phase = .speaking
                    do { try await voice.speak(response) } catch { }
                    guard operationID == operation else { return }
                    phase = Task.isCancelled ? .stopped : .ready
                }
            }
        }
    }

    /// Cold tokenizer/grammar preparation is distinct from deciding an action. Once
    /// inference starts, use the tighter decision deadline. The whole run is still bounded.
    private func armDecisionDeadline(_ operation: UUID, seconds: Int) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.operationID == operation, self.phase == .thinking else { return }
            self.interrupt()
            self.phase = .ready
            self.status = "Let's try that again"
            self.response = "That took too long. Hold Control and Fn to try a shorter request."
            self.expanded = true
            self.waitingForInput = true
            #if DEBUG
            self.diagnosticTrace?.event("generation.timeout", ["limit_seconds": String(seconds)])
            self.diagnosticTrace?.finish("timed_out")
            #endif
        }
    }

    func applyPending() {
        guard let proposal = pending, let bound = pendingContext, !mutationInFlight else { return }
        interrupt()
        waitingForInput = false
        expanded = false
        phase = .acting
        status = actionLabel(proposal)
        response = ""
        pending = nil // An already-dispatched operation can never be clicked twice.
        if let frame = bound.textTarget?.targetFrame, [.write, .revise].contains(proposal.action) { point(at: frame) }
        else if let frame = bound.desktop?.frame(for: proposal), [.press, .clickHere, .fill, .submitSearch, .searchPage].contains(proposal.action) { point(at: frame) }
        let operation = operationID
        #if DEBUG
        let trace = diagnosticTrace
        trace?.event("action.queued", ["action": proposal.action.rawValue, "editable": String(bound.textTarget != nil)])
        #endif
        let conversation = conversationID
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // A visible pre-action cue gives Escape a chance to cancel before mutation.
                try await Task.sleep(for: .milliseconds(350))
                guard operationID == operation else { return }
                try progress?.checkBudget()
                #if DEBUG
                trace?.event("action.started", ["action": proposal.action.rawValue])
                #endif
                let outcome: String
                var verified = true
                var nextApplication = bound.application
                switch proposal.action {
                case .write, .revise:
                    guard var target = bound.textTarget else { throw bound.textTargetFailure }
                    if !(target is any CoworkerDocumentDestination),
                       proposal.action == .revise || lastEdit?.sharesEditor(with: target) == true {
                        guard let lastEdit else { throw CoworkerError.changedContext }
                        target = try lastEdit.revisionTarget(current: target)
                    }
                    let draft = Self.draft(proposal.content)
                    mutationInFlight = true
                    let result: AssistantInsertionResult
                    if let document = target as? any CoworkerDocumentDestination {
                        result = try await document.update(.init(body: draft, fields: proposal.subject.isEmpty ? [:] : [.title: proposal.subject]))
                    } else {
                        result = try await target.insert(draft)
                    }
                    #if DEBUG
                    trace?.event("insertion.result", ["result": String(describing: result)])
                    #endif
                    mutationInFlight = false
                    // Escape may have ended this conversation while native paste
                    // verification was finishing. Its receipt must not revive the binding.
                    if conversationID == conversation {
                        lastEdit = result == .verified ? target as? any CoworkerRevisionDestination : nil
                    }
                    outcome = result == .verified ? "Your draft is updated. I've checked the text." : "The paste was sent, but I couldn't verify it. Please check the field before retrying."
                    verified = result == .verified
                    if result == .unverified { waitingForInput = true; expanded = true }
                case .newTab, .press, .clickHere, .navigate, .fill, .submitSearch, .openPage, .searchPage:
                    guard let desktop = bound.desktop else { throw CoworkerError.missingContext }
                    mutationInFlight = true
                    let result = try await desktop.perform(proposal, request: lastRequest, onVerification: { [weak self] in
                        guard let self, self.operationID == operation, !Task.isCancelled else { return }
                        self.status = CoworkerStage.checkingResult.rawValue
                    })
                    outcome = result.message
                    #if DEBUG
                    trace?.event("browser.verification", result.diagnostics)
                    #endif
                    verified = result.canContinue
                    if let pid = result.applicationPID { nextApplication = NSRunningApplication(processIdentifier: pid) }
                    mutationInFlight = false
                case .search:
                    if let desktop = bound.desktop, desktop.availableActions.contains(.navigate) {
                        mutationInFlight = true
                        let result = try await desktop.perform(proposal, request: lastRequest, onVerification: { [weak self] in
                            self?.status = CoworkerStage.checkingResult.rawValue
                        })
                        mutationInFlight = false
                        outcome = result.message
                        #if DEBUG
                        trace?.event("browser.verification", result.diagnostics)
                        #endif
                        verified = result.canContinue
                        break
                    }
                    var components = URLComponents(string: "https://www.google.com/search")!
                    components.queryItems = [.init(name: "q", value: proposal.content)]
                    guard let url = components.url, NSWorkspace.shared.open(url) else { throw CoworkerError.invalidLink }
                    outcome = "Opened the search in your browser. Ask me to read the results once the page is ready."
                    verified = false
                case .openLink:
                    let url = try CoworkerLinkPolicy.resolve(proposal, request: lastRequest, observation: bound.observation)
                    if let frame = bound.targetFrames[proposal.target] { point(at: frame) }
                    guard NSWorkspace.shared.open(url) else { throw CoworkerError.invalidLink }
                    outcome = "Opened the link in your browser."
                    verified = false
                case .meeting:
                    try CoworkerCalendarDraft.open(proposal)
                    outcome = "Opened a calendar draft for review. No invitation has been sent."
                case .diagram, .answer:
                    outcome = ""
                }
                guard operationID == operation else { return }
                if !verified { waitingForInput = true }
                highlight?.orderOut(nil)
                let completionStatus = waitingForInput ? "Please check the result" : ([.write, .revise].contains(proposal.action) ? "Draft updated" : "Done")
                status = Task.isCancelled ? "Stopped" : completionStatus
                response = outcome
                #if DEBUG
                trace?.event("action.completed", ["outcome": outcome, "verified": String(verified), "more": String(proposal.more)])
                #endif
                phase = Task.isCancelled ? .stopped : .ready
                if conversationID == conversation {
                    progress?.record(proposal.action, result: outcome, verified: verified)
                    if let previous = history.popLast() {
                        let results = progress?.checkpoints.map(\.result).joined(separator: "\n") ?? outcome
                        history.append(.init(request: previous.request, response: previous.response, artifact: previous.artifact, outcome: results))
                    }
                }
                if proposal.more, verified, !Task.isCancelled {
                    // The same goal continues against a new binding. Never reuse native handles
                    // from the preceding screen, and never replay an uncertain mutation.
                    try progress?.checkBudget()
                    status = "Checking the next step"
                    context = contextCapture(nextApplication)
                    sourceApplication = nextApplication
                    sourceName = nextApplication?.localizedName ?? bound.observation.application
                    #if DEBUG
                    trace?.event("checkpoint.verified", ["step": String(progress?.checkpoints.count ?? 0), "action": proposal.action.rawValue])
                    #endif
                    submit(progress?.goal ?? lastRequest, continuing: true)
                    return
                }
                if voiceEnabled, !Task.isCancelled {
                    phase = .speaking
                    do { try await voice.speak(outcome) }
                    catch is CancellationError { }
                    catch {
                        voiceStatus = error.localizedDescription; expanded = true
                        #if DEBUG
                        trace?.failure("voice.failed", error)
                        #endif
                    }
                    guard operationID == operation else { return }
                    phase = Task.isCancelled ? .stopped : .ready
                    status = Task.isCancelled ? "Stopped" : completionStatus
                }
                scheduleHide()
                #if DEBUG
                trace?.finish(Task.isCancelled ? "stopped_after_dispatch" : "action_completed")
                #endif
            } catch {
                #if DEBUG
                trace?.failure("action.failed", error)
                trace?.event("destination.at_failure", CoworkerDiagnostics.binding(bound.application))
                trace?.finish(error is CancellationError ? "cancelled" : "failed")
                #endif
                guard operationID == operation else { return }
                let mayHaveEdited = mutationInFlight
                let cancelled = error is CancellationError || Task.isCancelled
                mutationInFlight = false
                highlight?.orderOut(nil)
                phase = cancelled ? .stopped : .ready
                status = cancelled ? "Stopped" : "Let's check the destination"
                response = cancelled
                    ? (mayHaveEdited ? "Stopped. An edit may already have completed; please check the draft." : "No new action was performed.")
                    : error.localizedDescription
                waitingForInput = !cancelled
                expanded = waitingForInput
                if voiceEnabled, !cancelled {
                    phase = .speaking
                    do { try await voice.speak(response) }
                    catch { /* The visible error remains available if speech fails. */ }
                    guard operationID == operation else { return }
                    phase = Task.isCancelled ? .stopped : .ready
                    status = Task.isCancelled ? "Stopped" : "Let's check the destination"
                }
                scheduleHide()
            }
        }
    }

    static func draft(_ text: String) -> AssistantProposal {
        .init(decision: .draft, message: "", blocks: text.components(separatedBy: "\n\n")
            .filter { !$0.isEmpty }.map { .init(kind: .paragraph, text: $0) })
    }

    func actionLabel(_ reply: CoworkerReply) -> String {
        switch reply.action {
        case .write: return "Writing your draft"
        case .revise: return "Refining your draft"
        case .newTab: return "Opening a new tab"
        case .openPage: return "Opening the page in a new tab"
        case .press: return "Pressing the control"
        case .clickHere: return "Clicking where you pointed"
        case .navigate: return "Opening the page"
        case .fill: return "Filling the field"
        case .submitSearch: return "Searching this page"
        case .searchPage: return "Searching this page"
        case .search: return "Opening search"
        case .openLink: return "Opening the link"
        case .meeting: return "Preparing a calendar draft"
        case .diagram: return "Diagram"
        case .answer: return ""
        }
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: "assistant.voiceEnabled")
        if !voiceEnabled {
            if phase == .speaking {
                interrupt()
                phase = .ready
                status = waitingForInput ? "Your turn" : "Anything else?"
            } else { voice.stop() }
            expanded = !response.isEmpty
        }
        else if !response.isEmpty {
            task = Task { [weak self] in
                guard let self else { return }
                do { try await voice.speak(response) } catch { voiceStatus = error.localizedDescription }
            }
        }
    }

    func selectModel(_ provider: LLMProvider) {
        guard !isWorking else { return }
        CoworkerModelSettings.provider = provider
        objectWillChange.send()
        LLMRuntime.shared.preload(provider: provider)
    }

    func stop(endingConversation: Bool = true) {
        #if DEBUG
        diagnosticTrace?.event("user.stop", ["mutation_in_flight": String(mutationInFlight), "phase": String(describing: phase)])
        if !mutationInFlight { diagnosticTrace?.finish("stopped") }
        #endif
        if endingConversation { clearConversation() }
        if phase == .stopped && !mutationInFlight { hideSurfaces(); return }
        onCancelRecording?()
        recordingTurnID = nil
        expanded = false
        waitingForInput = false
        pending = nil
        panel?.orderOut(nil)
        if mutationInFlight { task?.cancel(); voice.stop(); status = "Checking the last edit…"; return }
        interrupt()
        phase = .stopped
        status = "Stopped"
        scheduleHide()
    }

    func dismiss() {
        stop()
        hideSurfaces()
    }

    private func hideSurfaces() {
        hideTask?.cancel(); hideTask = nil
        followTask?.cancel(); followTask = nil
        panel?.orderOut(nil)
        pointer?.orderOut(nil)
        highlight?.orderOut(nil)
        // Fading the cursor does not end a conversation. Keep Escape available
        // until the user explicitly ends it, even while the surface is hidden.
        if history.isEmpty { removeMonitors() }
    }

    func newConversation() {
        stop()
        guard !mutationInFlight else { return }
        phase = .ready; status = "Ready when you are"
        show()
    }

    private func clearConversation() {
        conversationID = UUID()
        history = []
        lastEdit = nil
        pending = nil
        pendingContext = nil
        context = nil
        progress = nil
        lastRequest = ""
        lastInteraction = .distantPast
        response = ""
        spokenText = ""
        waitingForInput = false
        expanded = false
    }

    private func interrupt() {
        task?.cancel(); deadline?.cancel(); hideTask?.cancel()
        task = nil; deadline = nil; hideTask = nil
        voice.stop()
        highlight?.orderOut(nil)
        operationID = UUID()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !expanded else { return }
        let delay: Duration = phase == .stopped ? .seconds(1.8) : (waitingForInput ? .seconds(8) : .seconds(3))
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, [.ready, .stopped].contains(self.phase) else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                self.pointer?.animator().alphaValue = 0
                self.panel?.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            self.hideSurfaces()
        }
    }

    private func followMouse() {
        followTask?.cancel()
        followTask = Task { [weak self] in
            var previousMouse = NSEvent.mouseLocation
            var holdingControls = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
                guard let self, self.pointer?.isVisible == true else { return }
                // Hold the surface still while the user reaches its controls. A pinned
                // control that continuously runs away from the pointer cannot be clicked.
                let mouse = NSEvent.mouseLocation
                let moved = hypot(mouse.x - previousMouse.x, mouse.y - previousMouse.y) > 0.1
                if let frame = self.pointer?.frame {
                    if !frame.contains(mouse) { holdingControls = false }
                    else if moved { holdingControls = true }
                }
                previousMouse = mouse
                if holdingControls { continue }
                let weight: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.55
                let next = NSPoint(x: self.pointerAnchor.x + (mouse.x - self.pointerAnchor.x) * weight,
                                   y: self.pointerAnchor.y + (mouse.y - self.pointerAnchor.y) * weight)
                if hypot(next.x - self.pointerAnchor.x, next.y - self.pointerAnchor.y) > 0.25 {
                    self.showPointer(at: next, animated: false)
                }
            }
        }
    }

    private func show() {
        anchor = NSEvent.mouseLocation
        pointerAnchor = anchor
        if panel == nil {
            let panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            configure(panel)
            panel.setAccessibilityIdentifier("hush.companion.window")
            panel.contentView = CompanionHostingView(rootView: AnyView(CompanionDetailView(controller: self)))
            panel.onEscape = { [weak self] in self?.stop() }
            self.panel = panel
        }
        if pointer == nil {
            let pointer = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            configure(pointer)
            pointer.setAccessibilityIdentifier("hush.companion.cursor.window")
            pointer.contentView = CompanionHostingView(rootView: AnyView(CompanionCursorView(controller: self)))
            self.pointer = pointer
        }
        pointer?.alphaValue = 1
        panel?.alphaValue = 1
        showPointer(at: anchor, animated: false)
        resize()
        installMonitors()
        followMouse()
    }

    private func configure(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func resize() {
        guard let panel, let content = panel.contentView else { return }
        guard expanded || !spokenText.isEmpty else { panel.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.contains(pointerAnchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame.insetBy(dx: 12, dy: 12) else { return }
        let size = NSSize(width: 332, height: min(max(content.fittingSize.height, 80), visible.height - 80))
        let cursor = pointer?.frame ?? NSRect(origin: anchor, size: .zero)
        let x = min(max(cursor.minX + 26, visible.minX), visible.maxX - size.width)
        var y = cursor.minY - size.height + 4
        if y < visible.minY { y = cursor.maxY - 4 }
        panel.setFrame(NSRect(x: x, y: min(max(y, visible.minY), visible.maxY - size.height), width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    private func point(at frame: CGRect) {
        guard let desktop = NSScreen.screens.first else { return }
        let rect = NSRect(x: frame.minX, y: desktop.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        let cue = highlight ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(cue)
        cue.ignoresMouseEvents = true
        cue.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: DesignTokens.brand500).opacity(0.65), lineWidth: 2).padding(2))
        cue.setFrame(rect.insetBy(dx: -3, dy: -3), display: true)
        cue.orderFrontRegardless()
        highlight = cue
        // Keep Hush attached to the user's pointer; the outline identifies the real
        // destination without moving or hiding the user's cursor.
    }

    private func showPointer(at point: NSPoint, animated: Bool) {
        guard let pointer else { return }
        pointerAnchor = point
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame.insetBy(dx: 10, dy: 10) else { return }
        let size = NSSize(width: 300, height: 64)
        let rect = NSRect(x: min(max(point.x + 8, visible.minX), visible.maxX - size.width),
                          y: min(max(point.y - size.height, visible.minY), visible.maxY - size.height),
                          width: size.width, height: size.height)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                pointer.animator().setFrame(rect, display: true)
            }
        } else { pointer.setFrame(rect, display: true) }
        pointer.orderFrontRegardless()
        resize()
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != MailAssistantDestination.pasteEventMarker else { return }
            MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == 53 { self?.stop() }
                else if self?.phase == .acting || (self?.phase == .thinking && self?.progress?.checkpoints.isEmpty == false) {
                    self?.stop(endingConversation: false)
                }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.stop(); return nil }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }

    #if DEBUG
    private func recordDiagnosticContext(_ captured: CoworkerContext?) {
        guard let trace = diagnosticTrace, let captured else { return }
        trace.encoded(.context, captured.observation)
        var fields = CoworkerDiagnostics.binding(captured.application)
        fields["editable"] = String(captured.textTarget != nil)
        fields["text_access"] = captured.textTarget is CoworkerMailDraftTarget ? "mail_document" : (captured.textTarget as? CoworkerTextTarget)?.textAccessKind ?? "unavailable"
        if captured.textTarget == nil { fields["binding_failure"] = String(describing: captured.textTargetFailure) }
        fields["controls"] = String(captured.observation.elements.count)
        fields["visible_characters"] = String(captured.observation.visibleText.count)
        trace.event("context.captured", fields)
        (captured.textTarget as? CoworkerTextTarget)?.diagnosticTrace = trace
        (captured.textTarget as? CoworkerMailDraftTarget)?.diagnosticTrace = trace
    }
    #endif
}

// A concrete host avoids a Swift 6.3 optimizer crash in the synthesized deinit
// of a generic NSHostingView subclass, while preserving inactive-app clicks.
private final class CompanionHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class CompanionPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// AppKit first-click behavior is explicit: Escape must work while Safari/Notes
/// keeps keyboard focus, including when SwiftUI's host application is inactive.
private struct CompanionEscapeButton: NSViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> FirstClickButton {
        let button = FirstClickButton(title: "esc", target: context.coordinator, action: #selector(Coordinator.press))
        button.isBordered = false
        button.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.sendAction(on: .leftMouseDown)
        button.setAccessibilityIdentifier("hush.companion.stop")
        button.setAccessibilityLabel("Stop Hush")
        return button
    }
    func updateNSView(_ view: FirstClickButton, context: Context) { context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    final class FirstClickButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { false }
    }
}

/// The everyday surface: a cursor, a truthful state, and an always available stop.
private struct CompanionCursorView: View {
    @ObservedObject var controller: AssistantCompanionController
    private var brand: Color { Color(nsColor: DesignTokens.brand500) }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Button { controller.onMicrophone?() } label: {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(brand)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: 33, height: 37)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Talk to Hush · Control + Fn")
            .accessibilityLabel("Talk to Hush").accessibilityIdentifier("hush.companion.microphone")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                            if controller.phase == .listening {
                                HStack(spacing: 2) {
                                    ForEach(0..<3) { index in
                                        Capsule().fill(brand).frame(width: 2, height: 4 + CGFloat(controller.level) * CGFloat(index == 1 ? 12 : 7))
                                    }
                                }.frame(width: 12, height: 16).accessibilityHidden(true)
                            } else {
                                Circle().fill(controller.phase == .stopped ? Color.secondary : brand)
                                    .frame(width: 5, height: 5).accessibilityHidden(true)
                            }
                            Text(controller.status).font(.system(size: 12, weight: .medium))
                                .lineLimit(1).accessibilityIdentifier("hush.companion.status")
                    }
                    Rectangle().fill(.primary.opacity(0.10)).frame(width: 1, height: 13)
                    CompanionEscapeButton { controller.stop() }
                        .frame(width: 27, height: 20)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                        .help("Stop Hush; press again to dismiss")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.primary.opacity(0.09), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.09), radius: 5, y: 2)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(controller.progressCaption(at: context.date))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .lineLimit(1)
                    .accessibilityIdentifier("hush.companion.progress")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(5).frame(width: 300, height: 64, alignment: .topLeading)
        .accessibilityElement(children: .contain).accessibilityIdentifier("hush.companion.cursor")
        .contextMenu {
            if !controller.response.isEmpty {
                Button("Read last reply") { controller.expanded.toggle() }
            }
            Button(controller.voiceEnabled ? "Mute spoken replies" : "Enable spoken replies") { controller.toggleVoice() }
            Button("New conversation") { controller.newConversation() }
            Divider()
            Button("Hush settings") { controller.onSettings?() }
            Button("Dismiss Hush") { controller.dismiss() }
        }
    }
}

/// Read-only captions and requested visuals. All conversational input is voice.
private struct CompanionDetailView: View {
    @ObservedObject var controller: AssistantCompanionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !controller.spokenText.isEmpty {
                Text(controller.spokenText).font(.system(size: 13)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hush.companion.speech")
            } else if !controller.response.isEmpty && (controller.waitingForInput || controller.expanded) {
                Text(controller.response).font(.system(size: 13)).lineSpacing(3)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hush.companion.response")
            }
            if controller.expanded, let pending = controller.pending, pending.action == .diagram {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(pending.content.split(separator: "\n").prefix(6).enumerated()), id: \.offset) { index, label in
                        if index > 0 { Image(systemName: "arrow.down").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Text(String(label)).font(.system(size: 12)).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            if controller.spokenText.isEmpty {
                Text("Hold ⌃ Fn to answer · Esc to stop")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

        }
        .padding(16).frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.10), lineWidth: 0.5))
        .padding(6)
        .accessibilityElement(children: .contain).accessibilityIdentifier("hush.companion.surface")
    }
}

enum CoworkerCalendarDraft {
    static func contents(_ reply: CoworkerReply, id: UUID = UUID(), now: Date = Date()) throws -> String {
        guard let start = ISO8601DateFormatter().date(from: reply.start), reply.minutes > 0, reply.minutes <= 480 else {
            throw CoworkerError.invalidResponse
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let title = reply.content.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
        return ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Hush//Calendar Draft//EN", "BEGIN:VEVENT",
                "UID:\(id.uuidString)@hush.local", "DTSTAMP:\(formatter.string(from: now))",
                "DTSTART:\(formatter.string(from: start))", "DTEND:\(formatter.string(from: start.addingTimeInterval(Double(reply.minutes * 60))))",
                "SUMMARY:\(title)", "DESCRIPTION:Prepared by Hush. Review before adding. No invitations sent.",
                "END:VEVENT", "END:VCALENDAR", ""].joined(separator: "\r\n")
    }

    @MainActor static func open(_ reply: CoworkerReply) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hush-calendar-drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Meeting-\(UUID().uuidString).ics")
        try contents(reply).write(to: file, atomically: true, encoding: .utf8)
        guard NSWorkspace.shared.open(file) else { try? FileManager.default.removeItem(at: file); throw CoworkerError.invalidResponse }
        // Calendar needs time to consume the file; only this temporary draft is removed.
        Task { try? await Task.sleep(for: .seconds(300)); try? FileManager.default.removeItem(at: file) }
    }
}

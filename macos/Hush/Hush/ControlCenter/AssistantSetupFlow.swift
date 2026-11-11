import Foundation
import Combine

/// One resumable setup sequence. Rechecks each prerequisite, skips completed
/// work, and never treats a permission request as a permission grant.
@MainActor
final class AssistantSetupFlow {
    enum Step: String, CaseIterable, Sendable {
        case microphone, accessibility, screen, intelligence, transcription, voice
        var title: String {
            switch self {
            case .microphone: "Allow microphone access"
            case .accessibility: "Allow Accessibility in System Settings"
            case .screen: "Allow Screen Recording in System Settings"
            case .intelligence: "Preparing intelligence & vision"
            case .transcription: "Preparing listening"
            case .voice: "Preparing the local voice"
            }
        }
    }
    enum State: Equatable {
        case idle, working(Step), cancelling, complete, cancelled, failed(String)
    }
    struct Dependencies {
        var ready: (Step) -> Bool
        var perform: (Step) async throws -> Void
    }
    static let shared = AssistantSetupFlow(dependencies: .live)
    let changes = PassthroughSubject<Void, Never>()
    private(set) var state: State = .idle { didSet { changes.send() } }
    private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private let dependencies: Dependencies

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    #if DEBUG
    /// Native settings journey fixture. Never requests real permissions or
    /// downloads files. Production always uses the live dependencies.
    static func settingsJourneyFixture() -> AssistantSetupFlow {
        var completed = Set<Step>()
        return AssistantSetupFlow(dependencies: .init(ready: { completed.contains($0) }, perform: { step in
            try await Task.sleep(for: .milliseconds(700))
            completed.insert(step)
        }))
    }
    #endif
    var isReady: Bool { Step.allCases.allSatisfy(dependencies.ready) }
    func ready(_ step: Step) -> Bool { dependencies.ready(step) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [self] in
            defer { isRunning = false; task = nil; changes.send() }
            do {
                for step in Step.allCases {
                    try Task.checkCancellation()
                    guard !dependencies.ready(step) else { continue }
                    state = .working(step)
                    try await dependencies.perform(step)
                    try Task.checkCancellation()
                    guard dependencies.ready(step) else {
                        throw AIModelLibrary.LibraryError.failed("\(step.title) did not finish. Try setup again.")
                    }
                }
                guard isReady else { throw AIModelLibrary.LibraryError.failed("Setup changed while it was running. Please try again.") }
                state = .complete
            } catch is CancellationError { state = .cancelled }
            catch { state = Task.isCancelled ? .cancelled : .failed(error.localizedDescription) }
        }
        changes.send()
    }
    func cancel() {
        guard isRunning else { return }
        state = .cancelling
        task?.cancel()
    }

    /// The user can reopen the current settings pane without restarting setup.
    func openPermissionSettings() {
        guard case .working(let step) = state else { return }
        switch step {
        case .microphone: PermissionsChecker.openMicrophoneSettings()
        case .accessibility: PermissionsChecker.openAccessibilitySettings()
        case .screen: PermissionsChecker.openScreenRecordingSettings()
        default: break
        }
    }
}

extension AssistantSetupFlow.Dependencies {
    static var live: Self {
        Self(ready: { step in
            switch step {
            case .microphone: PermissionsChecker.microphoneStatus == .authorized
            case .accessibility: PermissionsChecker.isAccessibilityGranted
            case .screen: PermissionsChecker.isScreenRecordingGranted
            case .intelligence: LLMRuntime.shared.isReady(provider: CoworkerModelSettings.provider)
            case .transcription: ModelManager.isAvailable(Settings.shared.modelID)
            case .voice: CoworkerVoice.shared.setupState.value == .ready
            }
        }, perform: { step in
            switch step {
            case .microphone:
                if PermissionsChecker.microphoneStatus == .notDetermined { _ = await PermissionsChecker.requestMicrophone() }
                try Task.checkCancellation()
                if PermissionsChecker.microphoneStatus != .authorized { PermissionsChecker.openMicrophoneSettings() }
            case .accessibility: PermissionsChecker.openAccessibilitySettings()
            case .screen: PermissionsChecker.openScreenRecordingSettings()
            case .intelligence:
                try await AIModelLibrary.shared.install(.intelligence(CoworkerModelSettings.provider))
            case .transcription:
                try await AIModelLibrary.shared.install(.speech(Settings.shared.modelID))
                if let coordinator = AIModelLibrary.shared.coordinator { await coordinator.prepareModelInBackground() }
            case .voice: try await AIModelLibrary.shared.install(.voice)
            }
            // macOS switches are user-controlled. Keep this cancellable while
            // waiting, and continue automatically only once the OS grants access.
            if [.microphone, .accessibility, .screen].contains(step) {
                while !Self.live.ready(step) { try await Task.sleep(for: .milliseconds(400)) }
            }
        })
    }
}

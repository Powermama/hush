import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingViewController: NSViewController {
    let flow: OnboardingFlowModel

    init(coordinator: DictationCoordinator, onFinish: @escaping () -> Void) {
        flow = OnboardingFlowModel(coordinator: coordinator, onFinish: onFinish)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = ImmersiveOnboardingView(flow: flow)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 860)
        host.setAccessibilityElement(true)
        host.setAccessibilityIdentifier("hush.onboarding")
        view = host
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        flow.start()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        flow.stop()
    }
}

@MainActor
final class OnboardingFlowModel: ObservableObject {
    enum Page: Int, CaseIterable {
        case welcome
        case voice
        case personas
        case proof
    }

    enum VoiceState: Equatable {
        case idle
        case preparing
        case listening
        case processing
        case complete
        case failed(String)
    }

    enum ProofState: Equatable {
        case off
        case preparing
        case on
        case failed(String)
    }

    @Published var page: Page = .welcome
    @Published var headlineIndex = 0
    @Published var permissionSheetPresented = false
    @Published var microphoneReady = false
    @Published var accessibilityReady = false
    @Published var modelReady = false
    @Published var modelProgress = 0.0
    @Published var voiceState: VoiceState = .idle
    @Published var voiceLevel: Float = 0
    @Published var transcript = ""
    @Published var personasEnabled: Bool
    @Published var personaStatus: String?
    @Published var proofState: ProofState
    @Published var isCompletingSetup = false

    private weak var coordinator: DictationCoordinator?
    private let onFinish: () -> Void
    private let isUITest: Bool
    private var subscriptions = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var headlineTimer: Timer?
    private var voiceTimer: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var pendingVoiceStart = false
    private var started = false

    let headlinePhrases = [
        "does the typing.",
        "ships it with personas.",
        "proves its origin.",
    ]

    init(
        coordinator: DictationCoordinator?,
        onFinish: @escaping () -> Void,
        isUITest: Bool = ProcessInfo.processInfo.arguments.contains("--onboarding-ui-test")
    ) {
        self.coordinator = coordinator
        self.onFinish = onFinish
        self.isUITest = isUITest
        personasEnabled = Settings.shared.llmProvider != .off
        proofState = Settings.shared.verifiedMessagesEnabled ? .on : .off
        bindCoordinator()
        refreshSystemState()
    }

    var permissionsReady: Bool { microphoneReady && accessibilityReady }

    var primaryTitle: String {
        switch page {
        case .welcome, .voice: return "Continue"
        case .personas: return personasEnabled ? "Continue" : "Skip"
        case .proof: return "Set up hush"
        }
    }

    var primaryEnabled: Bool {
        guard !isCompletingSetup else { return false }
        switch page {
        case .voice: return voiceState == .complete
        case .proof: return proofState != .preparing
        default: return true
        }
    }

    var footerMessage: String {
        switch page {
        case .welcome:
            return "You’ll be ready in under a minute."
        case .voice:
            switch voiceState {
            case .idle: return "Permissions appear only after you tap Start."
            case .preparing: return "Preparing the private on-device speech model."
            case .listening: return "Speak naturally. Tap the microphone again to finish."
            case .processing: return "Transcribing locally on this Mac."
            case .complete: return "That’s it. hush is hearing you perfectly."
            case .failed: return "Nothing was inserted or saved. Try the phrase again."
            }
        case .personas:
            if let personaStatus { return personaStatus }
            return personasEnabled
                ? "Apple Intelligence is on. Your personas are ready."
                : "Everything runs on-device. Nothing goes to the cloud or to ChatGPT."
        case .proof:
            switch proofState {
            case .off: return "Proof is optional. Your private audio is never included."
            case .preparing: return "Protecting this Mac’s signing identity."
            case .on: return "Private proof links are ready."
            case .failed: return "Proof stayed off. You can enable it later in Settings."
            }
        }
    }

    var voiceLabel: String {
        switch voiceState {
        case .idle: return "Tap to begin"
        case .preparing: return "Preparing on-device model…"
        case .listening: return "Listening…"
        case .processing: return "Transcribing locally…"
        case .complete: return "Tap to try again"
        case .failed: return "Tap to try again"
        }
    }

    var proofEnabled: Bool { proofState == .on || proofState == .preparing }

    func start() {
        guard !started else { return }
        started = true
        refreshSystemState()
        coordinator?.onOnboardingPracticeLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.voiceLevel = level }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSystemState() }
        }
        headlineTimer = Timer.scheduledTimer(withTimeInterval: 3.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.page == .welcome else { return }
                withAnimation(.easeInOut(duration: 0.42)) {
                    self.headlineIndex = (self.headlineIndex + 1) % self.headlinePhrases.count
                }
            }
        }
        // AppDelegate starts the coordinator before presenting onboarding. Reusing that
        // single preparation avoids concurrent WhisperKit and tokenizer cache writes.
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        headlineTimer?.invalidate()
        headlineTimer = nil
        voiceTimer?.cancel()
        voiceTimer = nil
        completionTask?.cancel()
        completionTask = nil
        coordinator?.onOnboardingPracticeLevel = nil
        if voiceState == .listening { coordinator?.cancelOnboardingPractice() }
        started = false
    }

    func goForward() {
        guard primaryEnabled else { return }
        if let next = Page(rawValue: page.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.5)) { page = next }
        } else {
            completeSetup()
        }
    }

    private func completeSetup() {
        guard !isCompletingSetup else { return }
        withAnimation(.easeInOut(duration: 0.32)) {
            isCompletingSetup = true
        }
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self] in
            let delay = self?.isUITest == true ? 4_600 : 1_650
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.onFinish()
        }
    }

    func goBack() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        if voiceState == .listening {
            coordinator?.cancelOnboardingPractice()
            voiceState = .idle
        }
        withAnimation(.easeInOut(duration: 0.5)) { page = previous }
    }

    func selectPage(_ newPage: Page) {
        guard newPage.rawValue <= page.rawValue else { return }
        withAnimation(.easeInOut(duration: 0.5)) { page = newPage }
    }

    func tapMicrophone() {
        switch voiceState {
        case .listening:
            finishVoiceTest()
        case .processing, .preparing:
            return
        case .idle, .complete, .failed:
            transcript = ""
            if permissionsReady && modelReady {
                startVoiceTest()
            } else {
                permissionSheetPresented = true
            }
        }
    }

    func requestMicrophone() {
        guard !microphoneReady else { return }
        if isUITest {
            microphoneReady = true
            return
        }
        Task { [weak self] in
            _ = await PermissionsChecker.requestMicrophone()
            self?.refreshSystemState()
        }
    }

    func requestAccessibility() {
        guard !accessibilityReady else { return }
        if isUITest {
            accessibilityReady = true
            return
        }
        PermissionsChecker.promptAccessibilityIfNeeded()
        PermissionsChecker.openAccessibilitySettings()
    }

    func continueFromPermissions() {
        guard permissionsReady else { return }
        permissionSheetPresented = false
        if modelReady {
            startVoiceTest()
        } else {
            pendingVoiceStart = true
            voiceState = .preparing
        }
    }

    func closePermissionSheet() {
        permissionSheetPresented = false
    }

    func togglePersonas(_ enabled: Bool) {
        guard enabled else {
            Settings.shared.llmProvider = .off
            Settings.shared.dictationPersonaEnabled = false
            personasEnabled = false
            personaStatus = nil
            return
        }

        if isUITest {
            Settings.shared.llmProvider = .appleIntelligence
            Settings.shared.dictationPersonaEnabled = true
            personasEnabled = true
            personaStatus = nil
            return
        }

        LLMRuntime.shared.refreshAppleAvailability()
        switch LLMRuntime.shared.appleAvailability {
        case .available:
            Settings.shared.llmProvider = .appleIntelligence
            Settings.shared.dictationPersonaEnabled = true
            personasEnabled = true
            personaStatus = nil
        case .unavailable(let reason):
            personasEnabled = false
            personaStatus = reason
        case .unsupportedOS:
            personasEnabled = false
            personaStatus = "Apple Intelligence requires macOS 26 or later. You can add another local model in Settings."
        }
    }

    func toggleProof(_ enabled: Bool) {
        guard enabled else {
            Settings.shared.verifiedMessagesEnabled = false
            proofState = .off
            return
        }
        proofState = .preparing
        if isUITest && ProcessInfo.processInfo.arguments.contains("--onboarding-verified-test-ready") {
            Settings.shared.verifiedMessagesEnabled = true
            proofState = .on
            return
        }
        guard let coordinator else {
            proofState = .failed("Could not prepare proof links.")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await coordinator.prepareVerifiedMessages()
                Settings.shared.verifiedMessagesEnabled = true
                proofState = .on
            } catch {
                Settings.shared.verifiedMessagesEnabled = false
                proofState = .failed("Could not enable proof links. Nothing was shared.")
            }
        }
    }

    private func bindCoordinator() {
        if isUITest { modelReady = true }
        if coordinator?.isModelReady == true { modelReady = true }
        coordinator?.phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .modelLoading(let progress):
                    guard !isUITest else { return }
                    modelReady = false
                    modelProgress = progress
                case .idle:
                    if coordinator?.isModelReady == true || isUITest {
                        modelReady = true
                        modelProgress = 1
                        if pendingVoiceStart && permissionsReady {
                            pendingVoiceStart = false
                            startVoiceTest()
                        }
                    }
                case .error(let message):
                    guard !isUITest else { return }
                    modelReady = false
                    if voiceState == .preparing { voiceState = .failed(message) }
                default:
                    break
                }
            }
            .store(in: &subscriptions)
    }

    private func refreshSystemState() {
        guard !isUITest else { return }
        microphoneReady = PermissionsChecker.microphoneStatus == .authorized
        accessibilityReady = PermissionsChecker.isAccessibilityGranted
        if coordinator?.isModelReady == true { modelReady = true }
    }

    private func startVoiceTest() {
        voiceTimer?.cancel()
        voiceLevel = 0
        if isUITest {
            voiceState = .listening
            coordinator?.hud.show(state: .recording)
        } else {
            do {
                try coordinator?.beginOnboardingPractice()
                voiceState = .listening
            } catch {
                voiceState = .failed(error.localizedDescription)
                return
            }
        }
        voiceTimer = Task { [weak self] in
            try? await Task.sleep(for: self?.isUITest == true ? .milliseconds(2_500) : .milliseconds(2_400))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finishVoiceTest() }
        }
    }

    private func finishVoiceTest() {
        guard voiceState == .listening else { return }
        voiceTimer?.cancel()
        voiceTimer = nil
        voiceState = .processing
        voiceLevel = 0
        if isUITest {
            coordinator?.hud.show(state: .transcribing)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(3_000))
                guard let self else { return }
                transcript = "Hello hush, this is my voice."
                voiceState = .complete
                coordinator?.hud.hide()
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let coordinator else { throw OnboardingPracticeError.notRecording }
                let result = try await coordinator.finishOnboardingPractice()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw TranscriberError.empty }
                transcript = result
                voiceState = .complete
            } catch {
                transcript = ""
                voiceState = .failed(error.localizedDescription)
            }
        }
    }
}

private enum OnboardingPalette {
    static let ink = Color(red: 0.086, green: 0.09, blue: 0.106)
    static let muted = Color(red: 0.435, green: 0.443, blue: 0.471)
    static let faint = Color(red: 0.627, green: 0.639, blue: 0.667)
    static let purple = Color(red: 0.471, green: 0.408, blue: 0.957)
    static let purple2 = Color(red: 0.624, green: 0.569, blue: 1)
    static let blue = Color(red: 0.471, green: 0.714, blue: 1)
    static let green = Color(red: 0.192, green: 0.659, blue: 0.42)
    static let go = Color(red: 0.204, green: 0.78, blue: 0.349)

    static let aurora = AngularGradient(
        colors: [
            Color(red: 1, green: 0.839, blue: 0.647),
            Color(red: 1, green: 0.702, blue: 0.78),
            Color(red: 0.788, green: 0.722, blue: 1),
            Color(red: 0.62, green: 0.788, blue: 1),
            Color(red: 0.659, green: 0.902, blue: 0.812),
            Color(red: 1, green: 0.839, blue: 0.647),
        ],
        center: .center,
        angle: .degrees(210)
    )

    static let brand = LinearGradient(
        colors: [Color(red: 0.56, green: 0.725, blue: 1), purple, Color(red: 0.55, green: 0.459, blue: 0.937)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headline = LinearGradient(
        colors: [Color(red: 0.424, green: 0.369, blue: 0.953), Color(red: 0.608, green: 0.475, blue: 0.937), Color(red: 0.42, green: 0.682, blue: 1)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct ImmersiveOnboardingView: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        ZStack {
            onboardingBackground
            VStack(spacing: 0) {
                header
                    .frame(height: 74)
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                footer
            }
            if flow.permissionSheetPresented {
                PermissionSetupOverlay(flow: flow)
                    .transition(.opacity)
                    .zIndex(4)
            }
            if flow.isCompletingSetup {
                OnboardingCompletionOverlay()
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .foregroundStyle(OnboardingPalette.ink)
        .frame(minWidth: 980, minHeight: 700)
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.94, blue: 0.97), .white, Color(red: 0.92, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.72, green: 0.68, blue: 1).opacity(0.24))
                .frame(width: 470, height: 470)
                .blur(radius: 75)
                .offset(x: -430, y: -360)
            Circle()
                .fill(Color(red: 0.56, green: 0.8, blue: 1).opacity(0.23))
                .frame(width: 560, height: 560)
                .blur(radius: 90)
                .offset(x: 520, y: 420)
            LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        ZStack {
            Text("hush")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingPalette.muted.opacity(0.72))
            HStack(spacing: 18) {
                Spacer()
                Text("\(flow.page.rawValue + 1) of 4")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.muted)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
                HStack(spacing: 10) {
                    ForEach(OnboardingFlowModel.Page.allCases, id: \.rawValue) { page in
                        Button { flow.selectPage(page) } label: {
                            Capsule()
                                .fill(page == flow.page ? AnyShapeStyle(OnboardingPalette.headline) : AnyShapeStyle(OnboardingPalette.ink.opacity(0.22)))
                                .frame(width: page == flow.page ? 64 : 54, height: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(page.rawValue > flow.page.rawValue)
                        .accessibilityLabel("Go to step \(page.rawValue + 1)")
                    }
                }
            }
            .padding(.trailing, 24)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch flow.page {
            case .welcome: WelcomeOnboardingStep(flow: flow)
            case .voice: VoiceOnboardingStep(flow: flow)
            case .personas: PersonasOnboardingStep(flow: flow)
            case .proof: ProofOnboardingStep(flow: flow)
            }
        }
        .id(flow.page)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: 28)),
            removal: .opacity.combined(with: .offset(x: -28))
        ))
        .padding(.horizontal, 94)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text(flow.footerMessage)
                .font(.system(size: 15))
                .foregroundStyle(OnboardingPalette.muted.opacity(0.9))
                .lineLimit(2)
            Spacer(minLength: 28)
            Button("Back") { flow.goBack() }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .disabled(flow.page == .welcome)
                .opacity(flow.page == .welcome ? 0.34 : 1)
            Button(flow.primaryTitle) { flow.goForward() }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!flow.primaryEnabled)
                .opacity(flow.primaryEnabled ? 1 : 0.38)
                .accessibilityIdentifier("hush.onboarding.primary")
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(.white.opacity(0.42))
        .overlay(alignment: .top) { Rectangle().fill(OnboardingPalette.ink.opacity(0.08)).frame(height: 1) }
    }
}

private struct OnboardingCompletionOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gathered = false
    @State private var ready = false

    private var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("--onboarding-ui-test")
    }

    private let features: [(symbol: String, title: String, offset: CGSize)] = [
        ("waveform", "Voice", CGSize(width: -190, height: -106)),
        ("person.crop.circle", "Personas", CGSize(width: 190, height: -106)),
        ("checkmark.seal.fill", "Proof", CGSize(width: -190, height: 106)),
        ("command", "Shortcuts", CGSize(width: 190, height: 106)),
    ]

    var body: some View {
        ZStack {
            completionBackground
            VStack(spacing: 0) {
                Text(ready ? "You’re ready." : "Setting things up.")
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(OnboardingPalette.ink)
                    .contentTransition(.opacity)

                Text(ready
                    ? "Your private workspace and Dashboard are ready on this Mac."
                    : "Bringing voice, personas, proof, and shortcuts into one private workspace."
                )
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(OnboardingPalette.muted)
                .padding(.top, 10)
                .contentTransition(.opacity)

                gatheringMark
                    .frame(width: 530, height: 286)
                    .padding(.top, 16)

                HStack(spacing: 13) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("hush stays in your menu bar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OnboardingPalette.ink)
                        Text("Open hush and its settings from there anytime.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OnboardingPalette.muted)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: OnboardingPalette.ink.opacity(0.08), radius: 24, y: 10)
                .opacity(ready ? 1 : 0.72)
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hush.onboarding.completion")
        .task { await runAnimation() }
    }

    private var completionBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.99),
                    .white,
                    Color(red: 0.92, green: 0.95, blue: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(OnboardingPalette.purple.opacity(0.18))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: -430, y: -300)
            Circle()
                .fill(Color(red: 0.45, green: 0.78, blue: 1).opacity(0.2))
                .frame(width: 560, height: 560)
                .blur(radius: 100)
                .offset(x: 470, y: 320)
        }
        .ignoresSafeArea()
    }

    private var gatheringMark: some View {
        ZStack {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 9) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 15, weight: .semibold))
                    Text(feature.title)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(OnboardingPalette.ink.opacity(0.82))
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(.white.opacity(0.76), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.94), lineWidth: 1) }
                .shadow(color: OnboardingPalette.ink.opacity(0.08), radius: 16, y: 7)
                .offset(gathered ? .zero : feature.offset)
                .scaleEffect(gathered ? 0.44 : 1)
                .opacity(gathered ? 0 : 1)
                .animation(
                    reduceMotion
                        ? .linear(duration: 0.01)
                        : .spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * 0.035),
                    value: gathered
                )
            }

            Circle()
                .fill(OnboardingPalette.brand)
                .opacity(0.18)
                .frame(width: ready ? 190 : 154, height: ready ? 190 : 154)
                .blur(radius: ready ? 8 : 15)
                .scaleEffect(gathered ? 1 : 0.78)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(OnboardingPalette.ink)
                .frame(width: 112, height: 112)
                .overlay {
                    Image(systemName: ready ? "checkmark" : "waveform")
                        .font(.system(size: ready ? 42 : 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: OnboardingPalette.purple.opacity(0.28), radius: 32, y: 18)
                .scaleEffect(gathered ? 1 : 0.88)
                .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.5, dampingFraction: 0.74), value: gathered)
        }
    }

    @MainActor
    private func runAnimation() async {
        if reduceMotion {
            gathered = true
            ready = true
            return
        }
        try? await Task.sleep(for: .milliseconds(130))
        guard !Task.isCancelled else { return }
        gathered = true
        try? await Task.sleep(for: .milliseconds(isUITest ? 2_000 : 690))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.3)) { ready = true }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 150)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(OnboardingPalette.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: OnboardingPalette.purple.opacity(configuration.isPressed ? 0.14 : 0.28), radius: 18, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OnboardingPalette.muted)
            .frame(minWidth: 92)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(OnboardingPalette.ink.opacity(configuration.isPressed ? 0.1 : 0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GradientHeadline: View {
    let text: String
    var size: CGFloat = 58

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(-2.7)
            .foregroundStyle(OnboardingPalette.headline)
    }
}

private struct WelcomeOnboardingStep: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        HStack(spacing: 76) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Talk and your Mac")
                    .font(.system(size: 45, weight: .bold))
                    .tracking(-2.2)
                Text(flow.headlinePhrases[flow.headlineIndex])
                    .font(.system(size: 53, weight: .bold))
                    .tracking(-2.8)
                    .foregroundStyle(OnboardingPalette.headline)
                    .lineLimit(1)
                    .id(flow.headlineIndex)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                Text("Speak naturally and get polished, private text you can confidently share with a signed creation trail.")
                    .font(.system(size: 20))
                    .foregroundStyle(OnboardingPalette.muted)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26)
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 10) {
                    TrustChip(symbol: "lock", text: "Audio stays local")
                    TrustChip(symbol: "checkmark.shield", text: "Proof is encrypted")
                }
                .padding(.top, 26)
            }
            .frame(maxWidth: 545, alignment: .leading)

            WelcomeAppVisual(showsPersona: flow.headlineIndex == 1)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrustChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OnboardingPalette.muted)
            .symbolRenderingMode(.monochrome)
            .tint(OnboardingPalette.green)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(OnboardingPalette.ink.opacity(0.07)) }
            .shadow(color: OnboardingPalette.ink.opacity(0.05), radius: 12, y: 7)
    }
}

private struct WelcomeAppVisual: View {
    let showsPersona: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(OnboardingPalette.purple.opacity(0.12))
                .frame(width: 390, height: 390)
                .blur(radius: 2)
            RoundedRectangle(cornerRadius: 92, style: .continuous)
                .fill(.white.opacity(0.64))
                .frame(width: 355, height: 355)
                .overlay { RoundedRectangle(cornerRadius: 92, style: .continuous).stroke(.white.opacity(0.9)) }
                .shadow(color: Color(red: 0.28, green: 0.28, blue: 0.46).opacity(0.18), radius: 38, y: 24)
            RoundedRectangle(cornerRadius: 39, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.16), Color(red: 0.065, green: 0.065, blue: 0.075)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 148, height: 148)
                .shadow(color: .black.opacity(0.27), radius: 22, y: 16)
                .overlay { HushWaveMark(color: .white).frame(width: 76, height: 70) }
            FloatingChip(symbol: "checkmark.shield", text: "Signed at\ncreation")
                .offset(x: 158, y: -154)
            FloatingChip(symbol: "waveform", text: "Local\ntranscription")
                .offset(x: -156, y: 150)
            if showsPersona {
                PersonaPreviewChip()
                    .offset(x: -176, y: -35)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(width: 470, height: 470)
        .animation(.easeInOut(duration: 0.55), value: showsPersona)
    }
}

private struct HushWaveMark: View {
    let color: Color
    private let heights: [CGFloat] = [25, 48, 70, 44, 22]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule().fill(color).frame(width: 10, height: height)
            }
        }
    }
}

private struct FloatingChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(OnboardingPalette.purple)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(OnboardingPalette.muted)
        }
        .padding(.horizontal, 14)
        .frame(width: 150, height: 62, alignment: .leading)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.84)) }
        .shadow(color: OnboardingPalette.ink.opacity(0.12), radius: 18, y: 10)
    }
}

private struct PersonaPreviewChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(OnboardingPalette.brand)
                    .frame(width: 34, height: 34)
                    .overlay { Image(systemName: "message").foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("PERSONA").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(OnboardingPalette.faint)
                    Text("Slack").font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Circle().fill(OnboardingPalette.go).frame(width: 7, height: 7)
            }
            Text("hey team 👋 shipping the redesign today")
                .font(.system(size: 13))
                .foregroundStyle(OnboardingPalette.muted)
        }
        .padding(16)
        .frame(width: 248)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: OnboardingPalette.ink.opacity(0.16), radius: 24, y: 14)
    }
}

private struct VoiceOnboardingStep: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text("Test your")
                GradientHeadline(text: "voice.", size: 54)
            }
            .font(.system(size: 54, weight: .bold))
            .tracking(-2.4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hush.onboarding.voice.title")

            Text("Say “Hello hush, this is my voice.”")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OnboardingPalette.muted)
                .padding(.top, 14)

            Button { flow.tapMicrophone() } label: {
                VoiceOrb(state: flow.voiceState, level: flow.voiceLevel)
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .accessibilityIdentifier("hush.onboarding.voice")
            .accessibilityLabel(flow.voiceState == .listening ? "Finish voice test" : "Start voice test")

            Text(flow.voiceLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(flow.voiceState == .complete ? OnboardingPalette.green : OnboardingPalette.purple)
                .padding(.top, 12)

            VoiceResult(flow: flow)
                .padding(.top, 16)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VoiceOrb: View {
    let state: OnboardingFlowModel.VoiceState
    let level: Float

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor)
                .frame(width: 218, height: 218)
                .blur(radius: 28)
                .opacity(0.5)
            Circle()
                .fill(state == .complete ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.84, blue: 0.48), OnboardingPalette.go], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(OnboardingPalette.aurora))
                .frame(width: 132, height: 132)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.34)).frame(width: 72, height: 72).blur(radius: 12).offset(x: 12, y: 8)
                }
                .clipShape(Circle())
                .overlay { Circle().stroke(.white.opacity(0.42), lineWidth: 1) }
                .shadow(color: state == .complete ? OnboardingPalette.go.opacity(0.32) : OnboardingPalette.purple.opacity(0.3), radius: 28, y: 16)
                .scaleEffect(state == .listening ? 1.04 + CGFloat(level) * 0.03 : 1)
            if state == .processing {
                LocalTranscriptionMark()
                    .transition(.opacity.combined(with: .scale(scale: 0.84)))
            } else {
                Image(systemName: state == .complete ? "checkmark" : "mic")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: OnboardingPalette.purple.opacity(0.28), radius: 3, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if state == .listening {
                Circle()
                    .stroke(OnboardingPalette.purple.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 176, height: 176)
                    .transition(.opacity)
            }
        }
        .frame(width: 260, height: 236)
        .animation(.easeInOut(duration: 0.3), value: state)
        .animation(.easeOut(duration: 0.1), value: level)
    }

    private var glowColor: Color {
        state == .complete ? OnboardingPalette.go.opacity(0.35) : OnboardingPalette.purple.opacity(0.3)
    }
}

private struct LocalTranscriptionMark: View {
    private let barCount = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 2.4
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let wave = (sin(phase + Double(index) * 0.82) + 1) / 2
                    Capsule()
                        .fill(.white.opacity(0.72 + wave * 0.28))
                        .frame(width: 6, height: 16 + wave * 30)
                }
            }
        }
        .frame(width: 76, height: 54)
        .shadow(color: OnboardingPalette.purple.opacity(0.3), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Local transcription activity")
        .accessibilityIdentifier("hush.onboarding.processingMark")
    }
}

private struct VoiceResult: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        HStack(spacing: 10) {
            if flow.voiceState == .complete {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.84, blue: 0.48), OnboardingPalette.go], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                Text("Heard clearly")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingPalette.green)
                Text("“\(flow.transcript)”")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("hush.onboarding.transcript")
            } else if case .failed(let message) = flow.voiceState {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(message).font(.system(size: 14, weight: .medium)).foregroundStyle(OnboardingPalette.muted)
            } else {
                Text(flow.voiceState == .listening ? "Listening   Say the phrase now…" : "Your words appear here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.faint)
            }
        }
        .frame(height: 30)
    }
}

private struct PermissionSetupOverlay: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        ZStack {
            Color(red: 0.937, green: 0.949, blue: 0.973).opacity(0.68)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow hush to listen and type.")
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-1.1)
                        Text("Grant both to continue. Accessibility opens System Settings - switch it on, then come back.")
                            .font(.system(size: 15))
                            .foregroundStyle(OnboardingPalette.muted)
                            .lineSpacing(4)
                    }
                    Spacer()
                    Button { flow.closePermissionSheet() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingPalette.muted)
                            .frame(width: 30, height: 30)
                            .background(OnboardingPalette.ink.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close permission setup")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)

                VStack(spacing: 8) {
                    PermissionRow(
                        symbol: "mic",
                        title: "Microphone",
                        detail: "So hush can hear your voice.",
                        action: flow.microphoneReady ? "Allowed" : "Allow",
                        ready: flow.microphoneReady,
                        identifier: "hush.onboarding.microphone",
                        onTap: flow.requestMicrophone
                    )
                    PermissionRow(
                        symbol: "accessibility",
                        title: "Accessibility",
                        detail: "So hush can type into any app. Opens System Settings.",
                        action: flow.accessibilityReady ? "Enabled" : "Open Settings",
                        ready: flow.accessibilityReady,
                        identifier: "hush.onboarding.accessibility",
                        onTap: flow.requestAccessibility
                    )
                }

                HStack(spacing: 12) {
                    Label("Your audio never leaves this Mac.", systemImage: "lock")
                        .font(.system(size: 13))
                        .foregroundStyle(OnboardingPalette.muted)
                        .tint(OnboardingPalette.go)
                    Spacer()
                    Button("Continue") { flow.continueFromPermissions() }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .disabled(!flow.permissionsReady)
                        .opacity(flow.permissionsReady ? 1 : 0.38)
                        .accessibilityIdentifier("hush.onboarding.permissions.continue")
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(OnboardingPalette.ink.opacity(0.07)).frame(height: 1) }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .padding(16)
            .frame(width: 660)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white) }
            .shadow(color: OnboardingPalette.ink.opacity(0.24), radius: 46, y: 24)
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: String
    let ready: Bool
    let identifier: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 17) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(OnboardingPalette.purple.opacity(0.09))
                    .frame(width: 58, height: 58)
                    .overlay { Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(OnboardingPalette.purple) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .bold))
                    Text(detail).font(.system(size: 13.5)).foregroundStyle(OnboardingPalette.muted)
                }
                Spacer()
                Text(action)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(ready ? OnboardingPalette.green : OnboardingPalette.purple)
                    .padding(.horizontal, 16)
                    .frame(minWidth: 104, minHeight: 44)
                    .background((ready ? OnboardingPalette.go : OnboardingPalette.purple).opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .padding(20)
            .background((ready ? Color(red: 0.97, green: 1, blue: 0.984) : Color(red: 0.973, green: 0.976, blue: 0.988)).opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ready ? OnboardingPalette.go.opacity(0.28) : OnboardingPalette.ink.opacity(0.07)) }
        }
        .buttonStyle(.plain)
        .disabled(ready)
        .accessibilityIdentifier(identifier)
    }
}

private struct PersonasOnboardingStep: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        HStack(spacing: 70) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Enable your")
                    .font(.system(size: 58, weight: .bold))
                    .tracking(-3)
                GradientHeadline(text: "local personas.")
                Text("Your personas run entirely on your Mac, powered by Apple’s on-device Foundation Models. Nothing is ever sent to the cloud or to ChatGPT.")
                    .font(.system(size: 17))
                    .foregroundStyle(OnboardingPalette.muted)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .frame(maxWidth: 540, alignment: .leading)
                OnboardingEngineCard(
                    symbol: "sparkles",
                    title: "Apple Intelligence",
                    detail: "On-device model · No download needed",
                    enabled: flow.personasEnabled,
                    identifier: "hush.onboarding.personas",
                    onToggle: flow.togglePersonas
                )
                .padding(.top, 28)
                Label("Download more local models anytime.", systemImage: "arrow.down.to.line")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(OnboardingPalette.faint)
                    .padding(.top, 15)
            }
            .frame(maxWidth: 540, alignment: .leading)

            PersonaRing(unlocked: flow.personasEnabled)
                .frame(width: 420, height: 420)
        }
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingEngineCard: View {
    let symbol: String
    let title: String
    let detail: String
    let enabled: Bool
    let identifier: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 15) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OnboardingPalette.aurora)
                .frame(width: 52, height: 52)
                .overlay { Image(systemName: symbol).font(.system(size: 25, weight: .medium)).foregroundStyle(.white) }
                .shadow(color: OnboardingPalette.purple.opacity(0.24), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(detail).font(.system(size: 13)).foregroundStyle(OnboardingPalette.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(OnboardingPalette.go)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background((enabled ? Color(red: 0.97, green: 1, blue: 0.984) : .white).opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(enabled ? OnboardingPalette.go.opacity(0.3) : OnboardingPalette.ink.opacity(0.08)) }
        .shadow(color: enabled ? OnboardingPalette.go.opacity(0.12) : OnboardingPalette.ink.opacity(0.08), radius: 22, y: 12)
    }
}

private struct PersonaRing: View {
    let unlocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(unlocked ? 0.58 : 0.46), lineWidth: 92)
                .background(Circle().fill(OnboardingPalette.purple.opacity(unlocked ? 0.11 : 0.05)))
                .frame(width: 300, height: 300)
                .shadow(color: OnboardingPalette.purple.opacity(unlocked ? 0.2 : 0.1), radius: 36, y: 18)
            VStack(spacing: 5) {
                Text("LOCAL PERSONAS").font(.system(size: 9.5, weight: .bold)).tracking(1.6).foregroundStyle(OnboardingPalette.faint)
                Text("Pick one later").font(.system(size: 15, weight: .bold)).foregroundStyle(unlocked ? OnboardingPalette.green : OnboardingPalette.muted)
            }
            PersonaNode(symbol: "building.2", title: "Executive", fill: LinearGradient(colors: [.black.opacity(0.82), .black], startPoint: .topLeading, endPoint: .bottomTrailing), unlocked: unlocked)
                .offset(y: -174)
            PersonaNode(symbol: "message", title: "Slack", fill: LinearGradient(colors: [OnboardingPalette.purple2, OnboardingPalette.purple], startPoint: .topLeading, endPoint: .bottomTrailing), unlocked: unlocked)
                .offset(x: 174)
            PersonaNode(symbol: "person", title: "Warm", fill: LinearGradient(colors: [Color(red: 1, green: 0.76, blue: 0.62), Color(red: 1, green: 0.62, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing), unlocked: unlocked)
                .offset(y: 174)
            PersonaNode(symbol: "envelope", title: "Email", fill: LinearGradient(colors: [Color(red: 0.56, green: 0.77, blue: 1), Color(red: 0.35, green: 0.63, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing), unlocked: unlocked)
                .offset(x: -174)
        }
        .animation(.easeInOut(duration: 0.5), value: unlocked)
    }
}

private struct PersonaNode: View {
    let symbol: String
    let title: String
    let fill: LinearGradient
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(unlocked ? AnyShapeStyle(fill) : AnyShapeStyle(.white.opacity(0.72)))
                .frame(width: 60, height: 60)
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(unlocked ? .clear : OnboardingPalette.faint.opacity(0.4), lineWidth: 1.5) }
                .overlay { Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(unlocked ? .white : OnboardingPalette.faint) }
                .shadow(color: OnboardingPalette.purple.opacity(0.16), radius: 12, y: 7)
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(unlocked ? OnboardingPalette.ink : OnboardingPalette.faint)
        }
    }
}

private struct ProofOnboardingStep: View {
    @ObservedObject var flow: OnboardingFlowModel

    var body: some View {
        HStack(spacing: 72) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Proof it’s")
                    .font(.system(size: 58, weight: .bold))
                    .tracking(-3)
                GradientHeadline(text: "really you.")
                Text("Feeds are full of AI slop. Prove your words are really yours. A signed trail shows your post came from your voice, not a bot.")
                    .font(.system(size: 17))
                    .foregroundStyle(OnboardingPalette.muted)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .frame(maxWidth: 540, alignment: .leading)
                OnboardingEngineCard(
                    symbol: "checkmark.shield",
                    title: "Attach proof",
                    detail: "Signed on-device · Audio never shared",
                    enabled: flow.proofEnabled,
                    identifier: "hush.onboarding.verified",
                    onToggle: flow.toggleProof
                )
                .padding(.top, 28)
                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("Signed privately in your Keychain.")
                    Text("How it works").foregroundStyle(OnboardingPalette.purple).underline()
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(OnboardingPalette.faint)
                .padding(.top, 15)
            }
            .frame(maxWidth: 540, alignment: .leading)

            ProofCreationCard(verified: flow.proofState == .on)
        }
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProofCreationCard: View {
    let verified: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                OnboardingExampleAvatar()
                    .frame(width: 46, height: 46)
                    .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 2) }
                    .shadow(color: OnboardingPalette.purple.opacity(0.24), radius: 8, y: 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Clemoji").font(.system(size: 15.5, weight: .bold))
                        if verified {
                            Circle().fill(OnboardingPalette.go).frame(width: 18, height: 18)
                                .overlay { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                        }
                    }
                    Text(verified ? "Voice-origin verified · signed on this Mac" : "Draft · not signed yet")
                        .font(.system(size: 12.5))
                        .foregroundStyle(OnboardingPalette.muted)
                }
            }

            Group {
                Text("shipped the redesign today 🚀 six months of late nights, finally live. every word here is mine. ")
                    .foregroundStyle(OnboardingPalette.ink)
                + Text(verified ? "- typed with hush" : "")
                    .foregroundStyle(OnboardingPalette.purple)
            }
            .font(.system(size: 20, weight: .bold))
            .tracking(-0.7)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .topLeading)
            .padding(.vertical, 17)

            Divider().opacity(0.45)

            VStack(spacing: 0) {
                ProofTimelineRow(number: "1", title: "Voice recorded", detail: "Captured and transcribed on your Mac.", visible: verified)
                ProofTimelineRow(number: "2", title: "Cleaned up locally", detail: "Spacing and punctuation, on-device.", visible: verified)
                ProofTimelineRow(number: "3", title: "Signed and encrypted", detail: "The exact final message is tamper-evident.", visible: verified)
            }

            Divider().opacity(0.45)
                .padding(.top, 4)

            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(OnboardingPalette.aurora)
                    .frame(width: 28, height: 28)
                Text("@clemoji · 4 Aug 2026")
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingPalette.faint)
                Spacer()
                Text("sha256  8b4c2fe3…")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(OnboardingPalette.green)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(OnboardingPalette.go.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .opacity(verified ? 1 : 0.28)
            .padding(.top, 14)
        }
        .padding(22)
        .frame(width: 456, height: 424, alignment: .topLeading)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(verified ? OnboardingPalette.go.opacity(0.3) : OnboardingPalette.ink.opacity(0.08)) }
        .shadow(color: verified ? OnboardingPalette.go.opacity(0.18) : OnboardingPalette.ink.opacity(0.13), radius: 34, y: 20)
        .animation(.easeInOut(duration: 0.5), value: verified)
    }
}

private struct OnboardingExampleAvatar: View {
    private static let image: NSImage? = {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "example-avatar",
            withExtension: "webp",
            subdirectory: "Onboarding"
        ) ?? bundle.url(forResource: "example-avatar", withExtension: "webp")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Example hiking profile photo")
            } else {
                Circle().fill(OnboardingPalette.headline)
            }
        }
        .clipShape(Circle())
    }
}

private struct ProofTimelineRow: View {
    let number: String
    let title: String
    let detail: String
    let visible: Bool

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(visible ? OnboardingPalette.go.opacity(0.12) : OnboardingPalette.ink.opacity(0.07))
                .frame(width: 28, height: 28)
                .overlay { Circle().stroke(visible ? OnboardingPalette.go.opacity(0.35) : .clear, lineWidth: 1.5) }
                .overlay { Text(visible ? number : "").font(.system(size: 12, weight: .bold)).foregroundStyle(OnboardingPalette.green) }
            VStack(alignment: .leading, spacing: 2) {
                Text(visible ? title : "                         ")
                    .font(.system(size: 13.5, weight: .bold))
                    .redacted(reason: visible ? [] : .placeholder)
                Text(visible ? detail : "                                      ")
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingPalette.muted)
                    .redacted(reason: visible ? [] : .placeholder)
            }
            Spacer()
        }
        .frame(height: 58)
        .opacity(visible ? 1 : 0.48)
    }
}

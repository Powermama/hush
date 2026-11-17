import AppKit
import Combine
import Foundation

/// The ChatGPT connection as the app sees it: whether an account is connected with plan
/// usage, its models, and the last limit hit. Drives Live Write's card, its status and the
/// engine's readiness; the protocol itself lives in `ChatGPTConnection`.
@MainActor
final class ChatGPTAccount {
    static let shared = ChatGPTAccount()

    enum State: Equatable {
        case disconnected
        case connecting
        case connected(email: String?, planUsage: Bool)
        case failed(String)
    }

    static let manageUsageURL = URL(string: "https://chatgpt.com/settings/usage")!
    static let privacyPolicyURL = URL(string: "https://openai.com/policies/privacy-policy/")!
    /// After a usage limit, plan requests pause for this long before hush tries again.
    static let limitPause: TimeInterval = 15 * 60

    let changes = PassthroughSubject<Void, Never>()
    private(set) var state: State = .disconnected { didSet { changes.send() } }
    private(set) var models: [ChatGPTResponses.Model] = [] { didSet { changes.send() } }
    private(set) var limitReachedAt: Date? { didSet { changes.send() } }
    private let connection: ChatGPTConnection
    /// Where each feature's consent is kept.
    let defaults: UserDefaults
    private var connectTask: Task<Void, Never>?
    /// Why the last sign-in failed, for callers that await it.
    private(set) var lastError: ChatGPTError?

    init(connection: ChatGPTConnection = .shared, defaults: UserDefaults = .standard, loads: Bool = true) {
        self.connection = connection
        self.defaults = defaults
        if loads { Task { await load() } }
    }

    var isConnected: Bool { if case .connected(_, true) = state { return true }; return false }
    var isLimitPaused: Bool { limitReachedAt.map { Date().timeIntervalSince($0) < Self.limitPause } ?? false }
    /// Ready to write: connected with plan usage, a model chosen, not paused by a limit.
    var isUsable: Bool { isConnected && Settings.shared.chatGPTModel != nil && !isLimitPaused }

    func load() async {
        if let account = await connection.account() {
            // Connections made before consent was tracked per feature were made from Live Write.
            if Settings.shared.llmProvider == .chatGPT, !hasConsent(.liveWrite) { grantConsent(.liveWrite) }
            state = .connected(email: account.identity.email, planUsage: account.planUsage)
            await refreshModels()
        } else {
            state = .disconnected
        }
    }

    func connect() {
        connectTask?.cancel()
        state = .connecting
        connectTask = Task { _ = await self.signIn() }
    }

    /// Signs in (or returns at once when connected) and reports whether the plan is usable.
    /// Assistant setup awaits this as its intelligence step.
    func ensureConnected() async -> Bool {
        if isConnected { return true }
        if let connectTask, state == .connecting {
            await connectTask.value
            return isConnected
        }
        connectTask?.cancel()
        state = .connecting
        let task = Task { _ = await self.signIn() }
        connectTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        return isConnected
    }

    private func signIn() async -> Bool {
        lastError = nil
        do {
            let identity = try await connection.signIn()
            state = .connected(email: identity.email, planUsage: true)
            limitReachedAt = nil
            await refreshModels()
            return true
        } catch ChatGPTError.planUsageNotGranted {
            lastError = .planUsageNotGranted
            let email = await connection.account()?.identity.email
            state = .connected(email: email, planUsage: false)
        } catch ChatGPTError.cancelled {
            state = .disconnected
        } catch is CancellationError {
            state = .disconnected
        } catch {
            lastError = error as? ChatGPTError ?? .network(error.localizedDescription)
            state = .failed(Self.message(for: error))
        }
        return false
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        if state == .connecting { state = .disconnected }
    }

    /// Revokes and forgets the session. Live Write and Assistant go back to engines on this
    /// Mac, and the Assistant's consent is withdrawn, so a new connection asks again.
    @discardableResult
    func disconnect() async -> Bool {
        let confirmed = await connection.signOut()
        state = .disconnected
        models = []
        if Settings.shared.llmProvider == .chatGPT {
            Settings.shared.llmProvider = LiveWriteStatus.bestReadyEngine() ?? .off
        }
        withdrawConsent()
        return confirmed
    }

    /// Forgets every feature's consent; Assistant goes back to its model on this Mac.
    func withdrawConsent() {
        for purpose in [Purpose.liveWrite, .assistant] { defaults.removeObject(forKey: purpose.consentKey) }
        CoworkerModelSettings.withdrawChatGPT()
        changes.send()
    }

    func refreshModels() async {
        guard isConnected else { return }
        if let list = try? await connection.models(), !list.isEmpty {
            models = list
            if Settings.shared.chatGPTModel.map({ chosen in !list.contains { $0.slug == chosen } }) ?? true {
                Settings.shared.chatGPTModel = list.first?.slug
            }
        }
    }

    /// Models that rejected image input, so the Assistant sends them text only.
    private var textOnlyModels: Set<String> = []
    func acceptsImages(_ slug: String?) -> Bool { slug.map { !textOnlyModels.contains($0) } ?? false }
    func rejectImages(_ slug: String?) { if let slug { textOnlyModels.insert(slug) } }

    func modelName(_ slug: String?) -> String {
        guard let slug else { return "ChatGPT" }
        return models.first { $0.slug == slug }?.displayName ?? slug
    }

    /// Writes on the plan; records a limit so the next dictations go to this Mac directly.
    func write(instructions: String, input: [ChatGPTResponses.Message]) async throws -> String {
        guard let model = Settings.shared.chatGPTModel else { throw ChatGPTError.badResponse("No ChatGPT model chosen") }
        do {
            return try await connection.write(model: model, instructions: instructions, input: input)
        } catch ChatGPTError.usageLimitReached {
            limitReachedAt = Date()
            throw ChatGPTError.usageLimitReached
        } catch ChatGPTError.signInRequired {
            state = .disconnected
            throw ChatGPTError.signInRequired
        }
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? ChatGPTError)?.errorDescription ?? "ChatGPT couldn\u{2019}t write this one."
    }
}

extension ChatGPTError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .usageLimitReached: "Your ChatGPT plan\u{2019}s limit for hush is reached."
        case .notEligible: "This ChatGPT account can\u{2019}t use its plan in hush."
        case .temporarilyUnavailable: "ChatGPT is not available right now."
        case .signInRequired: "Sign in to ChatGPT again."
        case .planUsageNotGranted: "hush wasn\u{2019}t allowed to use your ChatGPT plan."
        case .network: "hush couldn\u{2019}t reach ChatGPT."
        case .cancelled: "Stopped."
        default: "ChatGPT couldn\u{2019}t do this one."
        }
    }
}

extension ChatGPTAccount {
    /// What a feature sends to OpenAI. Each feature asks for its own consent, because the
    /// Assistant shares far more than Live Write.
    enum Purpose: String {
        case liveWrite, assistant

        var consentKey: String { "chatgpt.consent.\(rawValue).v1" }

        var consentTitle: String {
            switch self {
            case .liveWrite: "Write with your ChatGPT plan?"
            case .assistant: "Use your ChatGPT plan for Assistant?"
            }
        }

        var consentText: String {
            // As Apple says for its own ChatGPT extension: with the user's own account, OpenAI's
            // data rules apply. store:false keeps requests out of OpenAI's stored responses only.
            let account = "You sign in on OpenAI\u{2019}s website; hush never sees your password or your ChatGPT chats. Requests count toward your plan\u{2019}s limits. hush asks OpenAI not to store them; OpenAI\u{2019}s privacy policy and your ChatGPT data controls apply."
            switch self {
            case .liveWrite:
                return """
                Live Write will send what you dictate to OpenAI, which writes the text with your ChatGPT plan. Your screen is not sent.

                \(account) You can disconnect at any time, and Live Write then writes on this Mac again.
                """
            case .assistant:
                return """
                Assistant will send OpenAI what you ask, text it reads from the app you\u{2019}re working in, and, when it helps, a screenshot of that window. Your conversation stays in hush.

                \(account) If ChatGPT can\u{2019}t answer, Assistant uses a model on this Mac when one is installed. You can switch back at any time.
                """
            }
        }
    }

    /// Says plainly what leaves the Mac, then connects when needed. `onAccept` runs once the
    /// user agreed, so a feature records its own consent before the browser opens.
    func hasConsent(_ purpose: Purpose) -> Bool { defaults.bool(forKey: purpose.consentKey) }

    /// Records that the user agreed to what this feature sends.
    func grantConsent(_ purpose: Purpose) {
        defaults.set(true, forKey: purpose.consentKey)
        changes.send()
    }

    /// Asks only when this feature has no consent yet, then runs `onAccept`.
    func withConsent(for purpose: Purpose, in window: NSWindow?, onAccept: @escaping () -> Void) {
        if hasConsent(purpose) {
            onAccept()
            if !isConnected { connect() }
        } else {
            requestConsent(for: purpose, in: window, onAccept: onAccept)
        }
    }

    func requestConsent(for purpose: Purpose, in window: NSWindow?, onAccept: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = purpose.consentTitle
        alert.informativeText = purpose.consentText
        alert.addButton(withTitle: isConnected ? "Use ChatGPT" : "Continue with ChatGPT")
        alert.addButton(withTitle: "Cancel")
        // The standard help button opens OpenAI's privacy policy.
        alert.showsHelp = true
        alert.delegate = ChatGPTPrivacyHelp.shared
        let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.grantConsent(purpose)
            onAccept?()
            if !self.isConnected { self.connect() }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(alert.runModal()) }
    }

    func connectAfterConsent(in window: NSWindow?) { requestConsent(for: .liveWrite, in: window) }

    /// Disconnects after confirmation and says when OpenAI did not confirm the revocation.
    func disconnectReporting(in window: NSWindow?) {
        let confirm = NSAlert()
        confirm.messageText = "Disconnect ChatGPT?"
        confirm.informativeText = "hush signs out and stops using your ChatGPT plan. Live Write and Assistant use models on this Mac again."
        confirm.addButton(withTitle: "Disconnect")
        confirm.addButton(withTitle: "Cancel")
        let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { @MainActor in
                guard !(await self.disconnect()) else { return }
                let notice = NSAlert()
                notice.messageText = "Disconnected on this Mac"
                notice.informativeText = "hush removed your ChatGPT session, but OpenAI did not confirm the revocation. You can also remove hush in ChatGPT\u{2019}s settings."
                if let window { notice.beginSheetModal(for: window, completionHandler: nil) } else { notice.runModal() }
            }
        }
        if let window { confirm.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(confirm.runModal()) }
    }
}

/// Opens OpenAI's privacy policy from the help button of the consent alerts.
@MainActor
private final class ChatGPTPrivacyHelp: NSObject, NSAlertDelegate {
    static let shared = ChatGPTPrivacyHelp()

    func alertShowHelp(_ alert: NSAlert) -> Bool {
        NSWorkspace.shared.open(ChatGPTAccount.privacyPolicyURL)
        return true
    }
}

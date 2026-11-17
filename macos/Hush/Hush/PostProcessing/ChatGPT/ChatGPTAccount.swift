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
    /// After a usage limit, plan requests pause for this long before hush tries again.
    static let limitPause: TimeInterval = 15 * 60

    let changes = PassthroughSubject<Void, Never>()
    private(set) var state: State = .disconnected { didSet { changes.send() } }
    private(set) var models: [ChatGPTResponses.Model] = [] { didSet { changes.send() } }
    private(set) var limitReachedAt: Date? { didSet { changes.send() } }
    private let connection: ChatGPTConnection
    private var connectTask: Task<Void, Never>?

    init(connection: ChatGPTConnection = .shared) {
        self.connection = connection
        Task { await load() }
    }

    var isConnected: Bool { if case .connected(_, true) = state { return true }; return false }
    var isLimitPaused: Bool { limitReachedAt.map { Date().timeIntervalSince($0) < Self.limitPause } ?? false }
    /// Ready to write: connected with plan usage, a model chosen, not paused by a limit.
    var isUsable: Bool { isConnected && Settings.shared.chatGPTModel != nil && !isLimitPaused }

    func load() async {
        if let account = await connection.account() {
            state = .connected(email: account.identity.email, planUsage: account.planUsage)
            await refreshModels()
        } else {
            state = .disconnected
        }
    }

    func connect() {
        connectTask?.cancel()
        state = .connecting
        connectTask = Task {
            do {
                let identity = try await connection.signIn()
                state = .connected(email: identity.email, planUsage: true)
                limitReachedAt = nil
                await refreshModels()
            } catch ChatGPTError.planUsageNotGranted {
                let email = await connection.account()?.identity.email
                state = .connected(email: email, planUsage: false)
            } catch ChatGPTError.cancelled {
                state = .disconnected
            } catch {
                state = .failed(Self.message(for: error))
            }
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        if state == .connecting { state = .disconnected }
    }

    /// Revokes and forgets the session; Live Write goes back to an engine on this Mac.
    @discardableResult
    func disconnect() async -> Bool {
        let confirmed = await connection.signOut()
        state = .disconnected
        models = []
        if Settings.shared.llmProvider == .chatGPT {
            Settings.shared.llmProvider = LiveWriteStatus.bestReadyEngine() ?? .off
        }
        return confirmed
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

    static func message(for error: Error) -> String {
        switch error as? ChatGPTError {
        case .usageLimitReached: "Your ChatGPT plan\u{2019}s limit for hush is reached."
        case .notEligible: "This ChatGPT account can\u{2019}t use its plan in hush."
        case .temporarilyUnavailable: "ChatGPT is not available right now."
        case .signInRequired: "Sign in to ChatGPT again."
        case .planUsageNotGranted: "hush wasn\u{2019}t allowed to use your ChatGPT plan."
        case .network: "hush couldn\u{2019}t reach ChatGPT."
        default: "ChatGPT couldn\u{2019}t write this one."
        }
    }
}

extension ChatGPTAccount {
    /// Says plainly what leaves the Mac before the browser opens, then connects.
    func connectAfterConsent(in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Write with your ChatGPT plan?"
        alert.informativeText = """
        Live Write will send what you dictate to OpenAI, which writes the text with your ChatGPT plan and counts it toward the plan\u{2019}s limits. hush sends these requests with storage turned off.

        You sign in on OpenAI\u{2019}s website; hush never sees your password or your ChatGPT chats. Your screen is not sent. You can disconnect at any time, and Live Write then writes on this Mac again.
        """
        alert.addButton(withTitle: "Continue with ChatGPT")
        alert.addButton(withTitle: "Cancel")
        let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.connect()
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(alert.runModal()) }
    }

    /// Disconnects after confirmation and says when OpenAI did not confirm the revocation.
    func disconnectReporting(in window: NSWindow?) {
        let confirm = NSAlert()
        confirm.messageText = "Disconnect ChatGPT?"
        confirm.informativeText = "hush signs out and stops using your ChatGPT plan. Live Write writes on this Mac again."
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

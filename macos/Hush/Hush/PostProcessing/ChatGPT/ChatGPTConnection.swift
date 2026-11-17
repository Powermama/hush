import AppKit
import Foundation
import Network
import os

/// The one ChatGPT account connected to hush: signs in through the system browser,
/// keeps the session fresh, writes through the Responses API on the user's plan, and
/// signs out with revocation. Refreshes are serialized, as the documentation requires.
actor ChatGPTConnection {
    static let shared = ChatGPTConnection()

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "ChatGPT")
    private let store: ChatGPTCredentialStore
    private let urlSession: URLSession
    private let openBrowser: @Sendable (URL) async -> Void
    private var refreshTask: Task<ChatGPTSession, Error>?

    init(
        store: ChatGPTCredentialStore = ChatGPTCredentialStore(),
        urlSession: URLSession = .shared,
        openBrowser: @escaping @Sendable (URL) async -> Void = { url in _ = await MainActor.run { NSWorkspace.shared.open(url) } }
    ) {
        self.store = store
        self.urlSession = urlSession
        self.openBrowser = openBrowser
    }

    /// The signed-in account, if any, and whether it may use the plan.
    func account() -> (identity: ChatGPTIdentity, planUsage: Bool)? {
        guard let registration = try? store.registration(), let session = try? store.session() else { return nil }
        return (registration.identity, session.grantsPlanUsage)
    }

    // MARK: Sign in

    /// Opens the browser for sign-in and consent and waits for the callback on 127.0.0.1.
    @discardableResult
    func signIn(timeout: Duration = .seconds(300)) async throws -> ChatGPTIdentity {
        let hostID = try store.hostID()
        let registration = try store.registration()
        let server = try ChatGPTLoopbackServer.start(preferredPort: ChatGPTOAuth.preferredPort)
        defer { server.stop() }
        let attempt = ChatGPTOAuth.Attempt.fresh(redirectURI: ChatGPTOAuth.redirectURI(port: server.port), clientID: registration?.clientID)
        let url = ChatGPTOAuth.authorizationURL(
            for: attempt, hostID: hostID,
            idTokenHint: nil,
            loginHint: registration?.identity.email
        )
        await openBrowser(url)
        let callback = try await server.callback(timeout: timeout)
        let authorization = try ChatGPTOAuth.authorization(from: callback, for: attempt)

        let tokens: ChatGPTOAuth.TokenResponse = try await send(ChatGPTOAuth.tokenRequest(code: authorization.code, attempt: attempt, clientID: authorization.clientID))
        guard let idToken = tokens.idToken, let refreshToken = tokens.refreshToken else { throw ChatGPTError.badResponse("Sign-in returned no ID or refresh token") }
        let keys: ChatGPTIDToken.JWKS = try await send(URLRequest(url: ChatGPTOAuth.jwksURL))
        let identity = try ChatGPTIDToken.validate(idToken, keys: keys, clientID: authorization.clientID, nonce: attempt.nonce)
        try store.saveRegistration(ChatGPTRegistration(clientID: authorization.clientID, identity: identity))
        try store.saveSession(ChatGPTSession(
            accessToken: tokens.accessToken, refreshToken: refreshToken, idToken: idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            scopes: tokens.scope?.split(separator: " ").map(String.init) ?? []
        ))
        guard tokens.grantsPlanUsage else { throw ChatGPTError.planUsageNotGranted }
        Self.log.info("ChatGPT connected with plan usage")
        return identity
    }

    // MARK: Session

    /// A current access token, refreshed when it is about to expire. One refresh at a time.
    func accessToken() async throws -> String {
        guard let session = try store.session() else { throw ChatGPTError.signInRequired }
        guard session.grantsPlanUsage else { throw ChatGPTError.planUsageNotGranted }
        guard session.needsRefresh() else { return session.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await self.refresh(session) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    private func refresh(_ session: ChatGPTSession) async throws -> ChatGPTSession {
        guard let registration = try store.registration() else { throw ChatGPTError.signInRequired }
        let request = ChatGPTOAuth.refreshRequest(refreshToken: session.refreshToken, clientID: registration.clientID)
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else {
            let code = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            if let code, ChatGPTOAuth.terminalRefreshErrors.contains(code) {
                try store.deleteSession()
                throw ChatGPTError.signInRequired
            }
            throw ChatGPTError.temporarilyUnavailable
        }
        let tokens = try JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: data)
        var refreshed = session
        refreshed.accessToken = tokens.accessToken
        if let rotated = tokens.refreshToken { refreshed.refreshToken = rotated }
        if let idToken = tokens.idToken { refreshed.idToken = idToken }
        refreshed.expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        if let scope = tokens.scope { refreshed.scopes = scope.split(separator: " ").map(String.init) }
        try store.saveSession(refreshed)
        return refreshed
    }

    /// Revokes the refresh token, then forgets the session. Returns false when revocation
    /// could not be confirmed, so the UI can say so as the documentation asks.
    @discardableResult
    func signOut() async -> Bool {
        defer { try? store.deleteSession() }
        guard let session = try? store.session(), let registration = try? store.registration() else { return true }
        for attempt in 0..<3 {
            if let (_, response) = try? await data(for: ChatGPTOAuth.revocationRequest(refreshToken: session.refreshToken, clientID: registration.clientID)),
               response.statusCode == 200 { return true }
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
        }
        Self.log.notice("ChatGPT revocation not confirmed")
        return false
    }

    // MARK: Models and writing

    func models() async throws -> [ChatGPTResponses.Model] {
        var request = URLRequest(url: ChatGPTResponses.modelsEndpoint)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else { throw ChatGPTResponses.admissionError(status: response.statusCode, body: data) }
        return ChatGPTResponses.models(from: data)
    }

    /// Writes one answer on the user's plan and returns its full text.
    func write(model: String, instructions: String, input: [ChatGPTResponses.Message]) async throws -> String {
        let request = try ChatGPTResponses.request(model: model, instructions: instructions, input: input, accessToken: try await accessToken())
        do {
            return try await stream(request)
        } catch let error as ChatGPTError {
            throw error
        } catch is CancellationError {
            throw ChatGPTError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw ChatGPTError.cancelled
        } catch {
            // A dropped connection mid-stream is a network failure, so callers can fall back.
            throw ChatGPTError.network(error.localizedDescription)
        }
    }

    private func stream(_ request: URLRequest) async throws -> String {
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTError.badResponse("No HTTP response") }
        guard http.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw ChatGPTResponses.admissionError(status: http.statusCode, body: body)
        }
        var reader = ChatGPTResponses.StreamReader()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            try reader.consume(line: line)
            // URLSession's line reader drops empty lines, so dispatch every data line.
            if line.hasPrefix("data:") { try reader.consume(line: "") }
        }
        try reader.finish()
        return reader.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: HTTP

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ChatGPTError.badResponse("HTTP \(response.statusCode) \(object?["error"] as? String ?? "")")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatGPTError.badResponse("No HTTP response") }
            return (data, http)
        } catch let error as ChatGPTError {
            throw error
        } catch {
            throw ChatGPTError.network(error.localizedDescription)
        }
    }
}

/// A one-shot HTTP listener on 127.0.0.1 for the OAuth callback. It is started before the
/// browser opens, answers only the callback path, accepts one result, and is stopped
/// afterwards. It never binds to other interfaces.
final class ChatGPTLoopbackServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.decentralfreedom.hush.chatgpt.callback")
    private var continuation: CheckedContinuation<URL, Error>?
    private var pending: Result<URL, Error>?

    private init(listener: NWListener) {
        self.listener = listener
    }

    /// Binds the documented port when free, otherwise any free loopback port.
    static func start(preferredPort: UInt16) throws -> ChatGPTLoopbackServer {
        for candidate in [preferredPort, 0] {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: candidate) ?? .any)
            parameters.allowLocalEndpointReuse = false
            guard let listener = try? NWListener(using: parameters) else { continue }
            let server = ChatGPTLoopbackServer(listener: listener)
            if server.run() { return server }
        }
        throw ChatGPTError.network("No free loopback port for the sign-in callback")
    }

    /// Starts listening and waits briefly until the port is bound.
    private func run() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let bound = OSAllocatedUnfairLock<UInt16?>(initialState: nil)
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready:
                bound.withLock { $0 = listener.port?.rawValue }
                ready.signal()
            case .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            self.handle(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
        guard let value = bound.withLock({ $0 }), value != 0 else {
            listener.cancel()
            return false
        }
        port = value
        return true
    }

    func callback(timeout: Duration) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.queue.async {
                            if let pending = self.pending { continuation.resume(with: pending) } else { self.continuation = continuation }
                        }
                    }
                } onCancel: {
                    self.finish(.failure(ChatGPTError.cancelled))
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ChatGPTError.cancelled
            }
            let url = try await group.next()!
            group.cancelAll()
            return url
        }
    }

    func stop() {
        listener.cancel()
        finish(.failure(ChatGPTError.cancelled))
    }

    private func finish(_ result: Result<URL, Error>) {
        queue.async {
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else if self.pending == nil {
                self.pending = result
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let isCallback = target.hasPrefix(ChatGPTOAuth.callbackPath)
            let body = isCallback
                ? "<html><body style=\"font: 15px -apple-system; padding: 48px; text-align: center\"><h2>You can return to hush.</h2><p>This tab can be closed.</p></body></html>"
                : "Not found"
            let head = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isCallback, let url = URL(string: "http://127.0.0.1:\(self.port)\(target)") {
                self.finish(.success(url))
            }
        }
    }
}

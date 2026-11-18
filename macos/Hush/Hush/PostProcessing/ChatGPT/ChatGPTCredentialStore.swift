import Foundation
import Security

/// The ChatGPT connection's records, in the data protection keychain (see KeychainItem),
/// readable only on this Mac.
/// The registration (issued client ID and account) outlives a sign-out so the next
/// sign-in to the same account reuses it, as the documentation asks; the session
/// (tokens) is deleted on sign-out. The host ID is opaque and stable per Mac.
nonisolated struct ChatGPTRegistration: Codable, Equatable, Sendable {
    let clientID: String
    let identity: ChatGPTIdentity
}

nonisolated struct ChatGPTSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date
    var scopes: [String]

    var grantsPlanUsage: Bool { scopes.contains(ChatGPTOAuth.planScope) }

    /// Refresh a minute early, so a request never starts with a token about to expire.
    func needsRefresh(now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) < 60 }
}

nonisolated final class ChatGPTCredentialStore: Sendable {
    private let service: String

    init(service: String = "com.decentralfreedom.hush.chatgpt") {
        self.service = service
    }

    func hostID() throws -> String {
        if let data = try read("host-id"), let value = String(data: data, encoding: .utf8) { return value }
        let value = "urn:uuid:\(UUID().uuidString.lowercased())"
        try write("host-id", Data(value.utf8))
        return value
    }

    func registration() throws -> ChatGPTRegistration? { try decode("registration") }
    func saveRegistration(_ value: ChatGPTRegistration) throws { try write("registration", JSONEncoder().encode(value)) }

    func session() throws -> ChatGPTSession? { try decode("session") }
    func saveSession(_ value: ChatGPTSession) throws { try write("session", JSONEncoder().encode(value)) }
    func deleteSession() throws { try delete("session") }

    /// Forgets the account entirely, keeping only this Mac's host ID.
    func deleteAll() throws {
        try delete("session")
        try delete("registration")
    }

    // MARK: Keychain

    private func item(_ account: String) -> KeychainItem { KeychainItem(service: service, account: account) }

    private func decode<T: Decodable>(_ account: String) throws -> T? {
        guard let data = try read(account) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func read(_ account: String) throws -> Data? {
        do { return try item(account).read() } catch let error as KeychainError { throw ChatGPTError.keychain(error.status) }
    }

    private func write(_ account: String, _ data: Data) throws {
        do { try item(account).write(data) } catch let error as KeychainError { throw ChatGPTError.keychain(error.status) }
    }

    private func delete(_ account: String) throws {
        do { try item(account).delete() } catch let error as KeychainError { throw ChatGPTError.keychain(error.status) }
    }
}

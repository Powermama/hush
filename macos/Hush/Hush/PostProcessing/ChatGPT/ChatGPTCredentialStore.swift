import Foundation
import Security

/// The ChatGPT connection's records, in the Keychain, readable only on this Mac.
/// The registration (issued client ID and account) outlives a sign-out so the next
/// sign-in to the same account reuses it, as the documentation asks; the session
/// (tokens) is deleted on sign-out. The host ID is opaque and stable per Mac.
struct ChatGPTRegistration: Codable, Equatable, Sendable {
    let clientID: String
    let identity: ChatGPTIdentity
}

struct ChatGPTSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date
    var scopes: [String]

    var grantsPlanUsage: Bool { scopes.contains(ChatGPTOAuth.planScope) }

    /// Refresh a minute early, so a request never starts with a token about to expire.
    func needsRefresh(now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) < 60 }
}

final class ChatGPTCredentialStore: Sendable {
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

    private func decode<T: Decodable>(_ account: String) throws -> T? {
        guard let data = try read(account) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ChatGPTError.keychain(status) }
        return data
    }

    private func write(_ account: String, _ data: Data) throws {
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw ChatGPTError.keychain(update) }
        var add = query(account)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ChatGPTError.keychain(status) }
    }

    private func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ChatGPTError.keychain(status) }
    }
}

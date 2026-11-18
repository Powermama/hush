import Foundation
import os
import Security

/// One generic-password item, stored as Apple recommends for new Mac code (TN3137): in the
/// data protection keychain, whose access follows the app's keychain-access-groups
/// entitlement, so macOS never asks "hush wants to use your confidential information".
///
/// - Items written by earlier versions live in the file-based keychain. The first read moves
///   them over and deletes the old copy, so nobody is signed out and no key changes.
/// - A build without the entitlement (an ad-hoc build of a contributor, which has no
///   provisioning profile) gets errSecMissingEntitlement; it then keeps using the file-based
///   keychain, as hush did before.
nonisolated struct KeychainItem: Sendable {
    let service: String
    let account: String

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "Keychain")

    func read() throws -> Data? {
        switch Self.copy(query(protected: true)) {
        case .found(let data): return data
        case .failed(errSecMissingEntitlement): return try Self.value(Self.copy(query(protected: false)))
        case .failed(let status): throw KeychainError(status: status)
        case .notFound:
            // A value from an earlier version, or a build without the entitlement (which reads
            // "not found" here and fails only on writes).
            guard let legacy = try Self.value(Self.copy(query(protected: false))) else { return nil }
            migrate(legacy)
            return legacy
        }
    }

    func write(_ data: Data) throws {
        let status = Self.upsert(query(protected: true), data)
        if status == errSecMissingEntitlement {
            let legacy = Self.upsert(query(protected: false), data)
            guard legacy == errSecSuccess else { throw KeychainError(status: legacy) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Moves a file-based value to the data protection keychain. The old copy is deleted only
    /// after the new one reads back identical; otherwise nothing changes.
    private func migrate(_ legacy: Data) {
        let status = Self.upsert(query(protected: true), legacy)
        guard status == errSecSuccess else {
            if status != errSecMissingEntitlement {
                Self.log.error("Could not move \(service, privacy: .public): \(status)")
            }
            return
        }
        guard case .found(let moved) = Self.copy(query(protected: true)), moved == legacy else {
            Self.log.error("Moved \(service, privacy: .public) but could not read it back; keeping the old copy")
            return
        }
        SecItemDelete(query(protected: false) as CFDictionary)
        Self.log.notice("Moved \(service, privacy: .public) to the data protection keychain")
    }

    /// Removes the item from both keychains.
    func delete() throws {
        for protected in [true, false] {
            let status = SecItemDelete(query(protected: protected) as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement].contains(status) else {
                throw KeychainError(status: status)
            }
        }
    }

    private func query(protected: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if protected { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    private enum Lookup { case found(Data), notFound, failed(OSStatus) }

    private static func copy(_ base: [String: Any]) -> Lookup {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess, let data = result as? Data else { return .failed(status) }
        return .found(data)
    }

    private static func value(_ lookup: Lookup) throws -> Data? {
        switch lookup {
        case .found(let data): return data
        case .notFound: return nil
        case .failed(let status): throw KeychainError(status: status)
        }
    }

    private static func upsert(_ base: [String: Any], _ data: Data) -> OSStatus {
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return update }
        var add = base
        // Apple: "Always use the most restrictive option that makes sense for your app." hush
        // reads these while the user is logged in and the Mac is unlocked; ThisDeviceOnly keeps
        // them out of iCloud and out of other devices' backups.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }
}

nonisolated struct KeychainError: Error, Equatable {
    let status: OSStatus
}

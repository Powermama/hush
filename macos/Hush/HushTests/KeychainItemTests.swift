import Foundation
import Security
import Testing
@testable import Hush

/// The keychain item every store uses: written, read, replaced and deleted the same way
/// whichever keychain the build may use, and items from earlier versions are still found.
@Suite("Keychain item", .serialized)
struct KeychainItemTests {
    private func item() -> KeychainItem {
        KeychainItem(service: "com.decentralfreedom.hush.tests.keychain.\(UUID().uuidString)", account: "value")
    }

    @Test("A value is written, replaced, read back and deleted")
    func roundTrip() throws {
        let item = item()
        defer { try? item.delete() }
        #expect(try item.read() == nil)
        try item.write(Data("first".utf8))
        try item.write(Data("second".utf8))
        #expect(try item.read() == Data("second".utf8))
        try item.delete()
        #expect(try item.read() == nil)
        try item.delete()
    }

    @Test("A value written by an earlier version, in the file-based keychain, is still read")
    func readsLegacyItem() throws {
        let item = item()
        defer { try? item.delete() }
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
            kSecValueData as String: Data("from an earlier version".utf8),
        ]
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)
        #expect(try item.read() == Data("from an earlier version".utf8))
        // Read again: from wherever it now lives, unchanged.
        #expect(try item.read() == Data("from an earlier version".utf8))
        try item.delete()
        #expect(try item.read() == nil)
    }
}

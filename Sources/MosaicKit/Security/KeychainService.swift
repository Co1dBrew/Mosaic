import Foundation
import Security

/// Abstraction over secure storage so the app and tests can swap implementations
/// (PRD §6.1: API keys live in the Keychain, never in plain text).
public protocol KeychainStoring: AnyObject, Sendable {
    func setString(_ value: String?, for account: String) throws
    func string(for account: String) -> String?
    func remove(account: String) throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// `Security`-framework backed Keychain storage (generic password items).
public final class KeychainService: KeychainStoring, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.mosaic.apikeys") {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func setString(_ value: String?, for account: String) throws {
        guard let value, !value.isEmpty else {
            try remove(account: account)
            return
        }
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        // Delete any existing item, then add fresh (simplest correct upsert).
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory implementation for SwiftUI previews and unit tests.
public final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func setString(_ value: String?, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let value, !value.isEmpty { storage[account] = value } else { storage[account] = nil }
    }

    public func string(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    public func remove(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}

/// Keychain account names for stored secrets (one key per provider so switching
/// providers doesn't clobber a previously entered key).
public enum KeychainAccount {
    public static func apiKey(for provider: AIProvider) -> String {
        "apiKey.\(provider.rawValue)"
    }
}

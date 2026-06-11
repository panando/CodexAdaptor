import Security
import Foundation

/// Secure storage for API keys using macOS Keychain.
public final class KeychainService: Sendable {
    public static let shared = KeychainService()

    private let service = "com.codexrouter.apikeys"

    public init() {}

    /// Store an API key for a provider.
    public func storeAPIKey(_ key: String, for providerId: String) throws {
        let account = "provider-\(providerId)"

        // Delete any existing entry first
        try? deleteKey(for: providerId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8)!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    /// Retrieve an API key for a provider.
    public func getAPIKey(for providerId: String) throws -> String? {
        let account = "provider-\(providerId)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }

        return key
    }

    /// Delete an API key for a provider.
    public func deleteKey(for providerId: String) throws {
        let account = "provider-\(providerId)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Check if an API key exists for a provider.
    public func hasKey(for providerId: String) -> Bool {
        do {
            return try getAPIKey(for: providerId) != nil
        } catch {
            return false
        }
    }
}

/// Keychain errors.
public enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store key: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve key: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete key: \(status)"
        }
    }
}

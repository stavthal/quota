import Foundation
import Security

public actor KeychainSecretsStore: SecretsStore {
    private let service: String

    public init(service: String = "com.stavrosthalassinos.Quota") {
        self.service = service
    }

    public func get(_ provider: ProviderID) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretsStoreError.keychain(status)
        }
        return item as? Data
    }

    public func set(_ data: Data, for provider: ProviderID) async throws {
        try await delete(provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretsStoreError.keychain(status)
        }
    }

    public func delete(_ provider: ProviderID) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw SecretsStoreError.keychain(status)
    }
}

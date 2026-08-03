import Foundation

public enum SecretsStoreError: Error, Sendable, Equatable {
    case keychain(OSStatus)
}

public protocol SecretsStore: Sendable {
    func get(_ provider: ProviderID) async throws -> Data?
    func set(_ data: Data, for provider: ProviderID) async throws
    func delete(_ provider: ProviderID) async throws
}

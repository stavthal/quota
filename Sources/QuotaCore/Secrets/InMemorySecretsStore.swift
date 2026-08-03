import Foundation

public actor InMemorySecretsStore: SecretsStore {
    private var values: [ProviderID: Data] = [:]

    public init() {}

    public func get(_ provider: ProviderID) async throws -> Data? {
        values[provider]
    }

    public func set(_ data: Data, for provider: ProviderID) async throws {
        values[provider] = data
    }

    public func delete(_ provider: ProviderID) async throws {
        values[provider] = nil
    }
}

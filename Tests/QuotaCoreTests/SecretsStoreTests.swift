import Foundation
import QuotaCore
import Testing

@Test func inMemorySecretsRoundTrip() async throws {
    let store = InMemorySecretsStore()
    let data = Data("token-abc".utf8)
    try await store.set(data, for: .cursor)
    #expect(try await store.get(.cursor) == data)
    try await store.delete(.cursor)
    #expect(try await store.get(.cursor) == nil)
}

import Foundation
import QuotaCore
import Testing

@Test func appSessionRefreshUpdatesSnapshotsAndSeverity() async throws {
    let store = try UsageStore.inMemory()
    let secrets = InMemorySecretsStore()
    let cursor = MockCursorProvider(utilization: 0.95, secrets: secrets)
    try await cursor.authenticate(using: .sessionToken("test-token"))

    let session = await AppSession(
        providers: [cursor],
        usageStore: store,
        secretsStore: secrets,
        alertEngine: AlertEngine()
    )
    await session.refreshAll()
    #expect(await session.aggregateSeverity == .critical)
    #expect(await session.snapshots[.cursor] != nil)
}

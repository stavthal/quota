import Foundation
import QuotaCore
import Testing

@Test func usageStoreSavesAndReadsLatest() async throws {
    let store = try UsageStore.inMemory()
    let snap = UsageSnapshot(
        providerID: .cursor,
        windows: [
            UsageWindow(
                kind: .fiveHour,
                used: 10,
                limit: 100,
                unit: .percent,
                resetsAt: Date().addingTimeInterval(100)
            ),
        ]
    )
    try await store.save(snap)
    let latest = try await store.latestSnapshot(for: .cursor)
    #expect(latest?.providerID == .cursor)
    #expect(latest?.windows.first?.used == 10)
}

@Test func usageStorePreferencesRoundTrip() async throws {
    let store = try UsageStore.inMemory()
    var prefs = QuotaPreferences.defaults
    prefs.soundEnabled = false
    prefs.warnThreshold = 0.7
    try await store.savePreferences(prefs)
    let loaded = try await store.loadPreferences()
    #expect(loaded.soundEnabled == false)
    #expect(loaded.warnThreshold == 0.7)
}

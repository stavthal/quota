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

@Test func usageStorePersistsProviderOrderAndUsesItForMenuBarPins() async throws {
    let store = try UsageStore.inMemory()
    var prefs = QuotaPreferences.defaults
    prefs.setProviderOrder([.grok, .cursor])
    prefs.menuBarPins = [
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
        MenuBarPin(providerID: .grok, windowKind: .fiveHour),
    ]

    try await store.savePreferences(prefs)
    let loaded = try await store.loadPreferences()

    #expect(loaded.providerOrder == [.grok, .cursor, .codex, .claude, .copilot, .opencode, .gemini])
    #expect(loaded.orderedMenuBarPins.map(\.providerID) == [.grok, .cursor])
}

@Test func preferencesMoveProviderReordersPinnedMenuBarGroups() {
    var preferences = QuotaPreferences.defaults
    preferences.menuBarPins = [
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
        MenuBarPin(providerID: .opencode, windowKind: .weekly),
    ]

    let didMove = preferences.moveProvider(from: 5, to: 0)

    #expect(didMove)
    #expect(preferences.providerOrder.first == .opencode)
    #expect(preferences.orderedMenuBarPins.map(\.providerID) == [.opencode, .cursor])
}

import Foundation
import QuotaCore
import Testing

@Test func menuBarStatusFormatterBuildsCompactSegments() {
    let resets = Date().addingTimeInterval(3600)
    let snapshots: [ProviderID: UsageSnapshot] = [
        .cursor: UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(kind: .cursorAuto, used: 62, limit: 100, unit: .percent, resetsAt: resets),
                UsageWindow(kind: .cursorAPI, used: 10, limit: 100, unit: .percent, resetsAt: resets),
            ]
        ),
        .codex: UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, used: 41, limit: 100, unit: .percent, resetsAt: resets),
            ]
        ),
    ]
    let pins = [
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
        MenuBarPin(providerID: .codex, windowKind: .fiveHour),
    ]
    let text = MenuBarStatusFormatter.statusText(pins: pins, snapshots: snapshots)
    #expect(text == "Cur·M 62% · GPT·5h 41%")
}

@Test func menuBarStatusFormatterGroupsPinnedValuesUnderOneProviderIcon() {
    let resets = Date().addingTimeInterval(3600)
    let snapshots: [ProviderID: UsageSnapshot] = [
        .cursor: UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(kind: .cursorAuto, used: 62, limit: 100, unit: .percent, resetsAt: resets),
                UsageWindow(kind: .cursorAPI, used: 10, limit: 100, unit: .percent, resetsAt: resets),
            ]
        ),
        .codex: UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .weekly, used: 41, limit: 100, unit: .percent, resetsAt: resets),
            ]
        ),
    ]
    let pins = [
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
        MenuBarPin(providerID: .cursor, windowKind: .cursorAPI),
        MenuBarPin(providerID: .codex, windowKind: .weekly),
    ]

    let groups = MenuBarStatusFormatter.statusGroups(pins: pins, snapshots: snapshots)

    #expect(groups.map(\.providerID) == [.cursor, .codex])
    #expect(groups[0].values == ["62%", "10%"])
    #expect(groups[1].values == ["41%"])
}

@Test func menuBarStatusFormatterSkipsMissingWindows() {
    let pins = [MenuBarPin(providerID: .grok, windowKind: .weekly)]
    let text = MenuBarStatusFormatter.statusText(pins: pins, snapshots: [:])
    #expect(text == nil)
}

@Test func menuBarStatusFormatterCreditsWithoutLimit() {
    let window = UsageWindow(
        kind: .weekly,
        used: 12.4,
        limit: 0,
        unit: .credits,
        resetsAt: Date()
    )
    #expect(MenuBarStatusFormatter.valueLabel(for: window) == "$12.4")
}

@Test func quotaPreferencesCapsMenuBarPins() {
    var prefs = QuotaPreferences.defaults
    let kinds: [UsageWindowKind] = [.cursorAuto, .cursorAPI, .fiveHour, .weekly]
    for (index, kind) in kinds.enumerated() {
        let pin = MenuBarPin(providerID: .cursor, windowKind: kind)
        let ok = prefs.setMenuBarPin(pin, enabled: true)
        if index < QuotaPreferences.maxMenuBarPins {
            #expect(ok)
        } else {
            #expect(!ok)
        }
    }
    #expect(prefs.menuBarPins.count == QuotaPreferences.maxMenuBarPins)

    prefs.setMenuBarPin(MenuBarPin(providerID: .cursor, windowKind: .cursorAuto), enabled: false)
    #expect(prefs.menuBarPins.count == 2)
    let added = prefs.setMenuBarPin(MenuBarPin(providerID: .cursor, windowKind: .weekly), enabled: true)
    #expect(added)
    #expect(prefs.menuBarPins.count == 3)
}

@Test func usageStorePreferencesRoundTripMenuBarPins() async throws {
    let store = try UsageStore.inMemory()
    var prefs = QuotaPreferences.defaults
    prefs.menuBarPins = [
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
        MenuBarPin(providerID: .codex, windowKind: .weekly),
    ]
    try await store.savePreferences(prefs)
    let loaded = try await store.loadPreferences()
    #expect(loaded.menuBarPins == prefs.menuBarPins)
}

@Test func quotaPreferencesKeepsGeminiPinsDuringLegacyDecode() throws {
    let data = Data(
        #"{"menuBarPins":[{"providerID":"gemini","windowKind":"weekly"},{"providerID":"cursor","windowKind":"cursorAuto"}]}"#.utf8
    )

    let preferences = try JSONDecoder().decode(QuotaPreferences.self, from: data)

    #expect(preferences.menuBarPins == [
        MenuBarPin(providerID: .gemini, windowKind: .weekly),
        MenuBarPin(providerID: .cursor, windowKind: .cursorAuto),
    ])
}

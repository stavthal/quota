import Foundation
import QuotaCore
import Testing

@Test func alertEngineEmitsWarnAtEightyPercent() {
    let snap = UsageSnapshot(
        providerID: .cursor,
        windows: [
            UsageWindow(
                kind: .fiveHour,
                used: 80,
                limit: 100,
                unit: .percent,
                resetsAt: Date().addingTimeInterval(1000)
            ),
        ]
    )
    var cooldown = AlertCooldownState()
    let result = AlertEngine().evaluate(
        snapshots: [snap],
        thresholds: .defaults,
        cooldown: &cooldown,
        now: Date()
    )
    #expect(result.severity == .warn)
    #expect(result.events.count == 1)
    #expect(result.events[0].severity == .warn)
}

@Test func alertEngineDoesNotRepeatSameThresholdUntilReset() {
    let resets = Date().addingTimeInterval(1000)
    let snap = UsageSnapshot(
        providerID: .cursor,
        windows: [
            UsageWindow(kind: .fiveHour, used: 85, limit: 100, unit: .percent, resetsAt: resets),
        ]
    )
    var cooldown = AlertCooldownState()
    let engine = AlertEngine()
    _ = engine.evaluate(snapshots: [snap], thresholds: .defaults, cooldown: &cooldown, now: Date())
    let second = engine.evaluate(snapshots: [snap], thresholds: .defaults, cooldown: &cooldown, now: Date())
    #expect(second.events.isEmpty)
    #expect(second.severity == .warn)
}

@Test func alertEngineEscalatesWarnToCritical() {
    let resets = Date().addingTimeInterval(1000)
    var cooldown = AlertCooldownState()
    let engine = AlertEngine()
    let warnSnap = UsageSnapshot(
        providerID: .codex,
        windows: [UsageWindow(kind: .weekly, used: 80, limit: 100, unit: .percent, resetsAt: resets)]
    )
    _ = engine.evaluate(snapshots: [warnSnap], thresholds: .defaults, cooldown: &cooldown, now: Date())
    let criticalSnap = UsageSnapshot(
        providerID: .codex,
        windows: [UsageWindow(kind: .weekly, used: 95, limit: 100, unit: .percent, resetsAt: resets)]
    )
    let result = engine.evaluate(
        snapshots: [criticalSnap],
        thresholds: .defaults,
        cooldown: &cooldown,
        now: Date()
    )
    #expect(result.events.map(\.severity) == [.critical])
    #expect(result.severity == .critical)
}

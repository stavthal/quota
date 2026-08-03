import Foundation
import QuotaCore
import Testing

@Test func usageWindowUtilizationClamp() {
    let window = UsageWindow(
        kind: .fiveHour,
        used: 90,
        limit: 100,
        unit: .percent,
        resetsAt: Date().addingTimeInterval(3600)
    )
    #expect(window.utilization == 0.9)
}

@Test func usageWindowUtilizationZeroLimit() {
    let window = UsageWindow(
        kind: .weekly,
        used: 10,
        limit: 0,
        unit: .requests,
        resetsAt: Date()
    )
    #expect(window.utilization == 0)
}

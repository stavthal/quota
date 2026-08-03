import Foundation
import QuotaCore
import Testing

@Test func openCodeUsageParserMapsGoCaps() {
    let auth = OpenCodeLocalAuth(
        hasGoKey: true,
        hasZenKey: false,
        accountHint: "OpenCode Go"
    )
    let spend = OpenCodeSpendSnapshot(
        fiveHourGoUSD: 3.5,
        weeklyGoUSD: 10,
        monthlyGoUSD: 22,
        hasGoHistory: true,
        hasHostedHistory: true
    )
    let snap = OpenCodeUsageParser.snapshot(spend: spend, auth: auth)
    #expect(snap.providerID == .opencode)
    #expect(snap.windows.contains { $0.kind == .fiveHour && abs($0.used - 3.5) < 0.01 && $0.limit == 12 })
    #expect(snap.windows.contains { $0.kind == .weekly && abs($0.used - 10) < 0.01 && $0.limit == 30 })
    #expect(snap.windows.count == 2)
}

@Test func openCodeUsageParserMapsZenHostedSpendOnly() {
    let auth = OpenCodeLocalAuth(
        hasGoKey: false,
        hasZenKey: true,
        accountHint: "OpenCode Zen"
    )
    let spend = OpenCodeSpendSnapshot(
        weeklyHostedUSD: 1.25,
        monthlyHostedUSD: 4.5,
        hasHostedHistory: true,
        backends: [
            OpenCodeBackendUsage(
                providerKey: "openrouter",
                displayName: "OpenRouter",
                weeklyUSD: 2.0,
                monthlyUSD: 5.0
            )
        ]
    )
    let snap = OpenCodeUsageParser.snapshot(spend: spend, auth: auth)
    #expect(snap.windows.count == 2)
    #expect(snap.windows.contains { $0.kind == .weekly && abs($0.used - 1.25) < 0.01 && $0.limit == 0 })
    #expect(snap.windows.contains { $0.kind == .monthly && abs($0.used - 4.5) < 0.01 && $0.limit == 0 })
}

@Test func openCodeSubscriptionLabelPrefersGo() {
    let auth = OpenCodeLocalAuth(hasGoKey: true, hasZenKey: true, accountHint: "x")
    let spend = OpenCodeSpendSnapshot(hasGoHistory: true)
    #expect(OpenCodeUsageParser.subscriptionLabel(auth: auth, spend: spend) == "OpenCode Go")
}

@Test func openCodeTopBackendsCapsAtThree() {
    let backends = (1...5).map { i in
        OpenCodeBackendUsage(
            providerKey: "p\(i)",
            displayName: "P\(i)",
            weeklyUSD: Double(i),
            monthlyUSD: Double(i * 10)
        )
    }
    let spend = OpenCodeSpendSnapshot(backends: backends)
    #expect(spend.topBackends(limit: 3).count == 3)
    #expect(spend.topBackends(limit: 3).map(\.providerKey) == ["p1", "p2", "p3"])
}

@Test func openCodeBackendDisplayName() {
    #expect(OpenCodeBackendUsage.displayName(for: "openrouter") == "OpenRouter")
    #expect(OpenCodeBackendUsage.displayName(for: "github-copilot") == "Copilot")
}

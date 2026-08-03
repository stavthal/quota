import Foundation
import QuotaCore
import Testing

@Test func codexUsageMapsFiveHourAndWeeklyWindows() throws {
    let url = try #require(
        Bundle.module.url(forResource: "codex_usage", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: data)
    let snap = try CodexUsageParser.snapshot(from: dto)

    #expect(snap.providerID == .codex)
    #expect(snap.windows.contains { $0.kind == .fiveHour && abs($0.used - 42.5) < 0.01 })
    #expect(snap.windows.contains { $0.kind == .weekly && abs($0.used - 18.0) < 0.01 })
}

@Test func codexUsageMapsWeeklyPrimaryWhenPlanHasNoFiveHourWindow() throws {
    let url = try #require(
        Bundle.module.url(forResource: "codex_usage_weekly_only", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: data)
    let snap = try CodexUsageParser.snapshot(from: dto)

    #expect(snap.windows.count == 1)
    #expect(snap.windows[0].kind == .weekly)
    #expect(abs(snap.windows[0].used - 33.0) < 0.01)
    #expect(!snap.windows.contains { $0.kind == .fiveHour })
}

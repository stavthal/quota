import Foundation
import QuotaCore
import Testing

@Test func claudeUsageMapsFiveHourAndWeeklyWindows() throws {
    let data = try #require(
        """
        {
          "five_hour": { "utilization": 42.5, "resets_at": "2026-08-07T15:00:00Z" },
          "seven_day": { "utilization": 18, "resets_at": "2026-08-12T12:00:00Z" }
        }
        """.data(using: .utf8)
    )

    let snapshot = try ClaudeUsageParser.snapshot(from: data)

    #expect(snapshot.providerID == .claude)
    #expect(snapshot.windows.contains { $0.kind == .fiveHour && $0.used == 42.5 && $0.limit == 100 })
    #expect(snapshot.windows.contains { $0.kind == .weekly && $0.used == 18 && $0.limit == 100 })
}

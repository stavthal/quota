import Foundation
import QuotaCore
import Testing

@Test func claudeLocalUsageReaderReadsCachedWindowsWithoutCredentials() throws {
    let fileURL = URL.temporaryDirectory.appending(path: "claude-usage-cache-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let data = try #require(
        """
        {
          "oauthAccount": { "emailAddress": "person@example.com" },
          "cachedUsageUtilization": {
            "fetchedAtMs": 1786370000000,
            "utilization": {
              "five_hour": { "utilization": 42.5, "resets_at": "2026-08-10T20:00:00Z" },
              "seven_day": { "utilization": 18, "resets_at": "2026-08-15T12:00:00Z" }
            }
          }
        }
        """.data(using: .utf8)
    )
    try data.write(to: fileURL)

    let usage = try ClaudeLocalUsageReader(configFileURL: fileURL).read()

    #expect(usage.accountHint == "person@example.com")
    #expect(usage.snapshot.providerID == .claude)
    #expect(usage.snapshot.windows.contains { $0.kind == .fiveHour && $0.used == 42.5 })
    #expect(usage.snapshot.windows.contains { $0.kind == .weekly && $0.used == 18 })
}

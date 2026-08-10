import Foundation
import QuotaCore
import Testing

@Test func geminiQuotaParserMapsGeminiFiveHourAndWeekly() throws {
    let url = try #require(
        Bundle.module.url(forResource: "gemini_quota_summary", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let summary = try GeminiQuotaParser.summary(from: data)

    #expect(summary.buckets.count == 4)
    let gemini = summary.buckets.filter(\.isGeminiGroup)
    #expect(gemini.count == 2)

    let snap = GeminiQuotaParser.snapshot(from: summary)
    #expect(snap.providerID == .gemini)

    let five = try #require(snap.windows.first { $0.kind == .fiveHour })
    #expect(abs(five.used - 37.5) < 0.01)
    #expect(five.limit == 100)
    #expect(five.unit == .percent)

    let week = try #require(snap.windows.first { $0.kind == .weekly })
    #expect(abs(week.used - 5.0) < 0.01)

    #expect(snap.models.count == 4)
}

@Test func geminiLocalAuthReaderParsesCLITokenFile() throws {
    let url = try #require(
        Bundle.module.url(forResource: "gemini_cli_oauth_token", withExtension: "json", subdirectory: "Fixtures")
    )
    let reader = GeminiLocalAuthReader(cliTokenURL: url, databaseURLs: [])
    let auth = try reader.read()
    #expect(auth.accessToken == "ya29.test-access-token")
    #expect(auth.refreshToken == "1//test-refresh-token")
    #expect(auth.email == "user@example.com")
    #expect(auth.source == "cli")
    #expect(auth.expiresAt != nil)
}

@Test func geminiQuotaParserReadsProjectFromLoadCodeAssist() throws {
    let json = """
    {
      "cloudaicompanionProject": "rising-fact-p41fc",
      "currentTier": { "name": "Pro", "id": "pro-tier" },
      "planInfo": { "planType": "PRO" }
    }
    """.data(using: .utf8)!
    #expect(GeminiQuotaParser.projectID(fromLoadCodeAssist: json) == "rising-fact-p41fc")
    #expect(GeminiQuotaParser.planName(fromLoadCodeAssist: json) == "Pro")
}

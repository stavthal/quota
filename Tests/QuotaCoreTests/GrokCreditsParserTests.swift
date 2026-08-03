import Foundation
import QuotaCore
import Testing

@Test func grokCreditsParserReadsWeeklyPercentFromFixture() throws {
    let url = try #require(
        Bundle.module.url(forResource: "grok_credits_response", withExtension: "bin", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let config = try GrokCreditsParser.config(fromGrpcWebBody: data)

    #expect(abs(config.creditUsagePercent - 5.0) < 0.01)
    #expect(config.billingPeriodStart != nil)
    #expect(config.billingPeriodEnd != nil)

    let snap = GrokCreditsParser.snapshot(from: config)
    #expect(snap.providerID == .grok)
    #expect(snap.windows.contains { $0.kind == .weekly && abs($0.used - 5.0) < 0.01 })
}

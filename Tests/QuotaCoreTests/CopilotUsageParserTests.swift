import Foundation
import QuotaCore
import Testing

@Test func copilotUsageMapsCreditsWindow() throws {
    let url = try #require(
        Bundle.module.url(forResource: "copilot_usage", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let dto = try JSONDecoder().decode(CopilotUsageDTO.self, from: data)
    let snap = try CopilotUsageParser.snapshot(from: dto)

    #expect(snap.providerID == .copilot)
    #expect(snap.windows.count == 1)
    #expect(snap.windows[0].kind == .copilotCredits)
    #expect(abs(snap.windows[0].utilization - 0.001) < 0.001)
}

import Foundation
import QuotaCore
import Testing

@Test func cursorUsageSummaryMapsAutoAndAPIPools() throws {
    let url = try #require(
        Bundle.module.url(forResource: "cursor_usage_summary", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let dto = try JSONDecoder().decode(CursorUsageSummaryDTO.self, from: data)
    let snap = try CursorUsageSummaryParser.snapshot(from: dto)

    #expect(snap.providerID == .cursor)
    #expect(snap.windows.count == 2)
    #expect(snap.windows.contains { $0.kind == .cursorAuto && abs($0.used - 22.5) < 0.01 })
    #expect(snap.windows.contains { $0.kind == .cursorAPI && abs($0.used - 81.0) < 0.01 })
    #expect(snap.windows.allSatisfy { $0.unit == .percent })
}

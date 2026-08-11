import Foundation
import QuotaCore
import Testing

@Test func geminiUsageParserMapsGeminiWeeklyBucketFromAgyResponse() throws {
    let url = try #require(
        Bundle.module.url(forResource: "agy_usage_response", withExtension: "json", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    let snapshot = try GeminiUsageParser.snapshot(from: data)

    #expect(snapshot.providerID == .gemini)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].kind == .weekly)
    #expect(abs(snapshot.windows[0].used - 32) < 0.001)
    #expect(snapshot.windows[0].limit == 100)
}

@Test func geminiUsageParserThrowsWhenAgyReportsFailure() {
    let data = Data(#"{"status":"ERROR"}"#.utf8)
    var caught: GeminiProviderError?
    do {
        _ = try GeminiUsageParser.snapshot(from: data)
    } catch let error as GeminiProviderError {
        caught = error
    } catch {}
    #expect(caught == .notAuthenticated)
}

@Test func geminiUsageParserThrowsOnMalformedJSON() {
    let data = Data("not json".utf8)
    var caught: GeminiProviderError?
    do {
        _ = try GeminiUsageParser.snapshot(from: data)
    } catch let error as GeminiProviderError {
        caught = error
    } catch {}
    #expect(caught == .invalidResponse)
}

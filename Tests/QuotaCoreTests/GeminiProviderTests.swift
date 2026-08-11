import Foundation
import QuotaCore
import Testing

private struct FakeGeminiRunner: GeminiCLIUsageRunning {
    var result: Result<Data, Error>

    func fetchUsage() async throws -> Data {
        try result.get()
    }
}

private func fixtureData() throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: "agy_usage_response", withExtension: "json", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
}

@Test func geminiProviderReportsSignedInWhenAgySucceeds() async throws {
    let provider = GeminiProvider(trackingEnabled: true, runner: FakeGeminiRunner(result: .success(try fixtureData())))

    guard case .signedIn = await provider.authStatus() else {
        #expect(Bool(false), "expected signedIn when agy returns a parseable response")
        return
    }
    let snapshot = try await provider.fetchSnapshot()
    #expect(snapshot.providerID == .gemini)
}

@Test func geminiProviderFailsClosedWhenAgyIsMissing() async {
    let provider = GeminiProvider(
        trackingEnabled: true,
        runner: FakeGeminiRunner(result: .failure(GeminiProviderError.cliMissing))
    )

    #expect(await provider.authStatus() == .signedOut)
    var threw = false
    do {
        _ = try await provider.fetchSnapshot()
    } catch {
        threw = true
    }
    #expect(threw)
}

@Test func geminiProviderClearAuthDisablesTracking() async throws {
    let provider = GeminiProvider(trackingEnabled: true, runner: FakeGeminiRunner(result: .success(try fixtureData())))
    try await provider.clearAuth()

    #expect(await provider.authStatus() == .signedOut)
}

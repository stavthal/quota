import Foundation

/// Gemini (Antigravity) usage adapter. Shells out to the user's own installed, already
/// authenticated `agy` CLI in its documented headless mode (`agy -p "/usage"`) — the same
/// vendor-CLI pattern already used for Copilot. Headroom never reads, exports, or persists
/// any Antigravity credential; authentication is entirely `agy`'s own concern.
public actor GeminiProvider: Provider {
    public nonisolated let id: ProviderID = .gemini
    public nonisolated let displayName = "Gemini"

    private let runner: any GeminiCLIUsageRunning
    private var trackingEnabled: Bool

    public init(trackingEnabled: Bool, runner: any GeminiCLIUsageRunning = GeminiCLIUsageRunner()) {
        self.trackingEnabled = trackingEnabled
        self.runner = runner
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let data = try? await runner.fetchUsage(),
              (try? GeminiUsageParser.snapshot(from: data)) != nil
        else { return .signedOut }
        return .signedIn(accountHint: "Antigravity")
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        let data = try await runner.fetchUsage()
        _ = try GeminiUsageParser.snapshot(from: data)
        trackingEnabled = true
    }

    public func clearAuth() async throws { trackingEnabled = false }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw GeminiProviderError.notAuthenticated }
        let data = try await runner.fetchUsage()
        return try GeminiUsageParser.snapshot(from: data)
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedIn: .healthy
        case .signedOut, .expired, .invalid: .authRequired
        }
    }
}

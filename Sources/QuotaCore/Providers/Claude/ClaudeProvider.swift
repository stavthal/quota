import Foundation

/// Guarded Claude Code compatibility adapter. It reads the CLI's local usage cache and never
/// accesses Keychain credentials or makes a provider request.
public actor ClaudeProvider: Provider {
    public nonisolated let id: ProviderID = .claude
    public nonisolated let displayName = "Claude Code"

    private let usageReader: ClaudeLocalUsageReader
    private var trackingEnabled: Bool

    public init(trackingEnabled: Bool, usageReader: ClaudeLocalUsageReader = ClaudeLocalUsageReader()) {
        self.trackingEnabled = trackingEnabled
        self.usageReader = usageReader
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled, let usage = try? usageReader.read() else { return .signedOut }
        return .signedIn(accountHint: usage.accountHint ?? "Claude Code")
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        _ = try usageReader.read()
        trackingEnabled = true
    }

    public func clearAuth() async throws { trackingEnabled = false }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw ClaudeProviderError.notAuthenticated }
        return try usageReader.read().snapshot
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedIn: .healthy
        case .signedOut, .expired, .invalid: .authRequired
        }
    }
}

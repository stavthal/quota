import Foundation

/// Guarded Claude Code compatibility adapter. It uses a read-only local credential file and
/// fails closed when current Claude Code stores the session only in Keychain.
public actor ClaudeProvider: Provider {
    public nonisolated let id: ProviderID = .claude
    public nonisolated let displayName = "Claude Code"

    private let authReader: ClaudeLocalAuthReader
    private let session: URLSession
    private var trackingEnabled: Bool

    public static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(trackingEnabled: Bool, authReader: ClaudeLocalAuthReader = ClaudeLocalAuthReader(), session: URLSession = .shared) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled, let auth = try? authReader.read() else { return .signedOut }
        return .signedIn(accountHint: auth.accountHint ?? "Claude Code")
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        _ = try authReader.read()
        trackingEnabled = true
    }

    public func clearAuth() async throws { trackingEnabled = false }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw ClaudeProviderError.notAuthenticated }
        let auth = try authReader.read()
        var request = URLRequest(url: Self.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeProviderError.transport("Invalid Claude Code usage response")
        }
        guard (200..<300).contains(http.statusCode) else { throw ClaudeProviderError.httpStatus(http.statusCode) }
        do {
            return try ClaudeUsageParser.snapshot(from: data)
        } catch let error as ClaudeProviderError {
            throw error
        } catch {
            throw ClaudeProviderError.transport("Usage decode failed: \(error.localizedDescription)")
        }
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedIn: .healthy
        case .signedOut, .expired, .invalid: .authRequired
        }
    }
}

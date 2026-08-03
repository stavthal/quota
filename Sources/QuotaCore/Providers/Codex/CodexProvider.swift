import Foundation

/// Live Codex provider. Reads `~/.codex/auth.json` only — never stores tokens in Quota Keychain.
public actor CodexProvider: Provider {
    public nonisolated let id: ProviderID = .codex
    public nonisolated let displayName = "ChatGPT"

    private let authReader: CodexLocalAuthReader
    private let session: URLSession
    private var trackingEnabled: Bool

    public init(
        trackingEnabled: Bool,
        authReader: CodexLocalAuthReader = CodexLocalAuthReader(),
        session: URLSession = .shared
    ) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let local = try? authReader.read() else { return .signedOut }
        let hint = local.authMode ?? local.accountID ?? "Codex"
        return .signedIn(accountHint: hint)
    }

    public func authenticate(using method: AuthMethod) async throws {
        switch method {
        case .localApp, .sessionToken:
            _ = try authReader.read()
            trackingEnabled = true
        }
    }

    public func clearAuth() async throws {
        trackingEnabled = false
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw CodexProviderError.notAuthenticated }
        let local = try authReader.read()
        return try await fetchUsage(with: local)
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    private func fetchUsage(with auth: CodexLocalAuth) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexProviderError.transport("Invalid usage response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexProviderError.httpStatus(http.statusCode)
        }

        do {
            let dto = try JSONDecoder().decode(CodexUsageDTO.self, from: data)
            return try CodexUsageParser.snapshot(from: dto)
        } catch {
            let preview = String(data: data.prefix(180), encoding: .utf8) ?? "non-utf8"
            throw CodexProviderError.transport(
                "Usage decode failed: \(error.localizedDescription) · \(preview)"
            )
        }
    }
}

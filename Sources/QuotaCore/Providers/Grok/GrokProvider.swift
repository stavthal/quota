import Foundation

/// Live Grok provider. Reads `~/.grok/auth.json` from Grok CLI — never stores tokens in Quota Keychain.
public actor GrokProvider: Provider {
    public nonisolated let id: ProviderID = .grok
    public nonisolated let displayName = "Grok"

    private let authReader: GrokLocalAuthReader
    private let session: URLSession
    private var trackingEnabled: Bool

    public static let creditsEndpoint = URL(
        string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig"
    )!

    public init(
        trackingEnabled: Bool,
        authReader: GrokLocalAuthReader = GrokLocalAuthReader(),
        session: URLSession = .shared
    ) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let local = try? authReader.read() else { return .signedOut }
        if let expires = local.expiresAt, expires < Date().addingTimeInterval(-3600) {
            // Soft expired: still try; many tokens remain valid past expires_at until refresh fails.
        }
        return .signedIn(accountHint: local.email ?? "Grok")
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
        guard trackingEnabled else { throw GrokProviderError.notAuthenticated }
        let local = try authReader.read()
        let body = try await fetchCreditsBody(with: local.accessToken)
        let config = try GrokCreditsParser.config(fromGrpcWebBody: body)
        return GrokCreditsParser.snapshot(from: config)
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    private func fetchCreditsBody(with token: String) async throws -> Data {
        var request = URLRequest(url: Self.creditsEndpoint)
        request.httpMethod = "POST"
        // Empty protobuf message inside a gRPC-web data frame.
        request.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "X-Grpc-Web")
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        request.setValue("https://grok.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GrokProviderError.transport("Invalid usage response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw GrokProviderError.transport("Auth expired — run `grok login`")
            }
            throw GrokProviderError.httpStatus(http.statusCode)
        }
        return data
    }
}

import Foundation

/// Live Cursor provider. Tokens are read from the Cursor app DB only — never copied into Quota Keychain
/// (ad-hoc signed builds otherwise spam Keychain ACL prompts).
public actor CursorProvider: Provider {
    public nonisolated let id: ProviderID = .cursor
    public nonisolated let displayName = "Cursor"

    private let authReader: CursorLocalAuthReader
    private let session: URLSession
    private let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private var trackingEnabled: Bool

    public init(
        trackingEnabled: Bool,
        authReader: CursorLocalAuthReader = CursorLocalAuthReader(),
        session: URLSession = .shared
    ) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let local = try? authReader.read() else { return .signedOut }
        return .signedIn(accountHint: local.email ?? local.membershipType ?? "Cursor")
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
        guard trackingEnabled else { throw CursorProviderError.notAuthenticated }
        var local = try authReader.read()
        local = try await refreshIfNeeded(local)

        do {
            return try await fetchSummary(with: local.accessToken)
        } catch CursorProviderError.httpStatus(401), CursorProviderError.httpStatus(403) {
            local = try await forceRefresh(local)
            return try await fetchSummary(with: local.accessToken)
        }
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    private func refreshIfNeeded(_ credentials: CursorLocalAuth) async throws -> CursorLocalAuth {
        if let exp = jwtExpiration(credentials.accessToken), exp.timeIntervalSinceNow > 5 * 60 {
            return credentials
        }
        return try await forceRefresh(credentials)
    }

    private func forceRefresh(_ credentials: CursorLocalAuth) async throws -> CursorLocalAuth {
        if let local = try? authReader.read(), !local.accessToken.isEmpty {
            if let exp = jwtExpiration(local.accessToken), exp.timeIntervalSinceNow > 5 * 60 {
                return local
            }
        }

        guard let refresh = credentials.refreshToken, !refresh.isEmpty else {
            throw CursorProviderError.refreshFailed
        }

        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refresh,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorProviderError.refreshFailed
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String,
            !access.isEmpty,
            (json["shouldLogout"] as? Bool) != true
        else {
            throw CursorProviderError.refreshFailed
        }

        return CursorLocalAuth(
            accessToken: access,
            refreshToken: credentials.refreshToken,
            email: credentials.email,
            membershipType: credentials.membershipType
        )
    }

    private func fetchSummary(with accessToken: String) async throws -> UsageSnapshot {
        let cookie = workosCookie(from: accessToken)
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorProviderError.transport("Invalid usage response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorProviderError.httpStatus(http.statusCode)
        }

        do {
            let dto = try JSONDecoder().decode(CursorUsageSummaryDTO.self, from: data)
            return try CursorUsageSummaryParser.snapshot(from: dto)
        } catch {
            let preview = String(data: data.prefix(180), encoding: .utf8) ?? "non-utf8"
            throw CursorProviderError.transport(
                "Usage decode failed: \(error.localizedDescription) · \(preview)"
            )
        }
    }

    private func workosCookie(from accessToken: String) -> String {
        if accessToken.contains("%3A%3A") { return accessToken }
        if accessToken.contains("::") {
            return accessToken.replacingOccurrences(of: "::", with: "%3A%3A")
        }
        if let sub = jwtSubject(accessToken) {
            return "\(sub)%3A%3A\(accessToken)"
        }
        return accessToken
    }

    private func jwtSubject(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return json["sub"] as? String
    }

    private func jwtExpiration(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

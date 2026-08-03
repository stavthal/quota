import Foundation

struct CursorStoredCredentials: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var email: String?
    var membershipType: String?
}

public actor CursorProvider: Provider {
    public nonisolated let id: ProviderID = .cursor
    public nonisolated let displayName = "Cursor"

    private let secrets: any SecretsStore
    private let authReader: CursorLocalAuthReader
    private let session: URLSession
    private let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    public init(
        secrets: any SecretsStore,
        authReader: CursorLocalAuthReader = CursorLocalAuthReader(),
        session: URLSession = .shared
    ) {
        self.secrets = secrets
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        if let stored = try? await loadStored() {
            return .signedIn(accountHint: stored.email ?? stored.membershipType ?? "Cursor")
        }
        if let local = try? authReader.read() {
            return .signedIn(accountHint: local.email ?? "Cursor app (not connected yet)")
        }
        return .signedOut
    }

    public func authenticate(using method: AuthMethod) async throws {
        switch method {
        case .localApp:
            let local = try authReader.read()
            try await persist(CursorStoredCredentials(
                accessToken: local.accessToken,
                refreshToken: local.refreshToken,
                email: local.email,
                membershipType: local.membershipType
            ))
        case .sessionToken(let token):
            try await persist(CursorStoredCredentials(accessToken: token))
        }
    }

    public func clearAuth() async throws {
        try await secrets.delete(.cursor)
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var credentials = try await requireCredentials()
        credentials = try await refreshIfNeeded(credentials)

        do {
            return try await fetchSummary(with: credentials.accessToken)
        } catch CursorProviderError.httpStatus(401), CursorProviderError.httpStatus(403) {
            credentials = try await forceRefresh(credentials)
            return try await fetchSummary(with: credentials.accessToken)
        }
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut:
            return .authRequired
        case .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    // MARK: - Private

    private func requireCredentials() async throws -> CursorStoredCredentials {
        if let stored = try await loadStored() {
            return stored
        }
        // Auto-bind from the Cursor app if the user never pressed Connect.
        let local = try authReader.read()
        let credentials = CursorStoredCredentials(
            accessToken: local.accessToken,
            refreshToken: local.refreshToken,
            email: local.email,
            membershipType: local.membershipType
        )
        try await persist(credentials)
        return credentials
    }

    private func loadStored() async throws -> CursorStoredCredentials? {
        guard let data = try await secrets.get(.cursor) else { return nil }
        return try JSONDecoder().decode(CursorStoredCredentials.self, from: data)
    }

    private func persist(_ credentials: CursorStoredCredentials) async throws {
        let data = try JSONEncoder().encode(credentials)
        try await secrets.set(data, for: .cursor)
    }

    private func refreshIfNeeded(_ credentials: CursorStoredCredentials) async throws -> CursorStoredCredentials {
        if let exp = jwtExpiration(credentials.accessToken), exp.timeIntervalSinceNow > 5 * 60 {
            return credentials
        }
        return try await forceRefresh(credentials)
    }

    private func forceRefresh(_ credentials: CursorStoredCredentials) async throws -> CursorStoredCredentials {
        // Prefer a fresh token from the Cursor app DB when available.
        if let local = try? authReader.read(), !local.accessToken.isEmpty {
            var updated = credentials
            updated.accessToken = local.accessToken
            updated.refreshToken = local.refreshToken ?? updated.refreshToken
            updated.email = local.email ?? updated.email
            updated.membershipType = local.membershipType ?? updated.membershipType
            try await persist(updated)
            if let exp = jwtExpiration(updated.accessToken), exp.timeIntervalSinceNow > 5 * 60 {
                return updated
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
        guard let http = response as? HTTPURLResponse else {
            throw CursorProviderError.transport("Invalid refresh response")
        }
        guard http.statusCode == 200 else {
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

        var updated = credentials
        updated.accessToken = access
        try await persist(updated)
        return updated
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

        let dto = try JSONDecoder().decode(CursorUsageSummaryDTO.self, from: data)
        return try CursorUsageSummaryParser.snapshot(from: dto)
    }

    private func workosCookie(from accessToken: String) -> String {
        if accessToken.contains("%3A%3A") {
            return accessToken
        }
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

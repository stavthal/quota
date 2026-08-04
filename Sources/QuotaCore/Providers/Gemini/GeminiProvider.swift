import Foundation

/// Live Gemini (Antigravity) provider.
///
/// Auth sources (in order):
/// 1. `~/.gemini/antigravity-cli/antigravity-oauth-token` from `agy`
/// 2. Antigravity IDE `state.vscdb` OAuth / auth status
///
/// Usage comes from Google Cloud Code Assist `retrieveUserQuotaSummary`
/// (Gemini Models 5h + weekly, plus Claude/GPT pool when present).
public actor GeminiProvider: Provider {
    public nonisolated let id: ProviderID = .gemini
    public nonisolated let displayName = "Gemini"

    private let authReader: GeminiLocalAuthReader
    private let session: URLSession
    private var trackingEnabled: Bool
    private var cachedPlanName: String?

    public static let codeAssistBaseURLs = [
        URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal")!,
        URL(string: "https://cloudcode-pa.googleapis.com/v1internal")!,
    ]

    public init(
        trackingEnabled: Bool,
        authReader: GeminiLocalAuthReader = GeminiLocalAuthReader(),
        session: URLSession = .shared
    ) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let local = try? authReader.read() else { return .signedOut }
        let hint = cachedPlanName ?? local.email ?? "Antigravity"
        return .signedIn(accountHint: hint)
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        _ = try authReader.read()
        trackingEnabled = true
    }

    public func clearAuth() async throws {
        trackingEnabled = false
        cachedPlanName = nil
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw GeminiProviderError.notAuthenticated }
        var local = try authReader.read()
        local = try await refreshIfNeeded(local)

        do {
            return try await fetchQuota(with: local)
        } catch GeminiProviderError.httpStatus(401), GeminiProviderError.httpStatus(403) {
            local = try await forceRefresh(local)
            return try await fetchQuota(with: local)
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

    // MARK: - Network

    private func fetchQuota(with credentials: GeminiLocalAuth) async throws -> UsageSnapshot {
        let (projectID, planName) = (try? await loadCodeAssist(accessToken: credentials.accessToken))
            ?? (nil, nil)
        if let planName {
            cachedPlanName = planName
        } else if let email = credentials.email {
            cachedPlanName = email
        }

        let summaryData = try await retrieveQuotaSummary(
            accessToken: credentials.accessToken,
            projectID: projectID
        )
        var summary = try GeminiQuotaParser.summary(from: summaryData)
        if summary.projectID == nil {
            summary = GeminiQuotaSummary(
                buckets: summary.buckets,
                projectID: projectID,
                planName: planName ?? summary.planName
            )
        } else if summary.planName == nil, let planName {
            summary = GeminiQuotaSummary(
                buckets: summary.buckets,
                projectID: summary.projectID,
                planName: planName
            )
        }
        if let plan = summary.planName {
            cachedPlanName = plan
        }
        return GeminiQuotaParser.snapshot(from: summary)
    }

    private func loadCodeAssist(accessToken: String) async throws -> (projectID: String?, planName: String?) {
        let body: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "MACOS",
                "pluginType": "GEMINI",
            ]
        ]
        var lastError: Error = GeminiProviderError.transport("loadCodeAssist failed")
        for base in Self.codeAssistBaseURLs {
            do {
                let data = try await post(base: base, method: "loadCodeAssist", accessToken: accessToken, body: body)
                return (
                    GeminiQuotaParser.projectID(fromLoadCodeAssist: data),
                    GeminiQuotaParser.planName(fromLoadCodeAssist: data)
                )
            } catch {
                lastError = error
                if case GeminiProviderError.httpStatus(401) = error { throw error }
                if case GeminiProviderError.httpStatus(403) = error { throw error }
            }
        }
        throw lastError
    }

    private func retrieveQuotaSummary(accessToken: String, projectID: String?) async throws -> Data {
        var body: [String: Any] = [:]
        if let projectID, !projectID.isEmpty {
            body["project"] = projectID
        }

        var lastError: Error = GeminiProviderError.transport("retrieveUserQuotaSummary failed")
        for base in Self.codeAssistBaseURLs {
            do {
                return try await post(
                    base: base,
                    method: "retrieveUserQuotaSummary",
                    accessToken: accessToken,
                    body: body
                )
            } catch {
                lastError = error
                if case GeminiProviderError.httpStatus(401) = error { throw error }
                if case GeminiProviderError.httpStatus(403) = error { throw error }
            }
        }
        throw lastError
    }

    private func post(
        base: URL,
        method: String,
        accessToken: String,
        body: [String: Any]
    ) async throws -> Data {
        let url = URL(string: "\(base.absoluteString):\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "google-cloud-sdk vscode_cloudshelleditor/0.1",
            forHTTPHeaderField: "X-Goog-Api-Client"
        )
        request.setValue(
            #"{"ideType":"ANTIGRAVITY","platform":"MACOS","pluginType":"GEMINI"}"#,
            forHTTPHeaderField: "Client-Metadata"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiProviderError.transport("Invalid usage response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw GeminiProviderError.httpStatus(http.statusCode)
            }
            throw GeminiProviderError.httpStatus(http.statusCode)
        }
        return data
    }

    // MARK: - Token refresh

    private func refreshIfNeeded(_ credentials: GeminiLocalAuth) async throws -> GeminiLocalAuth {
        if let expires = credentials.expiresAt, expires.timeIntervalSinceNow > 60 {
            return credentials
        }
        // No expiry info — try the current token; refresh on 401.
        if credentials.expiresAt == nil {
            return credentials
        }
        return try await forceRefresh(credentials)
    }

    private func forceRefresh(_ credentials: GeminiLocalAuth) async throws -> GeminiLocalAuth {
        // Prefer a freshly rewritten CLI/IDE token if the user / agy re-authenticated.
        if let latest = try? authReader.read() {
            if let expires = latest.expiresAt, expires.timeIntervalSinceNow > 60 {
                return latest
            }
            if latest.expiresAt == nil,
               !latest.accessToken.isEmpty,
               latest.accessToken != credentials.accessToken
            {
                return latest
            }
        }

        guard let refresh = credentials.refreshToken, !refresh.isEmpty else {
            throw GeminiProviderError.refreshFailed
        }

        // OAuth client secret is NOT shipped in Headroom — discover it from the local `agy` binary.
        guard let oauth = GeminiOAuthClientDiscovery.credentials() else {
            throw GeminiProviderError.refreshFailed
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": oauth.clientID,
            "client_secret": oauth.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeminiProviderError.refreshFailed
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String,
            !access.isEmpty
        else {
            throw GeminiProviderError.refreshFailed
        }

        let expiresIn = (json["expires_in"] as? Int) ?? 3600
        let newRefresh = (json["refresh_token"] as? String) ?? refresh
        return GeminiLocalAuth(
            accessToken: access,
            refreshToken: newRefresh,
            email: credentials.email,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            source: credentials.source
        )
    }
}

public enum GeminiProviderError: Error, LocalizedError, Sendable, Equatable {
    case emptyUsage
    case httpStatus(Int)
    case transport(String)
    case notAuthenticated
    case refreshFailed

    public var errorDescription: String? {
        switch self {
        case .emptyUsage:
            return "Antigravity returned no usage data"
        case .httpStatus(let code):
            if code == 401 || code == 403 {
                return "Auth expired — sign in to Antigravity or run `agy` login"
            }
            return "Antigravity API HTTP \(code)"
        case .transport(let message):
            return message
        case .notAuthenticated:
            return "Gemini is not connected"
        case .refreshFailed:
            return "Could not refresh Antigravity OAuth token"
        }
    }
}

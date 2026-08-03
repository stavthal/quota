import Foundation

/// Live OpenCode provider. Reads `~/.local/share/opencode` auth + SQLite logs — no Keychain copy.
///
/// Menu bar shows:
/// - One subscription card: **OpenCode Go** or **OpenCode Zen**
/// - Up to 3 separate cards for the highest-spend backends used inside OpenCode (e.g. OpenRouter)
public actor OpenCodeProvider: Provider {
    public nonisolated let id: ProviderID = .opencode
    public nonisolated let displayName = "OpenCode"

    private let authReader: OpenCodeLocalAuthReader
    private let usageReader: OpenCodeLocalUsageReader
    private let session: URLSession
    private var trackingEnabled: Bool
    private var cachedBackends: [OpenCodeBackendUsage] = []
    private var cachedSubscriptionLabel = "OpenCode"

    public static let goUsageEndpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    public init(
        trackingEnabled: Bool,
        authReader: OpenCodeLocalAuthReader = OpenCodeLocalAuthReader(),
        usageReader: OpenCodeLocalUsageReader = OpenCodeLocalUsageReader(),
        session: URLSession = .shared
    ) {
        self.trackingEnabled = trackingEnabled
        self.authReader = authReader
        self.usageReader = usageReader
        self.session = session
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        guard let auth = try? authReader.read() else { return .signedOut }
        return .signedIn(accountHint: cachedSubscriptionLabel == "OpenCode" ? auth.accountHint : cachedSubscriptionLabel)
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        _ = try authReader.read()
        trackingEnabled = true
    }

    public func clearAuth() async throws {
        trackingEnabled = false
        cachedBackends = []
        cachedSubscriptionLabel = "OpenCode"
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let result = try await fetchSnapshotAndBackends()
        return result.snapshot
    }

    public func fetchSnapshotAndBackends() async throws -> (snapshot: UsageSnapshot, backends: [OpenCodeBackendUsage], label: String) {
        guard trackingEnabled else { throw OpenCodeProviderError.notAuthenticated }
        let auth = try authReader.read()
        let spend = try usageReader.readSpend()
        let label = OpenCodeUsageParser.subscriptionLabel(auth: auth, spend: spend)
        cachedSubscriptionLabel = label
        cachedBackends = spend.topBackends(limit: OpenCodeLocalUsageReader.maxBackends)

        if auth.hasGoKey, let key = auth.goAPIKey,
           let remote = try? await fetchGoUsageAPI(apiKey: key) {
            return (remote, cachedBackends, label)
        }

        let snapshot = OpenCodeUsageParser.snapshot(spend: spend, auth: auth)
        return (snapshot, cachedBackends, label)
    }

    public func latestBackends() -> [OpenCodeBackendUsage] {
        cachedBackends
    }

    public func latestSubscriptionLabel() -> String {
        cachedSubscriptionLabel
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    private func fetchGoUsageAPI(apiKey: String) async throws -> UsageSnapshot? {
        var request = URLRequest(url: Self.goUsageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func number(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = json[key] as? Double { return value }
                if let value = json[key] as? Int { return Double(value) }
                if let nested = json[key] as? [String: Any] {
                    if let used = nested["used"] as? Double { return used }
                    if let used = nested["used"] as? Int { return Double(used) }
                    if let pct = nested["percent"] as? Double {
                        return pct / 100.0 * (nested["limit"] as? Double ?? 0)
                    }
                }
            }
            return nil
        }

        let five = number(["five_hour", "fiveHour", "session", "rolling"])
        let week = number(["weekly", "week"])
        guard five != nil || week != nil else { return nil }

        let fetchedAt = Date()
        var windows: [UsageWindow] = []
        if let five {
            windows.append(
                UsageWindow(
                    kind: .fiveHour,
                    used: five,
                    limit: OpenCodeLocalUsageReader.goFiveHourCapUSD,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(5 * 3600)
                )
            )
        }
        if let week {
            windows.append(
                UsageWindow(
                    kind: .weekly,
                    used: week,
                    limit: OpenCodeLocalUsageReader.goWeeklyCapUSD,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(7 * 24 * 3600)
                )
            )
        }
        return UsageSnapshot(providerID: .opencode, fetchedAt: fetchedAt, windows: windows, models: [])
    }
}

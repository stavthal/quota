import Foundation

public actor MockCursorProvider: Provider {
    public nonisolated let id: ProviderID = .cursor
    public nonisolated let displayName = "Cursor"

    public var utilization: Double
    private let secrets: any SecretsStore

    public init(utilization: Double = 0.42, secrets: any SecretsStore = InMemorySecretsStore()) {
        self.utilization = utilization
        self.secrets = secrets
    }

    public func setUtilization(_ value: Double) {
        utilization = value
    }

    public func authStatus() async -> AuthStatus {
        if let data = try? await secrets.get(.cursor), !data.isEmpty {
            return .signedIn(accountHint: "mock-cursor")
        }
        return .signedOut
    }

    public func authenticate(using method: AuthMethod) async throws {
        switch method {
        case .sessionToken(let token):
            try await secrets.set(Data(token.utf8), for: .cursor)
        }
    }

    public func clearAuth() async throws {
        try await secrets.delete(.cursor)
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let used = utilization * 100
        let resetsFive = Date().addingTimeInterval(3 * 3600)
        let resetsWeek = Date().addingTimeInterval(4 * 24 * 3600)
        return UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(kind: .fiveHour, used: used, limit: 100, unit: .percent, resetsAt: resetsFive),
                UsageWindow(
                    kind: .weekly,
                    used: min(used * 0.7, 100),
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetsWeek
                ),
            ],
            models: [
                ModelBreakdown(
                    modelID: "claude-4-sonnet",
                    label: "Claude 4 Sonnet",
                    amount: used * 0.6,
                    unit: .percent
                ),
                ModelBreakdown(modelID: "gpt-5", label: "GPT-5", amount: used * 0.4, unit: .percent),
            ]
        )
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }
}

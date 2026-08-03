import Foundation

public actor MockCodexProvider: Provider {
    public nonisolated let id: ProviderID = .codex
    public nonisolated let displayName = "Codex"

    public var utilization: Double
    private let secrets: any SecretsStore

    public init(utilization: Double = 0.35, secrets: any SecretsStore = InMemorySecretsStore()) {
        self.utilization = utilization
        self.secrets = secrets
    }

    public func setUtilization(_ value: Double) {
        utilization = value
    }

    public func authStatus() async -> AuthStatus {
        if let data = try? await secrets.get(.codex), !data.isEmpty {
            return .signedIn(accountHint: "mock-codex")
        }
        return .signedOut
    }

    public func authenticate(using method: AuthMethod) async throws {
        switch method {
        case .sessionToken(let token):
            try await secrets.set(Data(token.utf8), for: .codex)
        }
    }

    public func clearAuth() async throws {
        try await secrets.delete(.codex)
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let used = utilization * 100
        let resetsFive = Date().addingTimeInterval(2 * 3600)
        let resetsWeek = Date().addingTimeInterval(5 * 24 * 3600)
        return UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, used: used, limit: 100, unit: .percent, resetsAt: resetsFive),
                UsageWindow(
                    kind: .weekly,
                    used: min(used * 0.55, 100),
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetsWeek
                ),
            ],
            models: [
                ModelBreakdown(modelID: "codex", label: "Codex", amount: used, unit: .percent),
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

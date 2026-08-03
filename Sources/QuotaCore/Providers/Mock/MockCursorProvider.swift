import Foundation

/// Test double that returns Cursor-shaped pools (Auto + API), not 5-hour windows.
public actor MockCursorProvider: Provider {
    public nonisolated let id: ProviderID = .cursor
    public nonisolated let displayName = "Cursor"

    public var autoUtilization: Double
    public var apiUtilization: Double
    private let secrets: any SecretsStore

    public init(
        utilization: Double = 0.42,
        autoUtilization: Double? = nil,
        apiUtilization: Double? = nil,
        secrets: any SecretsStore = InMemorySecretsStore()
    ) {
        self.autoUtilization = autoUtilization ?? utilization * 0.55
        self.apiUtilization = apiUtilization ?? utilization
        self.secrets = secrets
    }

    public func setUtilization(_ value: Double) {
        autoUtilization = value * 0.55
        apiUtilization = value
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
        case .localApp:
            try await secrets.set(Data("local-mock".utf8), for: .cursor)
        }
    }

    public func clearAuth() async throws {
        try await secrets.delete(.cursor)
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let resets = Date().addingTimeInterval(12 * 24 * 3600)
        return UsageSnapshot(
            providerID: .cursor,
            windows: [
                UsageWindow(
                    kind: .cursorAuto,
                    used: autoUtilization * 100,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resets
                ),
                UsageWindow(
                    kind: .cursorAPI,
                    used: apiUtilization * 100,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resets
                ),
            ],
            models: [
                ModelBreakdown(
                    modelID: "composer",
                    label: "Composer / Auto",
                    amount: autoUtilization * 100,
                    unit: .percent
                ),
                ModelBreakdown(
                    modelID: "api-models",
                    label: "API models",
                    amount: apiUtilization * 100,
                    unit: .percent
                ),
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

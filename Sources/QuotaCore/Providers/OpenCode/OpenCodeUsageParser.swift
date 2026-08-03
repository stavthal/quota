import Foundation

public enum OpenCodeUsageParser {
    public static func snapshot(
        spend: OpenCodeSpendSnapshot,
        auth: OpenCodeLocalAuth,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        let showGo = auth.hasGoKey || spend.hasGoHistory
        var windows: [UsageWindow] = []

        if showGo {
            // OpenCode Go subscription caps.
            windows.append(
                UsageWindow(
                    kind: .fiveHour,
                    used: spend.fiveHourGoUSD,
                    limit: OpenCodeLocalUsageReader.goFiveHourCapUSD,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(5 * 3600)
                )
            )
            windows.append(
                UsageWindow(
                    kind: .weekly,
                    used: spend.weeklyGoUSD,
                    limit: OpenCodeLocalUsageReader.goWeeklyCapUSD,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(7 * 24 * 3600)
                )
            )
        } else {
            // OpenCode Zen (or CLI without Go) — hosted OpenCode spend only.
            windows.append(
                UsageWindow(
                    kind: .weekly,
                    used: spend.weeklyHostedUSD,
                    limit: 0,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(7 * 24 * 3600)
                )
            )
            windows.append(
                UsageWindow(
                    kind: .monthly,
                    used: spend.monthlyHostedUSD,
                    limit: 0,
                    unit: .credits,
                    resetsAt: fetchedAt.addingTimeInterval(30 * 24 * 3600)
                )
            )
        }

        return UsageSnapshot(
            providerID: .opencode,
            fetchedAt: fetchedAt,
            windows: windows,
            models: []
        )
    }

    public static func subscriptionLabel(auth: OpenCodeLocalAuth, spend: OpenCodeSpendSnapshot) -> String {
        if auth.hasGoKey || spend.hasGoHistory { return "OpenCode Go" }
        if auth.hasZenKey || spend.hasHostedHistory { return "OpenCode Zen" }
        return "OpenCode"
    }
}

public enum OpenCodeProviderError: Error, LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case emptyUsage
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "OpenCode is not connected"
        case .emptyUsage:
            "OpenCode returned no usage data"
        case .transport(let message):
            message
        }
    }
}

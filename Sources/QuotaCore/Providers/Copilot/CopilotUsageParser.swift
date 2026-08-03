import Foundation

public struct CopilotUsageDTO: Decodable, Sendable {
    public var login: String?
    public var copilotPlan: String?
    public var quotaResetDateUTC: String?
    public var quotaSnapshots: [String: QuotaSnapshotDTO]?

    enum CodingKeys: String, CodingKey {
        case login
        case copilotPlan = "copilot_plan"
        case quotaResetDateUTC = "quota_reset_date_utc"
        case quotaSnapshots = "quota_snapshots"
    }

    public struct QuotaSnapshotDTO: Decodable, Sendable {
        public var percentRemaining: Double?
        public var unlimited: Bool?
        public var creditsUsed: Double?
        public var remaining: Double?
        public var entitlement: Double?
        public var quotaId: String?

        enum CodingKeys: String, CodingKey {
            case percentRemaining = "percent_remaining"
            case unlimited
            case creditsUsed = "credits_used"
            case remaining
            case entitlement
            case quotaId = "quota_id"
        }
    }
}

public enum CopilotUsageParser {
    public static func snapshot(from dto: CopilotUsageDTO, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let resetsAt = parseReset(dto.quotaResetDateUTC) ?? Calendar.current.date(byAdding: .month, value: 1, to: fetchedAt)!
        var windows: [UsageWindow] = []

        if let premium = dto.quotaSnapshots?["premium_interactions"] {
            if premium.unlimited == true {
                windows.append(
                    UsageWindow(kind: .copilotCredits, used: 0, limit: 100, unit: .percent, resetsAt: resetsAt)
                )
            } else if let remainingPct = premium.percentRemaining {
                let used = max(0, min(100, 100 - remainingPct))
                windows.append(
                    UsageWindow(kind: .copilotCredits, used: used, limit: 100, unit: .percent, resetsAt: resetsAt)
                )
            } else if let entitlement = premium.entitlement, entitlement > 0 {
                let remaining = premium.remaining ?? max(0, entitlement - (premium.creditsUsed ?? 0))
                windows.append(
                    UsageWindow(
                        kind: .copilotCredits,
                        used: entitlement - remaining,
                        limit: entitlement,
                        unit: .credits,
                        resetsAt: resetsAt
                    )
                )
            }
        }

        guard !windows.isEmpty else {
            throw CopilotProviderError.emptyUsage
        }

        return UsageSnapshot(
            providerID: .copilot,
            fetchedAt: fetchedAt,
            windows: windows,
            models: []
        )
    }

    private static func parseReset(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}

public enum CopilotProviderError: Error, LocalizedError, Sendable, Equatable {
    case emptyUsage
    case ghMissing
    case ghFailed(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .emptyUsage:
            "Copilot returned no credit quota"
        case .ghMissing:
            "GitHub CLI (`gh`) not found — install and run `gh auth login`"
        case .ghFailed(let message):
            message
        case .notAuthenticated:
            "Copilot is not connected"
        }
    }
}

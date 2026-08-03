import Foundation

public struct CodexUsageDTO: Decodable, Sendable {
    public var planType: String?
    public var email: String?
    public var rateLimit: RateLimitDTO?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case email
        case rateLimit = "rate_limit"
    }

    public struct RateLimitDTO: Decodable, Sendable {
        public var primaryWindow: WindowDTO?
        public var secondaryWindow: WindowDTO?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    public struct WindowDTO: Decodable, Sendable {
        public var usedPercent: Double?
        public var limitWindowSeconds: Double?
        public var resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }
}

public enum CodexUsageParser {
    public static func snapshot(from dto: CodexUsageDTO, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard let rate = dto.rateLimit else {
            throw CodexProviderError.emptyUsage
        }

        var windows: [UsageWindow] = []

        if let primary = rate.primaryWindow, let used = primary.usedPercent {
            let seconds = resolvedWindowSeconds(explicit: primary.limitWindowSeconds, resetAt: primary.resetAt, fetchedAt: fetchedAt, fallback: nil)
            windows.append(
                UsageWindow(
                    kind: kind(forWindowSeconds: seconds),
                    used: used,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetDate(primary.resetAt, fallbackFrom: fetchedAt, seconds: seconds ?? 604_800)
                )
            )
        }

        if let secondary = rate.secondaryWindow, let used = secondary.usedPercent {
            let seconds = resolvedWindowSeconds(explicit: secondary.limitWindowSeconds, resetAt: secondary.resetAt, fetchedAt: fetchedAt, fallback: 604_800)
            windows.append(
                UsageWindow(
                    kind: kind(forWindowSeconds: seconds),
                    used: used,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetDate(secondary.resetAt, fallbackFrom: fetchedAt, seconds: seconds ?? 604_800)
                )
            )
        }

        guard !windows.isEmpty else {
            throw CodexProviderError.emptyUsage
        }

        return UsageSnapshot(
            providerID: .codex,
            fetchedAt: fetchedAt,
            windows: windows,
            models: []
        )
    }

    private static func resetDate(_ unix: Double?, fallbackFrom: Date, seconds: Double) -> Date {
        if let unix {
            return Date(timeIntervalSince1970: unix)
        }
        return fallbackFrom.addingTimeInterval(seconds)
    }

    /// ChatGPT/Codex plans vary — some only expose a weekly window as `primary_window`.
    /// Classify from duration instead of assuming primary == 5h.
    private static func kind(forWindowSeconds seconds: Double?) -> UsageWindowKind {
        guard let seconds else {
            // Prefer weekly over a fake 5h label when ChatGPT omits duration.
            return .weekly
        }
        if seconds <= 21_600 { // ≤ 6 hours
            return .fiveHour
        }
        if seconds >= 500_000 { // ~6+ days
            return .weekly
        }
        return .monthly
    }

    private static func resolvedWindowSeconds(
        explicit: Double?,
        resetAt: Double?,
        fetchedAt: Date,
        fallback: Double?
    ) -> Double? {
        if let explicit { return explicit }
        if let resetAt {
            let delta = resetAt - fetchedAt.timeIntervalSince1970
            if delta > 0 { return delta }
        }
        return fallback
    }
}

public enum CodexProviderError: Error, LocalizedError, Sendable, Equatable {
    case emptyUsage
    case httpStatus(Int)
    case transport(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .emptyUsage:
            "Codex returned no usage windows"
        case .httpStatus(let code):
            "Codex API HTTP \(code)"
        case .transport(let message):
            message
        case .notAuthenticated:
            "Codex is not connected"
        }
    }
}

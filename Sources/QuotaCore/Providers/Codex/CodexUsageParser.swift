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
            windows.append(
                UsageWindow(
                    kind: .fiveHour,
                    used: used,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetDate(primary.resetAt, fallbackFrom: fetchedAt, seconds: primary.limitWindowSeconds ?? 18_000)
                )
            )
        }

        if let secondary = rate.secondaryWindow, let used = secondary.usedPercent {
            let seconds = secondary.limitWindowSeconds ?? 604_800
            let kind: UsageWindowKind = seconds >= 600_000 ? .weekly : .monthly
            windows.append(
                UsageWindow(
                    kind: kind,
                    used: used,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetDate(secondary.resetAt, fallbackFrom: fetchedAt, seconds: seconds)
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

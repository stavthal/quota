import Foundation

public struct CursorUsageSummaryDTO: Decodable, Sendable {
    public var billingCycleStart: String?
    public var billingCycleEnd: String?
    public var membershipType: String?
    public var individualUsage: IndividualUsageDTO?

    public struct IndividualUsageDTO: Decodable, Sendable {
        public var plan: PlanDTO?
    }

    public struct PlanDTO: Decodable, Sendable {
        public var enabled: Bool?
        public var used: Double?
        public var limit: Double?
        public var remaining: Double?
        public var autoPercentUsed: Double?
        public var apiPercentUsed: Double?
        public var totalPercentUsed: Double?
    }
}

public enum CursorUsageSummaryParser {
    public static func snapshot(
        from dto: CursorUsageSummaryDTO,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        let plan = dto.individualUsage?.plan
        let resetsAt = parseDate(dto.billingCycleEnd) ?? Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: fetchedAt
        )!

        var windows: [UsageWindow] = []

        if let auto = plan?.autoPercentUsed {
            windows.append(
                UsageWindow(
                    kind: .cursorAuto,
                    used: auto,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetsAt
                )
            )
        }

        if let api = plan?.apiPercentUsed {
            windows.append(
                UsageWindow(
                    kind: .cursorAPI,
                    used: api,
                    limit: 100,
                    unit: .percent,
                    resetsAt: resetsAt
                )
            )
        }

        // Fallback when percent fields are missing but request counts exist.
        if windows.isEmpty, let used = plan?.used, let limit = plan?.limit, limit > 0 {
            windows.append(
                UsageWindow(
                    kind: .cursorAPI,
                    used: used,
                    limit: limit,
                    unit: .requests,
                    resetsAt: resetsAt
                )
            )
        }

        guard !windows.isEmpty else {
            throw CursorProviderError.emptyUsageSummary
        }

        return UsageSnapshot(
            providerID: .cursor,
            fetchedAt: fetchedAt,
            windows: windows,
            models: []
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}

public enum CursorProviderError: Error, LocalizedError, Sendable, Equatable {
    case emptyUsageSummary
    case httpStatus(Int)
    case transport(String)
    case refreshFailed
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .emptyUsageSummary:
            "Cursor returned no usage pools"
        case .httpStatus(let code):
            "Cursor API HTTP \(code)"
        case .transport(let message):
            message
        case .refreshFailed:
            "Could not refresh Cursor session — sign in again in the Cursor app"
        case .notAuthenticated:
            "Cursor is not connected"
        }
    }
}

import Foundation

public struct ClaudeUsageDTO: Decodable, Sendable {
    public var fiveHour: WindowDTO?
    public var sevenDay: WindowDTO?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public struct WindowDTO: Decodable, Sendable {
        public var utilization: Double?
        public var resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

public enum ClaudeUsageParser {
    public static func snapshot(from data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try snapshot(from: decoder.decode(ClaudeUsageDTO.self, from: data), fetchedAt: fetchedAt)
    }

    public static func snapshot(from dto: ClaudeUsageDTO, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        var windows: [UsageWindow] = []

        if let window = dto.fiveHour, let usage = window.utilization {
            windows.append(
                UsageWindow(
                    kind: .fiveHour,
                    used: usage,
                    limit: 100,
                    unit: .percent,
                    resetsAt: window.resetsAt ?? fetchedAt.addingTimeInterval(5 * 60 * 60)
                )
            )
        }

        if let window = dto.sevenDay, let usage = window.utilization {
            windows.append(
                UsageWindow(
                    kind: .weekly,
                    used: usage,
                    limit: 100,
                    unit: .percent,
                    resetsAt: window.resetsAt ?? fetchedAt.addingTimeInterval(7 * 24 * 60 * 60)
                )
            )
        }

        guard !windows.isEmpty else { throw ClaudeProviderError.emptyUsage }
        return UsageSnapshot(providerID: .claude, fetchedAt: fetchedAt, windows: windows)
    }
}

public enum ClaudeProviderError: Error, LocalizedError, Sendable, Equatable {
    case usageCacheMissing
    case invalidUsageCache
    case emptyUsage
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .usageCacheMissing:
            "Claude Code has not cached usage yet — run Claude Code, then reconnect"
        case .invalidUsageCache:
            "Claude Code's local usage cache could not be read"
        case .emptyUsage:
            "Claude Code returned no usage windows"
        case .notAuthenticated:
            "Claude Code is not connected"
        }
    }
}

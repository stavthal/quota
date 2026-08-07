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
    case authFileMissing
    case notSignedIn
    case invalidAuthFile
    case emptyUsage
    case httpStatus(Int)
    case transport(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .authFileMissing:
            "Claude Code credentials are not available to Headroom"
        case .notSignedIn:
            "Claude Code is not signed in"
        case .invalidAuthFile:
            "Claude Code credentials could not be parsed"
        case .emptyUsage:
            "Claude Code returned no usage windows"
        case .httpStatus(let code):
            code == 401 || code == 403
                ? "Claude Code session expired — sign in again with `claude auth login`"
                : "Claude Code usage HTTP \(code)"
        case .transport(let message):
            message
        case .notAuthenticated:
            "Claude Code is not connected"
        }
    }
}

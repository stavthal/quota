import Foundation

/// Decoded shape of `agy -p "/usage" --output-format json` — Antigravity CLI's own
/// documented headless-mode output (see https://antigravity.google/docs/cli/commands/usage).
struct AgyUsageResponse: Decodable {
    var status: String
    var command: Command?

    struct Command: Decodable {
        var name: String
        var data: UsageData?
    }

    struct UsageData: Decodable {
        var groups: [Group]
    }

    struct Group: Decodable {
        var name: String
        var buckets: [Bucket]
    }

    struct Bucket: Decodable {
        var id: String
        var window: String
        var remainingFraction: Double
        var resetTime: Date
    }
}

public enum GeminiUsageParser {
    /// The Gemini Models group's weekly bucket id, per agy's own /usage output. Other groups
    /// (e.g. "3p-weekly" for Claude/GPT models routed through Antigravity) are not this
    /// provider's concern — Headroom tracks those models under their own providers.
    private static let geminiWeeklyBucketID = "gemini-weekly"

    public static func snapshot(from data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let response: AgyUsageResponse
        do {
            response = try decoder.decode(AgyUsageResponse.self, from: data)
        } catch {
            throw GeminiProviderError.invalidResponse
        }

        guard response.status == "SUCCESS" else { throw GeminiProviderError.notAuthenticated }

        guard
            let bucket = response.command?.data?.groups
                .flatMap(\.buckets)
                .first(where: { $0.id == geminiWeeklyBucketID })
        else { throw GeminiProviderError.emptyUsage }

        let usedPercent = max(0, min(100, (1 - bucket.remainingFraction) * 100))
        let window = UsageWindow(
            kind: .weekly,
            used: usedPercent,
            limit: 100,
            unit: .percent,
            resetsAt: bucket.resetTime
        )
        return UsageSnapshot(providerID: .gemini, fetchedAt: fetchedAt, windows: [window])
    }
}

public enum GeminiProviderError: Error, LocalizedError, Sendable, Equatable {
    case cliMissing
    case cliFailed(String)
    case notAuthenticated
    case invalidResponse
    case emptyUsage

    public var errorDescription: String? {
        switch self {
        case .cliMissing:
            "Antigravity CLI (`agy`) not found — install it and sign in once with `agy`"
        case .cliFailed(let message):
            "agy /usage failed: \(message)"
        case .notAuthenticated:
            "Gemini (Antigravity) is not connected"
        case .invalidResponse:
            "Antigravity's /usage response could not be parsed"
        case .emptyUsage:
            "Antigravity returned no Gemini usage buckets"
        }
    }
}

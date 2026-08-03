import Foundation
import GRDB

/// A BYOK / third-party provider observed inside OpenCode's local logs.
public struct OpenCodeBackendUsage: Sendable, Equatable, Identifiable {
    public var id: String { providerKey }
    public var providerKey: String
    public var displayName: String
    public var weeklyUSD: Double
    public var monthlyUSD: Double

    public init(providerKey: String, displayName: String, weeklyUSD: Double, monthlyUSD: Double) {
        self.providerKey = providerKey
        self.displayName = displayName
        self.weeklyUSD = weeklyUSD
        self.monthlyUSD = monthlyUSD
    }

    public static func displayName(for key: String) -> String {
        switch key.lowercased() {
        case "openrouter": "OpenRouter"
        case "openai": "OpenAI"
        case "anthropic": "Anthropic"
        case "google": "Google"
        case "groq": "Groq"
        case "xai": "xAI"
        case "mistral": "Mistral"
        case "deepseek": "DeepSeek"
        case "github-copilot": "Copilot"
        default:
            key
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { part in
                    guard let first = part.first else { return String(part) }
                    return String(first).uppercased() + part.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}

public struct OpenCodeSpendSnapshot: Sendable, Equatable {
    public var fiveHourGoUSD: Double
    public var weeklyGoUSD: Double
    public var monthlyGoUSD: Double
    public var weeklyHostedUSD: Double
    public var monthlyHostedUSD: Double
    public var hasGoHistory: Bool
    public var hasHostedHistory: Bool
    /// Ranked backends (excludes `opencode` / `opencode-go`), highest monthly spend first.
    public var backends: [OpenCodeBackendUsage]

    public init(
        fiveHourGoUSD: Double = 0,
        weeklyGoUSD: Double = 0,
        monthlyGoUSD: Double = 0,
        weeklyHostedUSD: Double = 0,
        monthlyHostedUSD: Double = 0,
        hasGoHistory: Bool = false,
        hasHostedHistory: Bool = false,
        backends: [OpenCodeBackendUsage] = []
    ) {
        self.fiveHourGoUSD = fiveHourGoUSD
        self.weeklyGoUSD = weeklyGoUSD
        self.monthlyGoUSD = monthlyGoUSD
        self.weeklyHostedUSD = weeklyHostedUSD
        self.monthlyHostedUSD = monthlyHostedUSD
        self.hasGoHistory = hasGoHistory
        self.hasHostedHistory = hasHostedHistory
        self.backends = backends
    }

    public func topBackends(limit: Int = 3) -> [OpenCodeBackendUsage] {
        Array(backends.prefix(limit))
    }
}

public enum OpenCodeLocalUsageError: Error, Sendable, Equatable, LocalizedError {
    case databaseMissing
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .databaseMissing:
            "OpenCode local database not found — run a session in OpenCode first"
        case .unreadable(let message):
            "Couldn't read OpenCode database: \(message)"
        }
    }
}

/// Reads observed spend from OpenCode's local SQLite logs (`opencode*.db`).
public struct OpenCodeLocalUsageReader: Sendable {
    public var dataDirectoryURL: URL

    public static let goFiveHourCapUSD: Double = 12
    public static let goWeeklyCapUSD: Double = 30
    public static let goMonthlyCapUSD: Double = 60
    public static let maxBackends: Int = 3

    public init(dataDirectoryURL: URL = OpenCodeLocalUsageReader.defaultDataDirectoryURL()) {
        self.dataDirectoryURL = dataDirectoryURL
    }

    public static func defaultDataDirectoryURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENCODE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    public func readSpend(now: Date = Date()) throws -> OpenCodeSpendSnapshot {
        let dbURLs = try discoverDatabases()
        guard !dbURLs.isEmpty else { throw OpenCodeLocalUsageError.databaseMissing }

        let fiveHourSince = now.addingTimeInterval(-5 * 3600)
        let weekSince = startOfUTCWeek(containing: now)
        let monthSince = now.addingTimeInterval(-30 * 24 * 3600)

        var snap = OpenCodeSpendSnapshot()
        var weeklyByProvider: [String: Double] = [:]
        var monthlyByProvider: [String: Double] = [:]

        for url in dbURLs {
            let partial = try readSpend(
                from: url,
                fiveHourSince: fiveHourSince,
                weekSince: weekSince,
                monthSince: monthSince
            )
            snap.fiveHourGoUSD += partial.snap.fiveHourGoUSD
            snap.weeklyGoUSD += partial.snap.weeklyGoUSD
            snap.monthlyGoUSD += partial.snap.monthlyGoUSD
            snap.weeklyHostedUSD += partial.snap.weeklyHostedUSD
            snap.monthlyHostedUSD += partial.snap.monthlyHostedUSD
            snap.hasGoHistory = snap.hasGoHistory || partial.snap.hasGoHistory
            snap.hasHostedHistory = snap.hasHostedHistory || partial.snap.hasHostedHistory
            for (key, value) in partial.weeklyByProvider {
                weeklyByProvider[key, default: 0] += value
            }
            for (key, value) in partial.monthlyByProvider {
                monthlyByProvider[key, default: 0] += value
            }
        }

        let hostedKeys: Set<String> = ["opencode", "opencode-go"]
        snap.backends = monthlyByProvider
            .filter { !hostedKeys.contains($0.key) && $0.value > 0 }
            .map { key, monthly in
                OpenCodeBackendUsage(
                    providerKey: key,
                    displayName: OpenCodeBackendUsage.displayName(for: key),
                    weeklyUSD: weeklyByProvider[key] ?? 0,
                    monthlyUSD: monthly
                )
            }
            .sorted {
                if $0.monthlyUSD != $1.monthlyUSD { return $0.monthlyUSD > $1.monthlyUSD }
                return $0.weeklyUSD > $1.weeklyUSD
            }

        return snap
    }

    private func discoverDatabases() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataDirectoryURL.path) else { return [] }
        let contents = try fm.contentsOfDirectory(at: dataDirectoryURL, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.lastPathComponent.hasPrefix("opencode") && $0.pathExtension == "db" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private struct PartialRead {
        var snap: OpenCodeSpendSnapshot
        var weeklyByProvider: [String: Double]
        var monthlyByProvider: [String: Double]
    }

    private func readSpend(
        from url: URL,
        fiveHourSince: Date,
        weekSince: Date,
        monthSince: Date
    ) throws -> PartialRead {
        do {
            var config = Configuration()
            config.readonly = true
            let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
            return try dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT
                      json_extract(data, '$.providerID') AS provider_id,
                      CAST(json_extract(data, '$.cost') AS REAL) AS cost,
                      CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS created_ms
                    FROM message
                    WHERE json_valid(data)
                      AND json_extract(data, '$.role') = 'assistant'
                      AND json_type(data, '$.cost') IN ('integer', 'real')
                    """
                )

                var snap = OpenCodeSpendSnapshot()
                var weeklyByProvider: [String: Double] = [:]
                var monthlyByProvider: [String: Double] = [:]

                for row in rows {
                    let provider: String = row["provider_id"] ?? ""
                    let cost: Double = row["cost"] ?? 0
                    let createdMs: Int64 = row["created_ms"] ?? 0
                    let created: Date = {
                        if createdMs > 10_000_000_000 {
                            return Date(timeIntervalSince1970: TimeInterval(createdMs) / 1000)
                        }
                        return Date(timeIntervalSince1970: TimeInterval(createdMs))
                    }()

                    let isGo = provider == "opencode-go"
                    let isHosted = isGo || provider == "opencode"
                    if isGo { snap.hasGoHistory = true }
                    if isHosted { snap.hasHostedHistory = true }

                    guard cost > 0, !provider.isEmpty else { continue }

                    if created >= weekSince { weeklyByProvider[provider, default: 0] += cost }
                    if created >= monthSince { monthlyByProvider[provider, default: 0] += cost }

                    if isHosted {
                        if created >= weekSince { snap.weeklyHostedUSD += cost }
                        if created >= monthSince { snap.monthlyHostedUSD += cost }
                    }

                    if isGo {
                        if created >= fiveHourSince { snap.fiveHourGoUSD += cost }
                        if created >= weekSince { snap.weeklyGoUSD += cost }
                        if created >= monthSince { snap.monthlyGoUSD += cost }
                    }
                }
                return PartialRead(snap: snap, weeklyByProvider: weeklyByProvider, monthlyByProvider: monthlyByProvider)
            }
        } catch {
            throw OpenCodeLocalUsageError.unreadable(error.localizedDescription)
        }
    }

    private func startOfUTCWeek(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date.addingTimeInterval(-7 * 24 * 3600)
    }
}

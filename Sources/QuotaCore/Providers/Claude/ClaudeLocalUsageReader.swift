import Foundation

/// A read-only view of Claude Code's locally cached subscription utilization.
/// It never reads a credential or makes a network request.
public struct ClaudeLocalUsage: Sendable {
    public var accountHint: String?
    public var snapshot: UsageSnapshot

    public init(accountHint: String?, snapshot: UsageSnapshot) {
        self.accountHint = accountHint
        self.snapshot = snapshot
    }
}

public struct ClaudeLocalUsageReader: Sendable {
    public var configFileURL: URL

    public init(configFileURL: URL = ClaudeLocalUsageReader.defaultConfigFileURL()) {
        self.configFileURL = configFileURL
    }

    public static func defaultConfigFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    public func read() throws -> ClaudeLocalUsage {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            throw ClaudeProviderError.usageCacheMissing
        }

        let data = try Data(contentsOf: configFileURL)
        let cache: CacheFile
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode(CacheFile.self, from: data)
        } catch {
            throw ClaudeProviderError.invalidUsageCache
        }

        guard let utilization = cache.cachedUsageUtilization?.utilization else {
            throw ClaudeProviderError.usageCacheMissing
        }

        let fetchedAt = cache.cachedUsageUtilization?.fetchedAtMs.map {
            Date(timeIntervalSince1970: $0 / 1_000)
        } ?? Date()
        let snapshot = try ClaudeUsageParser.snapshot(from: utilization, fetchedAt: fetchedAt)
        return ClaudeLocalUsage(
            accountHint: cache.oauthAccount?.emailAddress ?? cache.oauthAccount?.displayName,
            snapshot: snapshot
        )
    }

    private struct CacheFile: Decodable {
        var oauthAccount: Account?
        var cachedUsageUtilization: CachedUsage?
    }

    private struct Account: Decodable {
        var emailAddress: String?
        var displayName: String?
    }

    private struct CachedUsage: Decodable {
        var fetchedAtMs: TimeInterval?
        var utilization: ClaudeUsageDTO?
    }
}

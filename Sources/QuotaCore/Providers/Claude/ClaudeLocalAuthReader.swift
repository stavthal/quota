import Foundation

public struct ClaudeLocalAuth: Sendable, Equatable {
    public var accessToken: String
    public var accountHint: String?

    public init(accessToken: String, accountHint: String? = nil) {
        self.accessToken = accessToken
        self.accountHint = accountHint
    }
}

/// Reads the legacy Claude Code local credential file when the user has made it available.
/// Newer Claude Code releases can store this material solely in the macOS Keychain; Headroom
/// deliberately does not read or weaken that Keychain item.
public struct ClaudeLocalAuthReader: Sendable {
    public var credentialsFileURL: URL

    public init(credentialsFileURL: URL = ClaudeLocalAuthReader.defaultCredentialsFileURL()) {
        self.credentialsFileURL = credentialsFileURL
    }

    public static func defaultCredentialsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    public func read() throws -> ClaudeLocalAuth {
        guard FileManager.default.fileExists(atPath: credentialsFileURL.path) else {
            throw ClaudeProviderError.authFileMissing
        }
        let data = try Data(contentsOf: credentialsFileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeProviderError.invalidAuthFile
        }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ClaudeProviderError.notSignedIn
        }
        return ClaudeLocalAuth(
            accessToken: token,
            accountHint: oauth["email"] as? String ?? oauth["subscriptionType"] as? String
        )
    }
}

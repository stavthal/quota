import Foundation

public struct CodexLocalAuth: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var accountID: String?
    public var authMode: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        accountID: String? = nil,
        authMode: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.authMode = authMode
    }
}

public enum CodexLocalAuthError: Error, Sendable, Equatable, LocalizedError {
    case authFileMissing
    case notSignedIn
    case invalidAuthFile

    public var errorDescription: String? {
        switch self {
        case .authFileMissing:
            "Codex auth file not found — run `codex login` first"
        case .notSignedIn:
            "Codex is not signed in via ChatGPT — run `codex login`"
        case .invalidAuthFile:
            "Codex auth.json could not be parsed"
        }
    }
}

public struct CodexLocalAuthReader: Sendable {
    public var authFileURL: URL

    public init(authFileURL: URL = CodexLocalAuthReader.defaultAuthFileURL()) {
        self.authFileURL = authFileURL
    }

    public static func defaultAuthFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    public func read() throws -> CodexLocalAuth {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw CodexLocalAuthError.authFileMissing
        }
        let data = try Data(contentsOf: authFileURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexLocalAuthError.invalidAuthFile
        }
        let tokens = json["tokens"] as? [String: Any]
        let access =
            (tokens?["access_token"] as? String)
            ?? (tokens?["accessToken"] as? String)
        guard let access, !access.isEmpty else {
            throw CodexLocalAuthError.notSignedIn
        }
        let accountID =
            (tokens?["account_id"] as? String)
            ?? (tokens?["accountId"] as? String)
        let refresh =
            (tokens?["refresh_token"] as? String)
            ?? (tokens?["refreshToken"] as? String)
        return CodexLocalAuth(
            accessToken: access,
            refreshToken: refresh,
            accountID: accountID,
            authMode: json["auth_mode"] as? String
        )
    }
}

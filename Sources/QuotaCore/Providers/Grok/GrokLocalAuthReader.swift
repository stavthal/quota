import Foundation

public struct GrokLocalAuth: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var email: String?
    public var userID: String?
    public var expiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        email: String? = nil,
        userID: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.userID = userID
        self.expiresAt = expiresAt
    }
}

public enum GrokLocalAuthError: Error, Sendable, Equatable, LocalizedError {
    case authFileMissing
    case notSignedIn
    case invalidAuthFile

    public var errorDescription: String? {
        switch self {
        case .authFileMissing:
            "Grok auth file not found — run `grok login` first"
        case .notSignedIn:
            "Grok CLI is not signed in — run `grok login`"
        case .invalidAuthFile:
            "Grok ~/.grok/auth.json could not be parsed"
        }
    }
}

public struct GrokLocalAuthReader: Sendable {
    public var authFileURL: URL

    public init(authFileURL: URL = GrokLocalAuthReader.defaultAuthFileURL()) {
        self.authFileURL = authFileURL
    }

    public static func defaultAuthFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    public func read() throws -> GrokLocalAuth {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw GrokLocalAuthError.authFileMissing
        }
        let data = try Data(contentsOf: authFileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokLocalAuthError.invalidAuthFile
        }

        // Prefer the newest OIDC session entry (`issuer::client_id` → session object).
        var best: (create: Date, entry: [String: Any])?
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()

        for (_, value) in root {
            guard let entry = value as? [String: Any],
                  let key = entry["key"] as? String,
                  !key.isEmpty
            else { continue }

            let created: Date = {
                if let raw = entry["create_time"] as? String {
                    return formatter.date(from: raw) ?? formatterNoFrac.date(from: raw) ?? .distantPast
                }
                return .distantPast
            }()

            if best == nil || created > best!.create {
                best = (created, entry)
            }
        }

        guard let entry = best?.entry, let key = entry["key"] as? String, !key.isEmpty else {
            throw GrokLocalAuthError.notSignedIn
        }

        let expires: Date? = {
            guard let raw = entry["expires_at"] as? String else { return nil }
            return formatter.date(from: raw) ?? formatterNoFrac.date(from: raw)
        }()

        return GrokLocalAuth(
            accessToken: key,
            refreshToken: entry["refresh_token"] as? String,
            email: entry["email"] as? String,
            userID: entry["user_id"] as? String,
            expiresAt: expires
        )
    }
}

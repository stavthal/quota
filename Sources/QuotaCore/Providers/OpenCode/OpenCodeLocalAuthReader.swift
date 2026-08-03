import Foundation

public struct OpenCodeLocalAuth: Sendable, Equatable {
    public var hasGoKey: Bool
    public var hasZenKey: Bool
    public var goAPIKey: String?
    public var zenAPIKey: String?
    public var accountHint: String

    public init(
        hasGoKey: Bool,
        hasZenKey: Bool,
        goAPIKey: String? = nil,
        zenAPIKey: String? = nil,
        accountHint: String
    ) {
        self.hasGoKey = hasGoKey
        self.hasZenKey = hasZenKey
        self.goAPIKey = goAPIKey
        self.zenAPIKey = zenAPIKey
        self.accountHint = accountHint
    }

    public var prefersGo: Bool { hasGoKey }
}

public enum OpenCodeLocalAuthError: Error, Sendable, Equatable, LocalizedError {
    case authFileMissing
    case invalidAuthFile
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .authFileMissing:
            "OpenCode auth not found — run `opencode auth login`"
        case .invalidAuthFile:
            "OpenCode auth.json could not be parsed"
        case .notSignedIn:
            "OpenCode has no stored credentials — run `opencode auth login`"
        }
    }
}

public struct OpenCodeLocalAuthReader: Sendable {
    public var authFileURL: URL

    public init(authFileURL: URL = OpenCodeLocalAuthReader.defaultAuthFileURL()) {
        self.authFileURL = authFileURL
    }

    public static func defaultAuthFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENCODE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    public func read() throws -> OpenCodeLocalAuth {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw OpenCodeLocalAuthError.authFileMissing
        }
        let data = try Data(contentsOf: authFileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], !root.isEmpty else {
            throw OpenCodeLocalAuthError.invalidAuthFile
        }

        func key(in entry: [String: Any]) -> String? {
            for field in ["key", "token", "access"] {
                if let value = entry[field] as? String, !value.isEmpty { return value }
            }
            return nil
        }

        let goEntry = root["opencode-go"] as? [String: Any]
        let zenEntry = root["opencode"] as? [String: Any]
        let goKey = goEntry.flatMap(key)
        let zenKey = zenEntry.flatMap(key)

        let hint: String
        if goKey != nil {
            hint = "OpenCode Go"
        } else if zenKey != nil {
            hint = "OpenCode Zen"
        } else {
            hint = "OpenCode CLI"
        }

        return OpenCodeLocalAuth(
            hasGoKey: goKey != nil,
            hasZenKey: zenKey != nil,
            goAPIKey: goKey,
            zenAPIKey: zenKey,
            accountHint: hint
        )
    }
}

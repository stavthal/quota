import Foundation
import GRDB

public struct CursorLocalAuth: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var email: String?
    public var membershipType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        email: String? = nil,
        membershipType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.membershipType = membershipType
    }
}

public enum CursorLocalAuthError: Error, Sendable, Equatable {
    case databaseMissing
    case notSignedIn
    case readFailed(String)
}

public struct CursorLocalAuthReader: Sendable {
    public var databaseURL: URL

    public init(databaseURL: URL = CursorLocalAuthReader.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
    }

    public static func defaultDatabaseURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    public func read() throws -> CursorLocalAuth {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CursorLocalAuthError.databaseMissing
        }

        var configuration = Configuration()
        configuration.readonly = true
        let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)

        return try dbQueue.read { db in
            func value(_ key: String) throws -> String? {
                try String.fetchOne(
                    db,
                    sql: "SELECT value FROM ItemTable WHERE key = ?",
                    arguments: [key]
                )
            }

            guard let access = try value("cursorAuth/accessToken"), !access.isEmpty else {
                throw CursorLocalAuthError.notSignedIn
            }

            return CursorLocalAuth(
                accessToken: access,
                refreshToken: try value("cursorAuth/refreshToken"),
                email: try value("cursorAuth/cachedEmail"),
                membershipType: try value("cursorAuth/stripeMembershipType")
            )
        }
    }
}

import Foundation
import GRDB

public struct GeminiLocalAuth: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var email: String?
    public var expiresAt: Date?
    public var source: String

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        email: String? = nil,
        expiresAt: Date? = nil,
        source: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.expiresAt = expiresAt
        self.source = source
    }
}

public enum GeminiLocalAuthError: Error, Sendable, Equatable, LocalizedError {
    case authMissing
    case notSignedIn
    case invalidAuthFile

    public var errorDescription: String? {
        switch self {
        case .authMissing:
            "Antigravity auth not found — sign in to Antigravity or run `agy` login"
        case .notSignedIn:
            "Antigravity is not signed in"
        case .invalidAuthFile:
            "Antigravity auth file could not be parsed"
        }
    }
}

/// Reads Google OAuth tokens from Antigravity CLI / IDE local state — never copies into Quota Keychain.
public struct GeminiLocalAuthReader: Sendable {
    public var cliTokenURL: URL
    public var databaseURLs: [URL]

    public init(
        cliTokenURL: URL = GeminiLocalAuthReader.defaultCLITokenURL(),
        databaseURLs: [URL] = GeminiLocalAuthReader.defaultDatabaseURLs()
    ) {
        self.cliTokenURL = cliTokenURL
        self.databaseURLs = databaseURLs
    }

    public static func defaultCLITokenURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
    }

    public static func defaultDatabaseURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        return [
            support.appendingPathComponent("Antigravity IDE/User/globalStorage/state.vscdb"),
            support.appendingPathComponent("Antigravity/User/globalStorage/state.vscdb"),
        ]
    }

    public func read() throws -> GeminiLocalAuth {
        if let cli = try? readCLIToken() {
            return cli
        }

        var lastError: GeminiLocalAuthError = .authMissing
        for url in databaseURLs {
            do {
                return try readDatabase(url)
            } catch let error as GeminiLocalAuthError {
                lastError = error
            } catch {
                lastError = .invalidAuthFile
            }
        }
        throw lastError
    }

    // MARK: - CLI token file

    private func readCLIToken() throws -> GeminiLocalAuth {
        guard FileManager.default.fileExists(atPath: cliTokenURL.path) else {
            throw GeminiLocalAuthError.authMissing
        }
        let data = try Data(contentsOf: cliTokenURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiLocalAuthError.invalidAuthFile
        }

        let payload: [String: Any] = {
            if let nested = root["token"] as? [String: Any] { return nested }
            return root
        }()

        guard let access = stringValue(payload, keys: ["access_token", "AccessToken"]), !access.isEmpty else {
            throw GeminiLocalAuthError.notSignedIn
        }

        let refresh = stringValue(payload, keys: ["refresh_token", "RefreshToken"])
            ?? stringValue(root, keys: ["refresh_token", "RefreshToken"])
        let email = stringValue(root, keys: ["email", "Email", "account"])
            ?? stringValue(payload, keys: ["email", "Email"])
        let expires = parseExpiry(payload["expiry"] ?? payload["expires_at"] ?? root["expiry"])

        return GeminiLocalAuth(
            accessToken: access,
            refreshToken: refresh,
            email: email,
            expiresAt: expires,
            source: "cli"
        )
    }

    // MARK: - IDE SQLite

    private func readDatabase(_ databaseURL: URL) throws -> GeminiLocalAuth {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw GeminiLocalAuthError.authMissing
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

            // Prefer JSON status (access token + email). Refresh may live in protobuf state.
            if let statusJSON = try value("antigravityAuthStatus"),
               let data = statusJSON.data(using: .utf8),
               let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let access = stringValue(root, keys: ["apiKey", "accessToken", "access_token"]),
               !access.isEmpty
            {
                let proto = try? decodeOAuthFromProtobufKeys(db)
                return GeminiLocalAuth(
                    accessToken: access,
                    refreshToken: proto?.refreshToken,
                    email: stringValue(root, keys: ["email", "Email"]),
                    expiresAt: proto?.expiresAt,
                    source: "ide"
                )
            }

            if let proto = try decodeOAuthFromProtobufKeys(db), !proto.accessToken.isEmpty {
                return GeminiLocalAuth(
                    accessToken: proto.accessToken,
                    refreshToken: proto.refreshToken,
                    email: nil,
                    expiresAt: proto.expiresAt,
                    source: "ide"
                )
            }

            throw GeminiLocalAuthError.notSignedIn
        }
    }

    private func decodeOAuthFromProtobufKeys(_ db: Database) throws -> GeminiLocalAuth? {
        let keys = [
            "antigravityUnifiedStateSync.oauthToken",
            "jetskiStateSync.agentManagerInitState",
        ]
        for key in keys {
            guard let raw = try String.fetchOne(
                db,
                sql: "SELECT value FROM ItemTable WHERE key = ?",
                arguments: [key]
            ), !raw.isEmpty else { continue }

            if let auth = try? GeminiOAuthProtobufDecoder.decode(base64Value: raw, sourceKey: key) {
                return auth
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func parseExpiry(_ value: Any?) -> Date? {
        if let raw = value as? String {
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return withFrac.date(from: raw) ?? plain.date(from: raw)
        }
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }
}

/// Minimal protobuf decoder for Antigravity IDE OAuth envelopes.
enum GeminiOAuthProtobufDecoder {
    static func decode(base64Value: String, sourceKey: String) throws -> GeminiLocalAuth {
        guard let outer = Data(base64Encoded: base64Value) else {
            throw GeminiLocalAuthError.invalidAuthFile
        }

        // Unified state: outer → wrapper → payload(base64 string) → OAuthTokenInfo
        if sourceKey.contains("oauthToken") {
            if let info = try? decodeUnifiedEnvelope(outer) {
                return info
            }
        }

        // jetski AgentManagerInitState: field 6 = OAuthTokenInfo
        if let infoMsg = firstLengthDelimited(outer, field: 6),
           let info = try? parseOAuthTokenInfo(infoMsg) {
            return info
        }

        // Fallback: treat bytes as OAuthTokenInfo directly.
        if let info = try? parseOAuthTokenInfo(outer) {
            return info
        }

        throw GeminiLocalAuthError.invalidAuthFile
    }

    private static func decodeUnifiedEnvelope(_ outer: Data) throws -> GeminiLocalAuth {
        guard let wrapper = firstLengthDelimited(outer, field: 1) else {
            throw GeminiLocalAuthError.invalidAuthFile
        }
        guard let payload = firstLengthDelimited(wrapper, field: 2) else {
            throw GeminiLocalAuthError.invalidAuthFile
        }
        // payload field 1 is a UTF-8 base64 string of OAuthTokenInfo
        let fields = try fields(of: payload)
        guard let b64Field = fields.first(where: { $0.number == 1 && $0.wire == .lengthDelimited }),
              let b64 = String(data: b64Field.bytes, encoding: .utf8),
              let infoData = Data(base64Encoded: b64)
        else {
            // Sometimes payload itself is OAuthTokenInfo
            return try parseOAuthTokenInfo(payload)
        }
        return try parseOAuthTokenInfo(infoData)
    }

    private static func parseOAuthTokenInfo(_ message: Data) throws -> GeminiLocalAuth {
        var access = ""
        var refresh: String?
        var expires: Date?

        for field in try fields(of: message) {
            switch (field.number, field.wire) {
            case (1, .lengthDelimited):
                access = String(data: field.bytes, encoding: .utf8) ?? ""
            case (3, .lengthDelimited):
                refresh = String(data: field.bytes, encoding: .utf8)
            case (4, .lengthDelimited):
                expires = parseTimestamp(field.bytes)
            default:
                continue
            }
        }

        guard !access.isEmpty else { throw GeminiLocalAuthError.notSignedIn }
        return GeminiLocalAuth(
            accessToken: access,
            refreshToken: refresh,
            email: nil,
            expiresAt: expires,
            source: "ide"
        )
    }

    // MARK: - protobuf

    private enum Wire: Int {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    private struct Field {
        var number: Int
        var wire: Wire
        var varint: UInt64 = 0
        var bytes: Data = Data()
    }

    private static func fields(of data: Data) throws -> [Field] {
        var pos = 0
        var out: [Field] = []
        while pos < data.count {
            let (key, next) = try readVarint(data, pos)
            pos = next
            let number = Int(key >> 3)
            guard let wire = Wire(rawValue: Int(key & 0x7)) else {
                throw GeminiLocalAuthError.invalidAuthFile
            }
            switch wire {
            case .varint:
                let (value, npos) = try readVarint(data, pos)
                pos = npos
                out.append(Field(number: number, wire: wire, varint: value))
            case .fixed64:
                guard pos + 8 <= data.count else { throw GeminiLocalAuthError.invalidAuthFile }
                out.append(Field(number: number, wire: wire, bytes: data.subdata(in: pos..<(pos + 8))))
                pos += 8
            case .lengthDelimited:
                let (length, npos) = try readVarint(data, pos)
                pos = npos
                let len = Int(length)
                guard pos + len <= data.count else { throw GeminiLocalAuthError.invalidAuthFile }
                out.append(Field(number: number, wire: wire, bytes: data.subdata(in: pos..<(pos + len))))
                pos += len
            case .fixed32:
                guard pos + 4 <= data.count else { throw GeminiLocalAuthError.invalidAuthFile }
                out.append(Field(number: number, wire: wire, bytes: data.subdata(in: pos..<(pos + 4))))
                pos += 4
            }
        }
        return out
    }

    private static func firstLengthDelimited(_ data: Data, field: Int) -> Data? {
        guard let match = try? fields(of: data).first(where: {
            $0.number == field && $0.wire == .lengthDelimited
        }) else { return nil }
        return match.bytes
    }

    private static func readVarint(_ data: Data, _ pos: Int) throws -> (UInt64, Int) {
        var value: UInt64 = 0
        var shift = 0
        var i = pos
        while true {
            guard i < data.count else { throw GeminiLocalAuthError.invalidAuthFile }
            let byte = data[i]
            i += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, i) }
            shift += 7
            if shift > 70 { throw GeminiLocalAuthError.invalidAuthFile }
        }
    }

    private static func parseTimestamp(_ message: Data) -> Date? {
        guard let fields = try? fields(of: message) else { return nil }
        var seconds: Int64 = 0
        var nanos: Int32 = 0
        for field in fields {
            if field.number == 1, field.wire == .varint {
                seconds = Int64(bitPattern: field.varint)
            } else if field.number == 2, field.wire == .varint {
                nanos = Int32(truncatingIfNeeded: field.varint)
            }
        }
        guard seconds != 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
    }
}

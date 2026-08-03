import Foundation
import GRDB

public enum UsageStoreError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}

public actor UsageStore {
    private let dbQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) throws {
        self.dbQueue = databaseQueue
        try Self.migrate(databaseQueue)
    }

    public static func inMemory() throws -> UsageStore {
        try UsageStore(databaseQueue: DatabaseQueue())
    }

    public static func onDisk(url: URL) throws -> UsageStore {
        try UsageStore(databaseQueue: DatabaseQueue(path: url.path))
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "snapshots") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().indexed()
                t.column("fetched_at", .double).notNull().indexed()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .blob).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(snapshot) else {
            throw UsageStoreError.encodingFailed
        }
        let id = "\(snapshot.providerID.rawValue)-\(snapshot.fetchedAt.timeIntervalSince1970)"
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO snapshots (id, provider_id, fetched_at, payload)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [id, snapshot.providerID.rawValue, snapshot.fetchedAt.timeIntervalSince1970, payload]
            )
        }
    }

    public func latestSnapshot(for provider: ProviderID) throws -> UsageSnapshot? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT payload FROM snapshots
                WHERE provider_id = ?
                ORDER BY fetched_at DESC
                LIMIT 1
                """,
                arguments: [provider.rawValue]
            )
            guard let payload: Data = row?["payload"] else { return nil }
            return try decodeSnapshot(payload)
        }
    }

    public func history(for provider: ProviderID, from: Date, to: Date) throws -> [UsageSnapshot] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT payload FROM snapshots
                WHERE provider_id = ?
                  AND fetched_at >= ?
                  AND fetched_at <= ?
                ORDER BY fetched_at ASC
                """,
                arguments: [provider.rawValue, from.timeIntervalSince1970, to.timeIntervalSince1970]
            )
            return try rows.map { row in
                let payload: Data = row["payload"]
                return try decodeSnapshot(payload)
            }
        }
    }

    public func loadCooldown() throws -> AlertCooldownState {
        try loadMeta("cooldown", default: AlertCooldownState())
    }

    public func saveCooldown(_ state: AlertCooldownState) throws {
        try saveMeta("cooldown", value: state)
    }

    public func loadPreferences() throws -> QuotaPreferences {
        try loadMeta("preferences", default: .defaults)
    }

    public func savePreferences(_ preferences: QuotaPreferences) throws {
        try saveMeta("preferences", value: preferences)
    }

    private func decodeSnapshot(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(UsageSnapshot.self, from: data) else {
            throw UsageStoreError.decodingFailed
        }
        return snap
    }

    private func loadMeta<T: Decodable>(_ key: String, default defaultValue: T) throws -> T {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = ?",
                arguments: [key]
            )
            guard let payload: Data = row?["value"] else {
                return defaultValue
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: payload)
        }
    }

    private func saveMeta<T: Encodable>(_ key: String, value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(value) else {
            throw UsageStoreError.encodingFailed
        }
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
                arguments: [key, payload]
            )
        }
    }
}

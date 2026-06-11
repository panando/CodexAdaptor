import Foundation
import GRDB
import CodexRouterCore

/// Data Access Object for Provider records.
public final class ProviderDAO {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    /// Save a provider.
    public func save(_ provider: Provider, appType: String = "codex") throws {
        var record = try ProviderRecord(from: provider, appType: appType)
        try db.dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Get all providers for an app type.
    public func getAll(appType: String = "codex") throws -> [Provider] {
        try db.dbQueue.read { db in
            let records = try ProviderRecord
                .filter(Column("app_type") == appType)
                .order(Column("sort_index"))
                .fetchAll(db)
            return try records.map { try $0.toProvider() }
        }
    }

    /// Get a provider by ID.
    public func get(byId id: String, appType: String = "codex") throws -> Provider? {
        try db.dbQueue.read { db in
            guard let record = try ProviderRecord
                .filter(Column("id") == id && Column("app_type") == appType)
                .fetchOne(db) else {
                return nil
            }
            return try record.toProvider()
        }
    }

    /// Delete a provider.
    public func delete(id: String, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            _ = try ProviderRecord
                .filter(Column("id") == id && Column("app_type") == appType)
                .deleteAll(db)
        }
    }

    /// Set current provider (update sort_index to 0).
    public func setCurrent(id: String, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            // Reset all sort indexes for this app type
            try db.execute(
                sql: "UPDATE providers SET sort_index = 1 WHERE app_type = ?",
                arguments: [appType]
            )
            // Set selected provider to 0
            try db.execute(
                sql: "UPDATE providers SET sort_index = 0 WHERE id = ? AND app_type = ?",
                arguments: [id, appType]
            )
        }
    }

    /// Get current provider.
    public func getCurrent(appType: String = "codex") throws -> Provider? {
        try db.dbQueue.read { db in
            guard let record = try ProviderRecord
                .filter(Column("app_type") == appType && Column("sort_index") == 0)
                .fetchOne(db) else {
                return nil
            }
            return try record.toProvider()
        }
    }
}

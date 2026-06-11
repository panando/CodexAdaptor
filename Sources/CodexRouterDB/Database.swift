import Foundation
import GRDB
import CodexRouterCore

/// Database manager for CodexRouter persistence.
public final class Database {
    public let dbQueue: DatabaseQueue
    public let databasePath: String

    public init(path: String? = nil) throws {
        let dbPath = path ?? Self.defaultDatabasePath()
        self.databasePath = dbPath

        // Ensure directory exists
        let directory = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.dbQueue = try DatabaseQueue(path: dbPath)

        try migrate()
    }

    /// Create in-memory database for testing.
    public static func inMemory() throws -> Database {
        let dbQueue = try DatabaseQueue()
        let database = Database(dbQueue: dbQueue, path: ":memory:")
        try database.migrate()
        return database
    }

    private init(dbQueue: DatabaseQueue, path: String) {
        self.dbQueue = dbQueue
        self.databasePath = path
    }

    /// Default database path: ~/.codex-router/proxy.db
    public static func defaultDatabasePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex-router/proxy.db"
    }

    /// Run database migrations.
    public func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // Providers table
            try db.create(table: "providers") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("app_type", .text).notNull().defaults(to: "codex")
                t.column("settings_config", .text).notNull()
                t.column("category", .text)
                t.column("meta", .text)
                t.column("sort_index", .integer)
                t.column("in_failover_queue", .boolean).defaults(to: false)
                t.column("created_at", .datetime)
            }

            // Failover queue table
            try db.create(table: "failover_queue") { t in
                t.column("app_type", .text).notNull()
                t.column("provider_id", .text).notNull()
                t.column("priority", .integer).notNull()
                t.primaryKey(["app_type", "provider_id"])
            }

            // Proxy config table
            try db.create(table: "proxy_config") { t in
                t.column("app_type", .text).primaryKey()
                t.column("auto_failover_enabled", .boolean).defaults(to: false)
                t.column("max_retries", .integer).defaults(to: 3)
                t.column("circuit_failure_threshold", .integer).defaults(to: 5)
                t.column("circuit_success_threshold", .integer).defaults(to: 3)
                t.column("circuit_timeout_seconds", .integer).defaults(to: 60)
                t.column("streaming_first_byte_timeout", .integer).defaults(to: 60)
                t.column("streaming_idle_timeout", .integer).defaults(to: 120)
            }

            // Provider health table
            try db.create(table: "provider_health") { t in
                t.column("provider_id", .text).notNull()
                t.column("app_type", .text).notNull()
                t.column("is_healthy", .boolean).defaults(to: true)
                t.column("consecutive_failures", .integer).defaults(to: 0)
                t.column("last_success_at", .datetime)
                t.column("last_failure_at", .datetime)
                t.column("last_error", .text)
                t.primaryKey(["provider_id", "app_type"])
            }
        }

        try migrator.migrate(dbQueue)
    }
}

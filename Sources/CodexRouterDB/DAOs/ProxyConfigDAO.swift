import Foundation
import GRDB
import CodexRouterCore

/// Data Access Object for ProxyConfig records.
public final class ProxyConfigDAO {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    /// Get config for an app type, creating default if not exists.
    public func get(appType: String = "codex") throws -> ProxyConfig {
        try db.dbQueue.read { db in
            guard let record = try ProxyConfigRecord
                .filter(Column("appType") == appType)
                .fetchOne(db) else {
                return ProxyConfig(appType: appType)
            }
            return record.toProxyConfig()
        }
    }

    /// Save config for an app type.
    public func save(_ config: ProxyConfig) throws {
        let record = ProxyConfigRecord(from: config)
        try db.dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Update auto failover setting.
    public func setAutoFailover(enabled: Bool, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO proxy_config
                    (app_type, auto_failover_enabled, max_retries, circuit_failure_threshold,
                     circuit_success_threshold, circuit_timeout_seconds, streaming_first_byte_timeout, streaming_idle_timeout)
                    VALUES (?, ?,
                        COALESCE((SELECT max_retries FROM proxy_config WHERE app_type = ?), 3),
                        COALESCE((SELECT circuit_failure_threshold FROM proxy_config WHERE app_type = ?), 5),
                        COALESCE((SELECT circuit_success_threshold FROM proxy_config WHERE app_type = ?), 3),
                        COALESCE((SELECT circuit_timeout_seconds FROM proxy_config WHERE app_type = ?), 60),
                        COALESCE((SELECT streaming_first_byte_timeout FROM proxy_config WHERE app_type = ?), 60),
                        COALESCE((SELECT streaming_idle_timeout FROM proxy_config WHERE app_type = ?), 120)
                    )
                """,
                arguments: [appType, enabled, appType, appType, appType, appType, appType, appType]
            )
        }
    }
}

import Foundation
import GRDB
import CodexRouterCore

/// Provider health status.
public struct ProviderHealth: Codable, Equatable {
    public var providerId: String
    public var appType: String
    public var isHealthy: Bool
    public var consecutiveFailures: Int
    public var lastSuccessAt: Date?
    public var lastFailureAt: Date?
    public var lastError: String?

    public init(
        providerId: String,
        appType: String,
        isHealthy: Bool = true,
        consecutiveFailures: Int = 0,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.providerId = providerId
        self.appType = appType
        self.isHealthy = isHealthy
        self.consecutiveFailures = consecutiveFailures
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastError = lastError
    }
}

/// Data Access Object for provider health records.
public final class ProviderHealthDAO {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    /// Get health status for a provider.
    public func get(providerId: String, appType: String) throws -> ProviderHealth {
        try db.dbQueue.read { db in
            guard let record = try ProviderHealthRecord
                .filter(Column("provider_id") == providerId && Column("app_type") == appType)
                .fetchOne(db) else {
                return ProviderHealth(providerId: providerId, appType: appType)
            }
            return ProviderHealth(
                providerId: record.providerId,
                appType: record.appType,
                isHealthy: record.isHealthy,
                consecutiveFailures: record.consecutiveFailures,
                lastSuccessAt: record.lastSuccessAt,
                lastFailureAt: record.lastFailureAt,
                lastError: record.lastError
            )
        }
    }

    /// Record a successful request.
    public func recordSuccess(providerId: String, appType: String) throws {
        try db.dbQueue.write { db in
            var record = try ProviderHealthRecord
                .filter(Column("provider_id") == providerId && Column("app_type") == appType)
                .fetchOne(db) ?? ProviderHealthRecord(providerId: providerId, appType: appType)

            record.isHealthy = true
            record.consecutiveFailures = 0
            record.lastSuccessAt = Date()
            record.lastError = nil

            try record.save(db)
        }
    }

    /// Record a failed request.
    public func recordFailure(providerId: String, appType: String, error: String? = nil) throws {
        try db.dbQueue.write { db in
            var record = try ProviderHealthRecord
                .filter(Column("provider_id") == providerId && Column("app_type") == appType)
                .fetchOne(db) ?? ProviderHealthRecord(providerId: providerId, appType: appType)

            record.consecutiveFailures += 1
            record.lastFailureAt = Date()
            record.lastError = error

            // Mark as unhealthy after threshold (use config)
            if record.consecutiveFailures >= 5 {
                record.isHealthy = false
            }

            try record.save(db)
        }
    }

    /// Reset health status for a provider.
    public func reset(providerId: String, appType: String) throws {
        try db.dbQueue.write { db in
            var record = try ProviderHealthRecord
                .filter(Column("provider_id") == providerId && Column("app_type") == appType)
                .fetchOne(db) ?? ProviderHealthRecord(providerId: providerId, appType: appType)

            record.isHealthy = true
            record.consecutiveFailures = 0
            record.lastError = nil

            try record.save(db)
        }
    }

    /// Get all unhealthy providers for an app type.
    public func getUnhealthyProviders(appType: String) throws -> [ProviderHealth] {
        try db.dbQueue.read { db in
            let records = try ProviderHealthRecord
                .filter(Column("app_type") == appType && Column("is_healthy") == false)
                .fetchAll(db)

            return records.map { record in
                ProviderHealth(
                    providerId: record.providerId,
                    appType: record.appType,
                    isHealthy: record.isHealthy,
                    consecutiveFailures: record.consecutiveFailures,
                    lastSuccessAt: record.lastSuccessAt,
                    lastFailureAt: record.lastFailureAt,
                    lastError: record.lastError
                )
            }
        }
    }
}

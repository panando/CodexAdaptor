import Foundation
import GRDB
import CodexRouterCore

/// Data Access Object for failover queue.
public final class FailoverDAO {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    /// Get the failover queue for an app type.
    public func getQueue(appType: String) throws -> [Provider] {
        let records = try db.dbQueue.read { db in
            try FailoverQueueRecord
                .filter(Column("app_type") == appType)
                .order(Column("priority"))
                .fetchAll(db)
        }

        var providers: [Provider] = []
        let providerDAO = ProviderDAO(db)
        for record in records {
            if let provider = try providerDAO.get(byId: record.providerId, appType: appType) {
                providers.append(provider)
            }
        }
        return providers
    }

    /// Add a provider to the failover queue.
    public func addToQueue(providerId: String, appType: String, priority: Int) throws {
        try db.dbQueue.write { db in
            let record = FailoverQueueRecord(appType: appType, providerId: providerId, priority: priority)
            try record.save(db)
        }
    }

    /// Remove a provider from the failover queue.
    public func removeFromQueue(providerId: String, appType: String) throws {
        try db.dbQueue.write { db in
            _ = try FailoverQueueRecord
                .filter(Column("app_type") == appType && Column("provider_id") == providerId)
                .deleteAll(db)
        }
    }

    /// Reorder the failover queue.
    public func reorderQueue(appType: String, providerIds: [String]) throws {
        try db.dbQueue.write { db in
            // Delete existing queue for this app type
            _ = try FailoverQueueRecord
                .filter(Column("app_type") == appType)
                .deleteAll(db)

            // Insert new queue order
            for (index, providerId) in providerIds.enumerated() {
                let record = FailoverQueueRecord(appType: appType, providerId: providerId, priority: index)
                try record.save(db)
            }
        }
    }

    /// Clear the failover queue for an app type.
    public func clearQueue(appType: String) throws {
        try db.dbQueue.write { db in
            _ = try FailoverQueueRecord
                .filter(Column("app_type") == appType)
                .deleteAll(db)
        }
    }
}

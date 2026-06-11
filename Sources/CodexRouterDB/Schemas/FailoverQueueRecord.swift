import Foundation
import GRDB
import CodexRouterCore

/// Database record for failover queue.
public struct FailoverQueueRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "failover_queue"

    public var appType: String
    public var providerId: String
    public var priority: Int

    enum CodingKeys: String, CodingKey {
        case appType = "app_type"
        case providerId = "provider_id"
        case priority
    }

    public init(appType: String, providerId: String, priority: Int) {
        self.appType = appType
        self.providerId = providerId
        self.priority = priority
    }
}

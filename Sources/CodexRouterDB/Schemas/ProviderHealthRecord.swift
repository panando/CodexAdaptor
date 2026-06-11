import Foundation
import GRDB
import CodexRouterCore

/// Database record for provider health status.
public struct ProviderHealthRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "provider_health"

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
        consecutiveFailures: Int = 0
    ) {
        self.providerId = providerId
        self.appType = appType
        self.isHealthy = isHealthy
        self.consecutiveFailures = consecutiveFailures
        self.lastSuccessAt = nil
        self.lastFailureAt = nil
        self.lastError = nil
    }
}

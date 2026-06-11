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

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case appType = "app_type"
        case isHealthy = "is_healthy"
        case consecutiveFailures = "consecutive_failures"
        case lastSuccessAt = "last_success_at"
        case lastFailureAt = "last_failure_at"
        case lastError = "last_error"
    }

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

import Foundation
import CodexRouterCore

/// Manages provider failover queue and priority-based switching.
public actor FailoverManager {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Get the failover queue for an app type.
    public func getQueue(appType: String) async throws -> [Provider] {
        let dao = FailoverDAO(database)
        return try dao.getQueue(appType: appType)
    }

    /// Add a provider to the failover queue.
    public func addToQueue(providerId: String, appType: String, priority: Int) async throws {
        let dao = FailoverDAO(database)
        try dao.addToQueue(providerId: providerId, appType: appType, priority: priority)
    }

    /// Remove a provider from the failover queue.
    public func removeFromQueue(providerId: String, appType: String) async throws {
        let dao = FailoverDAO(database)
        try dao.removeFromQueue(providerId: providerId, appType: appType)
    }

    /// Reorder the failover queue.
    public func reorderQueue(appType: String, providerIds: [String]) async throws {
        let dao = FailoverDAO(database)
        try dao.reorderQueue(appType: appType, providerIds: providerIds)
    }

    /// Get the next available provider from the failover queue, skipping unhealthy ones.
    public func getNextProvider(
        appType: String,
        providerRouter: ProviderRouter,
        excludeIds: Set<String> = []
    ) async throws -> Provider? {
        let queue = try await getQueue(appType: appType)

        for provider in queue {
            // Skip excluded providers
            if excludeIds.contains(provider.id) {
                continue
            }

            // Check circuit breaker
            let breaker = await providerRouter.getCircuitBreaker(for: provider.id)
            let allowed = await breaker.allowRequest()

            if allowed {
                return provider
            }
        }

        return nil
    }

    /// Check if failover is enabled for an app type.
    public func isFailoverEnabled(appType: String) throws -> Bool {
        let dao = ProxyConfigDAO(database)
        let config = try dao.get(appType: appType)
        return config.autoFailoverEnabled
    }
}

/// Failover queue entry.
public struct FailoverEntry: Codable, Identifiable {
    public var id: String { providerId }
    public var providerId: String
    public var appType: String
    public var priority: Int

    public init(providerId: String, appType: String, priority: Int) {
        self.providerId = providerId
        self.appType = appType
        self.priority = priority
    }
}

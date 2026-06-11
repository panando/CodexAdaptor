import Foundation
import CodexRouterCore

/// Manages provider selection and failover.
public actor ProviderRouter {
    private let database: Database
    private var circuitBreakers: [String: CircuitBreaker] = [:]

    public init(database: Database) {
        self.database = database
    }

    /// Select available providers for an app type.
    public func selectProviders(appType: String) async throws -> [Provider] {
        let dao = ProviderDAO(database)
        let allProviders = try dao.getAll(appType: appType)
        return allProviders
    }

    /// Get or create circuit breaker for a provider.
    public func getCircuitBreaker(for providerId: String) -> CircuitBreaker {
        if let existing = circuitBreakers[providerId] {
            return existing
        }
        let breaker = CircuitBreaker()
        circuitBreakers[providerId] = breaker
        return breaker
    }
}
